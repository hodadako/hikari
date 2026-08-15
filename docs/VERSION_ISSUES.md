# 버전별 이슈 및 검증 기록

최신 항목을 위에 추가한다. 각 릴리스에는 사용자 영향, 원인, 조치, 검증, 남은 제약을 기록한다.

## Hikari v0.1.0 (1) — 2026-08-16

### 이슈와 영향

- Hikari는 별도 bundle ID와 설치 경로를 사용하지만 마케팅 버전은 Lumina의
  `MARKETING_VERSION`을 공유했고, 로컬 빌드 번호는 항상 `1`로 고정됐다.
  따라서 Hikari 코드를 갱신해도 About과 bundle plist만으로 어떤 빌드인지
  구분하거나 독립적으로 버전을 올릴 수 없었다.

### 조치

- `project.yml`에 Hikari 전용 `HIKARI_MARKETING_VERSION`과
  `HIKARI_BUILD_NUMBER`을 추가하고 첫 독립 기준을 `0.1.0 (1)`로 정했다.
- Hikari Info.plist, Xcode 타깃, 로컬 빌드 스크립트, Native Local CI가 모두
  같은 두 값을 사용·검증하도록 연결했다. 일반 Lumina의 `0.3.1 (1)`과
  release tag 검증은 바꾸지 않았다.

### 검증

- 로컬 Hikari 빌드의 `CFBundleShortVersionString`이 `0.1.0`,
  `CFBundleVersion`이 `1`인지 확인한다.
- Native Local CI의 macOS 15·26 Xcode 빌드가 같은 bundle plist 값을
  검사한다.

### 남은 제약

- Hikari는 source-only 로컬 빌드이며 앱 내 업데이트, artifact, GitHub Release
  또는 전용 태그를 만들지 않는다. 다음 Hikari 변경 전
  `HIKARI_MARKETING_VERSION`과 `HIKARI_BUILD_NUMBER`을 함께 올린다.

## Unreleased — Native 지속 검증 및 검은 잠금 화면 복구

### 이슈와 영향

- macOS 26 전환을 앞두고 일반 push/PR의 표준 CI는 macOS 15만, Native Local CI도
  macOS 15만 실행했다. 표준 macOS 26 검사는 major release tag에서만 실행돼 일상적인
  변경의 호환성 회귀를 조기에 발견할 수 없었다.
- display/Space 변경 알림이 누락되거나 choice가 적용 뒤 생성되면 일반 wallpaper session과
  Native Lock mapping이 다음 이벤트 전까지 갱신되지 않을 수 있었다.
- 새 데스크탑을 만들거나 Mission Control을 닫은 뒤, 기존 wallpaper `NSWindow`는 남아도
  `AVPlayerLayer`의 WindowServer 표시 표면만 비어 검은 배경이 보일 수 있었다.
- 실제 macOS 15.7.9에서 Native mapping과 system asset은 정상인데도 unlock ramp-down 중
  `WallpaperVideoCore.VideoSampleReadingErrors` Code 4가 발생했다. 고착된
  `WallpaperVideoExtension`은 다음 잠금에서 frame을 enqueue하지 않아 검은 화면을 보였다.
- macOS 26.6.1에서는 manifest schema version 1과 user index의 기본 구조가 읽혔지만,
  실제 local Apply 뒤 macOS가 새 wallpaper mapping을 유지하지 않아 Native Lock을
  활성 상태로 전환할 수 없었다.
- 메뉴 막대 팝오버가 외부 클릭 뒤에도 남는 경우가 있었고, 기존 앱 비활성화 처리는
  별도 설정 창까지 함께 숨겼다.
- Native Lock이 활성 또는 복구 필요 상태인 채 macOS major version을 올리면, 새 OS에서
  write가 차단될 뿐 아니라 기존 transaction의 Restore도 같은 guard에 막힐 수 있다.

### 조치

- 일반 build/test와 Native Local compile/test를 macOS 15 및 26 runner matrix로
  전환했다. major release 호환성 job은 중복 실행을 피하면서 macOS 14 검증을 추가로
  유지한다. Native Local CI는 macOS 26에서도 앱을 실행하거나 system write를 하지 않고
  compile/test와 번들 격리만 확인한다.
- Native Local 앱의 제품명과 표시명을 `Hikari`로 변경했다. 로컬 빌드 스크립트는
  산출물을 `/Applications/Hikari.app`에 교체 설치하고 Launch Services와 Spotlight에
  명시적으로 등록해 검색 후 직접 실행할 수 있게 한다. bundle ID와 별도 저장소,
  CI의 compile/test-only 격리는 그대로 유지한다.
