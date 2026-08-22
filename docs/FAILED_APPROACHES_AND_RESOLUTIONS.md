# 실패한 접근과 해결 기록

재시도하기 전에 이 문서를 확인한다. 실패한 접근은 다시 적용하지 말고, 전제가 달라진 경우에만 근거와 함께 재검토한다.

## Native Local CI 테스트 helper에서 명시적 `return` 누락

### 관찰

2026-08-22 Native Local CI runs `32564671678`와 최신 `32587430131`에서 macOS 15·26 두
runner의 Debug build는 통과했지만 Unit test 컴파일이
`missing return in instance method expected to return 'Data'`로 실패했다. 실패 지점은
`NativeLockModernTransactionTests.makeIndex(includeLinkedChoices:)`였다.

### 원인

`makeIndex`에 지역 변수와 조건문을 추가한 뒤 마지막
`PropertyListSerialization.data(...)` expression을 단일 expression 함수처럼 남겼다.
Swift는 앞에 실행문이 있는 함수에서 해당 expression을 암시적으로 반환하지 않는다.

### 해결

마지막 plist 생성식에 명시적인 `return`을 추가했다. 이 수정은 테스트 helper만 변경하며
Native Lock production code나 ad-hoc signing 구조를 변경하지 않는다. 수정 후에는 macOS
15·26 Native Local build/test와 Hikari release package gate를 다시 통과시켜야 한다.

## macOS 26 Lock Screen에서 portrait 영상이 세로로 늘어짐

### 관찰

2026-08-23 Hikari 선택 영상의 source와 Aerial용 output을 읽기 전용으로 검사한 결과 둘 다
1080×1920, identity preferred transform이었다. H.264 source를 10-bit HEVC Main10으로
변환한 뒤에도 Lock Screen 화면에서는 세로 방향으로 과도하게 늘어져 보였다. 따라서 이번
현상은 영상 pixel dimension이나 rotation metadata만의 문제로 단정할 수 없었다.

### 실패한 접근

`Linked` choice의 `Content.EncodedOptionValues`를 문자열 `$null`로 둔 채 코덱과 WallpaperAgent
재시작만 반복했다. 파일은 정상적으로 저장되고 mapping도 `active`가 됐지만 Aerial renderer가
배치 옵션을 자체 fallback으로 해석할 여지가 남아 있었다.

### 해결

- 기존 `Linked` choice에서 바이너리 `EncodedOptionValues`를 찾아 그대로 재사용한다.
- 값이 없는 새 choice에는 바이너리 plist
  `values → placement → picker → _0 → id = FillScreen`을 기록한다.
- 이 옵션을 macOS 26 Linked mapping에만 갱신하고, macOS 15 전체 choice 경로의 기존 동작은
  건드리지 않는다.
- `NativeLockModernTransactionTests`는 적용 후 option이 Data이고 선택 ID가 `FillScreen`인지
  확인한다.

최신 설치본의 실제 `Index.plist`에서 해당 Data를 decode해 `FillScreen`을 확인했고 transaction은
`4F264DEE-DEA1-427F-BBBB-3B033D1F2918`로 `active` 상태다. 최종 Lock Screen의 aspect-fit/crop
품질은 사용자가 잠금·해제해 수동 확인해야 하며, 여전히 늘어지면 renderer가 지원하는 다른
placement 값이나 letterbox 전용 사전 렌더링을 별도로 검증한다.

## `FillScreen` placement만으로 portrait Lock Screen 왜곡을 해결하려 한 접근

### 결과

사용자 확인 결과 바이너리 `FillScreen` option을 넣어도 세로 영상이 정상 비율로 보이지 않았다.
즉 `EncodedOptionValues` 타입은 필요한 조건이지만, macOS 26 Aerial renderer가 세로 원본
movie 자체를 Apple Aerial의 가로 canvas처럼 확장하는 문제까지 해결하지 못했다.

### 해결

Apple user Aerial store에 실제로 존재하는 로컬 영상은 3840×2160 또는 유사한 가로 비율이었다.
Hikari의 준비 단계가 1080×1920 원본을 그대로 저장하지 않도록, 1920×1080 16:9 canvas를
만들고 AVAsset video composition에서 source transform을 적용한 뒤 aspect-fit으로 중앙 합성한다.
이때 빈 영역은 검은색으로 두고 non-uniform scale이나 crop을 하지 않는다. 합성 결과를 다시
video-only 10-bit HEVC Main10으로 기록해 기존 Aerial codec 요구 조건도 유지한다.

