# ⚡ Mac Power Guard

> **실시간 전력 공급량 & 하드웨어 전원선 안전 진단 시스템**  
> Real-time Power Telemetry, Waveform Monitor & Safety Diagnosis System for macOS

Mac Power Guard는 Apple Silicon 및 Intel Mac의 IOKit 전원 공급 텔레메트리를 실시간으로 분석하여 충전기/케이블의 전압 강하, 과부하, 전력 리플 및 접촉 불량을 감지하고 시각화하는 macOS 네이티브 대시보드 앱입니다.

---

## ✨ 주요 기능 (Key Features)

- 📈 **실시간 전력(W) & 전압(V) 파형 차트**:
  - SwiftUI `Canvas` 2D 엔진 기반 부드러운 베지에 곡선 및 네온 글로우 렌더링
  - 어댑터 정격 전압(`20V`) 대비 인입 전압의 전압 강하 실시간 추적
  - 비정상 전압 튐 및 하단 왜곡 없는 정밀 오토스케일링
- 🛡️ **지능형 위험도 진단 (Safety Risk Score)**:
  - 전압 강하율, 리플 불안정성, 어댑터 과부하율, 잦은 탈락 감지
  - 3단계 위험도 판정 (`SAFE`, `CAUTION`, `DANGER`) 및 실시간 이벤트 알림 피드
- 🔌 **정밀 하드웨어 스펙 모니터링**:
  - 어댑터 정격 와트수, 인입 전압/전류, 배터리 충전 상태 및 사이클 수명
  - 열/전력 스로틀링 및 충전 지연 상태 감지
- 🚀 **100% 네이티브 실행**:
  - 별도 백엔드 서버나 의존성 없이 `dist/MacPowerGuard.app` 독립 실행 가능
  - Python 웹 대시보드 (`monitor_power_chart.py`) 및 CLI 툴 (`check_mac_power.py`) 동시 지원

---

## 🛠️ 빌드 및 실행 방법 (Build & Run)

### 1. 네이티브 macOS 앱 빌드
macOS 13.0 (Ventura) 이상에서 동작하며, 내장 스크립트로 즉시 빌드할 수 있습니다:

```bash
chmod +x build_app.sh
./build_app.sh
```

### 2. 앱 실행
빌드가 완료되면 `dist/MacPowerGuard.app`을 실행합니다:

```bash
open dist/MacPowerGuard.app
```

---

## 📂 프로젝트 구조 (Project Structure)

```
MacPowerMonitoring/
├── MacPowerGuardSwift/           # SwiftUI 네이티브 앱 소스코드
│   └── Sources/
│       ├── Models.swift          # 전력 텔레메트리 및 차트 데이터 모델
│       ├── RiskEvaluator.swift   # 위험도 판정 알고리즘
│       ├── TelemetryService.swift# IOKit 전원 데이터 폴링 서비스
│       ├── MacPowerGuardApp.swift# 앱 진입점
│       └── Views/
│           ├── DashboardView.swift      # 메인 대시보드
│           ├── WaveformChartView.swift  # Canvas 2D 실시간 파형 차트
│           ├── MetricCardView.swift     # 상단 주요 지표 카드
│           ├── AlertsListView.swift     # 안전 진단 이벤트 피드
│           └── HardwareDetailsView.swift# 하드웨어 스펙 상세 테이블
├── build_app.sh                  # 네이티브 앱 컴파일 빌드 스크립트
├── dist/                         # 빌드된 배포용 .app 번들
├── check_mac_power.py            # CLI 기반 전력 진단 스크립트
├── monitor_power_chart.py        # Web/PWA 기반 대시보드
└── README.md
```

---

## 📄 라이선스 (License)

MIT License