- Native Local의 설정, 환영 화면, 메뉴, 오류 안내와 system Aerial category에 남아 있던
  일반 앱 제품명을 `Hikari`로 분기했다. 일반 빌드의 `Lumina` 표기와 기존 저장소 경로,
  bundle ID 및 transaction 식별자는 호환성을 위해 유지한다.
- 일반 wallpaper는 콘텐츠가 있는 동안 5초 간격으로 display topology, player 오류,
  다중 session drift를 함께 조정한다. Pause 중에도 topology 확인은 유지한다.
- Space 변경의 초기 두 확인에서는 창의 all-Spaces 소속만 다시 확인하고, 최종 안정화
  확인에서만 재생 상태를 보존해 wallpaper 창과 `AVPlayerLayer`를 한 번 재생성한다.
- Native Local은 active mapping을 5초마다 확인하고 drift가 있을 때만 user index를
  transaction 방식으로 조정한다. 새 choice의 원래 값은 exact path restore overlay에
  저장해 나중에 현재 display/Space topology를 보존하며 복원한다.
- active transaction이 있으면 앱 시작과 unlock 직후 `WallpaperAgent`를 한 번 재시작해
  다음 잠금 전에 system video renderer를 새로 구성한다. 주기 검사는 관리자 승인,
  privileged helper 또는 system manifest/media write를 실행하지 않는다.
- 메뉴 막대 팝오버가 표시된 동안 외부 마우스 클릭을 감시해 닫되, 별도 설정 창을
  숨기던 app-deactivation 처리는 제거한다. 큰 설정 창은 빨간 닫기 버튼으로만 숨긴다.
- Native Lock의 미완료 transaction에는 설정 화면에서 macOS major 업데이트 전 Restore를
  요구하는 경고를 표시한다. 현재 major-version write guard는 유지한다.
- macOS 26에는 root-owned legacy catalog를 사용하지 않는 user Aerial transaction을
  추가했다. Hikari 영상과 PNG preview를 현재 사용자의 Aerial media store에 두고,
  schema version 1 manifest에 Hikari 전용 asset/category를 병합한다. user index에서는
  Lock Screen 경로인 `Linked` choice만 Hikari asset ID로 바꾸며 `Desktop`과 `Idle`은
  보존한다. Apply와 Restore는 원본 manifest/index bytes, hash, 단계별 journal 및
  선택적 외부 변경 보존을 사용한다. macOS 15 root helper 경로는 그대로 유지한다.

### 검증

- workflow YAML과 matrix 구성을 로컬에서 검증하고, push 뒤 macOS 15/26 표준 및
  Native Local GitHub Actions 결과를 확인한다.
- `Hikari.app`의 앱 이름, 실행 파일, bundle ID, 설치 경로, ad-hoc 서명 및 Spotlight
  등록을 로컬 빌드와 Native Local CI 번들 검사에서 확인한다. macOS 26.6.1 로컬
  실행에서 일반·모양·Native 잠금·정보 탭의 제품명 표기가 `Hikari`이며, 같은 소스의
  macOS 13 일반 빌드 compilation condition도 통과했다.
- `swift build`와 Native Local 로컬 앱 빌드, macOS 13 standard 직접 컴파일 통과.
- 임시 user index에서 새 display choice 추가 → 자동 reconcile → 전체 asset ID 일치 →
  restore overlay로 새 display 원래 값과 기존 원래 값을 각각 복구하는 round trip 통과.
- 기존 v0.3.1 active journal에 새 optional 필드가 없는 상태로 새 앱을 실행해 record를
  읽고 `WallpaperAgent`/`WallpaperVideoExtension` PID가 교체되며 refresh 로그가 남는
  것을 확인했다.
- Space 복구 스케줄은 초기 확인 두 번과 최종 표면 재생성 한 번으로 분리된다. 실제
  Mission Control·새 데스크탑 반복 전환에서의 표시 복구는 수동 확인이 필요하다.
- macOS 26.6.1 실제 local Apply는 `wallpaperMappingRejected`로 실패했다. 즉시 Restore를
  실행해 Hikari system asset/category와 staged asset reference가 모두 제거되고 journal이
  `restored`로 끝난 것을 확인했다. 따라서 macOS 26 system write는 활성화하지 않는다.
  Native 설정의 Apply 버튼도 safety report가 `ready`가 아닌 동안 비활성화한다.