새 방식은 source metadata만 확인하는 이전 검증과 달리 실제 Aerial 입력 프레임의 canvas
geometry를 바꾼다. 따라서 재적용 후 Lock Screen에서 portrait 내용이 늘어나지 않는지 수동
확인한다.

## 원본 `AVAssetTrack`을 직접 합성해 portrait 위치가 왼쪽으로 밀린 접근

### 관찰

16:9 canvas에 aspect-fit을 적용한 첫 구현은 비율과 letterbox는 보존했지만, 실제 생성된
`1280×720` preview의 비검정 영역이 `x=242…663`으로 측정돼 canvas 중심보다 왼쪽에 있었다.
`fitTransform`의 수학적 bounds는 중앙을 가리켰으므로, 단순히 translation에 상수를 더하는
방식은 회전·가로 영상에서 다시 틀어질 수 있다.

### 원인과 해결

`AVAssetReaderVideoCompositionOutput`에 원본 `AVAssetTrack`을 직접 전달할 때 compositor가
track의 source-space origin을 layer transform 평가에 다시 반영했다. 원본을
`AVMutableComposition`의 video track으로 먼저 삽입하고 그 track의 preferred transform을
identity로 설정한 뒤, 원본 transform·aspect-fit·center translation을 Hikari의 단일
layer transform으로 적용하도록 바꿨다. 이 경로는 magic pixel offset이나 crop을 사용하지
않는다.

### 검증

수정 후 transaction `61F4266D-F52F-42D4-8404-F5B69098A742`의 preview와 user Aerial
thumbnail 모두 `x=434…844`(중심 `639`)로 측정됐고, `1920×1080` 10-bit HEVC media와
active mapping이 30초 동안 유지됐다.

## macOS 26에서 `Linked` choice가 없는 Aerial catalog에 Native Lock Apply

### 관찰

2026-08-22 macOS 26.6.1의 Hikari `0.1.7 (8)`에서 user Aerial manifest에
Hikari asset/category를 transaction으로 추가하는 단계는 성공했지만, user
`Index.plist`에는 `Desktop`과 `Idle` choice만 있고 `Linked` container가 하나도
없었다. Apply는 `No wallpaper choices were found to update.`로
`recoveryRequired`가 됐으며 active marker는 만들어지지 않았다.

### 원인

macOS 26 user backend는 Lock Screen 전용 `Linked` choice만 Hikari asset으로
바꾸도록 설계돼 있다. 이 Mac의 현재 wallpaper topology는 해당 choice를
materialize하지 않았고, `Desktop` 또는 `Idle`을 대체하면 Lock Screen 전용 적용이라는
범위와 사용자의 기존 wallpaper/screen-saver 설정 보존 규칙을 위반한다.

이는 macOS 26 전체가 Native Lock을 지원하지 않는다는 뜻은 아니다. 2026-08-16의
다른 Mac active transaction에서는 Hikari asset을 가리키는 모든 `Linked` choice가
실제로 유지됐으며, 이후 검은 화면은 mapping 실패가 아니라 renderer refresh 누락으로
분리해 수정했다. 따라서 이 실패는 현재 Mac의 index topology 차이로 한정한다.

### 해결

- `Desktop`과 `Idle`을 fallback 값으로 재사용하는 방식은 시도하지 않는다.
- 성공 Mac에서 새 앱이 실행 직후 만든 결과를 읽기 전용으로 관찰했다. 기존 manifest의
  실제 Apple Aerial asset을 선택하고, `Index.plist`를 `SystemDefault`·현재 Space·display
  아래의 `Type: linked`/`Linked` 구조로 materialize했으며, manifest에 새 Hikari record는
  추가하지 않았다.
- Hikari는 이 관찰된 lifecycle을 transaction 안에서 재현한다. 원본 `Index.plist`를 먼저
  `prepare` 백업하고, manifest에 이미 존재하며 media/preview 파일이 실제로 있는 Apple
  Aerial asset과 현재 `com.apple.spaces`·NSScreen 식별자를 사용해 Linked topology를 만든
  다음 Hikari asset/category와 Linked choice를 적용한다.
