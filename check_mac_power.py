#!/usr/bin/env python3
"""
Mac 전력 공급 안정성 진단 및 실시간 모니터링 스크립트 (check_mac_power.py)

macOS의 IOKit(AppleSmartBattery) 및 pmset을 활용하여
현재 맥의 전원 공급 상태, 충전기 정격, 실시간 인입 전압/전류, 전압 강하율,
서멀/전력 스로틀링 및 전력 텔레메트리 에러를 종합 진단합니다.
"""

from __future__ import annotations

import argparse
import json
import math
import plistlib
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional, Tuple


# ==============================================================================
# 터미널 컬러 ANSI 코드
# ==============================================================================
class Colors:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    CYAN = "\033[96m"
    BLUE = "\033[94m"
    GRAY = "\033[90m"


def colorize(text: str, color: str) -> str:
    if not sys.stdout.isatty():
        return text
    return f"{color}{text}{Colors.RESET}"


# ==============================================================================
# 시스템 정보 수집 함수 (IOKit & pmset)
# ==============================================================================
def get_iokit_battery_data() -> Optional[Dict[str, Any]]:
    """IOKit AppleSmartBattery에서 배터리 및 전원 공급 상세 정보를 가져옵니다."""
    try:
        proc = subprocess.run(
            ["ioreg", "-arn", "AppleSmartBattery"],
            capture_output=True,
            check=True,
            timeout=5.0,
        )
        if not proc.stdout:
            return None
        parsed = plistlib.loads(proc.stdout)
        if isinstance(parsed, list) and len(parsed) > 0 and isinstance(parsed[0], dict):
            return parsed[0]
        if isinstance(parsed, dict):
            return parsed
        return None
    except Exception:
        return None


def get_pmset_batt_info() -> Dict[str, Any]:
    """pmset -g batt 명령 결과를 파싱합니다."""
    info: Dict[str, Any] = {"power_source": "Unknown", "is_ac": False, "raw": ""}
    try:
        proc = subprocess.run(
            ["pmset", "-g", "batt"],
            capture_output=True,
            text=True,
            check=True,
            timeout=5.0,
        )
        raw = proc.stdout.strip()
        info["raw"] = raw
        if "AC Power" in raw:
            info["power_source"] = "AC Power"
            info["is_ac"] = True
        elif "Battery Power" in raw:
            info["power_source"] = "Battery Power"
            info["is_ac"] = False
    except Exception:
        pass
    return info


def get_pmset_adapter_info() -> Dict[str, Any]:
    """pmset -g adapter 명령 결과를 파싱합니다."""
    adapter_info: Dict[str, Any] = {}
    try:
        proc = subprocess.run(
            ["pmset", "-g", "adapter"],
            capture_output=True,
            text=True,
            check=True,
            timeout=5.0,
        )
        for line in proc.stdout.splitlines():
            line = line.strip()
            if "=" in line:
                k, v = line.split("=", 1)
                adapter_info[k.strip().lower()] = v.strip()
    except Exception:
        pass
    return adapter_info


def get_pmset_thermal_info() -> Dict[str, Any]:
    """pmset -g therm 명령 결과를 파싱하여 서멀/전력 스로틀링 여부를 확인합니다."""
    therm_info: Dict[str, Any] = {
        "has_thermal_warning": False,
        "has_performance_warning": False,
        "has_cpu_power_warning": False,
        "cpu_speed_limit": 100,
        "details": [],
    }
    try:
        proc = subprocess.run(
            ["pmset", "-g", "therm"],
            capture_output=True,
            text=True,
            check=True,
            timeout=5.0,
        )
        raw = proc.stdout.strip()
        for line in raw.splitlines():
            line = line.strip()
            if not line:
                continue
            therm_info["details"].append(line)
            if "No thermal warning level has been recorded" in line:
                continue
            elif "thermal warning" in line.lower():
                therm_info["has_thermal_warning"] = True

            if "No performance warning level has been recorded" in line:
                continue
            elif "performance warning" in line.lower():
                therm_info["has_performance_warning"] = True

            if "No CPU power status has been recorded" in line:
                continue
            elif "cpu power" in line.lower():
                therm_info["has_cpu_power_warning"] = True

            if "CPU_Speed_Limit" in line and "=" in line:
                try:
                    limit = int(line.split("=")[1].strip())
                    therm_info["cpu_speed_limit"] = limit
                except ValueError:
                    pass
    except Exception:
        pass
    return therm_info