- 실제 잠금 화면의 영상 표시와 unlock 뒤 다음 잠금 재발 방지는 macOS 15에서만 수동 확인
  대상이며, macOS 26은 공식 catalog refresh/selection 경로가 확인될 때까지 차단한다.
- active·recoveryRequired·restored·없음의 transaction phase별 major-update Restore 경고
  조건을 Native Lock 단위 테스트로 검증한다.
- 격리된 임시 macOS 26 user Aerial store에서 Hikari Apply → 모든 `Linked` choice의
  asset ID 유지 → Desktop/Idle 원본 보존 → Restore 후 원본 manifest/index bytes 일치와
  staged media 삭제까지 확인했다. 실제 사용자 store에는 Hikari Apply를 실행하지
  않았다. 같은 store를 수정하는 다른 도구가 실행 중이면 먼저 해당 transaction을
  복원하거나 종료한 뒤 실제 Hikari lock → unlock → Restore 수동 검증을 수행한다.

## v0.3.1 — 2026-08-14

### 이슈와 영향

- v0.3.0의 ZIP digest 자체는 정확했지만 `.sha256` 안의 대상 이름이
  `dist/Lumina-macOS-portable.zip`이었다. 두 release asset을 같은 폴더에 받은 뒤
  README의 `shasum -a 256 -c` 명령을 실행하면 파일을 찾지 못해 실패했다.

### 원인 및 조치

- package job이 저장소 루트에서 `dist/...zip`을 hash해 그 상대 경로까지 checksum
  파일에 기록했다. `dist` 안에서 basename만 hash하도록 바꾸고, artifact를 업로드하기
  전에 CI가 생성된 checksum 파일로 ZIP을 다시 검증하는 gate를 추가했다.
- 이미 push한 `v0.3.0` 태그는 이동하거나 재사용하지 않고 `v0.3.1`로 후속 릴리스한다.

### 검증

- 실제 v0.3.0 release asset을 다운로드해 ZIP의 SHA-256 값은 asset digest와 같고,
  실패 원인이 checksum 내부의 `dist/` 경로임을 확인했다.
- v0.3.1 태그 CI에서 Debug/Release/XCTest, portable 격리, package 단계 자체 checksum,
  GitHub Release 다운로드 후 checksum을 다시 검증한다.

## v0.3.0 — 2026-08-14

### 이슈와 사용자 영향

- 일반 Lumina의 화면 보호기 방식은 시스템 잠금 단축키 직후 native Lock Screen에서
  임의 영상을 직접 재생할 수 없다.
- 기존 Native Local 타깃은 별도 bundle/storage/CI와 안전 상태 UI만 제공했고 실제
  적용·복원 경로가 없었다.
- MP4만 가정한 가져오기 경로와 로컬 수동 빌드의 누락된 앱 아이콘 때문에 MOV/M4V
  사용 및 실행본 식별이 불편했다.

### 원인 및 조치

- 일반 타깃은 기존 ScreenSaver.framework, 선택형 event tap, macOS 13 배포 범위를
  그대로 유지한다. Native Local은 macOS 15 전용 소스 빌드로 분리하고 시스템 소유
  `Control-Command-Q` 경로를 그대로 사용한다.
- Native Local에 user/root 양쪽의 hash 검증 백업, 단계별 journal, 조건부 rollback,
  선택적 외부 변경 보존, 명시적 복원을 구현했다. root 변경은 설치형 daemon이 아닌
  매 작업 관리자 승인을 요구하는 고정 인자 one-shot 도구만 사용한다. backup,
  journal, active marker 및 원자적 교체 파일은 파일과 상위 디렉터리까지 `fsync`한
  뒤 다음 단계로 진행한다.
- 실행 중인 `WallpaperAgent`가 새 user index를 덮어쓰는 실제 장비 race를 수정했다.
  에이전트를 먼저 정지한 상태에서 index를 교체하고 재시작 뒤 모든 choice의 asset
  ID가 유지되는지 검증한다. root transaction 동안 `idleassetsd`도 먼저 정지하고,
  종료 뒤 launchd가 새 manifest와 cache 상태로 재시작하게 한다.
- AVFoundation이 재생 가능한 MP4, MOV, M4V를 원본 확장자로 관리하고 Native 적용
  시 검증된 MOV로 export한다. 로컬 빌드 스크립트는 `.icns`, localization, helper,
  ad-hoc 서명 검증을 한 번에 구성한다.
- standard/native CI를 분리했다. Native workflow는 compile/test/번들 격리만 하고
  앱 실행, root 작업, artifact 업로드 또는 release를 하지 않는다.

### 검증

