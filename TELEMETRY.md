# 확장 텔레메트리

앱과 메뉴 막대는 하나의 TelemetryService를 공유한다. 메뉴 막대는 기본적으로 시스템 소비 전력(W), CPU 사용률(%), GPU 사용률(%)을 간결하게 표시하며, 각 항목은 메뉴에서 켜고 끌 수 있다. 메뉴 막대 자체는 앱 설정에서 숨기거나 다시 켤 수 있다.

## 데이터 출처와 의미

- 공급 전력: AppleSmartBattery / PowerTelemetryData / SystemPowerIn (mW → W). 외부 전원 연결 및 필드가 있을 때만 표시.
- 시스템 소비 전력: SystemLoad (mW → W). 칩셋 패키지 전력 또는 보드의 모든 레일을 별도로 합산한 값이 아니며, 센서 필드가 없으면 표시하지 않는다.
- 배터리 충·방전: 팩 Voltage (mV) × signed InstantAmperage 또는 Amperage (mA). + 충전, − 방전. 어댑터 입력과 시스템 소비의 차이를 임의로 배터리 충전 전력으로 간주하지 않는다.
- 배터리 성능: 공칭 최대 용량 / 설계 용량, 100% 상한. 용량 원본도 mAh로 노출.
- 배터리 온도: AppleSmartBatteryPack / BatteryData / Temperature (0.1 K → °C). 유효 범위 밖 또는 누락 값은 미표시.
- 셀 그룹 전압: AppleSmartBatteryBank / BatteryData / CellVoltage (mV → V). 개별 물리 셀의 온도나 전류를 의미하지 않는다.
- USB 출력: PowerOutDetails / Watts (이 레코드의 단위는 mW), 노출되는 포트들의 합계.
- CPU: HOST_CPU_LOAD_INFO의 전후 tick 차이로 전체 코어 사용률을 0~100%로 정규화. 첫 샘플은 비교 대상이 없어 -- 표시.
- GPU: IOAccelerator / PerformanceStatistics / Device Utilization %. Renderer와 Tiler도 별도로 표시. 복수 장치에서는 사용률이 가장 높은 장치의 값을 선택하며, 드라이버가 필드를 제공하지 않거나 접근이 거부되면 -- 표시. 샘플 간 평균 CPU 사용률과 드라이버 GPU 사용률은 시간 창이 다를 수 있다.
- 열 상태: 공개 ProcessInfo.thermalState의 Nominal / Fair / Serious / Critical. 온도 센서나 powermetrics의 pressure 단계와 같은 값으로 간주하지 않는다.

모든 차트는 앱 실행 전체의 유효 샘플을 대상으로 LTTB 다운샘플링 후 단조 cubic Hermite 곡선을 그린다. 측정점과 구간별 최저·최고를 유지하고, 0% 및 배터리 음수 전력을 제외하지 않는다.

## 현재 수집하지 않는 항목

CPU E/P·GPU·ANE·DRAM·SoC 도메인별 전력, 디스플레이/백라이트 전력, CPU/GPU/충전 컨트롤러 온도 및 팬 RPM은 현재 App Store 배포에서 수집하지 않는다. powermetrics는 관리자 권한이 필요하며, IOReport·SMC 인터페이스는 현재 공개 SDK 기반 구현에 포함하지 않았다. 이 항목들은 센서 접근 상태 패널에서 이유를 표시한다. 앱은 sudo나 권한 상승 도우미를 설치하지 않는다.

## 확인

tests/ExtendedTelemetryCheck.swift: 전력 분리, signed 전류, 온도 단위, 누락 센서, CPU tick wrap, GPU 범위 검증, 곡선 제어점 경계 검사.
tests/LiveTelemetryCheck.swift: 실제 장치 읽기 검사. CPU/GPU %, 공급·시스템·배터리 W, 온도와 그룹 전압만 출력한다. 식별자는 출력하지 않는다.

실제 장치 읽기는 일반 실행에서 확인했다. 서명된 App Sandbox GUI에서 메뉴 막대 및 센서 접근까지의 최종 확인은 별도로 필요하다.