- Hikari Lock Screen의 **Restore Previous Wallpaper**는 materialization과 Hikari 적용을
  모두 원본 bytes로 되돌린다. manifest hash가 바뀐 경우에도 다른 Hikari asset이 shared
  category를 사용하면 해당 category는 보존한다.
- 성공 Mac은 Apple Aerial을 선택한 뒤 `SystemDefault`·display·Space 아래에 `Linked`
  choice가 materialize됐고, 현재 Mac은 당시 `Desktop`·`Idle`만 있었다. 이제 Hikari는
  선택 영상이 있는 첫 실행에서 이 초기화를 자동 수행한다.

## 이전 Backdrop renderer가 Hikari의 Native Lock mapping을 되돌림

### 관찰

2026-08-22 macOS 26.6.1에서 Hikari 자동 Apply가 Aerial manifest와 `Linked` choice를
원자적으로 기록했지만 곧 `wallpaperMappingRejected`로 끝났다. H.264/8-bit 영상을
10-bit HEVC Main10으로 변환하고 `WallpaperAgent`·`WallpaperAerialsExtension`을
재시작한 뒤에도 같은 현상이 남았다. 당시 process 목록에는 다음 외부 writer가 있었다.

- `/Applications/Backdrop.app/.../BackdropWallpaper`
- Backdrop category `BD000000-0000-4000-8000-000000000001`
- 기존 asset `3B2922AA-19BD-4D54-B43E-B45EE5DFA56E`

Backdrop process를 종료한 뒤 같은 Hikari asset을 전역 `Linked` 형식으로 기록하자 Index가
수 초 뒤에도 유지됐다. 이어 Backdrop process가 없는 상태에서 Hikari 자동 Apply를 다시
실행하자 transaction `2AEC5A06-6A95-4D7B-8E8E-092762F6474B`가 `active`가 되고 30초
검증을 통과했다.

### 원인

Backdrop의 renderer가 공유 user wallpaper Index를 감시하면서 이전 Aerial choice를 다시
기록했다. Backdrop의 manifest/media가 남아 있는 것 자체가 문제라기보다, 실행 중인 두
writer가 같은 `Index.plist`를 서로 덮어쓴 것이 원인이었다. H.264 코덱만의 문제로 단정해
서는 안 되지만, macOS 26 Aerial 호환성을 위해 Hikari 영상은 video-only 10-bit HEVC
Main10으로 준비한다.

### 해결

- macOS 26 Apply 및 active transaction 유지보수 직전에 실행 중인 `BackdropWallpaper`
  helper만 `TERM`으로 종료한다. Backdrop의 category, asset, video, thumbnail은 수정·삭제하지
  않는다.
- Apple `WallpaperAgent`와 `WallpaperAerialsExtension`도 공유 파일 교체 구간에서 정지하고
  작업 후 재시작한다.
- 다른 wallpaper 도구는 transaction 중 동시에 실행하지 않는다는 운영 제약을 유지한다.

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

## Command Line Tools만 설치된 환경에서 XCTest 실행

### 시도

전체 Xcode 없이 `/Library/Developer/CommandLineTools`의 SwiftPM으로 `swift test`를
실행했다.

### 결과

해당 설치에는 `Testing.framework`만 있고 `XCTest` 모듈이 없어 기존 테스트
타깃부터 `no such module 'XCTest'`로 중단됐다. 제품 모듈의 컴파일 오류가 아니다.

### 해결

- 로컬에서는 `swift build`와 일반/Native compilation condition 각각의
  `swiftc -typecheck`로 소스 컴파일을 우선 검증한다.
- XCTest와 실제 앱 번들 빌드는 전체 Xcode가 있는 일반 CI 및 별도 Native Local
  CI에서 실행한다.
- 전체 Xcode가 설치된 장비에서는 `xcode-select`가 그 Xcode를 가리키는지 확인한
  뒤 `swift test` 또는 각 Xcode 스킴의 테스트를 실행한다.

## wallpaper index를 쓴 뒤 `WallpaperAgent` 종료

### 시도

Native Local이 사용자 `Index.plist`를 원자적으로 교체한 다음 실행 중인
`WallpaperAgent`를 종료해 새 설정을 읽게 했다.

### 결과