# ==============================================================================
# 전력 안정성 진단 데이터 클래스/함수
# ==============================================================================
def sample_power_telemetry() -> Dict[str, Any]:
    """현재 시점의 전력 및 전압/전류 상태를 스냅샷으로 추출합니다."""
    iokit = get_iokit_battery_data()
    pmset_batt = get_pmset_batt_info()
    pmset_adapter = get_pmset_adapter_info()
    pmset_therm = get_pmset_thermal_info()

    # 기본값 설정
    is_ac = pmset_batt.get("is_ac", False)
    external_connected = is_ac

    adapter_watts: Optional[float] = None
    adapter_voltage_v: Optional[float] = None
    adapter_current_a: Optional[float] = None
    adapter_desc: str = "Unknown"

    system_voltage_v: Optional[float] = None
    system_current_a: Optional[float] = None
    system_power_w: Optional[float] = None
    telemetry_errors: int = 0

    slow_charging_reason: int = 0
    thermal_limited_sec: int = 0
    is_charging: bool = False

    battery_level_pct: Optional[int] = None
    battery_max_capacity_pct: Optional[int] = None
    battery_cycle_count: Optional[int] = None

    if iokit:
        if "ExternalConnected" in iokit:
            external_connected = bool(iokit.get("ExternalConnected", False))

        # 어댑터 정보
        adapter_details = iokit.get("AdapterDetails")
        if isinstance(adapter_details, dict):
            if "Watts" in adapter_details:
                adapter_watts = float(adapter_details["Watts"])
            if "AdapterVoltage" in adapter_details:
                adapter_voltage_v = float(adapter_details["AdapterVoltage"]) / 1000.0
            if "Current" in adapter_details:
                adapter_current_a = float(adapter_details["Current"]) / 1000.0
            if "Description" in adapter_details:
                adapter_desc = str(adapter_details["Description"])

        # 실시간 텔레메트리 정보
        telemetry = iokit.get("PowerTelemetryData")
        if isinstance(telemetry, dict):
            if "SystemVoltageIn" in telemetry:
                system_voltage_v = float(telemetry["SystemVoltageIn"]) / 1000.0
            if "SystemCurrentIn" in telemetry:
                system_current_a = float(telemetry["SystemCurrentIn"]) / 1000.0
            if "SystemPowerIn" in telemetry:
                system_power_w = float(telemetry["SystemPowerIn"]) / 1000.0
            if "PowerTelemetryErrorCount" in telemetry:
                telemetry_errors = int(telemetry["PowerTelemetryErrorCount"])

        # 충전기 데이터
        charger_data = iokit.get("ChargerData")
        if isinstance(charger_data, dict):
            slow_charging_reason = int(charger_data.get("SlowChargingReason", 0))
            thermal_limited_sec = int(charger_data.get("TimeChargingThermallyLimited", 0))
            is_charging = bool(charger_data.get("IsCharging", 0))

        # 배터리 데이터
        battery_data = iokit.get("BatteryData")
        if isinstance(battery_data, dict):
            if "CurrentCapacity" in battery_data:
                battery_level_pct = int(battery_data["CurrentCapacity"])
            if "MaxCapacity" in battery_data:
                battery_max_capacity_pct = int(battery_data["MaxCapacity"])

        if "CycleCount" in iokit:
            battery_cycle_count = int(iokit["CycleCount"])

    # IOKit에서 어댑터 정보를 못 가져온 경우 pmset adapter로 보완
    if adapter_watts is None and "wattage" in pmset_adapter:
        try:
            val_str = pmset_adapter["wattage"].replace("W", "").strip()
            adapter_watts = float(val_str)
        except ValueError:
            pass

    if adapter_voltage_v is None and "voltage" in pmset_adapter:
        try:
            val_mv = float(pmset_adapter["voltage"].replace("mV", "").strip())
            adapter_voltage_v = val_mv / 1000.0
        except ValueError:
            pass

    # 전압 강하 계산 (정격 전압 vs 실제 인입 전압)
    voltage_drop_pct: Optional[float] = None
    voltage_drop_v: Optional[float] = None
    if adapter_voltage_v and system_voltage_v and adapter_voltage_v > 0:
        voltage_drop_v = adapter_voltage_v - system_voltage_v
        voltage_drop_pct = (voltage_drop_v / adapter_voltage_v) * 100.0

    return {
        "timestamp": time.time(),
        "external_connected": external_connected,
        "is_ac": is_ac,
        "adapter_watts": adapter_watts,
        "adapter_voltage_v": adapter_voltage_v,
        "adapter_current_a": adapter_current_a,
        "adapter_desc": adapter_desc,
        "system_voltage_v": system_voltage_v,
        "system_current_a": system_current_a,
        "system_power_w": system_power_w,
        "voltage_drop_v": voltage_drop_v,
        "voltage_drop_pct": voltage_drop_pct,
        "telemetry_errors": telemetry_errors,
        "slow_charging_reason": slow_charging_reason,
        "thermal_limited_sec": thermal_limited_sec,
        "is_charging": is_charging,
        "battery_level_pct": battery_level_pct,
        "battery_max_capacity_pct": battery_max_capacity_pct,
        "battery_cycle_count": battery_cycle_count,
        "thermal_info": pmset_therm,
    }


