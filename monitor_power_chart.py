#!/usr/bin/env python3
"""
Mac 실시간 전력 모니터링 & 위험 진단 대시보드 (monitor_power_chart.py)

1. 웹 대시보드 모드 (기본):
   - 외부 CDN 의존성 없이 순수 내장 고해상도 Canvas 2D 렌더러로 실시간 전력/전압 파형을 그립니다.
   - 단방향 폴링(800ms) 및 초기 히스토리 자동 하이드레이션으로 화면 멈춤 없이 즉시 연속 렌더링됩니다.
   - IOKit 텔레메트리 및 pmset 기반으로 실시간 위험도(SAFE / CAUTION / DANGER)를 진단합니다.

2. 터미널 CLI 차트 모드 (--cli):
   - 브라우저 없이 터미널에서 유니코드 실시간 바/스파크 차트와 위험도를 표시합니다.
"""

from __future__ import annotations

import argparse
import collections
import json
import math
import os
import struct
import subprocess
import sys
import threading
import time
import webbrowser
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Deque, Dict, List, Optional, Tuple

# check_mac_power 모듈에서 텔레메트리 수집 함수 가져오기
try:
    from check_mac_power import sample_power_telemetry
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from check_mac_power import sample_power_telemetry


# ==============================================================================
# 위험도(Risk) 평가 엔진
# ==============================================================================
class PowerRiskEvaluator:
    """전력 텔레메트리 데이터를 분석하여 하드웨어 위험도를 평가합니다."""

    def __init__(self, history_size: int = 600) -> None:
        self.history: Deque[Dict[str, Any]] = collections.deque(maxlen=history_size)
        self.disconnect_events: Deque[float] = collections.deque(maxlen=20)
        self.last_connected: Optional[bool] = None

    def evaluate(self, sample: Dict[str, Any]) -> Dict[str, Any]:
        curr_time = sample.get("timestamp", time.time())
        conn = bool(sample.get("external_connected", False))

        # 순간 단절(Intermittent Disconnection) 감지
        if self.last_connected is not None and self.last_connected and not conn:
            self.disconnect_events.append(curr_time)
        self.last_connected = conn

        # 최근 60초 내 단절 횟수 카운트
        recent_disconnects = sum(1 for t in self.disconnect_events if (curr_time - t) <= 60.0)

        risk_score = 0  # 0: 완벽히 안전, 100: 극도로 위험
        risk_level = "SAFE"
        alerts: List[Dict[str, str]] = []

        adapt_w = sample.get("adapter_watts")
        adapt_v = sample.get("adapter_voltage_v")
        sys_v = sample.get("system_voltage_v")
        sys_w = sample.get("system_power_w")
        drop_pct = sample.get("voltage_drop_pct")
        telemetry_err = sample.get("telemetry_errors", 0)
        slow_charging = sample.get("slow_charging_reason", 0)
        therm = sample.get("thermal_info", {})

        # 1. 단절 빈도 검사 (쇼트/아크 발생 위험)
        if recent_disconnects >= 2:
            risk_score += 45
            alerts.append({
                "level": "DANGER",
                "title": "잦은 전원 연결 해제 (단선/접촉 불량 의심)",
                "message": f"최근 1분간 어댑터 연결 끊김이 {recent_disconnects}회 감지되었습니다. 포트 쇼트나 스파크 위험이 있습니다.",
            })
        elif not conn:
            risk_score += 15
            alerts.append({
                "level": "INFO",
                "title": "배터리 전원 사용 중",
                "message": "AC 충전기가 연결되어 있지 않아 배터리로 가동 중입니다.",
            })

        # 2. 전압 강하율 검사 (가장 치명적인 전원선 결함 지표)
        if drop_pct is not None:
            if drop_pct > 7.0:
                risk_score += 50
                alerts.append({
                    "level": "DANGER",
                    "title": "위험 수준의 전압 강하 감지",
                    "message": f"정격 대비 전압 강하율이 {drop_pct:.2f}%로 기준치(5%)를 크게 초과했습니다. 케이블/충전기 과열 위험이 있습니다.",
                })
            elif drop_pct > 4.5:
                risk_score += 25
                alerts.append({
                    "level": "WARNING",
                    "title": "전압 강하 주의",
                    "message": f"전압 강하율이 {drop_pct:.2f}%입니다. 접촉 상태나 고전력 케이블 규격을 확인하세요.",
                })

        # 3. 인입 전압 절대치 저하 검사 (저전압)
        if adapt_v is not None and sys_v is not None:
            if adapt_v >= 19.0 and sys_v < 18.0:
                risk_score += 40
                alerts.append({
                    "level": "DANGER",
                    "title": "비정상 저전압 인입",
                    "message": f"정격 {adapt_v:.1f}V 어댑터에서 실제 인입 전압이 {sys_v:.2f}V로 심각하게 낮습니다.",
                })

        # 4. 전력 과부하 검사
        if adapt_w is not None and sys_w is not None and adapt_w > 0:
            load_ratio = (sys_w / adapt_w) * 100.0
            if load_ratio > 95.0:
                risk_score += 30
                alerts.append({
                    "level": "WARNING",
                    "title": "어댑터 정격 전력 한계 근접",
                    "message": f"소비 전력이 어댑터 정격의 {load_ratio:.1f}%에 도달했습니다. 고부하 시 배터리가 동시 소모될 수 있습니다.",
                })

        # 5. 하드웨어 텔레메트리 에러 검사
        if telemetry_err > 0:
            risk_score += 35
            alerts.append({
                "level": "DANGER",
                "title": "IOKit 전력 통신 에러 발생",
                "message": f"PMIC 텔레메트리 오류가 {telemetry_err}건 기록되었습니다.",
            })

        # 6. 저속 충전 플래그
        if slow_charging != 0:
            risk_score += 20
            alerts.append({
                "level": "WARNING",
                "title": "저속 충전 모드 감지",
                "message": "충전기 출력 부족 또는 케이블 협상 실패로 저속 충전 중입니다.",
            })

        # 7. 서멀 / CPU 전력 스로틀링
        cpu_limit = therm.get("cpu_speed_limit", 100)
        if cpu_limit < 100 or therm.get("has_cpu_power_warning") or therm.get("has_thermal_warning"):
            risk_score += 25
            alerts.append({
                "level": "WARNING",
                "title": "전력/서멀 스로틀링 작동 중",
                "message": f"CPU 속도가 최대치의 {cpu_limit}%로 제한되었습니다. 전원 발열 또는 공급 한계일 수 있습니다.",
            })

        # 최종 위험도 레벨 판정
        risk_score = max(0, min(100, risk_score))
        if risk_score >= 50:
            risk_level = "DANGER"
        elif risk_score >= 25:
            risk_level = "CAUTION"
        else:
            risk_level = "SAFE"

        processed = dict(sample)
        processed["risk_score"] = risk_score
        processed["risk_level"] = risk_level
        processed["alerts"] = alerts
        processed["recent_disconnects"] = recent_disconnects

        self.history.append(processed)
        return processed


# ==============================================================================
# 전역 상태 및 공유 모니터 스레드
# ==============================================================================
class GlobalMonitor:
    def __init__(self) -> None:
        self.evaluator = PowerRiskEvaluator(history_size=600)
        self.lock = threading.Lock()
        self.latest_data: Optional[Dict[str, Any]] = None
        self.is_running = True

        # 시작 시 즉시 1회 초기화
        self.update()

    def update(self) -> Dict[str, Any]:
        raw_sample = sample_power_telemetry()
        with self.lock:
            data = self.evaluator.evaluate(raw_sample)
            self.latest_data = data
            return data

    def get_snapshot(self) -> Dict[str, Any]:
        with self.lock:
            if self.latest_data is None:
                return self.update()
            return dict(self.latest_data)

    def get_history(self) -> List[Dict[str, Any]]:
        with self.lock:
            return list(self.evaluator.history)


GLOBAL_MONITOR = GlobalMonitor()


def monitor_background_worker(interval: float = 1.0) -> None:
    """백그라운드에서 텔레메트리를 주기적으로 갱신합니다."""
    while GLOBAL_MONITOR.is_running:
        try:
            GLOBAL_MONITOR.update()
        except Exception as e:
            print(f"[모니터링 경고] 데이터 수집 오류: {e}", file=sys.stderr)
        time.sleep(interval)


