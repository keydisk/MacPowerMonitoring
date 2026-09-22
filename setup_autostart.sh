#!/bin/bash
# Mac Power Guard - 백그라운드 자동 실행 서비스 등록 스크립트

PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="$PLIST_DIR/com.macpowerguard.monitor.plist"
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/monitor_power_chart.py"

mkdir -p "$PLIST_DIR"

# 기존 서비스가 실행 중이면 언로드
if launchctl list | grep -q "com.macpowerguard.monitor"; then
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
fi

cat <<EOF > "$PLIST_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.macpowerguard.monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$SCRIPT_PATH</string>
        <string>--no-browser</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/macpowerguard.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/macpowerguard.err</string>
</dict>
</plist>
EOF

launchctl load "$PLIST_FILE"

echo "=================================================================="
echo " ⚡ Mac Power Guard 백그라운드 자동 실행 등록 완료!"
echo "=================================================================="
echo " • 이제 Mac을 부팅할 때마다 모니터링 서버가 조용히 자동 실행됩니다."
echo " • Dock의 PWA 앱 아이콘을 누르면 언제든 즉시 그래프가 표시됩니다."
echo " • 서비스를 중지/삭제하려면 ./uninstall_autostart.sh 를 실행하세요."
echo "=================================================================="