def evaluate_stability(data: Dict[str, Any]) -> Tuple[str, int, List[str], List[str]]:
    """
    수집된 전력 데이터를 평가하여 종합 안정성 판정 및 점수(100점 만점)를 산출합니다.

    Returns:
        status: "STABLE", "WARNING", "UNSTABLE"
        score: 0 ~ 100
        positives: 안정적 근거 목록
        warnings: 경고 및 주의 항목 목록
    """
    score = 100
    positives: List[str] = []
    warnings: List[str] = []

    # 1. 전원 공급원 검사
    if not data["external_connected"]:
        score -= 20
        warnings.append("AC 전원 어댑터가 연결되어 있지 않고 배터리 전원으로 동작 중입니다.")
    else:
        positives.append("AC 전원 어댑터가 정상적으로 연결되어 있습니다.")

    # 2. 어댑터 정격 검사
    watts = data.get("adapter_watts")
    if watts is not None:
        if watts >= 60:
            positives.append(f"충분한 정격 출력의 어댑터({watts:.0f}W)가 체결되어 있습니다.")
        elif watts >= 30:
            positives.append(f"중형 정격 어댑터({watts:.0f}W)가 연결되어 있습니다.")
        else:
            score -= 15
            warnings.append(f"저출력 어댑터({watts:.0f}W) 연결 감지: 고부하 작업 시 전력이 부족할 수 있습니다.")

    # 3. 전압 강하율 검사 (가장 중요한 안정성 지표)
    drop_pct = data.get("voltage_drop_pct")
    sys_v = data.get("system_voltage_v")
    adapt_v = data.get("adapter_voltage_v")

    if drop_pct is not None and sys_v is not None and adapt_v is not None:
        if drop_pct <= 2.5:
            positives.append(f"정격 전압({adapt_v:.1f}V) 대비 실시간 인입 전압({sys_v:.2f}V)의 전압 강하가 {drop_pct:.2f}%로 매우 우수합니다.")
        elif drop_pct <= 5.0:
            positives.append(f"전압 강하({drop_pct:.2f}%)가 정상 허용 범위(5% 이내)에 있습니다.")
        elif drop_pct <= 8.0:
            score -= 20
            warnings.append(f"전압 강하가 {drop_pct:.2f}%로 다소 높습니다 (케이블 저항 또는 접촉 상태 점검 권장).")
        else:
            score -= 40
            warnings.append(f"심각한 전압 강하 감지({drop_pct:.2f}%): 충전기 또는 케이블 접촉 불량 위험이 있습니다.")

    # 4. 텔레메트리 에러 검사
    err_count = data.get("telemetry_errors", 0)
    if err_count == 0:
        positives.append("IOKit 전력 텔레메트리 에러 발생 0건 (정상).")
    else:
        score -= min(30, err_count * 10)
        warnings.append(f"전력 텔레메트리 에러 {err_count}회 발생.")

    # 5. 저속 충전 플래그 검사
    slow_reason = data.get("slow_charging_reason", 0)
    if slow_reason == 0:
        positives.append("저속 충전(Slow Charging) 제한 없음 (정상 속도 전력 인입).")
    else:
        score -= 25
        warnings.append(f"저속 충전 플래그 감지 (SlowChargingReason={slow_reason}): 공급 전력이 부족합니다.")

    # 6. 서멀 및 전력 스로틀링 검사
    therm = data.get("thermal_info", {})
    if therm.get("has_thermal_warning") or therm.get("has_cpu_power_warning"):
        score -= 25
        warnings.append("시스템 서멀/전력 경고가 감지되었습니다. 발열 또는 전력 한계로 인한 스로틀링 위험이 있습니다.")
    else:
        positives.append("전력/서멀 스로틀링 경고 없음 (클린 상태).")

    cpu_speed = therm.get("cpu_speed_limit", 100)
    if cpu_speed < 100:
        score -= 20
        warnings.append(f"CPU 속도 제한 발생: 현재 최대치의 {cpu_speed}%로 제한 중입니다.")

    score = max(0, min(100, score))

    if score >= 85 and not warnings:
        status = "STABLE"
    elif score >= 65:
        status = "WARNING"
    else:
        status = "UNSTABLE"

    return status, score, positives, warnings


