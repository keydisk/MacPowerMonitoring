#!/bin/bash
# Mac Power Guard - 백그라운드 자동 실행 서비스 제거 스크립트

PLIST_FILE="$HOME/Library/LaunchAgents/com.macpowerguard.monitor.plist"

if [ -f "$PLIST_FILE" ]; then
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    rm -f "$PLIST_FILE"
    echo "=================================================================="
    echo " ⚡ Mac Power Guard 백그라운드 자동 실행이 해제되었습니다."
    echo "=================================================================="
else
    echo "등록된 백그라운드 서비스가 없습니다."
fi
