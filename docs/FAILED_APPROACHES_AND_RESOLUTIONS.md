# 실패한 접근과 해결 기록

재시도하기 전에 이 문서를 확인한다. 실패한 접근은 다시 적용하지 말고, 전제가 달라진 경우에만 근거와 함께 재검토한다.

## 화면 보호기에서 앱 샌드박스 경로를 강제 사용

### 시도

화면 보호기에서 비디오를 확실히 찾기 위해 `SharedContainer.screenSaverRootURL`을 강제로 지정하고 `playImmediately()`를 호출했다.

### 결과

v0.2.5 이후 실제 루미나 잠금 화면의 비디오 재생이 회귀했다. 화면 보호기 프로세스의 컨테이너 구성과 맞지 않는 경로일 가능성이 높다.

### 해결

화면 보호기에서는 `SharedContainer()`의 기본 해석과 일반 `player.play()`를 사용한다. 이 복원은 v0.2.6에서 CI를 통과했다.

## 설치된 화면 보호기는 앱 업데이트로 자동 갱신된다는 가정

### 시도/가정

Lumina.app만 업데이트하면 `~/Library/Screen Savers/Lumina.saver`도 최신 코드가 된다고 보았다.

### 결과

앱에 내장된 saver와 별도 설치된 saver의 버전이 달라질 수 있었다. 실제로 설치 위치에는 v0.1.12가 남아 있었고, 앱은 더 최신 버전이었다.

### 해결

- 앱의 화면 보호기 업데이트 흐름을 실행해 별도 설치본을 갱신한다.
- 문제 재현 시 앱 번들만 보지 말고 `~/Library/Screen Savers/Lumina.saver`의 버전과 실제 실행 프로세스가 매핑한 바이너리를 함께 확인한다.

## 화면 보호기 파일 교체만으로 이미 실행 중인 프로세스가 바뀐다는 가정

### 시도/가정

`.saver`를 디스크에서 교체한 뒤 바로 다음 화면 보호기 실행이 새 바이너리를 사용할 것으로 보았다.

### 결과

장시간 실행 중인 `legacyScreenSaver` 프로세스가 삭제된 옛 바이너리를 계속 메모리에 매핑할 수 있었다.

### 해결

실행 중인 화면 보호기 프로세스를 종료한 뒤 다시 시작하여, 새 프로세스가 설치된 최신 `.saver`와 비디오를 매핑하는지 확인한다.

## 단축키에 Accessibility 권한만 요청

### 시도

전역 CGEvent tap의 동작 조건으로 Accessibility 권한만 확인했다.

### 결과

macOS 15에서는 키보드 이벤트 감시에 Input Monitoring 권한도 필요할 수 있어 event tap 생성이 실패하고 단축키가 동작하지 않았다.

### 해결

v0.2.8부터 Accessibility와 Input Monitoring을 함께 사전 확인·요청한다. 앱 업데이트로 서명이 달라지는 ad-hoc 배포에서는 TCC 권한이 다시 필요할 수 있다.

## Input Monitoring 사전 판정을 event tap 생성의 하드 게이트로 사용

### 시도

v0.2.8은 `CGPreflightListenEventAccess()`가 true일 때만 `CGEvent.tapCreate`를 호출했다.

### 결과

시스템 설정에서 Lumina의 Input Monitoring 토글이 켜져 있어도 사전 판정이 false이면
이벤트 탭을 만들 기회 자체가 없었다. Accessibility가 허용된 내장 키보드 환경에서도
단축키가 동작하지 않는 상태가 확인됐다.

### 해결

v0.2.9부터 사전 판정은 권한 안내용으로만 사용한다. Accessibility가 허용됐다면
CoreGraphics의 실제 `CGEvent.tapCreate`를 시도하고, 그 결과를 활성화 여부로 사용한다.

## 시스템 설정의 권한 행만 보고 현재 실행본 권한이 있다고 판단

### 관찰

ad-hoc 서명된 v0.2.10에서 시스템 설정에 Lumina 행이 보이더라도, 실행 중인
프로세스의 `AXIsProcessTrusted()`는 `1`이고 `CGPreflightListenEventAccess()`는
`0`인 상태가 실제로 확인됐다. 이 상태에서는 Lumina가 키보드 이벤트를 받을 수
없어 macOS 기본 잠금만 실행됐다.