# ==============================================================================
# PWA (Progressive Web App) 메타데이터 & 에셋
# ==============================================================================
MANIFEST_JSON = json.dumps(
    {
        "name": "Mac Power Guard",
        "short_name": "PowerGuard",
        "description": "Mac 실시간 전력 공급량 및 하드웨어 안전 진단 대시보드",
        "start_url": "/",
        "scope": "/",
        "display": "standalone",
        "background_color": "#080c14",
        "theme_color": "#080c14",
        "icons": [
            {
                "src": "/icon.svg",
                "sizes": "any",
                "type": "image/svg+xml",
                "purpose": "any maskable",
            },
            {
                "src": "/icon-192.png",
                "sizes": "192x192",
                "type": "image/png",
                "purpose": "any maskable",
            },
            {
                "src": "/icon-512.png",
                "sizes": "512x512",
                "type": "image/png",
                "purpose": "any maskable",
            },
        ],
    },
    indent=2,
    ensure_ascii=False,
)

SERVICE_WORKER_JS = """// Mac Power Guard Service Worker (PWA Shell Caching & Realtime API Bypass)
const CACHE_NAME = 'mac-power-guard-v1';
const STATIC_ASSETS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/icon.svg',
  '/icon-192.png',
  '/icon-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(STATIC_ASSETS)).catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  // 실시간 텔레메트리 API(/api/power)는 캐시하지 않고 항상 네트워크로 통과
  if (url.pathname.startsWith('/api/')) {
    return;
  }
  event.respondWith(
    fetch(event.request)
      .then((response) => {
        if (response.status === 200 && event.request.method === 'GET') {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return response;
      })
      .catch(() => caches.match(event.request).then((c) => c || (event.request.mode === 'navigate' ? caches.match('/') : null)))
  );
});
"""

ICON_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#0f172a" />
      <stop offset="100%" stop-color="#080c14" />
    </linearGradient>
    <linearGradient id="borderGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#06b6d4" stop-opacity="0.8" />
      <stop offset="100%" stop-color="#10b981" stop-opacity="0.6" />
    </linearGradient>
    <linearGradient id="boltGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#38bdf8" />
      <stop offset="45%" stop-color="#06b6d4" />
      <stop offset="100%" stop-color="#10b981" />
    </linearGradient>
    <filter id="glow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="16" result="blur" />
      <feMerge>
        <feMergeNode in="blur" />
        <feMergeNode in="SourceGraphic" />
      </feMerge>
    </filter>
  </defs>
  <rect width="512" height="512" rx="112" fill="url(#bg)" stroke="url(#borderGrad)" stroke-width="12" />
  <path d="M 256,80 L 380,130 C 380,270 256,380 256,420 C 256,380 132,270 132,130 Z" fill="none" stroke="rgba(6,182,212,0.25)" stroke-width="14" stroke-linejoin="round" />
  <path d="M 285,115 L 180,265 L 260,265 L 225,395 L 340,235 L 260,235 Z" fill="url(#boltGrad)" filter="url(#glow)" stroke="#080c14" stroke-width="4" stroke-linejoin="round" />