실제 Mac에서 system asset과 manifest는 정상 등록됐지만, 종료 직전 에이전트가
메모리에 있던 이전 상태를 파일에 다시 기록했다. 사용자 journal은 `active`인데
현재 choice는 기본값으로 돌아가는 거짓 성공 상태가 재현됐다.

### 해결

- 기존 `WallpaperAgent`에 먼저 `SIGSTOP`을 보내 이전 상태의 추가 기록을 막는다.
- 정지된 동안 user index를 원자적으로 교체한 뒤 해당 PID를 `SIGKILL`하여 launchd가
  새 파일로 재시작하게 한다.
- system manifest 적용 직후에는 `idleassetsd`의 SQLite/WAL에 해당 transaction의
  새 asset ID가 나타날 때까지 기다린 뒤 user index를 변경한다. 준비 전에
  `WallpaperAgent`를 시작하면 수 초 뒤 12개 choice가 `default`로 되돌아갔다.
- 재시작 뒤 30초 동안 모든 기존 wallpaper choice의 asset ID를 계속 재검증하고,
  한 번이라도 유지되지 않으면 성공으로 반환하지 않고 `recoveryRequired`로 기록한다.
- 실제 Mac에서 DB 인덱싱 완료 뒤 적용하면 1/5/10/20/30/40초 시점 모두 12개
  display/Space/Desktop/Idle choice가 같은 새 asset ID를 유지하는 것을 확인했다.

## 수동 `swiftc` 앱 조립에서 asset catalog 생략

### 시도

전체 Xcode 없이 Native Local 앱 실행을 먼저 확인하면서 실행 파일과 plist만 직접
조립했다.

### 결과

앱 기능은 실행됐지만 `AppIcon`과 런타임 아이콘 resource가 번들에 없어 일반 기본
아이콘으로 보였다.

### 해결

`scripts/build-native-local.sh`가 모든 앱 아이콘 크기로 `.icns`를 만들고 메뉴 막대
이미지와 localization을 포함하며, ad-hoc 서명과 `codesign --verify --deep --strict`까지
수행하도록 통합했다.

## 원본 wallpaper plist를 dictionary로 다시 직렬화해 복원

### 시도

현재 user index가 적용 직후 hash와 동일한 경우에도 백업 plist를 dictionary로
읽은 다음 새 binary plist로 직렬화해 복원했다.

### 결과

의미상 같은 값이어도 plist object 순서와 binary encoding이 달라질 수 있어 수동
round-trip 검사가 `index=false`를 반환했다. 검증 프로그램은 이 결과로 종료됐다.

### 해결

현재 hash가 적용 기록과 같으면 `Index.original.plist`의 검증된 원본 bytes를 그대로
원자적으로 쓴다. 외부 변경 때문에 hash가 다를 때만 구조를 해석해 Lumina-owned
choice를 선택적으로 복원한다.

## Xcode tool 타깃의 `main.swift`에서 `@main` 사용

### 시도

one-shot tool entry를 `Sources/LuminaNativeTool/main.swift`에 두고 `@main` 구조체로
선언했다. SwiftPM과 로컬 빌드 스크립트는 `-parse-as-library`를 사용해 통과했다.

### 결과

Xcode 16.4는 이름이 `main.swift`인 파일을 top-level entry로 취급하므로 `@main`
선언과 충돌해 Native Local CI Debug build가 실패했다.

### 해결

동작 코드는 유지하고 파일명을 `LuminaNativeTool.swift`로 변경했다. SwiftPM, 직접
`swiftc`, Xcode가 모두 같은 `@main` entry 규칙을 사용하게 한다.

## 저장소 루트에서 release ZIP checksum 생성

### 시도

package job이 `shasum -a 256 dist/Lumina-macOS-portable.zip` 출력 전체를
`.sha256` asset으로 저장했다.

### 결과

hash 값은 정확했지만 checksum 안의 파일명이 `dist/...zip`이 됐다. GitHub Release
두 파일을 같은 폴더에 내려받고 README 명령을 실행하면 해당 하위 경로가 없어
`FAILED open or read`로 실패했다.

### 해결

`dist` 디렉터리 안에서 ZIP basename을 hash하고, 업로드 전에 같은 `.sha256` 파일로
CI가 `shasum -a 256 -c`를 실행한다. push된 v0.3.0 태그는 변경하지 않고 v0.3.1로
후속 릴리스한다.

