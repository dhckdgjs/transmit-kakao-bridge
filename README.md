# TransmitKakaoBridge

Transmit에서 카카오톡 대화 입력창으로 파일/폴더를 드래그하면, Transmit이 드롭 payload에 넣어주는 remote path를 읽어서 카카오톡 입력창에 텍스트로 붙여넣는 macOS helper입니다.
(최근 카카오톡 대화 입력창에서 해당 기능이 삭제되었음)

## 주요 기능

- Transmit에서 시작한 드래그만 감지합니다.
- 카카오톡 창의 하단 입력 영역에만 드롭 receiver를 잠깐 띄웁니다.
- Transmit의 `public.utf8-plain-text` / URL payload에서 remote path를 읽습니다.
- 여러 파일/폴더는 path 사이에 빈 줄 1줄을 넣어 붙여넣습니다.
- 파일/이미지성 드롭 fallback은 기본값에서 꺼져 있으며, 메뉴바 `TK`에서 켤 수 있습니다.
- 붙여넣기 후 기존 텍스트 클립보드만 가볍게 복원합니다.
- 앱 아이콘은 Tahoe 계열 아이콘 배경 처리를 고려한 불투명 full-canvas 방식으로 생성합니다.

## 실행

릴리즈 zip을 받아 `TransmitKakaoBridge.app`을 실행합니다. 메뉴바에 `TK`가 보이면 동작 중입니다.

종료하려면 메뉴바 `TK > Quit`을 누릅니다.

## 권한

처음 실행 시 Accessibility 권한이 필요합니다.

- System Settings > Privacy & Security > Accessibility
- `TransmitKakaoBridge` 허용

앱은 실행 시 권한 상태를 확인하고 권한 창을 열 수 있지만, macOS 보안 정책상 Accessibility 권한을 자동 삭제하거나 자동 재허용할 수는 없습니다.

## 업데이트와 코드서명

ad-hoc 서명 앱은 빌드마다 designated requirement가 `cdhash`로 바뀌어, 업데이트 후 Accessibility 항목을 삭제하고 다시 허용해야 할 수 있습니다.

패키징 스크립트는 현재 Mac에 코드서명 인증서가 있으면 다음 순서로 자동 사용합니다.

1. Developer ID Application
2. Apple Development
3. ad-hoc fallback

배포에서 권한 유지와 Gatekeeper 경고를 줄이려면 같은 Developer ID 인증서로 계속 서명하고 공증하는 흐름이 권장됩니다.

## 빌드

```bash
swift build -c release --product TransmitKakaoBridge
```

## 패키징

```bash
scripts/package_bridge.sh /path/to/output
```

패키징 스크립트는 다음을 수행합니다.

- 앱 아이콘 생성
- `.icns` 생성
- release build
- `.app` 번들 구성
- 코드서명
- zip 생성

## 로그

```text
~/Library/Logs/TransmitKakaoBridge/TransmitKakaoBridge.log
```

## 구성

- `Sources/TransmitKakaoBridge`: 카카오톡 입력창용 helper
- `Sources/TransmitDropProbe`: Transmit drag payload 조사용 probe
- `scripts/generate_app_icon.py`: 앱 아이콘 생성
- `scripts/package_bridge.sh`: 배포 패키지 생성
