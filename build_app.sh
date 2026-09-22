#!/bin/bash
set -e

# ==============================================================================
# Mac Power Guard - SwiftUI 네이티브 앱 빌드 스크립트
# ==============================================================================
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/dist/MacPowerGuard.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
CACHE_DIR="$PROJECT_DIR/.cache"

echo "⚡ [1/4] 빌드 디렉토리 준비 중..."
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$CACHE_DIR"

echo "⚡ [2/4] Info.plist 생성 중..."
cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MacPowerGuard</string>
    <key>CFBundleIdentifier</key>
    <string>com.macpowerguard.monitor</string>
    <key>CFBundleName</key>
    <string>MacPowerGuard</string>
    <key>CFBundleDisplayName</key>
    <string>Mac Power Guard</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>2.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "APPL????" > "$APP_DIR/Contents/PkgInfo"

echo "⚡ [3/4] SwiftUI 네이티브 앱 컴파일 중 (Mach-O arm64)..."
swiftc -module-cache-path "$CACHE_DIR" \
  -parse-as-library \
  -O \
  -target arm64-apple-macos13.0 \
  -o "$MACOS_DIR/MacPowerGuard" \
  "$PROJECT_DIR/MacPowerGuardSwift/Sources/Models.swift" \
  "$PROJECT_DIR/MacPowerGuardSwift/Sources/RiskEvaluator.swift" \
  "$PROJECT_DIR/MacPowerGuardSwift/Sources/TelemetryService.swift" \
  "$PROJECT_DIR/MacPowerGuardSwift/Sources/Views/MetricCardView.swift" \
  "$PROJECT_DIR/MacPowerGuardSwift/Sources/Views/WaveformChartView.swift" \
  "$PROJECT_DIR/MacPowerGuardSwift/Sources/Views/AlertsListView.swift" \
  "$PROJECT_DIR/MacPowerGuardSwift/Sources/Views/HardwareDetailsView.swift" \
  "$PROJECT_DIR/MacPowerGuardSwift/Sources/Views/HeaderView.swift" \
  "$PROJECT_DIR/MacPowerGuardSwift/Sources/Views/DashboardView.swift" \
  "$PROJECT_DIR/MacPowerGuardSwift/Sources/MacPowerGuardApp.swift"

chmod +x "$MACOS_DIR/MacPowerGuard"

# 리소스 복사 (아이콘 등)
if [ -f "$PROJECT_DIR/icon.svg" ]; then
    cp "$PROJECT_DIR/icon.svg" "$RESOURCES_DIR/"
fi
if [ -f "$PROJECT_DIR/icon-512.png" ]; then
    cp "$PROJECT_DIR/icon-512.png" "$RESOURCES_DIR/"
fi

echo "⚡ [4/4] 빌드 완료!"
echo "=================================================================="
echo " ✅ Mac Power Guard 네이티브 SwiftUI 앱이 성공적으로 빌드되었습니다."
echo " 📂 위치 : $APP_DIR"
echo " 🚀 실행 : open \"$APP_DIR\" 또는 더블클릭"
echo "=================================================================="