## Native 적용 직후 30초 검증만으로 이후 잠금도 정상이라고 판단

### 관찰

active transaction의 12개 display/Space/Desktop/Idle choice와 MOV hash는 모두
정상이었지만 반복 잠금 뒤 화면이 검게 남았다. unified log에서 첫 잠금은 실제
frame을 출력했으나 unlock ramp-down 중 `WallpaperVideoCore.VideoSampleReadingErrors`
Code 4가 발생했다. 같은 `WallpaperVideoExtension` 프로세스는 이후 잠금에서
`Play Called`만 받고 frame을 enqueue하지 못했다.

또한 최초 적용 뒤 연결된 display나 새 Space가 만드는 choice는 30초 안정화 검증의
대상이 아니므로 mapping 일부가 나중에 달라질 수 있다.

### 해결

- 일반 wallpaper는 콘텐츠가 있는 동안 5초마다 display topology와 실패한 player를
  조정한다. `SuspendingClock`을 사용해 Sleep 동안 missed tick을 몰아서 실행하지 않는다.
- Native Local은 5초마다 user choice mapping을 읽되 drift가 있을 때만 `WallpaperAgent`를
  정지한 상태로 choice를 다시 적용한다. privileged helper와 system write는 반복하지 않는다.
- 새 topology의 원래 choice는 exact path restore overlay에 기록한 다음 교체하고,
  restore 시 현재 topology에 선택적으로 병합한다.
- active transaction이 있으면 앱 시작과 매 unlock 뒤 user `WallpaperAgent`를 한 번
  종료해 launchd가 video extension을 새로 구성하게 한다. 잠금 상태나 고정 주기마다
  renderer를 반복 종료하지 않는다.

## macOS 26 user Aerial transaction에서 renderer 새로 시작을 건너뜀

### 관찰

활성 transaction의 manifest, staged media 및 모든 `Linked` choice가 정상인데도
다음 잠금 화면이 검게 표시됐다. 앱 시작과 unlock 후 실행되는 renderer refresh가
legacy backend에만 제한돼 macOS 26 user Aerial backend에서는 실행되지 않았다.

### 해결

backend와 무관하게, active transaction이 있고 시작에 의한 refresh가 요청된 경우
`WallpaperAgent`를 한 번 새로 시작한다. unlock 뒤에는 Lock Screen 전환이 끝난
뒤에만 같은 refresh를 실행한다. mapping을 재조정해 이미 agent를 교체한 경우에는
중복 실행하지 않으며, 잠금 중 또는 주기 maintenance에서는 재시작하지 않는다.

## Lock Screen 영상의 movie header를 media 뒤에 둠

### 관찰

활성 Hikari 영상은 66MB 4K H.264 파일의 마지막에 `moov` movie header가 있었다.
Lock Screen extension이 cold start에서 이 header를 찾으려면 media payload를 먼저
읽어야 하므로 첫 프레임 표시가 늦어질 수 있었다.

### 해결

Native Lock 준비 단계의 passthrough export에 fast-start 최적화를 사용한다. 영상
codec·해상도·화질은 유지하면서 movie header와 track index를 파일 앞쪽으로 옮긴다.
이미 적용된 transaction의 hash-보호 media는 자동으로 덮어쓰지 않으며, Restore 후
같은 영상을 다시 Apply할 때 새 레이아웃이 사용된다.

## unlock을 display recovery로 처리

### 관찰

잠금 해제 알림 뒤의 보조 확인이 display recovery를 호출해 3회에 걸쳐 desktop
window와 `AVPlayerLayer`를 재생성했다. Lock Screen surface가 사라지는 동안 이
재생성이 겹치면 해제 직후 검은 프레임이 번쩍였다.

### 해결

unlock 뒤에는 재생 정책만 한 번 더 확인하고 desktop surface를 재생성하지 않는다.
실제 잠자기 복귀, 디스플레이 변경 및 Space 전환의 display recovery는 유지한다.

## 상태 항목 symbol effect를 비반복 옵션으로만 변경

### 시도

메뉴 막대 반짝임의 `.repeating` 옵션만 제거하고 `isActive: true` 기반의 symbol
effect를 유지했다.

### 결과