# ==============================================================================
# 리포트 출력 함수
# ==============================================================================
def print_diagnostic_report(data: Dict[str, Any]) -> None:
    """단발 진단 결과 리포트를 터미널에 미려하게 출력합니다."""
    status, score, positives, warnings = evaluate_stability(data)

    status_badge = {
        "STABLE": colorize("[ 안정 (STABLE) ]", Colors.GREEN),
        "WARNING": colorize("[ 주의 (WARNING) ]", Colors.YELLOW),
        "UNSTABLE": colorize("[ 불안정 (UNSTABLE) ]", Colors.RED),
    }.get(status, status)

    print("=" * 68)
    print(colorize(" ⚡ Mac 전력 공급 안정성 종합 진단 리포트", Colors.BOLD + Colors.CYAN))
    print("=" * 68)

    # 1. 종합 상태
    print(f" • 종합 판정      : {status_badge}  (안정성 점수: {score}/100점)")
    power_src_str = "AC 전원 어댑터 연결됨" if data["external_connected"] else "배터리 전원 사용 중 (어댑터 미연결)"
    print(f" • 현재 전원 상태 : {colorize(power_src_str, Colors.BOLD)}")

    # 2. 어댑터 사양
    print("-" * 68)
    print(colorize(" 🔌 충전기(어댑터) 정격 및 입력 프로파일", Colors.BOLD))
    watts = data.get("adapter_watts")
    adapt_v = data.get("adapter_voltage_v")
    adapt_a = data.get("adapter_current_a")
    desc = data.get("adapter_desc", "Unknown")

    watts_str = f"{watts:.0f} W" if watts is not None else "정보 없음"
    adapt_v_str = f"{adapt_v:.1f} V" if adapt_v is not None else "정보 없음"
    adapt_a_str = f"{adapt_a:.2f} A" if adapt_a is not None else "정보 없음"

    print(f" • 어댑터 종류    : {desc}")
    print(f" • 정격 전력      : {colorize(watts_str, Colors.GREEN if watts and watts >= 60 else Colors.YELLOW)}")
    print(f" • 정격 전압/전류 : {adapt_v_str} / {adapt_a_str}")

    # 3. 실시간 전압/전류/전력 & 전압 강하율
    print("-" * 68)
    print(colorize(" 📊 실시간 전력 인입 및 전압 안정성 지표", Colors.BOLD))
    sys_v = data.get("system_voltage_v")
    sys_a = data.get("system_current_a")
    sys_w = data.get("system_power_w")
    drop_v = data.get("voltage_drop_v")
    drop_pct = data.get("voltage_drop_pct")

    sys_v_str = f"{sys_v:.2f} V" if sys_v is not None else "N/A"
    sys_a_str = f"{sys_a:.2f} A" if sys_a is not None else "N/A"
    sys_w_str = f"{sys_w:.1f} W" if sys_w is not None else "N/A"

    print(f" • 실시간 인입 전압 : {colorize(sys_v_str, Colors.CYAN)} (정격 대비)")
    print(f" • 실시간 인입 전류 : {sys_a_str}")
    print(f" • 실시간 소비 전력 : {colorize(sys_w_str, Colors.CYAN)}")

    if drop_pct is not None and drop_v is not None:
        drop_color = Colors.GREEN if drop_pct <= 3.0 else (Colors.YELLOW if drop_pct <= 5.0 else Colors.RED)
        print(f" • 실시간 전압 강하 : {colorize(f'{drop_v:.3f} V ({drop_pct:.2f}%)', drop_color)}")
        if drop_pct <= 3.0:
            print(f"   ↳ {colorize('✓ 케이블 및 전원선 전압 강하가 3% 이하로 매우 안정적입니다.', Colors.GRAY)}")
        elif drop_pct <= 5.0:
            print(f"   ↳ {colorize('✓ 전압 강하가 일반 허용 기준(5% 이내)에 부합합니다.', Colors.GRAY)}")
        else:
            print(f"   ↳ {colorize('⚠️ 전압 강하가 기준치를 초과했습니다. 케이블 저항 또는 접촉 상태 점검이 권장됩니다.', Colors.YELLOW)}")

    # 4. 배터리 및 보호 상태
    print("-" * 68)
    print(colorize(" 🔋 배터리 헬스 및 충전 제어 상태", Colors.BOLD))
    batt_pct = data.get("battery_level_pct")
    max_cap = data.get("battery_max_capacity_pct")
    cycle = data.get("battery_cycle_count")
    charging = data.get("is_charging")

    batt_str = f"{batt_pct}%" if batt_pct is not None else "N/A"
    health_str = f"{max_cap}%" if max_cap is not None else "N/A"
    cycle_str = f"{cycle} 회" if cycle is not None else "N/A"
    charge_state_str = "충전 중" if charging else "충전 대기 / 완충 (전원 공급 유지)"

    print(f" • 배터리 잔량    : {batt_str} ({charge_state_str})")
    print(f" • 배터리 수명효율 : {health_str} (사이클: {cycle_str})")

    # 5. 서멀 및 시스템 스로틀링
    therm = data.get("thermal_info", {})
    cpu_speed = therm.get("cpu_speed_limit", 100)
    therm_status_str = "정상 (스로틀링 없음)" if cpu_speed == 100 and not therm.get("has_thermal_warning") else "경고 (전력/발열 제약 감지)"
    print(f" • CPU 전력 제약  : {colorize(therm_status_str, Colors.GREEN if cpu_speed == 100 else Colors.RED)}")

    # 6. 세부 평가 결과 요약
    print("=" * 68)
    print(colorize(" 📋 세부 진단 결과 요약", Colors.BOLD))
    for p in positives:
        print(f"  {colorize('✔', Colors.GREEN)} {p}")
    for w in warnings:
        print(f"  {colorize('✖', Colors.YELLOW if status == 'WARNING' else Colors.RED)} {w}")

    print("=" * 68)


