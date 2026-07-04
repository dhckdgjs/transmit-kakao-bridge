# TransmitKakaoBridge 0.2.5

Transmit에서 카카오톡 대화 입력창으로 파일/폴더를 드래그하면 remote path를 텍스트로 붙여넣는 macOS helper입니다.

## 주요 개선사항

- **Safari/Finder 미세 드래그 완화**  
  전역 `leftMouseDragged` 모니터링을 제거했습니다. 이제 Safari/Finder 같은 다른 앱에서 드래그 이벤트가 발생해도 TK 앱이 관찰하지 않습니다.

- **Transmit 감지 방식 변경**  
  Transmit 위에서 `mouseDown`이 시작될 때 카카오톡 입력창 drop receiver를 바로 띄웁니다. 덕분에 드래그 중 반복 이벤트 감시 없이 Transmit 드롭을 받을 수 있습니다.

- **네이티브 AppKit drop receiver 적용**  
  Hammerspoon pasteboard polling 대신 TextEdit와 같은 AppKit drag destination 구조로 전환했습니다.

- **Transmit remote path 안정 수신**  
  Transmit 드롭 payload의 `public.utf8-plain-text` / URL 데이터를 읽어 `/00.MOONSATAM/...` 형태의 path를 붙여넣습니다.

- **여러 항목 가독성 개선**  
  여러 파일/폴더를 드롭하면 path 사이에 빈 줄 1줄을 넣습니다.

- **카카오톡 멈춤 완화**  
  드래그 중 반복 pasteboard 읽기를 제거하고, 전체 클립보드 복원 대신 기존 텍스트 클립보드만 가볍게 복원합니다.

- **파일/이미지 fallback 옵션화**  
  카카오톡 기본 파일/이미지 드롭 동작을 방해하지 않도록 파일/이미지 fallback은 기본 OFF입니다. 메뉴바 `TK`에서 켤 수 있습니다.

- **Accessibility 권한 안내 개선**  
  실행 시 권한 상태를 확인하고, 메뉴바에서 권한 창을 다시 열 수 있습니다.

- **Tahoe 대응 아이콘**  
  macOS Tahoe 계열 아이콘 배경 처리를 고려한 불투명 full-canvas 아이콘을 포함했습니다.

- **패키징 자동화**  
  `scripts/package_bridge.sh`로 아이콘 생성, release build, 앱 번들 생성, 코드서명, zip 생성을 한 번에 처리합니다.

## 배포 참고

현재 패키징 Mac에 코드서명 인증서가 없으면 ad-hoc 서명으로 생성됩니다. ad-hoc 서명 앱은 업데이트 후 Accessibility 항목을 삭제하고 다시 허용해야 할 수 있습니다.

직원 배포에서 권한 유지와 Gatekeeper 경고를 줄이려면 같은 Developer ID 인증서로 계속 서명하고 공증하는 흐름을 권장합니다.