macOS 26에서 `isActive`가 true인 동안 `RBSymbolAnimator`와 SwiftUI display list
렌더링이 계속 실행됐다. 4K 영상 재생 중 CPU 표본이 다시 약 16~21%까지 올라가
상태 항목의 지속 비용을 제거하지 못했다.

### 해결

메뉴 막대 반짝임을 정적 symbol로 표시한다. 아이콘 크기와 반짝임의 위쪽 offset은
유지하면서 SwiftUI의 지속 animation transaction을 만들지 않는다.

## macOS 26에서 macOS 15의 Native catalog transaction을 그대로 활성화

### 시도

macOS 26.6.1의 manifest schema version 1과 user index의 기본 choice 구조가
읽기 전용 검사와 격리된 Apply → Restore 복사본 검증을 통과한 것을 근거로, 새
wallpaper extension lifecycle에 맞춰 catalog host 재시작과 option-value 정규화를
더한 뒤 실제 local Apply를 한 번 실행했다.

### 결과

system manifest와 Hikari asset은 생성됐지만 macOS가 새 user wallpaper mapping을
유지하지 않아 30초 안정화 검증이 `wallpaperMappingRejected`로 실패했다. 앱은
`recoveryRequired`를 기록했다. 즉 schema가 읽힌다는 사실만으로 실제 system
catalog의 인덱싱·선택 유지까지 호환된다고 볼 수 없었다.

### 해결

- macOS 26의 system write 허용을 즉시 제거하고 macOS 15 전용 guard를 유지한다.
- 즉시 Restore를 실행해 manifest의 Hikari asset/category를 제거하고, user index에
  staged asset 참조가 남지 않았으며 transaction journal이 `restored`로 끝난 것을
  확인한다.
- 추후 재시도는 macOS 26 extension이 공식적으로 제공하는 catalog refresh 또는
  selection API를 확인하고, 실제 Apply → lock → unlock → Restore 왕복이 성공한
  뒤에만 허용한다.

### 후속 조사와 수정된 해결

macOS 26에서 실제로 동작 중인 별도 로컬 Aerial 클라이언트를 읽기 전용으로
조사한 결과, 새 extension은 root-owned legacy catalog 대신 현재 사용자의
`~/Library/Application Support/com.apple.wallpaper/aerials`를 읽는다. 동영상과
미리보기를 그 store에 두고, schema version 1 `entries.json`에 `file://` URL의
asset/category를 병합한 다음 `Index.plist`의 `Linked` choice만 새 `assetID`로
바꾸면 선택값이 유지됐다. `Desktop`과 `Idle` choice는 유지됐다.

따라서 macOS 15 root transaction을 macOS 26에 되살리지 않는다. Hikari에는 별도
user Aerial transaction을 구현하고, 원본 manifest/index bytes와 hash를 journal에
보관한다. 격리된 임시 store에서 Apply → Linked 검증 → Restore 왕복은 통과했지만,
Hikari 실제 장비 적용 전에는 같은 저장소를 변경하는 다른 도구를 종료하거나
복원해 동시 transaction을 피한다.

## 디스플레이 topology 안정화 중 wallpaper surface를 반복 재생성

### 관찰

외부 요인으로 디스플레이 번호나 연결 상태가 바뀌면 WindowServer가 여러 화면
parameter 알림을 연속해서 보냈다. 각 확인에서 wallpaper 창과 `AVPlayerLayer`를
다시 만들면서 영상이 여러 번 멈췄다가 다시 시작했고, 화면마다 재생 위치도
처음으로 돌아갈 수 있었다.

### 원인

초기 알림은 디스플레이 membership와 geometry만 바뀐 불안정한 snapshot일 수 있다.
이 단계에서 `AVPlayer` 기반 surface까지 재생성하면 다음 알림이 도착할 때마다
현재 재생 세션을 해제하고 새로 만들게 된다.

### 해결

- 초기 display recovery pass에서는 기존 session을 유지한 채 display topology만
  동기화하고, 최종 안정화 pass에서만 surface를 한 번 재생성한다.
- rebuild 전에 대표 session의 유효한 playback position과 재생 의도를 저장하고,
  새 session을 만든 뒤 모든 display에 position을 복원한 다음 재생을 재개한다.
- `DisplayRecoveryPolicy`와 모든 session의 `seekAll` 동작을 단위 테스트로 고정해
  topology 확인 횟수와 playback 복원 규칙이 다시 합쳐지지 않도록 한다.