# ==============================================================================
# 실시간 모니터링 모드 (--watch / --duration)
# ==============================================================================
def run_monitoring_session(interval: float = 1.0, duration: Optional[float] = None) -> None:
    """일정 시간 또는 사용자가 중단할 때까지 전력 공급 안정성을 실시간으로 감시합니다."""
    print(colorize(f"🚀 실시간 Mac 전력 모니터링을 시작합니다... (측정 주기: {interval}초)", Colors.BOLD + Colors.CYAN))
    if duration:
        print(colorize(f"⏱  설정된 지속 시간: {duration}초 동안 집중 샘플링합니다.", Colors.GRAY))
    else:
        print(colorize("종료하려면 언제든 Ctrl+C 를 누르세요.", Colors.GRAY))
    print("-" * 75)
    print(f"{'시간':^8} | {'전원':^8} | {'인입 전압':^10} | {'전압강하':^12} | {'인입 전류':^9} | {'소비 전력':^9} | {'상태':^8}")
    print("-" * 75)

    samples: List[Dict[str, Any]] = []
    start_time = time.time()
    drop_count = 0
    was_connected: Optional[bool] = None

    try:
        while True:
            sample = sample_power_telemetry()
            samples.append(sample)

            now_str = time.strftime("%H:%M:%S")
            conn = sample["external_connected"]
            if was_connected is not None and was_connected and not conn:
                drop_count += 1
            was_connected = conn

            pwr_str = "AC" if conn else "BATT"
            sys_v = sample.get("system_voltage_v")
            drop_pct = sample.get("voltage_drop_pct")
            sys_a = sample.get("system_current_a")
            sys_w = sample.get("system_power_w")

            v_str = f"{sys_v:.2f} V" if sys_v is not None else "--"
            drop_str = f"{drop_pct:.2f} %" if drop_pct is not None else "--"
            a_str = f"{sys_a:.2f} A" if sys_a is not None else "--"
            w_str = f"{sys_w:.1f} W" if sys_w is not None else "--"

            stat_badge = colorize("정상", Colors.GREEN)
            if not conn:
                stat_badge = colorize("배터리", Colors.YELLOW)
            elif drop_pct is not None and drop_pct > 5.0:
                stat_badge = colorize("강하주의", Colors.YELLOW)

            print(f"{now_str:^8} | {pwr_str:^8} | {v_str:^10} | {drop_str:^12} | {a_str:^9} | {w_str:^9} | {stat_badge:^8}")

            if duration and (time.time() - start_time) >= duration:
                break
            time.sleep(interval)

    except KeyboardInterrupt:
        print("\n" + colorize("사용자에 의해 모니터링이 중단되었습니다.", Colors.YELLOW))

    # 모니터링 통계 요약 분석
    if not samples:
        return

    voltages = [s["system_voltage_v"] for s in samples if s.get("system_voltage_v") is not None]
    powers = [s["system_power_w"] for s in samples if s.get("system_power_w") is not None]
    drops = [s["voltage_drop_pct"] for s in samples if s.get("voltage_drop_pct") is not None]

    print("\n" + "=" * 68)
    print(colorize(" 📈 모니터링 통계 및 전력선 변동성(리플) 분석 요약", Colors.BOLD + Colors.CYAN))
    print("=" * 68)
    print(f" • 총 샘플 수        : {len(samples)} 회")
    print(f" • 전원 탈락(Drop) 횟수: {drop_count} 회")

    if voltages:
        mean_v = sum(voltages) / len(voltages)
        min_v = min(voltages)
        max_v = max(voltages)
        v_diff = max_v - min_v
        variance = sum((x - mean_v) ** 2 for x in voltages) / len(voltages)
        std_dev = math.sqrt(variance)

        print(f" • 평균 인입 전압    : {mean_v:.3f} V")
        print(f" • 전압 변동폭 (ΔV)  : {v_diff:.3f} V  (최소 {min_v:.3f}V ~ 최대 {max_v:.3f}V)")
        print(f" • 전압 표준편차     : {std_dev:.4f} V")

        if std_dev < 0.05:
            jitter_msg = colorize("극히 안정적 (전압 흔들림 거의 없음)", Colors.GREEN)
        elif std_dev < 0.15:
            jitter_msg = colorize("안정적 (정상적인 부하 변동 범위)", Colors.GREEN)
        elif std_dev < 0.30:
            jitter_msg = colorize("주의 (전압 출렁임 다소 발생)", Colors.YELLOW)
        else:
            jitter_msg = colorize("불안정 (전압 변동성 높음 - 전원선 점검 요망)", Colors.RED)

        print(f" • 전원선 안정성 평결: {jitter_msg}")

    if drops:
        avg_drop = sum(drops) / len(drops)
        print(f" • 평균 전압 강하율  : {avg_drop:.2f} %")

    if powers:
        avg_w = sum(powers) / len(powers)
        max_w = max(powers)
        print(f" • 평균/최대 소비전력: {avg_w:.1f} W / {max_w:.1f} W")

    print("=" * 68)


