#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="${1:-"$ROOT_DIR/../../outputs"}"
STAMP="$(date +%Y%m%d-%H%M%S)"
VERSION="0.2.5"
BUNDLE_VERSION="${STAMP/-/.}"
PACKAGE_NAME="TransmitKakaoBridge-$STAMP"
PACKAGE_DIR="$OUTPUT_ROOT/$PACKAGE_NAME"
APP_DIR="$PACKAGE_DIR/TransmitKakaoBridge.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F '"' '/Developer ID Application/ { print $2; exit }')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F '"' '/Apple Development/ { print $2; exit }')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
  SIGNING_NOTE="ad-hoc"
else
  SIGNING_NOTE="$SIGN_IDENTITY"
fi

"$ROOT_DIR/scripts/generate_app_icon.py"
iconutil -c icns "$ROOT_DIR/assets/AppIcon.iconset" -o "$ROOT_DIR/assets/AppIcon.icns"
swift build -c release --product TransmitKakaoBridge --package-path "$ROOT_DIR"

cp "$ROOT_DIR/.build/release/TransmitKakaoBridge" "$MACOS_DIR/TransmitKakaoBridge"
chmod +x "$MACOS_DIR/TransmitKakaoBridge"
cp "$ROOT_DIR/assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>ko</string>
  <key>CFBundleExecutable</key>
  <string>TransmitKakaoBridge</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>local.codex.TransmitKakaoBridge</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>TransmitKakaoBridge</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUNDLE_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>카카오톡 입력창에 드롭된 Transmit 경로를 붙여넣기 위해 사용합니다.</string>
  <key>NSHumanReadableCopyright</key>
  <string>Local helper for Transmit to KakaoTalk path drops.</string>
</dict>
</plist>
PLIST

cat > "$PACKAGE_DIR/README.md" <<'README'
# TransmitKakaoBridge

Transmit에서 카카오톡 대화 입력창으로 파일/폴더를 드래그하면, Transmit이 드롭 payload에 넣어주는 remote path를 읽어서 카카오톡 입력창에 텍스트로 붙여넣는 네이티브 macOS helper입니다.

## 실행

1. `TransmitKakaoBridge.app`을 더블클릭합니다.
2. 메뉴바에 `TK`가 보이면 실행 중입니다.
3. 카카오톡 대화창을 열고, Transmit 파일/폴더를 카카오톡 입력창으로 드래그합니다.
4. 종료하려면 메뉴바 `TK`를 클릭한 뒤 `Quit`을 누릅니다.

## 권한

처음 실행 시 앱이 Accessibility 권한 상태를 확인하고, 권한이 없으면 macOS 권한 창을 자동으로 엽니다.

- System Settings > Privacy & Security > Accessibility
- `TransmitKakaoBridge`를 허용

권한이 없으면 path 읽기는 성공해도 마지막 클릭/Cmd+V 입력이 막힐 수 있습니다.

macOS 보안 정책상 앱이 Accessibility 권한을 자동으로 삭제하거나 재허용할 수는 없습니다. 업데이트 후 권한이 깨지는 현상은 ad-hoc 서명 앱에서 발생할 수 있으며, 완전히 없애려면 같은 Developer ID 인증서로 계속 서명/공증해야 합니다.

현재 Mac에 코드서명 인증서가 있으면 패키징 스크립트가 자동으로 그 인증서를 사용합니다. 인증서가 없으면 ad-hoc 서명으로 빌드되며, 이 경우 업데이트 때 Accessibility 항목을 삭제 후 다시 허용해야 할 수 있습니다.

## 옵션

메뉴바 `TK`에서 `파일/이미지 드롭도 TK로 처리`를 켜거나 끌 수 있습니다.

메뉴바 `TK`의 `Accessibility 권한 열기`를 누르면 권한 창을 다시 열 수 있습니다.

- 기본값: 꺼짐
- 꺼짐: Transmit이 제공하는 텍스트 path/URL만 처리합니다.
- 켜짐: file URL 같은 파일/이미지성 드롭 payload도 path 후보로 처리합니다.

기본값을 꺼둔 이유는 카카오톡이 원래 파일/이미지 붙여넣기를 잘 처리하기 때문입니다.

## 동작 범위

- Transmit에서 시작한 마우스 드래그만 감지합니다.
- 드롭 receiver는 카카오톡 창의 하단 입력 영역 위에 드래그 중에만 잠깐 나타납니다.
- Safari/Finder 같은 다른 앱의 드래그 이벤트는 모니터링하지 않습니다.
- TextEdit 등 다른 앱에는 관여하지 않습니다.
- AppleScript 선택 항목 fallback은 사용하지 않습니다.
- 여러 파일/폴더 path는 항목 사이에 빈 줄 1줄을 넣어 붙여넣습니다.
- 붙여넣기 후 기존 텍스트 클립보드만 가볍게 복원합니다. 이미지/파일 클립보드는 freeze 방지를 위해 기본값에서 읽거나 복원하지 않습니다.

## 로그

`~/Library/Logs/TransmitKakaoBridge/TransmitKakaoBridge.log`에 드롭 감지, path 읽기, paste 시도 여부가 기록됩니다.

## 배포 참고

이 패키지는 앱 번들 형태로 서명되어 있습니다. 패키징 Mac에 Developer ID 또는 Apple Development 코드서명 인증서가 없으면 ad-hoc 서명으로 생성됩니다. ad-hoc 서명 앱은 사내 테스트에는 사용할 수 있지만, 업데이트 후 Accessibility 권한이 유지되지 않을 수 있고 다른 Mac에서 Gatekeeper 안내가 나올 수 있습니다.
README

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_DIR"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
fi

(
  cd "$OUTPUT_ROOT"
  ditto -c -k --keepParent "$PACKAGE_NAME" "$PACKAGE_NAME.zip"
)

echo "$OUTPUT_ROOT/$PACKAGE_NAME.zip"
echo "Signing identity: $SIGNING_NOTE"