- Command Line Tools 환경에서 `swift build`, `xcodegen generate`, workflow YAML
  parsing, macOS 13 standard compilation condition, macOS 15 Native compilation
  condition을 통과했다.
- `scripts/build-native-local.sh` 산출물에서 앱 아이콘, embedded one-shot tool,
  ad-hoc signature를 확인했다.
- 임시 system/user 경로를 사용한 apply → 외부 manifest 변경 보존 → restore 수동
  round trip이 원본 index/manifest 복원과 active marker 제거를 통과했다.
- 실제 macOS 15.7.9 장비에서 영상·미리보기 hash와 system manifest 등록을 확인했고,
  `idleassetsd` DB 인덱싱 완료 뒤 에이전트를 재시작해 1/5/10/20/30/40초 시점에
  12개 display/Space/Desktop/Idle choice가 동일 asset ID를 유지하는 것을 확인했다.
  복원 뒤에는 12개 choice가 적용 전 asset ID로 돌아가고,
  Lumina system asset/category, root-owned 영상·미리보기, user active marker가 제거되며
  user journal이 `restored`로 끝나는 것도 확인했다.
- 전체 XCTest와 Xcode Debug/Release 번들 검사는 PR의 standard/native macOS 15 CI
  결과로 최종 확인한다.

### 남은 제약

- Native system write는 확인된 macOS 15, manifest schema version 1에서만 활성화된다.
- Native Local은 소스 전용이며 GitHub release artifact나 앱 내 업데이트로 배포하지
  않는다. 일반 Portable 앱만 태그 workflow에서 패키징한다.
- 다중 디스플레이·장시간 sleep/wake 실제 검증은 Git에서 제외된
  `.personal/MULTI_DISPLAY_SLEEP_WAKE_VALIDATION.md` 절차로 계속 수행한다.

## v0.2.11 — 2026-08-13

### 이슈

- 메뉴 막대에서 설정을 연 뒤 다른 앱 창이나 바탕화면을 클릭해도 설정 창이 계속 남아 있었다.
- 여러 디스플레이에서 사용한 뒤 잠자기에서 복귀하면, 화면 구성은 그대로인데 Lumina 배경이 검은 화면으로 남을 수 있었다.

### 원인 및 조치

- 설정 창은 닫기 버튼만 숨기도록 처리돼 있었고, Lumina가 비활성화될 때 숨기는 처리가 없었다. 앱 비활성화 시 설정 창만 숨기며, 파일 선택 시트 등 Lumina 소유 창은 정상적으로 유지한다.
- v0.1.15의 다중 디스플레이 토폴로지 최적화가 화면 구성에 변화가 없으면 기존 창과 `AVPlayerLayer`를 재사용했다. wake 뒤 WindowServer가 해당 레이어 표면을 잃으면 이 경로로는 복구되지 않는다. 화면 복구 알림마다 모든 배경 세션을 재생 상태, 음소거, 현재 콘텐츠를 보존한 채 다시 만든다.

### 검증

- macOS CI에서 Debug/Release 빌드, 코어 단위 테스트, 내장 `.saver` 번들 검사를 통과시킨다.
- 실제 장비에서 설정을 열고 Finder·바탕화면을 클릭해 설정 창이 숨겨지는지 확인한다.
- 두 대 이상 디스플레이 연결 상태에서 잠자기·복귀를 반복해 각 디스플레이가 영상으로 복구되는지 확인한다.

## v0.2.10 — 2026-08-11

### 이슈

- v0.2.9가 설치되고 권한도 모두 허용됐지만, 내장 키보드의 `Control` + `Command` + `Q`가 여전히 Lumina에 도달하지 않았다.

### 원인 및 조치

- 세션 단계 event tap은 macOS 표준 잠금 단축키가 시스템에 소비된 뒤에 실행될 수 있다.
- HID 단계 event tap을 우선 사용하고, 지원되지 않는 환경에서는 기존 세션 탭으로 폴백한다.
- event tap 생성 실패·활성화·실제 단축키 수신을 `com.hodadako.Lumina/LockShortcut` unified log에 기록한다.

### 검증 계획

- macOS CI 빌드·테스트·릴리스 패키징을 통과시킨다.
- v0.2.10 설치 후 내장 키보드 단축키를 누르고 unified log에서 수신을 확인한다.

### 실제 장비 권한 확인

- 초기에는 현재 프로세스의 Accessibility만 허용되고 Input Monitoring은 미허용이었다.
  이 경우 기본 macOS 잠금이 실행된다.
