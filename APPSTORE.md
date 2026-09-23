# App Store 출시 체크리스트

## 이미 준비된 것 (이 저장소)
- 7개 언어 현지화: `MacPowerGuardSwift/Resources/Localizable.xcstrings` (ko, en, ja, zh-Hans, de, fr, es). 없는 언어는 영어로 표시
- 서명: Automatic, Team `BXAD9Q3TC8` (`project.yml` 에 고정 — `xcodegen generate` 후에도 유지)
- App Sandbox + Hardened Runtime: `MacPowerGuardSwift/MacPowerGuard.entitlements`
- 개인정보 매니페스트: `MacPowerGuardSwift/Resources/PrivacyInfo.xcprivacy` (systemUptime 사용 사유 35F9.1)
- Info.plist: 카테고리(Utilities), 암호화 미사용(`ITSAppUsesNonExemptEncryption = NO`), 빌드 번호 `1`
- 스토어 메타데이터(7개 언어): `fastlane/metadata/<locale>/` — 이름·부제·키워드·프로모션 문구·설명·URL
- 심사 메모: `fastlane/metadata/review_information/notes.txt`
- 스크린샷(2880×1800): `fastlane/screenshots/ko/`
- 지원/개인정보 웹페이지 + AdSense: `docs/` (GitHub Pages)

## 직접 해야 하는 것
1. **바꿀 자리표시자**
   - `docs/*.html`, `docs/ads.txt`: `ca-pub-XXXXXXXXXXXXXXXX` → AdSense 게시자 ID
   - `docs/*.html`: `support@example.com` → 지원 이메일
   - `fastlane/metadata/copyright.txt`: 저작권자 이름
3. **App Store Connect**
   - 앱 생성: 번들 ID `com.macpowerguard.monitor`, 기본 언어 영어(또는 한국어)
   - 앱 개인정보: **데이터 수집 안 함 (Data Not Collected)**
   - 연령 등급: 전부 "없음" → 4+
   - 가격: 무료(권장, 아래 광고 참고)
4. **웹페이지 공개**: GitHub › Settings › Pages › `master` 브랜치 `/docs` 폴더. 지원 URL `https://keydisk.github.io/MacPowerMonitoring/`, 개인정보 URL `…/privacy.html`
5. **업로드**: Xcode › Product › Archive → Distribute App › App Store Connect. 메타데이터는 `fastlane deliver` 로 일괄 업로드하거나 파일 내용을 복사해 붙여넣기
6. **다른 언어 스크린샷**: 시스템 언어를 바꾸거나 `-AppleLanguages "(en)"` 인자로 실행해 캡처 후 `fastlane/screenshots/<locale>/` 에 추가 (없으면 기본 언어 스크린샷이 모든 언어에 사용됨)

## 광고(AdSense)에 대해
- AdSense는 **웹사이트 전용**이고, 앱용 AdMob은 **iOS/Android만** 지원합니다. macOS 앱 안에 넣을 공식 Google 광고 SDK는 없고, WebView로 AdSense를 띄우는 것은 AdSense 정책 위반(계정 정지 위험)입니다.
- 그래서 광고는 앱의 지원/소개 웹페이지(`docs/`)에 넣었습니다(자동 광고).
- AdSense 승인은 github.io 하위 경로로는 어렵습니다 (`ads.txt` 가 도메인 루트에 있어야 함). 개인 도메인을 연결하는 것을 권장합니다.
- EEA/영국 방문자용 동의 배너는 AdSense 콘솔 › 개인정보 보호 및 메시지에서 켜세요.

## 심사 리스크
- 앱 이름: 스토어 이름은 `Power Guard: <언어별 부제>`, 설치 후 표시 이름은 `Power Guard` (Apple 상표 "Mac" 제외).
- 데스크톱 Mac에서는 동작하지 않으므로 설명에 명시했습니다(가이드라인 2.3). 심사 메모에도 적어 두었습니다.
