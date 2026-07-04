# Changelog

## 0.2.4

- 패키징 스크립트가 코드서명 인증서를 자동 탐색하도록 개선했습니다.
- `Developer ID Application`, `Apple Development`, `ad-hoc` 순서로 서명 방식을 선택합니다.
- Accessibility 권한 안내를 업데이트했습니다.

## 0.2.3

- Accessibility 권한 상태를 앱 실행 시 확인하도록 추가했습니다.
- 메뉴바에서 Accessibility 권한 창을 다시 열 수 있게 했습니다.

## 0.2.2

- Transmit file promise 계열 pasteboard type을 항상 수신하도록 복원했습니다.
- 파일/이미지 fallback 옵션은 기본 OFF로 유지했습니다.
- 로그 위치를 `~/Library/Logs/TransmitKakaoBridge/`로 고정했습니다.

## 0.2.1

- 드래그 중 반복 pasteboard 읽기를 제거해 카카오톡 멈춤 가능성을 줄였습니다.
- 전체 클립보드 복원 대신 텍스트 클립보드만 가볍게 복원하도록 변경했습니다.

## 0.2.0

- 앱 아이콘과 패키징 스크립트를 추가했습니다.
- Tahoe 계열 아이콘 배경 처리를 고려해 불투명 full-canvas 아이콘으로 전환했습니다.
- 파일/이미지 드롭 fallback을 메뉴 옵션으로 분리했습니다.

## 0.1.x

- Hammerspoon 방식에서 네이티브 AppKit drop receiver 구조로 전환했습니다.
- TextEdit처럼 `NSDraggingInfo.draggingPasteboard`를 직접 수신하는 구조를 검증했습니다.
- Transmit payload probe를 통해 `public.utf8-plain-text`에 remote path가 들어오는 것을 확인했습니다.
- 여러 파일/폴더 path 사이에 빈 줄 1줄을 넣어 붙여넣도록 구현했습니다.