# ==============================================================================
# 메인 CLI 엔트리포인트
# ==============================================================================
def main() -> None:
    parser = argparse.ArgumentParser(
        description="Mac 전력 공급 안정성 실시간 진단 도구",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "-w",
        "--watch",
        action="store_true",
        help="실시간 전력 모니터링 모드로 실행 (주기적으로 전압/전류/소비전력 갱신)",
    )
    parser.add_argument(
        "-d",
        "--duration",
        type=float,
        default=None,
        help="실시간 모니터링 지속 시간 (초 단위, 예: --duration 10)",
    )
    parser.add_argument(
        "-i",
        "--interval",
        type=float,
        default=1.0,
        help="모니터링 측정 간격 (초 단위, 기본값: 1.0초)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="진단 결과를 JSON 형식으로 출력",
    )

    args = parser.parse_args()

    if args.watch or args.duration is not None:
        run_monitoring_session(interval=args.interval, duration=args.duration)
    else:
        data = sample_power_telemetry()
        if args.json:
            status, score, positives, warnings = evaluate_stability(data)
            data["verdict"] = {
                "status": status,
                "score": score,
                "positives": positives,
                "warnings": warnings,
            }
            print(json.dumps(data, indent=2, ensure_ascii=False))
        else:
            print_diagnostic_report(data)


if __name__ == "__main__":
    main()