- 권한을 재부여하고 Lumina를 재실행한 뒤 두 런타임 권한 API가 모두 허용 상태이며,
  전역 event tap 생성 로그가 남는 것을 확인했다.

## v0.2.9 — 2026-08-11

### 이슈

- v0.2.8에서 Accessibility와 Input Monitoring이 모두 시스템 설정에서 허용된 상태인데도 내장 키보드의 Lumina 잠금 단축키가 동작하지 않았다.

### 원인 및 조치

- v0.2.8은 `CGPreflightListenEventAccess()`가 false이면 `CGEvent.tapCreate`를 시도하지 않았다. 이 사전 판정은 TCC 설정 화면의 현재 상태보다 늦게 갱신될 수 있다.
- v0.2.9는 Accessibility만 확인한 뒤 CoreGraphics의 실제 event tap 생성 결과를 사용한다. Input Monitoring 권한 요청과 안내는 유지한다.
- 화면 보호기 설치 갱신 뒤 Lumina가 선택된 상태라면, 이전 `legacyScreenSaver` 호스트를 종료해 다음 실행이 새 `.saver`를 사용하도록 한다.

### 검증 계획

- macOS CI 빌드·테스트와 릴리스 패키징을 통과시킨다.
- 실제 장비에서 내장 키보드 `Control` + `Command` + `Q`로 event tap과 화면 보호기 실행을 확인한다.

## v0.2.8 — 2026-08-11

### 이슈

- `Control` + `Command` + `Q` 루미나 잠금 단축키가 일부 macOS 15 환경에서 동작하지 않았다.

### 조치 및 검증

- 전역 키보드 이벤트 감시에 필요한 **손쉬운 사용(Accessibility)** 및 **입력 모니터링(Input Monitoring)** 권한을 함께 점검하고, 부족하면 시스템 권한 요청을 하도록 수정했다.
- 설정 화면에 필요한 두 권한을 명시하고, 단축키를 켤 때 두 권한을 안내한다.
- 문자열 파일 검사와 코어 릴리스 타입 검사 통과. 태그 CI의 메타데이터·빌드·테스트 단계 통과; 패키지 아티팩트 단계는 기록 시점에 진행 중이었다.

### 남은 확인 사항

- 업데이트 뒤 설정에서 단축키를 껐다가 다시 켜고, Lumina에 두 권한을 모두 부여한 뒤 재실행하여 실제 단축키를 확인한다.
- Karabiner 등 다른 전역 단축키 도구가 같은 조합을 가로채는지 확인한다. 실제 확인에서 Q 조합을 가로채는 규칙은 없었지만, 외장 키보드의 Command/Option 교환 때문에 물리 키 조합이 달라질 수 있었다.

## v0.2.7 — 2026-08-11

### 이슈

- 앱의 업데이트 확인이 실패했다.

### 원인 및 조치

- GitHub Release JSON을 해석할 때 `convertFromSnakeCase`를 적용하면서, 이미 snake_case로 지정한 `CodingKeys`와 충돌해 `tag_name`을 찾지 못했다.
- 키 변환 전략을 제거하고 실제 `v0.2.6` 릴리스 응답을 정상 해석하는 것으로 확인했다.

### 검증

- 태그 CI의 메타데이터, 빌드, 테스트, 릴리스 패키징 성공.

## v0.2.6 — 2026-08-11

### 이슈

- v0.2.5에서 화면 보호기 컨테이너의 비디오를 강제로 앱 루트에서 열고 즉시 재생하도록 바꾼 뒤, 루미나 잠금 화면 재생이 회귀했다.

### 조치

- 화면 보호기 프로세스에서는 원래의 컨테이너 기본 경로와 일반 `play()` 동작으로 복원했다.

### 검증

- 태그 CI의 메타데이터, 빌드, 테스트, 릴리스 패키징 성공.

## v0.2.5 — 2026-08-11

### 이슈

- 설정 창을 닫으면 메뉴 막대 앱이 같이 종료된 것처럼 보였다.
- 잠금 후 복귀 시 비디오 재생 상태가 복구되지 않을 수 있었다.
- 메뉴 막대 아이콘의 반짝임 위치 조정이 필요했다.

### 조치

- 설정 창 닫기를 앱 종료가 아닌 창 숨김으로 처리했다.
- 잠금 복귀 시 화면 보호기 실행 상태를 해제하고 재생 복구를 예약했다.
- 기존 아이콘 크기를 유지한 채 반짝임 위치만 소폭 위로 조정했다.

### 검증

- 태그 CI의 메타데이터, 빌드, 테스트, 릴리스 패키징 성공.