</svg>
"""

_ICON_PNG_CACHE: Dict[int, bytes] = {}


def get_icon_png(size: int = 192) -> bytes:
    """순수 파이썬 표준 라이브러리(zlib, struct)로 PWA 사양의 RGBA PNG 아이콘을 생성합니다."""
    if size in _ICON_PNG_CACHE:
        return _ICON_PNG_CACHE[size]

    cx, cy = size / 2.0, size / 2.0
    rows: List[bytes] = []

    for y in range(size):
        row = bytearray(b"\\x00")  # Filter type None
        for x in range(size):
            dx = x - cx
            dy = y - cy
            sq = (abs(dx) ** 3.2 + abs(dy) ** 3.2) ** (1.0 / 3.2)
            if sq <= size * 0.46:
                # 배경 그라데이션 (#0f172a -> #080c14)
                t = (x + y) / (2.0 * size)
                r = int(15 * (1.0 - t) + 8 * t)
                g = int(23 * (1.0 - t) + 12 * t)
                b = int(42 * (1.0 - t) + 20 * t)
                a = 255

                # 번개 형상 판정
                nx = (x - cx) / (size * 0.38)
                ny = (y - cy) / (size * 0.38)
                is_bolt = False
                if -0.85 <= ny <= 0.05:
                    mid_x = -0.15 + ny * 0.35
                    if abs(nx - mid_x) <= 0.28:
                        is_bolt = True
                if -0.05 <= ny <= 0.85:
                    mid_x = 0.15 - ny * 0.3
                    if abs(nx - mid_x) <= 0.24:
                        is_bolt = True

                if is_bolt:
                    r, g, b = 6, 182, 212
                    if abs(nx) < 0.1 and abs(ny) < 0.3:
                        r, g, b = 56, 189, 248
                elif sq >= size * 0.43:
                    # 네온 사이언 테두리
                    r, g, b = 6, 182, 212
                    a = 220
            else:
                r, g, b, a = 0, 0, 0, 0

            row.extend((r, g, b, a))
        rows.append(bytes(row))

    raw_data = b"".join(rows)

    def chunk(tag: bytes, data: bytes) -> bytes:
        c = tag + data
        crc = struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
        return struct.pack(">I", len(data)) + c + crc

    png = bytearray(b"\\x89PNG\\r\\n\\x1a\\n")
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png += chunk(b"IHDR", ihdr)
    png += chunk(b"IDAT", zlib.compress(raw_data, level=6))
    png += chunk(b"IEND", b"")
    result = bytes(png)
    _ICON_PNG_CACHE[size] = result
    return result


# ==============================================================================
# HTML & JS 실시간 대시보드 UI (순수 Canvas 기반 - 외부 CDN 의존 없음)
# ==============================================================================
DASHBOARD_HTML = """<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Mac Power Guard | 실시간 전력 & 위험 진단 대시보드</title>

  <!-- PWA & Mobile Web App Meta Tags -->
  <link rel="manifest" href="/manifest.json">
  <link rel="icon" type="image/svg+xml" href="/icon.svg">
  <link rel="icon" type="image/png" sizes="192x192" href="/icon-192.png">
  <link rel="apple-touch-icon" href="/icon-192.png">
  <meta name="theme-color" content="#080c14">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="PowerGuard">
  <meta name="application-name" content="Mac Power Guard">

  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;600;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg-base: #080c14;
      --bg-surface: #0f172a;
      --bg-card: rgba(15, 23, 42, 0.82);
      --border-card: rgba(255, 255, 255, 0.08);
      
      --text-main: #f8fafc;
      --text-muted: #94a3b8;
      --text-dim: #64748b;

      --accent-green: #10b981;
      --accent-green-glow: rgba(16, 185, 129, 0.25);
      --accent-yellow: #f59e0b;
      --accent-red: #ef4444;
      --accent-cyan: #06b6d4;
      --accent-purple: #8b5cf6;

      --font-sans: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
      --font-mono: 'JetBrains Mono', monospace;
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      background-color: var(--bg-base);
      background-image: 
        radial-gradient(circle at 10% 10%, rgba(6, 182, 212, 0.08) 0%, transparent 40%),
        radial-gradient(circle at 90% 20%, rgba(16, 185, 129, 0.06) 0%, transparent 40%),
        radial-gradient(circle at 50% 90%, rgba(139, 92, 246, 0.06) 0%, transparent 50%);
      color: var(--text-main);
      font-family: var(--font-sans);
      min-height: 100vh;
      padding: 24px;
      overflow-x: hidden;
    }

    .container {
      max-width: 1440px;
      margin: 0 auto;
      display: flex;
      flex-direction: column;
      gap: 20px;
    }

    /* Glassmorphism Header */
    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 16px 24px;
      background: var(--bg-card);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      border: 1px solid var(--border-card);
      border-radius: 16px;
      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4);
      -webkit-app-region: drag; /* 단독 앱 창 모드에서 macOS 창 드래그 지원 */
      user-select: none;
    }

    header button, header a, header input, .no-drag {
      -webkit-app-region: no-drag; /* 버튼 클릭 등 인터랙션 보장 */
    }

    .app-mode-badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      background: linear-gradient(135deg, rgba(6, 182, 212, 0.18), rgba(16, 185, 129, 0.18));
      border: 1px solid rgba(6, 182, 212, 0.4);
      color: #38bdf8;
      padding: 6px 14px;
      border-radius: 9999px;
      font-size: 11.5px;
      font-weight: 700;
      letter-spacing: 0.5px;
      font-family: var(--font-mono);
      box-shadow: 0 0 12px rgba(6, 182, 212, 0.25);
    }

    .btn-install-pwa {
      background: linear-gradient(135deg, #06b6d4, #10b981) !important;
      border: 1px solid rgba(255, 255, 255, 0.35) !important;
      color: #041017 !important;
      font-weight: 700 !important;
      box-shadow: 0 0 16px rgba(6, 182, 212, 0.4);
      cursor: pointer;
      animation: installGlow 2.5s infinite alternate;
    }

    .btn-install-pwa:hover {
      transform: translateY(-1px);
      box-shadow: 0 0 22px rgba(16, 185, 129, 0.6);
      filter: brightness(1.08);
    }

    @keyframes installGlow {
      0% { box-shadow: 0 0 10px rgba(6, 182, 212, 0.3); }
      100% { box-shadow: 0 0 20px rgba(16, 185, 129, 0.6); }
    }

    .server-offline-banner {
      background: rgba(239, 68, 68, 0.15);
      border: 1px solid rgba(239, 68, 68, 0.4);
      border-radius: 12px;
      padding: 14px 20px;
      display: flex;
      align-items: center;
      gap: 14px;
      color: #fecaca;
      box-shadow: 0 4px 20px rgba(239, 68, 68, 0.2);
    }

    .offline-icon { font-size: 24px; }
    .offline-title { font-weight: 700; font-size: 14px; color: #ef4444; margin-bottom: 3px; }
    .offline-desc { font-size: 12px; color: #cbd5e1; line-height: 1.4; }
    .offline-desc code {
      background: rgba(0, 0, 0, 0.4);
      padding: 2px 6px;
      border-radius: 4px;
      font-family: var(--font-mono);
      color: #38bdf8;
    }

    .brand {
      display: flex;
      align-items: center;
      gap: 14px;
    }

    .brand-icon {
      width: 44px;
      height: 44px;
      background: linear-gradient(135deg, rgba(6, 182, 212, 0.25), rgba(16, 185, 129, 0.25));
      border: 1px solid rgba(6, 182, 212, 0.4);
      border-radius: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 24px;
      box-shadow: 0 0 20px rgba(6, 182, 212, 0.3);
    }

    .brand-title {
      font-size: 20px;
      font-weight: 800;
      letter-spacing: -0.5px;
      background: linear-gradient(120deg, #ffffff, #cbd5e1);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }

    .brand-subtitle {
      font-size: 12px;
      color: var(--text-muted);
      margin-top: 2px;
    }

    .header-actions {
      display: flex;
      align-items: center;
      gap: 12px;
    }

    .live-pulse-badge {
      display: flex;
      align-items: center;
      gap: 8px;
      background: rgba(16, 185, 129, 0.12);
      border: 1px solid rgba(16, 185, 129, 0.3);
      padding: 7px 14px;
      border-radius: 9999px;
      font-size: 12px;
      font-weight: 600;
      color: var(--accent-green);
      font-family: var(--font-mono);
    }

    .pulse-dot {
      width: 9px;
      height: 9px;
      background-color: var(--accent-green);
      border-radius: 50%;
      box-shadow: 0 0 10px var(--accent-green);
      animation: pulse 1.4s infinite ease-in-out;
    }

    @keyframes pulse {
      0% { transform: scale(0.85); opacity: 0.6; }
      50% { transform: scale(1.35); opacity: 1; box-shadow: 0 0 14px var(--accent-green); }
      100% { transform: scale(0.85); opacity: 0.6; }
    }

    .btn {
      background: rgba(255, 255, 255, 0.06);
      border: 1px solid var(--border-card);
      color: var(--text-main);
      padding: 8px 16px;
      border-radius: 10px;
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s ease;
      display: flex;
      align-items: center;
      gap: 6px;
    }

    .btn:hover {
      background: rgba(255, 255, 255, 0.12);
      border-color: rgba(255, 255, 255, 0.2);
    }

    /* Stat Cards */
    .grid-stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 18px;
    }

    .card {
      background: var(--bg-card);
      backdrop-filter: blur(16px);
      -webkit-backdrop-filter: blur(16px);
      border: 1px solid var(--border-card);
      border-radius: 16px;
      padding: 22px;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      position: relative;
      box-shadow: 0 6px 24px rgba(0, 0, 0, 0.25);
      transition: transform 0.25s ease, border-color 0.25s ease;
    }

    .card:hover {
      transform: translateY(-2px);
      border-color: rgba(255, 255, 255, 0.18);
    }

    .card-top {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 12px;
    }

    .card-label {
      font-size: 12.5px;
      font-weight: 600;
      color: var(--text-muted);
      text-transform: uppercase;
      letter-spacing: 0.6px;
    }

    .card-icon-wrap {
      width: 36px;
      height: 36px;
      border-radius: 10px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 18px;
      background: rgba(255, 255, 255, 0.05);
    }

    .card-val {
      font-family: var(--font-mono);
      font-size: 34px;
      font-weight: 700;
      letter-spacing: -1px;
      display: flex;
      align-items: baseline;
      gap: 6px;
    }

    .card-unit {
      font-size: 15px;
      font-weight: 500;
      color: var(--text-dim);
    }

    .card-subtext {
      font-size: 12px;
      color: var(--text-dim);
      margin-top: 10px;
      display: flex;
      align-items: center;
      gap: 6px;
    }

    /* Risk Card */
    .card-risk { border-width: 1.5px; }
    .card-risk.safe {
      border-color: rgba(16, 185, 129, 0.4);
      box-shadow: 0 6px 28px rgba(16, 185, 129, 0.14);
    }
    .card-risk.caution {
      border-color: rgba(245, 158, 11, 0.45);
      box-shadow: 0 6px 28px rgba(245, 158, 11, 0.16);
    }
    .card-risk.danger {
      border-color: rgba(239, 68, 68, 0.6);
      box-shadow: 0 6px 36px rgba(239, 68, 68, 0.3);
      animation: dangerFlash 1.6s infinite ease-in-out;
    }

    @keyframes dangerFlash {
      0%, 100% { box-shadow: 0 0 20px rgba(239, 68, 68, 0.25); }
      50% { box-shadow: 0 0 40px rgba(239, 68, 68, 0.55); }
    }

    .badge-risk {
      padding: 5px 12px;
      border-radius: 8px;
      font-size: 12px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }

    .badge-risk.safe { background: rgba(16, 185, 129, 0.16); color: var(--accent-green); border: 1px solid rgba(16, 185, 129, 0.3); }
    .badge-risk.caution { background: rgba(245, 158, 11, 0.16); color: var(--accent-yellow); border: 1px solid rgba(245, 158, 11, 0.3); }
    .badge-risk.danger { background: rgba(239, 68, 68, 0.22); color: var(--accent-red); border: 1px solid rgba(239, 68, 68, 0.4); }

    .progress-bar-bg {
      width: 100%;
      height: 6px;
      background: rgba(255, 255, 255, 0.08);
      border-radius: 999px;
      margin-top: 12px;
      overflow: hidden;
    }

    .progress-bar-fill {
      height: 100%;
      background: linear-gradient(90deg, var(--accent-cyan), var(--accent-green));
      border-radius: 999px;
      transition: width 0.35s ease;
    }

    /* Charts Grid */
    .grid-charts {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 20px;
    }

    @media (max-width: 1000px) {
      .grid-charts {
        grid-template-columns: 1fr;
      }
    }

    .chart-card {
      background: var(--bg-card);
      backdrop-filter: blur(16px);
      -webkit-backdrop-filter: blur(16px);
      border: 1px solid var(--border-card);
      border-radius: 16px;
      padding: 22px;
      display: flex;
      flex-direction: column;
      gap: 14px;
      min-height: 380px;
    }

    .chart-header {
      display: flex;
      flex-direction: column;
      gap: 10px;
    }

    .chart-header-row1 {
      display: flex;
      align-items: center;
      justify-content: space-between;
    }

    .chart-header-row2 {
      display: flex;
      align-items: center;
      gap: 10px;
    }

    .chart-title {
      font-size: 15px;
      font-weight: 700;
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .chart-badge-now {
      font-family: var(--font-mono);
      font-size: 13px;
      font-weight: 700;
      padding: 4px 10px;
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.05);
    }

    .chart-badge-stat {
      font-family: var(--font-mono);
      font-size: 11.5px;
      font-weight: 700;
      padding: 3px 8px;
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid rgba(255, 255, 255, 0.06);
      display: flex;
      align-items: center;
      gap: 4px;
    }

    .badge-lbl {
      font-size: 10px;
      font-weight: 500;
      color: rgba(255, 255, 255, 0.5);
    }

    .canvas-wrapper {
      position: relative;
      flex: 1;
      width: 100%;
      min-height: 280px;
      background: rgba(0, 0, 0, 0.25);
      border: 1px solid rgba(255, 255, 255, 0.04);
      border-radius: 12px;
      overflow: hidden;
    }

    canvas {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      display: block;
    }

    /* Event & Telemetry Logs */
    .alerts-card {
      background: var(--bg-card);
      backdrop-filter: blur(16px);
      -webkit-backdrop-filter: blur(16px);
      border: 1px solid var(--border-card);
      border-radius: 16px;
      padding: 22px;
      display: flex;
      flex-direction: column;
      gap: 14px;
      max-height: 400px;
    }

    .alerts-list {
      display: flex;
      flex-direction: column;
      gap: 10px;
      overflow-y: auto;
      padding-right: 4px;
    }

    .alerts-list::-webkit-scrollbar { width: 5px; }
    .alerts-list::-webkit-scrollbar-thumb {
      background: rgba(255, 255, 255, 0.15);
      border-radius: 4px;
    }

    .alert-item {
      padding: 12px 14px;
      border-radius: 10px;
      font-size: 12.5px;
      line-height: 1.45;
      display: flex;
      flex-direction: column;
      gap: 4px;
      background: rgba(255, 255, 255, 0.03);
      border-left: 3px solid;
    }

    .alert-item.DANGER {
      border-color: var(--accent-red);
      background: rgba(239, 68, 68, 0.1);
    }
    .alert-item.WARNING {
      border-color: var(--accent-yellow);
      background: rgba(245, 158, 11, 0.1);
    }
    .alert-item.INFO, .alert-item.SAFE {
      border-color: var(--accent-green);
      background: rgba(16, 185, 129, 0.08);
    }

    .alert-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      font-weight: 700;
    }

    .alert-time {
      font-family: var(--font-mono);
      font-size: 11px;
      color: var(--text-dim);
    }

    .table-details {
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
    }

    .table-details tr {
      border-bottom: 1px solid rgba(255, 255, 255, 0.05);
    }

    .table-details td { padding: 9px 6px; }
    .table-details td:first-child { color: var(--text-muted); width: 42%; }
    .table-details td:last-child {
      font-family: var(--font-mono);
      font-weight: 600;
      text-align: right;
    }
  </style>
</head>
<body>
  <div class="container">
    <!-- Header -->
    <header>
      <div class="brand">
        <div class="brand-icon">⚡</div>
        <div>
          <div class="brand-title">Mac Power Guard</div>
          <div class="brand-subtitle">실시간 전력 공급량 & 하드웨어 전원선 안전 진단 시스템</div>
        </div>
      </div>
      <div class="header-actions no-drag">
        <div id="appModeBadge" class="app-mode-badge" style="display: none;">
          <span>⚡</span> <span>STANDALONE APP</span>
        </div>
        <button id="btnInstallPwa" class="btn btn-install-pwa" style="display: none;" onclick="triggerPwaInstall()">
          <span>📲</span> <span>앱으로 설치</span>
        </button>
        <div class="live-pulse-badge">
          <div class="pulse-dot" id="liveDot"></div>
          <span id="liveStatusText">연결됨 (수신 0회)</span>
        </div>
        <button id="btnSound" class="btn" onclick="toggleSound()">
          <span id="soundIcon">🔔</span> <span id="soundText">경고음 켜기</span>
        </button>
        <button id="btnPause" class="btn" onclick="togglePause()">
          <span id="pauseIcon">⏸</span> <span id="pauseText">일시정지</span>
        </button>
    </header>

    <!-- Server Offline Alert Banner -->
    <div id="serverOfflineBanner" class="server-offline-banner" style="display: none;">
      <div class="offline-icon">⚠️</div>
      <div class="offline-content">
        <div class="offline-title">모니터링 서버 연결 끊김 (백그라운드 서버 미실행)</div>
        <div class="offline-desc">
          하드웨어 텔레메트리 서버가 꺼져 있어 실시간 그래프가 멈추었습니다. 
          <strong>MacPowerGuard.app</strong>을 실행하거나 터미널에서 <code>python3 monitor_power_chart.py</code>를 실행하세요. (서버 시작 시 자동 재연결됩니다)
        </div>
      </div>
    </div>

    <!-- Top 4 Metrics Grid -->
    <div class="grid-stats">
      <!-- 1. Real-time Power Draw -->
      <div class="card">
        <div class="card-top">
          <span class="card-label">실시간 소비 전력</span>
          <div class="card-icon-wrap" style="color: var(--accent-cyan)">⚡</div>
        </div>
        <div class="card-val" id="valPower">
          -- <span class="card-unit">W</span>
        </div>
        <div class="progress-bar-bg">
          <div id="barPowerLoad" class="progress-bar-fill" style="width: 0%"></div>
        </div>
        <div class="card-subtext" id="subtextPower">
          어댑터 정격: -- W (부하율 --%)
        </div>
      </div>

      <!-- 2. Input Voltage & Voltage Drop -->
      <div class="card">
        <div class="card-top">
          <span class="card-label">실시간 인입 전압</span>
          <div class="card-icon-wrap" style="color: var(--accent-green)">🔌</div>
        </div>
        <div class="card-val" id="valVoltage">
          -- <span class="card-unit">V</span>
        </div>
        <div class="progress-bar-bg">
          <div id="barVoltageDrop" class="progress-bar-fill" style="width: 100%; background: var(--accent-green);"></div>
        </div>
        <div class="card-subtext" id="subtextVoltage">
          정격: -- V (전압 강하: -- %)
        </div>
      </div>

      <!-- 3. Current & Battery -->
      <div class="card">
        <div class="card-top">
          <span class="card-label">인입 전류 & 배터리</span>
          <div class="card-icon-wrap" style="color: var(--accent-purple)">🔋</div>
        </div>
        <div class="card-val" id="valCurrent">
          -- <span class="card-unit">A</span>
        </div>
        <div class="card-subtext" id="subtextBattery">
          배터리: --% | 효율: --% | 충전: --
        </div>
      </div>

      <!-- 4. Comprehensive Risk Status Badge -->
      <div class="card card-risk safe" id="cardRisk">
        <div class="card-top">
          <span class="card-label">전력 공급 위험도 판정</span>
          <span class="badge-risk safe" id="badgeRisk">안전 (SAFE)</span>
        </div>
        <div class="card-val" id="valRiskScore">
          0 <span class="card-unit">위험지수 (0~100)</span>
        </div>
        <div class="card-subtext" id="subtextRisk">
          ✓ 전압 강하 및 리플 정상, 스로틀링 없음
        </div>
      </div>
    </div>

    <!-- Dual Native Canvas Charts -->
    <div class="grid-charts">
      <!-- Chart 1: Realtime Power Draw (W) -->
      <div class="chart-card">
        <div class="chart-header">
          <div class="chart-header-row1">
            <div class="chart-title">
              <span>📈</span> 실시간 소비 전력 (W) 파형
            </div>
            <div class="chart-badge-now" id="badgeNowPower" style="color: var(--accent-cyan);">-- W</div>
          </div>
          <div class="chart-header-row2">
            <div class="chart-badge-stat"><span class="badge-lbl">최저</span><span class="badge-val" id="badgeMinPower" style="color: #38bdf8;">-- W</span></div>
            <div class="chart-badge-stat"><span class="badge-lbl">평균</span><span class="badge-val" id="badgeAvgPower" style="color: #cbd5e1;">-- W</span></div>
            <div class="chart-badge-stat"><span class="badge-lbl">최고</span><span class="badge-val" id="badgeMaxPower" style="color: #f59e0b;">-- W</span></div>
          </div>
        </div>
        <div class="canvas-wrapper">
          <canvas id="canvasPower"></canvas>
        </div>
      </div>

      <!-- Chart 2: Realtime Voltage (V) -->
      <div class="chart-card">
        <div class="chart-header">
          <div class="chart-header-row1">
            <div class="chart-title">
              <span>⚡</span> 실시간 인입 전압 (V) 파형
            </div>
            <div class="chart-badge-now" id="badgeNowVoltage" style="color: var(--accent-green);">-- V</div>
          </div>
          <div class="chart-header-row2">
            <div class="chart-badge-stat"><span class="badge-lbl">최저</span><span class="badge-val" id="badgeMinVoltage" style="color: #38bdf8;">-- V</span></div>
            <div class="chart-badge-stat"><span class="badge-lbl">평균</span><span class="badge-val" id="badgeAvgVoltage" style="color: #cbd5e1;">-- V</span></div>
            <div class="chart-badge-stat"><span class="badge-lbl">최고</span><span class="badge-val" id="badgeMaxVoltage" style="color: #f59e0b;">-- V</span></div>
          </div>
        </div>
        <div class="canvas-wrapper">
          <canvas id="canvasVoltage"></canvas>
        </div>
      </div>
    </div>

    <!-- Bottom Details & Alert Feed -->
    <div class="grid-charts">
      <!-- Alerts Feed -->
      <div class="alerts-card">
        <div class="chart-title">
          <span>🛡️</span> 실시간 위험 감지 및 안전 이벤트 피드
        </div>
        <div class="alerts-list" id="alertsList">
          <div class="alert-item SAFE">
            <div class="alert-header">
              <span>시스템 정상 모니터링 활성화</span>
              <span class="alert-time">LIVE</span>
            </div>
            <div>실시간 전력선 안정성 검증 중입니다. 전압 강하, 과부하, 잦은 탈락 발생 시 실시간으로 경고가 기록됩니다.</div>
          </div>
        </div>
      </div>

      <!-- Telemetry Specs -->
      <div class="alerts-card">
        <div class="chart-title">
          <span>⚙️</span> 전원 하드웨어 정밀 진단 정보
        </div>
        <table class="table-details">
          <tr>
            <td>전원 어댑터 종류</td>
            <td id="tdAdapterDesc">--</td>
          </tr>
          <tr>
            <td>어댑터 정격 전압 / 전류</td>
            <td id="tdAdapterSpecs">-- V / -- A</td>
          </tr>
          <tr>
            <td>전력 텔레메트리 에러 수</td>
            <td id="tdTelemetryErrors">0 건 (정상)</td>
          </tr>
          <tr>
            <td>저속 충전(Slow Charging) 제한</td>
            <td id="tdSlowCharging">없음 (정상)</td>
          </tr>
          <tr>
            <td>CPU 전력/서멀 스로틀링</td>
            <td id="tdThrottling">100% 정상</td>
          </tr>
          <tr>
            <td>최근 1분간 연결 끊김 횟수</td>
            <td id="tdDropCount">0 회</td>
          </tr>
        </table>
      </div>
    </div>
  </div>

  <script>
    // =========================================================================
    // 순수 HTML5 Canvas 2D 고성능 차트 렌더러 (외부 라이브러리 불필요)
    // =========================================================================
    class CyberCanvasChart {
      constructor(canvasId, options = {}) {
        this.canvas = document.getElementById(canvasId);
        this.ctx = this.canvas.getContext('2d');
        this.options = Object.assign({
          lineColor: '#06b6d4',
          fillColorStart: 'rgba(6, 182, 212, 0.28)',
          fillColorEnd: 'rgba(6, 182, 212, 0.0)',
          thresholdColor: 'rgba(239, 68, 68, 0.65)',
          unit: 'W',
          minY: 0,
          maxY: 40,
          autoScale: true,
          thresholdValue: null,
          maxPoints: 600
        }, options);

        this.dataPoints = []; // [{ time: '14:20:01', val: 18.5 }]
        this.resize();
        window.addEventListener('resize', () => this.resize());
      }

      resize() {
        const rect = this.canvas.parentElement.getBoundingClientRect();
        const dpr = window.devicePixelRatio || 1;
        this.canvas.width = rect.width * dpr;
        this.canvas.height = rect.height * dpr;
        this.ctx.scale(dpr, dpr);
        this.width = rect.width;
        this.height = rect.height;
        this.draw();
      }

      addData(val, timeStr) {
        if (val === null || val === undefined || isNaN(val)) return;
        this.dataPoints.push({ val: Number(val), time: timeStr });
        if (this.dataPoints.length > this.options.maxPoints) {
          this.dataPoints.shift();
        }
        this.draw();
      }

      setHistory(points) {
        this.dataPoints = points.slice(-this.options.maxPoints);
        this.draw();
      }

      draw() {
        const { ctx, width, height, options } = this;
        if (!width || !height) return;

        ctx.clearRect(0, 0, width, height);

        const padLeft = 45;
        const padRight = 20;
        const padTop = 25;
        const padBottom = 30;

        const chartW = width - padLeft - padRight;
        const chartH = height - padTop - padBottom;

        // Auto Scale Calculate
        let minV = options.minY;
        let maxV = options.maxY;

        if (this.dataPoints.length > 0) {
          const vals = this.dataPoints.map(p => p.val);
          const dataMin = Math.min(...vals);
          const dataMax = Math.max(...vals);

          if (options.autoScale) {
            minV = Math.floor(Math.min(minV, dataMin * 0.95));
            maxV = Math.ceil(Math.max(maxV, dataMax * 1.15));
            if (options.thresholdValue) {
              maxV = Math.max(maxV, options.thresholdValue * 1.05);
            }
          }
        }

        const vRange = Math.max(maxV - minV, 0.001);

        // 1. Draw Grid Lines
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.06)';
        ctx.fillStyle = '#64748b';
        ctx.font = '11px "JetBrains Mono", monospace';
        ctx.textAlign = 'right';
        ctx.textBaseline = 'middle';

        const gridSteps = 4;
        for (let i = 0; i <= gridSteps; i++) {
          const yVal = minV + (vRange * (i / gridSteps));
          const yPos = padTop + chartH - (chartH * (i / gridSteps));

          ctx.beginPath();
          ctx.moveTo(padLeft, yPos);
          ctx.lineTo(width - padRight, yPos);
          ctx.stroke();

          ctx.fillText(yVal.toFixed(yVal < 10 ? 1 : 0) + options.unit, padLeft - 8, yPos);
        }

        // 2. Draw Threshold Line (if any)
        if (options.thresholdValue !== null && options.thresholdValue >= minV && options.thresholdValue <= maxV) {
          const threshY = padTop + chartH - ((options.thresholdValue - minV) / vRange) * chartH;
          ctx.save();
          ctx.strokeStyle = options.thresholdColor;
          ctx.setLineDash([5, 5]);
          ctx.lineWidth = 1.5;
          ctx.beginPath();
          ctx.moveTo(padLeft, threshY);
          ctx.lineTo(width - padRight, threshY);
          ctx.stroke();

          ctx.fillStyle = options.thresholdColor;
          ctx.textAlign = 'left';
          ctx.fillText(`정격 한계 (${options.thresholdValue}${options.unit})`, padLeft + 6, threshY - 8);
          ctx.restore();
        }

        if (this.dataPoints.length === 0) {
          ctx.fillStyle = '#64748b';
          ctx.textAlign = 'center';
          ctx.fillText('데이터 수신 대기 중...', padLeft + chartW / 2, padTop + chartH / 2);
          return;
        }

        // 3. Calculate Coordinates
        const pts = [];
        const n = this.dataPoints.length;
        const xStep = n > 1 ? chartW / (n - 1) : 0;

        for (let i = 0; i < n; i++) {
          const x = padLeft + (n > 1 ? i * xStep : chartW / 2);
          const y = padTop + chartH - ((this.dataPoints[i].val - minV) / vRange) * chartH;
          pts.push({ x, y, val: this.dataPoints[i].val, time: this.dataPoints[i].time });
        }

        // 4. Fill Gradient Under Curve
        const grad = ctx.createLinearGradient(0, padTop, 0, padTop + chartH);
        grad.addColorStop(0, options.fillColorStart);
        grad.addColorStop(1, options.fillColorEnd);

        ctx.beginPath();
        ctx.moveTo(pts[0].x, padTop + chartH);
        for (let i = 0; i < pts.length; i++) {
          ctx.lineTo(pts[i].x, pts[i].y);
        }
        ctx.lineTo(pts[pts.length - 1].x, padTop + chartH);
        ctx.closePath();
        ctx.fillStyle = grad;
        ctx.fill();

        // 5. Draw Curve Line
        ctx.beginPath();
        ctx.moveTo(pts[0].x, pts[0].y);
        for (let i = 1; i < pts.length; i++) {
          // Smooth Bezier Curve
          const prev = pts[i - 1];
          const curr = pts[i];
          const midX = (prev.x + curr.x) / 2;
          ctx.bezierCurveTo(midX, prev.y, midX, curr.y, curr.x, curr.y);
        }
        ctx.strokeStyle = options.lineColor;
        ctx.lineWidth = 2.5;
        ctx.lineJoin = 'round';
        ctx.stroke();

        // 6. Draw Glowing Head Dot
        const lastPt = pts[pts.length - 1];
        ctx.save();
        ctx.beginPath();
        ctx.arc(lastPt.x, lastPt.y, 5.5, 0, Math.PI * 2);
        ctx.fillStyle = '#ffffff';
        ctx.shadowColor = options.lineColor;
        ctx.shadowBlur = 12;
        ctx.fill();
        ctx.restore();

        // 7. Time Ticks at Bottom
        ctx.fillStyle = '#64748b';
        ctx.textAlign = 'center';
        if (n >= 2) {
          ctx.fillText(pts[0].time || '', pts[0].x, padTop + chartH + 18);
          ctx.fillText(lastPt.time || '', lastPt.x, padTop + chartH + 18);
        }
      }
    }

    // =========================================================================
    // 메인 앱 상태 및 폴링 루프
    // =========================================================================
    let isPaused = false;
    let soundEnabled = false;
    let packetCount = 0;
    let audioCtx = null;

    let chartPower = null;
    let chartVoltage = null;

    function playAlertBeep(freq = 550, duration = 0.3) {
      if (!soundEnabled) return;
      try {
        if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        if (audioCtx.state === 'suspended') audioCtx.resume();
        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        osc.type = 'sine';
        osc.frequency.setValueAtTime(freq, audioCtx.currentTime);
        gain.gain.setValueAtTime(0.2, audioCtx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.01, audioCtx.currentTime + duration);
        osc.connect(gain);
        gain.connect(audioCtx.destination);
        osc.start();
        osc.stop(audioCtx.currentTime + duration);
      } catch (e) {
        console.error("Audio error:", e);
      }
    }

    function toggleSound() {
      soundEnabled = !soundEnabled;
      const btn = document.getElementById("btnSound");
      const icon = document.getElementById("soundIcon");
      const text = document.getElementById("soundText");
      if (soundEnabled) {
        icon.textContent = "🔊";
        text.textContent = "경고음 켜짐";
        btn.style.background = "rgba(16, 185, 129, 0.15)";
        btn.style.borderColor = "var(--accent-green)";
        playAlertBeep(880, 0.15);
      } else {
        icon.textContent = "🔔";
        text.textContent = "경고음 켜기";
        btn.style.background = "";
        btn.style.borderColor = "";
      }
    }

    function togglePause() {
      isPaused = !isPaused;
      const text = document.getElementById("pauseText");
      const icon = document.getElementById("pauseIcon");
      const liveBadge = document.getElementById("liveStatusText");
      if (isPaused) {
        text.textContent = "모니터링 재개";
        icon.textContent = "▶";
        liveBadge.textContent = "일시정지됨";
      } else {
        text.textContent = "일시정지";
        icon.textContent = "⏸";
        liveBadge.textContent = `실시간 수신 중 (${packetCount}회)`;
      }
    }

    // UI 업데이트 함수
    function handleIncomingPayload(payload) {
      if (isPaused || !payload) return;

      packetCount++;
      const data = payload.latest || payload;
      const historyList = payload.history || [];

      const now = new Date();
      const timeStr = now.toTimeString().split(' ')[0];

      // Live Badge Flash
      const liveStatusText = document.getElementById("liveStatusText");
      liveStatusText.textContent = `실시간 수신 중 (${packetCount}회 | ${timeStr})`;

      // 1. Power Stat
      const pwr = data.system_power_w !== null ? data.system_power_w.toFixed(1) : '--';
      document.getElementById('valPower').innerHTML = `${pwr} <span class="card-unit">W</span>`;
      document.getElementById('badgeNowPower').textContent = `${pwr} W`;

      const adaptWatts = data.adapter_watts || 0;
      let loadRatio = 0;
      if (adaptWatts > 0 && data.system_power_w !== null) {
        loadRatio = Math.min(100, (data.system_power_w / adaptWatts) * 100);
      }
      document.getElementById('barPowerLoad').style.width = `${loadRatio.toFixed(1)}%`;
      document.getElementById('subtextPower').textContent = 
        `어댑터 정격: ${adaptWatts > 0 ? adaptWatts + ' W' : '미연결'} (부하율 ${loadRatio.toFixed(0)}%)`;

      // 2. Voltage Stat
      const volt = data.system_voltage_v !== null ? data.system_voltage_v.toFixed(2) : '--';
      document.getElementById('valVoltage').innerHTML = `${volt} <span class="card-unit">V</span>`;
      document.getElementById('badgeNowVoltage').textContent = `${volt} V`;

      const adaptV = data.adapter_voltage_v || 0;
      const dropPct = data.voltage_drop_pct !== null ? data.voltage_drop_pct.toFixed(2) : '--';
      document.getElementById('subtextVoltage').textContent = 
        `정격: ${adaptV > 0 ? adaptV.toFixed(1) + ' V' : '배터리'} (전압 강하: ${dropPct}%)`;

      // 3. Current & Battery Stat
      const curr = data.system_current_a !== null ? data.system_current_a.toFixed(2) : '--';
      document.getElementById('valCurrent').innerHTML = `${curr} <span class="card-unit">A</span>`;
      
      const battPct = data.battery_level_pct !== null ? data.battery_level_pct + '%' : '--';
      const maxCap = data.battery_max_capacity_pct !== null ? data.battery_max_capacity_pct + '%' : '--';
      const chgState = data.is_charging ? '충전 중' : (data.external_connected ? '충전 대기' : '방전 중');
      document.getElementById('subtextBattery').textContent = 
        `배터리: ${battPct} | 효율: ${maxCap} | ${chgState}`;

      // 4. Risk Card
      const riskLevel = data.risk_level || 'SAFE';
      const riskScore = data.risk_score || 0;
      const cardRisk = document.getElementById('cardRisk');
      const badgeRisk = document.getElementById('badgeRisk');
      const valRiskScore = document.getElementById('valRiskScore');
      const subtextRisk = document.getElementById('subtextRisk');

      cardRisk.className = 'card card-risk ' + riskLevel.toLowerCase();
      badgeRisk.className = 'badge-risk ' + riskLevel.toLowerCase();

      let badgeLabel = '안전 (SAFE)';
      if (riskLevel === 'CAUTION') badgeLabel = '주의 (CAUTION)';
      if (riskLevel === 'DANGER') {
        badgeLabel = '위험 (DANGER)';
        playAlertBeep(440, 0.4);
      }
      badgeRisk.textContent = badgeLabel;
      valRiskScore.innerHTML = `${riskScore} <span class="card-unit">위험지수 (0~100)</span>`;

      if (data.alerts && data.alerts.length > 0) {
        subtextRisk.textContent = '⚠️ ' + data.alerts[0].title;
      } else {
        subtextRisk.textContent = '✓ 전압 강하 및 리플 정상, 스로틀링 없음';
      }

      // 5. Details Table
      document.getElementById('tdAdapterDesc').textContent = data.adapter_desc || (data.external_connected ? 'AC Charger' : '배터리 전원');
      document.getElementById('tdAdapterSpecs').textContent = adaptV > 0 ? `${adaptV.toFixed(1)} V / ${(data.adapter_current_a || 0).toFixed(2)} A (${adaptWatts}W)` : '미연결';
      document.getElementById('tdTelemetryErrors').textContent = `${data.telemetry_errors || 0} 건 (${data.telemetry_errors === 0 ? '정상' : '오류 감지'})`;
      document.getElementById('tdSlowCharging').textContent = data.slow_charging_reason === 0 ? '없음 (정상 속도)' : `감지됨 (코드: ${data.slow_charging_reason})`;
      
      const therm = data.thermal_info || {};
      const cpuSpeed = therm.cpu_speed_limit || 100;
      document.getElementById('tdThrottling').textContent = cpuSpeed === 100 ? '100% (스로틀링 없음)' : `${cpuSpeed}% (성능 제약 중)`;
      document.getElementById('tdDropCount').textContent = `${data.recent_disconnects || 0} 회`;

      // 6. Push to Canvas Charts
      if (chartPower && data.system_power_w !== null) {
        chartPower.options.thresholdValue = adaptWatts > 0 ? adaptWatts : null;
        chartPower.addData(data.system_power_w, timeStr);
        updateChartBadges(chartPower, 'badgeMinPower', 'badgeAvgPower', 'badgeMaxPower', 'W');
      }

      if (chartVoltage && data.system_voltage_v !== null) {
        chartVoltage.options.thresholdValue = adaptV > 0 ? adaptV : null;
        chartVoltage.addData(data.system_voltage_v, timeStr);
        updateChartBadges(chartVoltage, 'badgeMinVoltage', 'badgeAvgVoltage', 'badgeMaxVoltage', 'V');
      }

      // 7. Alert feed
      if (data.alerts && data.alerts.length > 0) {
        const alertsList = document.getElementById('alertsList');
        data.alerts.forEach(al => {
          const item = document.createElement('div');
          item.className = 'alert-item ' + al.level;
          item.innerHTML = `
            <div class="alert-header">
              <span>${al.title}</span>
              <span class="alert-time">${timeStr}</span>
            </div>
            <div>${al.message}</div>
          `;
          alertsList.insertBefore(item, alertsList.firstChild);
        });
        while (alertsList.children.length > 15) {
          alertsList.removeChild(alertsList.lastChild);
        }
      }
    }

    function updateChartBadges(chart, minId, avgId, maxId, unit) {
      if (!chart || !chart.dataPoints || chart.dataPoints.length === 0) return;
      const vals = chart.dataPoints.map(p => p.val).filter(v => v >= 0);
      if (vals.length === 0) return;
      const minVal = Math.min(...vals);
      const maxVal = Math.max(...vals);
      const avgVal = vals.reduce((a, b) => a + b, 0) / vals.length;
      const dec = unit === 'V' ? 2 : 1;
      const minEl = document.getElementById(minId);
      const avgEl = document.getElementById(avgId);
      const maxEl = document.getElementById(maxId);
      if (minEl) minEl.textContent = `${minVal.toFixed(dec)} ${unit}`;
      if (avgEl) avgEl.textContent = `${avgVal.toFixed(dec)} ${unit}`;
      if (maxEl) maxEl.textContent = `${maxVal.toFixed(dec)} ${unit}`;
    }

    // 초기 히스토리 하이드레이션
    function hydrateHistory(historyList) {
      if (!historyList || historyList.length === 0) return;
      const pPoints = [];
      const vPoints = [];

      historyList.forEach(item => {
        const d = new Date(item.timestamp * 1000);
        const t = d.toTimeString().split(' ')[0];
        if (item.system_power_w !== null) pPoints.push({ val: item.system_power_w, time: t });
        if (item.system_voltage_v !== null) vPoints.push({ val: item.system_voltage_v, time: t });
      });

      if (chartPower && pPoints.length > 0) {
        chartPower.setHistory(pPoints);
        updateChartBadges(chartPower, 'badgeMinPower', 'badgeAvgPower', 'badgeMaxPower', 'W');
      }
      if (chartVoltage && vPoints.length > 0) {
        chartVoltage.setHistory(vPoints);
        updateChartBadges(chartVoltage, 'badgeMinVoltage', 'badgeAvgVoltage', 'badgeMaxVoltage', 'V');
      }
    }

    // 초강력 실시간 폴링 루프 (네트워크 단절 회복력 100%)
    let isHydrated = false;
    let consecutiveFailures = 0;

    function setServerConnectionState(connected) {
      const banner = document.getElementById('serverOfflineBanner');
      const liveDot = document.getElementById('liveDot');
      const liveText = document.getElementById('liveStatusText');

      if (connected) {
        if (consecutiveFailures > 0) {
          console.log("⚡ 서버 재연결 성공!");
        }
        consecutiveFailures = 0;
        if (banner) banner.style.display = 'none';
        if (liveDot) {
          liveDot.style.backgroundColor = 'var(--accent-green)';
          liveDot.style.boxShadow = '0 0 10px var(--accent-green)';
        }
      } else {
        consecutiveFailures++;
        if (consecutiveFailures >= 2) {
          if (banner) banner.style.display = 'flex';
          if (liveDot) {
            liveDot.style.backgroundColor = 'var(--accent-red)';
            liveDot.style.boxShadow = '0 0 10px var(--accent-red)';
          }
          if (liveText && !isPaused) {
            liveText.textContent = `서버 연결 끊김 (재시도 ${consecutiveFailures}회)`;
          }
        }
      }
    }

    async function pollData() {
      try {
        const resp = await fetch('/api/power');
        if (resp.ok) {
          const payload = await resp.json();
          setServerConnectionState(true);
          if (!isHydrated && payload.history) {
            hydrateHistory(payload.history);
            isHydrated = true;
          }
          handleIncomingPayload(payload);
        } else {
          setServerConnectionState(false);
        }
      } catch (err) {
        setServerConnectionState(false);
      } finally {
        setTimeout(pollData, 1000);
      }
    }

    window.addEventListener('DOMContentLoaded', () => {
      chartPower = new CyberCanvasChart('canvasPower', {
        lineColor: '#06b6d4',
        fillColorStart: 'rgba(6, 182, 212, 0.28)',
        fillColorEnd: 'rgba(6, 182, 212, 0.0)',
        unit: 'W',
        minY: 0,
        maxY: 35,
        maxPoints: 600
      });

      chartVoltage = new CyberCanvasChart('canvasVoltage', {
        lineColor: '#10b981',
        fillColorStart: 'rgba(16, 185, 129, 0.25)',
        fillColorEnd: 'rgba(16, 185, 129, 0.0)',
        unit: 'V',
        minY: 18,
        maxY: 21,
        maxPoints: 600
      });

      // 즉시 첫 폴링 시작
      pollData();

      // PWA & Standalone App 모드 감지 및 초기화
      initPwaFeatures();
    });

    // =========================================================================
    // PWA (Progressive Web App) & Standalone Window 시스템
    // =========================================================================
    let deferredPrompt = null;
    const isStandalone = window.matchMedia('(display-mode: standalone)').matches || 
                         window.navigator.standalone === true ||
                         document.referrer.includes('android-app://');

    function initPwaFeatures() {
      const appBadge = document.getElementById('appModeBadge');
      const installBtn = document.getElementById('btnInstallPwa');

      if (isStandalone) {
        if (appBadge) appBadge.style.display = 'inline-flex';
        if (installBtn) installBtn.style.display = 'none';
        console.log('⚡ Mac Power Guard: 독립형 앱 모드(Standalone Window)로 동작 중입니다.');
      } else {
        if (appBadge) appBadge.style.display = 'none';
        if (deferredPrompt && installBtn) {
          installBtn.style.display = 'inline-flex';
        }
      }
    }

    // Chrome, Edge 등에서 앱 설치 프롬프트 발생 시 캡처
    window.addEventListener('beforeinstallprompt', (e) => {
      e.preventDefault();
      deferredPrompt = e;
      const installBtn = document.getElementById('btnInstallPwa');
      if (installBtn && !isStandalone) {
        installBtn.style.display = 'inline-flex';
      }
    });

    window.addEventListener('appinstalled', () => {
      deferredPrompt = null;
      const installBtn = document.getElementById('btnInstallPwa');
      const appBadge = document.getElementById('appModeBadge');
      if (installBtn) installBtn.style.display = 'none';
      if (appBadge) appBadge.style.display = 'inline-flex';
      console.log('⚡ Mac Power Guard PWA 가 macOS 시스템에 성공적으로 설치되었습니다.');
    });

    async function triggerPwaInstall() {
      const installBtn = document.getElementById('btnInstallPwa');
      if (deferredPrompt) {
        deferredPrompt.prompt();
        const { outcome } = await deferredPrompt.userChoice;
        if (outcome === 'accepted') {
          if (installBtn) installBtn.style.display = 'none';
        }
        deferredPrompt = null;
      } else {
        alert(
          "⚡ Mac Power Guard 앱 설치 안내:\\n\\n" +
          "• Google Chrome / MS Edge: 상단 주소창 우측의 [앱 설치] 아이콘을 누르거나, 메뉴(⋮) > [저장 및 공유] > [바로가기 만들기(창으로 열기 체크)]\\n" +
          "• macOS Safari: 상단 메뉴 [파일] > [Dock에 추가...]\\n" +
          "• 단독 창 모드로 바로 실행하려면 터미널에서 python3 monitor_power_chart.py 를 실행하세요."
        );
      }
    }

    // Service Worker 등록
    if ('serviceWorker' in navigator) {
      window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js')
          .then((reg) => console.log('Service Worker 등록 완료:', reg.scope))
          .catch((err) => console.warn('Service Worker 등록 실패 (무시 가능):', err));
      });
    }
  </script>