### 해결 및 검증

두 TCC 권한을 재부여하고 Lumina를 재실행한 뒤, 현재 프로세스에서 두 API가 모두
`1`을 반환하는 것을 확인했다. 같은 프로세스는 `Global keyboard event tap enabled`
로그도 남겼다. 권한 문제를 판정할 때는 UI 색상만 보지 않고 이 런타임 상태와 탭
생성 로그를 함께 확인한다. ad-hoc 릴리스는 코드 정체성이 바뀔 수 있으므로,
장기적으로는 Developer ID 서명으로 배포 정체성을 고정해야 한다.

## 표준 macOS 잠금 단축키에 세션 단계 event tap만 사용

### 시도

`Control` + `Command` + `Q`를 `.cgSessionEventTap`에서 가로챘다.

### 결과

권한·설정·실행 버전이 정상인 내장 키보드 환경에서도 macOS가 표준 잠금 조합을
세션 탭 전에 소비할 수 있었다.

### 해결

v0.2.10부터 `.cghidEventTap`을 먼저 만들고, 해당 위치를 지원하지 않는 경우에만
세션 탭으로 폴백한다. 생성과 단축키 수신은 unified log로 확인 가능하게 남긴다.

## 권한이 정상인데 단축키가 동작하지 않는 경우 Karabiner를 단순 충돌로 판단

### 확인 결과

v0.2.8 실행본에서 다음 상태를 실제 시스템 설정으로 확인했다.

- `overrideSystemLockShortcut`이 `true`
- Lumina가 실행 중이며 앱과 설치된 `.saver`가 모두 v0.2.8
- Accessibility와 Input Monitoring의 Lumina 토글이 모두 켜짐
- Karabiner의 활성 프로파일에는 Q 키 또는 잠금 조합을 직접 가로채는 complex modification이 없음

### 실제 원인

해당 Karabiner 장치 설정은 물리 `left_command`를 `left_option`으로,
물리 `left_option`을 `left_command`로 바꾼다. Lumina는 `Control` +
`Command` + `Q`만 받고 Option 또는 Shift가 포함된 이벤트는 거부한다.
따라서 이 외장 키보드의 물리 `Control` + `left_command` + `Q`는
`Control` + `Option` + `Q`가 되어 단축키가 발동하지 않는다.

### 해결

- 이 외장 키보드에서는 물리 `Control` + `left_option` + `Q`를 사용한다.
- 내장 키보드 또는 Karabiner 변환이 적용되지 않는 장치에서는 원래의
  `Control` + `Command` + `Q`를 사용한다.
- 그래도 동작하지 않으면 `Shortcut Status`가 Active인지 확인하고, 실제
  키 입력 장치와 Karabiner EventViewer의 변환 결과를 함께 확인한다.

## 화면 보호기 프로세스가 남아 있는 상태에서 잠금 실행 결과를 단축키 실패로 판단

### 관찰

현재 설치본으로 갱신한 뒤에도 이전 `legacyScreenSaver` 프로세스가 예전
`.saver` inode를 계속 매핑하고, 새 프로세스가 동시에 실행될 수 있다.

### 영향

이 상태는 Lumina의 키 이벤트 탭을 막지는 않지만, 단축키가 호출하는
ScreenSaverEngine 실행 요청이 이미 실행 중인 화면 보호기 때문에 눈에 띄는
새 화면 전환 없이 성공으로 반환될 수 있다.

### 대응

문제 재현을 판별할 때는 키 입력 수신과 화면 보호기 시작을 분리한다. 실제
화면 보호기 프로세스가 중복·잔존했다면 종료 후 새 프로세스로 다시 확인한다.
후속 설치 갱신 흐름은 Lumina가 선택된 경우 이 호스트를 종료해 다음 실행이
새 번들을 사용하도록 한다.

## 자동 화면 보호기의 큰 영상 크기를 재생 버그로 판단

### 관찰

16:9 영상이 약 3:2 디스플레이에서 크게 잘려 보였다.

### 원인

`Fill` 모드는 의도적으로 `.resizeAspectFill`을 사용하므로 화면을 채우기 위해 영상 일부가 잘린다.

### 해결

전체 영상 표시가 필요하면 설정의 크기 조절 모드를 `Fit`으로 선택한다. `Fill` 동작 자체는 변경하지 않는다.