</body>
</html>
"""


# ==============================================================================
# HTTP Request Handler (REST API, PWA Assets & Native UI)
# ==============================================================================
class PowerDashboardHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send_bytes(self, content: bytes, content_type: str, cache_control: str = "no-cache") -> None:
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", cache_control)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(content)

    def do_HEAD(self) -> None:
        self.do_GET()

    def do_GET(self) -> None:
        path = self.path.split("?")[0]

        if path in ("/", "/index.html"):
            self._send_bytes(DASHBOARD_HTML.encode("utf-8"), "text/html; charset=utf-8")

        elif path == "/manifest.json":
            self._send_bytes(
                MANIFEST_JSON.encode("utf-8"),
                "application/manifest+json; charset=utf-8",
                cache_control="public, max-age=86400",
            )

        elif path == "/sw.js":
            self._send_bytes(
                SERVICE_WORKER_JS.encode("utf-8"),
                "application/javascript; charset=utf-8",
                cache_control="no-cache, must-revalidate",
            )

        elif path == "/icon.svg":
            self._send_bytes(
                ICON_SVG.encode("utf-8"),
                "image/svg+xml",
                cache_control="public, max-age=604800",
            )

        elif path in ("/icon-192.png", "/apple-touch-icon.png"):
            self._send_bytes(
                get_icon_png(192),
                "image/png",
                cache_control="public, max-age=604800",
            )

        elif path == "/icon-512.png":
            self._send_bytes(
                get_icon_png(512),
                "image/png",
                cache_control="public, max-age=604800",
            )

        elif path in ("/favicon.ico", "/favicon.svg"):
            self._send_bytes(
                ICON_SVG.encode("utf-8"),
                "image/svg+xml",
                cache_control="public, max-age=604800",
            )

        elif path.startswith("/api/power"):
            latest = GLOBAL_MONITOR.get_snapshot()
            history = GLOBAL_MONITOR.get_history()
            payload = {
                "latest": latest,
                "history": history,
            }
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self._send_bytes(
                body,
                "application/json; charset=utf-8",
                cache_control="no-cache, no-store, must-revalidate",
            )

        else:
            self.send_error(404, "Not Found")

    def log_message(self, format: str, *args: Any) -> None:
        # 콘솔 로그 억제 (깨끗한 터미널 유지)
        pass


# ==============================================================================
# CLI 터미널 실시간 차트 모드 (--cli)
# ==============================================================================
def run_cli_chart_mode(interval: float = 1.0) -> None:
    """터미널에서 유니코드 바 차트와 스파크라인으로 실시간 전력을 시각화합니다."""
    SPARKS = [" ", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    history_w: Deque[float] = collections.deque(maxlen=40)

    print("\033[2J\033[H", end="")  # 터미널 클리어
    print("=" * 72)
    print(" ⚡ Mac 전력 공급량 실시간 CLI 차트 & 위험도 모니터")
    print("    (종료하려면 Ctrl + C 를 누르세요)")
    print("=" * 72)

    try:
        while True:
            data = GLOBAL_MONITOR.update()
            pwr = data.get("system_power_w") or 0.0
            history_w.append(pwr)

            sys_v = data.get("system_voltage_v") or 0.0
            drop_pct = data.get("voltage_drop_pct") or 0.0
            adapt_w = data.get("adapter_watts") or 100.0
            risk_lvl = data.get("risk_level", "SAFE")
            risk_score = data.get("risk_score", 0)

            # 스파크라인 생성
            min_p = min(history_w)
            max_p = max(max(history_w), 1.0)
            spark_str = ""
            for v in history_w:
                idx = int((v - min_p) / max(max_p - min_p, 0.001) * (len(SPARKS) - 1))
                idx = max(0, min(len(SPARKS) - 1, idx))
                spark_str += SPARKS[idx]

            # 수평 바 게이지 (40칸)
            bar_len = int(min(1.0, pwr / max(adapt_w, 1.0)) * 36)
            bar_str = "█" * bar_len + "░" * (36 - bar_len)

            # 상태 배지
            if risk_lvl == "SAFE":
                status_badge = "\033[92m[ 안전 (SAFE) ]\033[0m"
            elif risk_lvl == "CAUTION":
                status_badge = "\033[93m[ 주의 (CAUTION) ]\033[0m"
            else:
                status_badge = "\033[91m[ 위험 (DANGER) ]\033[0m"

            # 커서 상단 이동 후 다시 그리기
            print("\033[4;1H", end="")
            print(f" • 전력 안정성 상태 : {status_badge} (위험도 지수: {risk_score}/100)            ")
            print(f" • 인입 전압 / 강하 : {sys_v:.2f} V  (전압 강하율: {drop_pct:.2f}%)            ")
            print(f" • 실시간 소비 전력 : {pwr:.1f} W / 정격 {adapt_w:.0f} W  [{bar_str}]")
            print(f" • 전력 추이 (스파크): [{spark_str.ljust(40)}]")
            print("-" * 72)
            
            alerts = data.get("alerts", [])
            if alerts:
                print(f" ⚠️ 최신 감지 알림 : {alerts[0].get('title', '')}                           ")
            else:
                print(" ✔ 전원선 및 충전기 동작 상태 매우 양호함 (이상 없음)        ")

            time.sleep(interval)

    except KeyboardInterrupt:
        print("\n\n모니터링을 종료했습니다.")


# ==============================================================================
# 단독 앱 창(Standalone App Window) 및 브라우저 런처
# ==============================================================================
def launch_dashboard(url: str, force_browser: bool = False) -> str:
    """유튜브 뮤직 스타일의 단독 앱 창(Standalone App Window) 또는 일반 브라우저로 엽니다."""
    if force_browser:
        webbrowser.open(url)
        return "기본 웹 브라우저 탭 (Standard Browser)"

    # macOS에서 단독 앱 창 모드(--app=)를 지원하는 Chromium 계열 브라우저 탐색
    chromium_candidates = [
        "/Applications/Google Chrome.app",
        "/Applications/Microsoft Edge.app",
        "/Applications/Brave Browser.app",
        os.path.expanduser("~/Applications/Google Chrome.app"),
        os.path.expanduser("~/Applications/Microsoft Edge.app"),
    ]

    for app_path in chromium_candidates:
        if os.path.exists(app_path):
            try:
                # -n: 새 인스턴스로 분리, -a: 해당 앱, --args --app=: 주소창/탭 없는 단독 창으로 실행
                subprocess.Popen(
                    ["open", "-na", app_path, "--args", f"--app={url}"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                app_name = os.path.basename(app_path).replace(".app", "")
                return f"단독 앱 창 모드 (Standalone App Window via {app_name})"
            except Exception:
                pass

    # 크로뮴 브라우저가 없거나 실패 시 시스템 기본 브라우저로 오픈
    webbrowser.open(url)
    return "기본 웹 브라우저 탭 (Standard Browser)"


# ==============================================================================
# 메인 엔트리포인트
# ==============================================================================
def main() -> None:
    parser = argparse.ArgumentParser(
        description="Mac 실시간 전력 공급량 차트 및 위험도 판단 시스템",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--cli",
        action="store_true",
        help="브라우저 대신 터미널에서 유니코드 실시간 차트로 실행",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8765,
        help="웹 대시보드 로컬 포트 (기본값: 8765)",
    )
    parser.add_argument(
        "--browser",
        action="store_true",
        help="단독 앱 창 대신 일반 웹 브라우저 탭으로 열기",
    )
    parser.add_argument(
        "--no-browser",
        action="store_true",
        help="웹 서버 시작 시 브라우저/앱 창을 자동으로 열지 않음",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=1.0,
        help="데이터 갱신 주기(초, 기본값: 1.0초)",
    )

    args = parser.parse_args()

    if args.cli:
        run_cli_chart_mode(interval=args.interval)
        return

    # 1. 백그라운드 데이터 샘플링 워커 시작
    bg_thread = threading.Thread(
        target=monitor_background_worker,
        args=(args.interval,),
        daemon=True,
    )
    bg_thread.start()

    # 2. 웹 서버 시작
    server_address = ("127.0.0.1", args.port)
    httpd = ThreadingHTTPServer(server_address, PowerDashboardHandler)
    url = f"http://localhost:{args.port}"

    print("=" * 68)
    print(" ⚡ Mac Power Guard 실시간 전력 모니터링 & 위험 진단 대시보드")
    print("=" * 68)
    print(f" • 대시보드 URL : {url}")
    print(f" • PWA 지원    : 활성화 (주소창 및 헤더의 [앱으로 설치] 버튼 제공)")
    print(f" • 측정 주기    : {args.interval} 초")
    print(" • 브라우저 주소창이나 대시보드의 [앱으로 설치]를 눌러 독(Dock)에 등록할 수 있습니다.")
    print(" • 서버를 종료하려면 언제든 [Ctrl + C] 를 누르세요.")
    print("=" * 68)

    # 3. 단독 앱 창 또는 브라우저 자동 오픈
    if not args.no_browser:
        def _launch() -> None:
            mode_desc = launch_dashboard(url, force_browser=args.browser)
            print(f" • 실행 모드    : {mode_desc}")
            print("-" * 68)

        threading.Timer(0.8, _launch).start()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n웹 대시보드 서버를 종료합니다...")
    finally:
        GLOBAL_MONITOR.is_running = False
        httpd.server_close()


if __name__ == "__main__":
    main()
