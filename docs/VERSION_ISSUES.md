# 버전별 이슈 및 검증 기록

최신 항목을 위에 추가한다. 각 릴리스에는 사용자 영향, 원인, 조치, 검증, 남은 제약을 기록한다.

## Unreleased — Hikari ad-hoc release channel

### 이슈와 영향

- Hikari는 Native Local compile/test와 별도 ad-hoc release asset을 게시할 수 있는
  경로로 분리되어 있으며, 첫 Hikari tag 전에는 일반 Lumina Portable 릴리스에 포함되지
  않는다.
- Hikari `0.1.9 (10)` preflight 변경에서 Native Local CI 테스트 helper의 명시적 `return`이
  누락되어 macOS 15·26 Unit test compile이 실패했다.

### 조치

- `hikari-vX.Y.Z` tag 전용 Hikari Release workflow를 추가했다. macOS 15·26 build/test와
  Release bundle isolation을 통과한 뒤 현재 ad-hoc 서명 구조로 Hikari ZIP과 SHA-256
  checksum을 만들고 별도 GitHub Release asset으로 게시한다.
- 일반 Lumina Portable release workflow와 Hikari release를 분리하고, Hikari version/build
  값을 tag·bundle plist·package output에서 검증한다.
- 테스트 helper의 plist 생성식에 명시적 `return`을 추가했다.
- transaction backup/hash 검증, `Linked` topology 안전성, macOS major-version guard,
  Restore 및 외부 writer 보호 같은 Native Lock runtime guard는 유지한다.

### 검증

- 실패 run `32564671678`과 최신 run `32587430131`의 원인이 테스트 helper의 missing return임을
  확인하고 수정했다.
- Hikari package workflow는 ad-hoc signing, `codesign --verify --deep --strict`, ZIP
  checksum 검증 및 Hikari bundle version/isolation 검사를 포함한다.
- 실제 tag release 실행, GitHub asset 다운로드 후 checksum, Gatekeeper 경고, macOS 15
  관리자 승인 동작의 수동 검증은 첫 Hikari release tag에서 수행해야 한다. Hikari는
  Lumina의 선택적 전역 event-tap 단축키를 사용하지 않으므로 Accessibility/Input Monitoring
  권한 재승인은 이 release 경로의 검증 항목이 아니다.

### 남은 제약

- Hikari release asset은 Developer ID/notarization이 아닌 ad-hoc·비공증 실험용 배포다.
  앱 내 자동 업데이트에는 포함하지 않는다.
- 실제 release tag를 push하기 전, 현재 Hikari `0.1.10 (11)`의 macOS 15·26 Native Local
  CI와 release workflow를 다시 통과시켜야 한다.

## Hikari v0.1.10 (11) — 2026-08-23

### 이슈와 영향

- macOS 26의 새 사용자 index가 `Desktop`·`Idle`만 가진 Mac에서는 Hikari가 Lock Screen
  적용 전에 사용자가 별도 Apple Aerial 선택을 해야 했다.
- 사용자가 확인한 외부 앱은 실행 직후 기존 Apple Aerial asset을 선택해 `Linked` topology를
  materialize한 뒤 적용을 진행했다.
- 이전 Backdrop의 `BackdropWallpaper` renderer가 실행 중이면 Hikari가 쓴 `Linked` choice를
  즉시 이전 asset으로 되돌려 자동 Apply가 `wallpaperMappingRejected`가 됐다.
- 세로 영상의 원본과 Aerial용 변환본은 모두 1080×1920 및 정상 transform인데도 Lock Screen에서
  영상이 위아래로 늘어져 보였다. 기존 `Linked` choice의 `EncodedOptionValues`가 문자열
  `$null`인 상태였다.

### 조치

- Native Local Hikari는 macOS 26 첫 실행 시 선택 영상이 있고 active/recovery transaction이
  없으면 자동 Apply를 시작한다.
- `Linked`가 없으면 기존 user Aerial manifest에서 media와 preview가 실제로 존재하는 Apple
  asset을 읽고, 현재 `com.apple.spaces`와 NSScreen display ID로 `SystemDefault`·Space·display
  linked topology를 transaction 안에서 준비한다. Desktop/Idle 값은 fallback으로 사용하지 않는다.
- 원본 `Index.plist`를 먼저 transaction backup하고 materialized index hash를 journal에 남긴다.
  Apply 또는 Restore 중간에 중단돼도 원본 hash와 materialized hash를 비교해 외부 변경을 보존한다.
- Hikari 영상은 macOS 26 Aerial renderer가 요구하는 video-only 10-bit HEVC Main10 형식으로
  준비한다. 자동 초기화와 Hikari manifest/media/index 변경은 `WallpaperAgent`와
  `WallpaperAerialsExtension`을 정지한 구간에서 수행한다.
- Apply와 active 유지보수 직전에 실행 중인 `BackdropWallpaper` helper만 종료한다. Backdrop의
  manifest/media record는 보존한다.
- macOS 26 `Linked` choice를 갱신할 때 기존 바이너리 `EncodedOptionValues`를 보존하고, 값이
  없으면 바이너리 plist의 `values.placement.picker._0.id = FillScreen`을 기록한다. 새로
  materialize하는 Linked topology에도 같은 옵션을 넣어 Aerial renderer의 레거시 stretch
  fallback을 피한다. macOS 15의 전체 choice 경로에는 이 modern placement 값을 쓰지 않는다.

### 검증

- 성공 외부 앱의 실제 결과와 비교해 `Linked` path, `Type: linked`, nested `Configuration`
  `{assetID: ...}` 구조를 확인했다.
- 격리된 transaction 단위 테스트에서 `Desktop`·`Idle`만 있는 index를 materialize한 뒤
  Restore하면 원본 bytes가 그대로 돌아오는지 검증했다.
- Native Local 직접 빌드·ad-hoc 서명 검증 통과. Command Line Tools 환경의 XCTest 실행은
  `XCTest` 모듈 부재로 여전히 실행할 수 없으며 전체 Xcode CI에서 최종 확인한다.
- Backdrop renderer를 종료한 상태에서 최신 Hikari 자동 Apply transaction
  `1B512569-A657-461F-BD42-2BADEB04A388`가 `active`가 되고 30초 mapping 안정화 검증을
  통과했으며, Backdrop category/asset은 manifest에 그대로 남았다.
- 최신 옵션 수정본을 빌드·설치한 뒤 transaction `4F264DEE-DEA1-427F-BBBB-3B033D1F2918`가
  `active`가 됐고, 실제 user `Index.plist`의 Linked option을 바이너리 plist로 읽어
  `FillScreen` 값을 확인했다. Native Local 빌드는 통과했으며, Command Line Tools 환경에서는
  `XCTest` 모듈 부재 제약이 계속되어 회귀 테스트는 full Xcode CI에서 실행해야 한다.
- `FillScreen` 옵션만으로는 세로 원본이 늘어지는 현상이 없어지지 않아, Apple 로컬 Aerial
  영상이 사용하는 16:9 가로 캔버스(1920×1080)를 기준으로 다시 수정했다. 세로 원본은 이
  캔버스 중앙에 비율을 유지해 letterbox로 합성하고 10-bit HEVC로 인코딩한다. 소스 transform은
  합성 transform에 한 번만 반영하며, 회전 영상도 같은 fit geometry를 사용한다.
- 16:9 합성 후에도 원본 `AVAssetTrack`을 `AVAssetReaderVideoCompositionOutput`에 직접
  넘기면 portrait 프레임의 source-space origin이 다시 적용돼 왼쪽으로 밀렸다. 입력을
  identity preferred transform의 `AVMutableCompositionTrack`으로 중립화한 뒤 Hikari의
  합성 transform만 적용하도록 수정했다. 임의의 pixel 보정값은 추가하지 않았다.

### 남은 제약

- 자동 Apply는 선택 영상이 이미 있고 macOS 26 user Aerial manifest에 로컬 Apple asset이
  하나 이상 있어야 한다. Apple manifest나 Space/display ID를 추측 생성하지 않는다.
- Native Local은 source build와 별도 ad-hoc release asset으로 게시할 수 있으며 앱 실행 시
  실제 user wallpaper를 변경하므로, 적용 중 같은 wallpaper store를 수정하는 외부 앱을
  동시에 실행하지 않는다.
- Hikari가 자동으로 종료하는 것은 알려진 `BackdropWallpaper` renderer process뿐이다. 다른
  wallpaper 도구가 같은 store를 쓰면 먼저 종료해야 하며, Hikari는 이를 임의로 제거하지 않는다.
- 실제 Lock Screen에서 세로 영상이 늘어나지 않는지와 FillScreen의 가장자리 crop 여부는 이
  Mac에서 잠금·해제 수동 확인이 필요하다. 옵션 타입/값과 영상 metadata만으로 최종 화면
  렌더링을 보증할 수는 없다.
- 새 가로 캔버스 변환본으로 다시 Apply한 뒤 잠금·해제하는 수동 검증이 남아 있다. 16:9
  캔버스와 다른 display 비율에서는 검은 letterbox가 보일 수 있지만 원본 영상은 비율을
  유지해야 한다.
- 중앙 정렬 수정본을 Native Local로 다시 Apply한 transaction
  `61F4266D-F52F-42D4-8404-F5B69098A742`가 `active` 상태이고, 생성된 Aerial thumbnail
  `1280×720`의 비검정 영역이 `x=434…844`(중심 `639`, canvas 중심 `640`)로 측정됐다.
  30초 후에도 같은 geometry와 active mapping을 유지했다. 최종 Lock Screen surface의
  display별 crop 여부는 잠금·해제 수동 확인이 필요하다.

## Hikari v0.1.9 (10) — 2026-08-22

### 이슈와 영향

- 현재 Mac의 macOS 26 `Index.plist`가 `Desktop`·`Idle`만 가진 topology에서는
  Native Lock Apply가 Aerial manifest/media를 먼저 준비한 뒤 `Linked` choice가 없음을
  발견했다. 이 경우 적용할 Lock Screen target은 없지만 recovery-only journal이 남을 수 있었다.

### 조치

- macOS 26 Apply는 media 준비·transaction 생성·Aerial manifest 쓰기 전에 read-only로
  Apple-materialized `Linked` choice를 검사한다. 없으면 어떠한 Native Lock 파일도 쓰지 않고,
  System Settings에서 Apple Aerial을 선택·다운로드하라는 오류를 반환한다.
- 비교한 성공 Mac의 active `userAerials` transaction은 원본에 8개 `Linked` choice가 있었고,
  topology 정리 뒤에도 2개가 active Hikari asset을 가리켰다. `Desktop`과 `Idle`은 계속
  변경 대상이 아니다.

### 검증

- 격리된 index에서 Apple-materialized `Linked` choice가 있으면 preflight가 통과하고,
  `Desktop`·`Idle`만 있으면 거부하는 단위 테스트를 추가했다.
- 현재 Mac과 성공 Mac의 journal/index를 읽기 전용 비교해, 성공 기록의 provider와 nested
  configuration 구조가 동일한 Aerial `Linked` choice임을 확인했다.

### 남은 제약

- Apple이 `Linked` choice를 materialize하는 lifecycle은 macOS가 소유한다. Hikari는 그
  구조를 만들거나 Desktop/Idle choice를 대체하지 않는다.

## Hikari v0.1.8 (9) — 2026-08-22

### 이슈와 영향

- macOS 26 Native Lock transaction의 applied manifest hash가 외부 변경으로 달라진 상태에서 Restore하면, 현재 transaction 외의 Hikari asset이 공유하는 Hikari category까지 제거해 외부 asset을 orphan할 수 있었다.

### 조치

- 선택적 Restore는 현재 transaction asset만 제거한다. 남아 있는 Hikari asset이 shared category/subcategory를 참조하면 category record를 보존한다.

### 검증

- 외부 Hikari asset을 manifest에 추가한 뒤 현재 transaction을 Restore해, 현재 asset만 사라지고 외부 asset과 Hikari category가 남는 단위 테스트를 추가했다.

### 남은 제약

- `Linked` Lock Screen choice가 없는 현재 Mac에서는 Native Lock Apply를 계속 차단한다. Restore는 failed transaction의 manifest/media 정리에만 사용한다.

## Hikari v0.1.7 (8) — 2026-08-22

### 이슈와 영향

- 설정 창의 영상 라이브러리가 portrait 영상을 썸네일 프레임에 맞추기 위해 aspect-fill crop을 사용했다. 위아래가 잘리고, 이전 버전에서는 clip 순서에 따라 행 밖에 그려질 수도 있었다.

### 조치

- 공용 `ThumbnailView`를 검은 배경의 고정 프레임 안에서 aspect-fit으로 그리도록 바꿨다. 영상 전체가 라이브러리와 메뉴 팝오버의 `72×44pt` 프레임 안에 보이며, 남는 공간은 letterbox로 처리한다.

### 검증

- Native Local 전체 빌드와 ad-hoc 서명 검증으로 SwiftUI 앱 소스·bundle version을 확인한다.

### 남은 제약

- portrait 및 landscape 영상의 실제 표시 품질은 설정 창에서 수동 확인이 필요하다.

## Hikari v0.1.6 (7) — 2026-08-22

### 이슈와 영향

- 2개와 3개 디스플레이를 오갈 때 최종 topology 확인이 연결되지 않은 화면까지 포함해 모든 `AVPlayerLayer`를 재생성했다. 각 영상이 다시 준비되며 화면이 버벅였다.
- 설정과 메뉴 막대의 영상 썸네일은 호출자가 크기를 제한한 뒤 내부 clip을 적용했다. 세로 비율 썸네일이 자신의 intrinsic bounds로 먼저 그려져 설정 창 밖으로 보일 수 있었다.
- 이 Mac의 macOS 26.6.1에는 backend 정보가 없는 구형 Native Lock journal이 `recoveryRequired`로 남아 있었다. 기록된 오류는 macOS 26에서 구형 helper가 system write 전에 거절된 경우였지만, 이후 Native Lock Apply까지 막혔다.

### 조치

- display 전환의 최종 pass는 topology와 실제 playback 오류만 조정한다. wake와 Space 복구의 명시적 surface rebuild는 유지하되, display 추가/제거만으로 건강한 기존 session을 다시 만들지 않는다.
- `ThumbnailView`가 제안된 고정 크기 안에서 먼저 frame·clip·compositing을 적용하도록 바꿨다.
- macOS 26의 정확한 legacy-helper preflight 실패(backend 없음, user/system applied hash 없음, 알려진 거절 오류)만 `Clear Failed Preparation`으로 journal을 완료 처리할 수 있게 했다. 실제 mapping 또는 manifest가 적용됐을 가능성이 있는 transaction은 이 경로로 절대 해제하지 않고 Restore를 계속 요구한다.

### 검증

- Native Lock의 알려진 무변경 preflight failure는 해제되고 applied mapping hash가 있는 journal은 해제되지 않는 단위 테스트를 추가했다.
- SwiftPM/XCTest는 활성 developer directory가 Command Line Tools를 가리켜 실행하지 못했다. 전체 Xcode 환경의 Native Local CI 또는 로컬 full Xcode에서 최종 빌드·테스트가 필요하다.

### 남은 제약

- 실제 디스플레이 연결·해제의 프레임 연속성과 세로 영상 썸네일 clipping은 이 Mac에서 수동 확인이 필요하다.
- macOS 26의 실제 Native Lock Apply → lock → unlock → Restore는 Aerial store를 수정하므로 사용자가 Hikari에서 명시적으로 수행해야 한다. 구형 transaction에 user/system applied hash가 있으면 원래 macOS 15에서 Restore해야 한다.

## Unreleased — macOS 26 Native Lock 초기화 및 구형 헬퍼 실행 수정

### 이슈와 영향

- macOS 26에서 Native Lock 적용 시 `The Native Lock helper failed: Native Lock system writes are not enabled for macOS 26.` 오류가 발생했다. `restore()`에서 `journal.backend == nil`인 구형 저널이 macOS 26에서도 `runPrivilegedTool()`로 라우팅됐기 때문이다.
- macOS 26에서 Apple Aerial 카탈로그가 초기화되지 않은 경우 `entries.json`이 없어 `apply()` 중 저수준 파일 없음 오류가 발생했다.
- `build-native-local.sh`가 기존 Hikari 프로세스를 종료하지 않고 번들을 교체해, 구형 실행 파일이 새 번들 파일을 계속 사용할 수 있었다.

### 조치

- `NativeLockRuntimeBackend` 열거형(`legacySystemCatalog`, `userAerials`, `unknownLegacy`)을 추가해 백엔드를 명시적으로 결정한다. `nil` 백엔드 저널은 macOS 26에서 `unknownLegacy`로 처리하고 `legacyTransactionUnsupportedOnCurrentOperatingSystem` 오류를 반환한다.
- `runPrivilegedTool()`에 방어적 macOS 26 가드를 추가해 라우팅 오류가 있어도 헬퍼를 실행하지 않는다.
- `NativeLockModernTransactionManager.apply()`에서 `entries.json` 부재 시 `aerialCatalogMissing` 도메인 오류를 반환한다.
- `NativeLockSafetyInspector`에 Aerial 카탈로그 사전 검사를 추가하고 `aerialCatalogRequired` 안전 상태를 노출한다. 매니페스트 없음·스키마 불일치를 구분한다.
- `build-native-local.sh`가 번들 교체 전 `com.hodadako.Lumina.NativeLocal` 프로세스만 정상 종료 후 SIGTERM으로 처리한다.
- 영어·한국어 로컬라이제이션에 새 안전 상태 문자열을 추가한다.
- `LOCAL_NATIVE_BUILD.md`에 macOS 15/26 백엔드 차이, macOS 26 Aerial 카탈로그 초기화 전제 조건, 재빌드 후 재실행 안내를 추가한다.

### 검증

- `swift build` 및 `swiftc -typecheck -D LUMINA_NATIVE_LOCAL Sources/LuminaApp/NativeLockController.swift` 통과.
- `swiftc -typecheck Sources/LuminaNativeLock/*.swift` 통과.
- 새 안전 검사 테스트(매니페스트 없음·불일치·정상), 새 오류 모델 테스트, 기존 모던 트랜잭션 테스트 추가. XCTest 실행은 전체 Xcode가 있는 CI에서 확인한다.

### 남은 제약

- `unknownLegacy` 저널(macOS 26에서 `backend == nil` 구형 트랜잭션)은 복원 불가 오류를 반환한다. 해당 트랜잭션은 원래 macOS 15에서 생성됐으므로 macOS 15 환경에서 복원해야 한다.
- macOS 26 실제 장비에서 Aerial 카탈로그 초기화 후 Apply → lock → unlock → Restore 왕복은 수동 확인이 필요하다.

## Hikari v0.1.5 (6) — 2026-08-16

### 이슈와 영향

- 4K H.264 desktop wallpaper를 재생 중인 Hikari의 30초 표본은 CPU 22~24%,
  RSS 약 350MB를 보였다. physical footprint는 약 118MB로 안정적이어서
  지속적인 메모리 증가가 아니라 렌더링 비용이 문제였다.
- 메뉴 막대 반짝임이 무한 SwiftUI symbol effect로 동작해, 영상 재생 외에도
  상태 항목이 계속 display list를 갱신했다.

### 조치

- 메뉴 막대 반짝임은 정적인 표시로 유지한다. macOS 13 fallback도 무한 opacity
  애니메이션 대신 정적 이미지를 쓴다. 기존 아이콘 크기와 위쪽 offset은 유지한다.

### 검증

- `swift build`, native 로컬 앱 빌드 및 ad-hoc 서명 검증을 통과한다.
- Hikari 실행본의 CPU·RSS를 같은 재생 상태에서 다시 표본 추출해 status-item의
  지속 UI 렌더링 비용이 제거됐는지 확인한다.

### 남은 제약

- 3840×2160, 약 39Mbps H.264 영상의 디코딩 비용은 영상 해상도·코덱에서
  발생한다. 앱은 품질을 자동으로 낮추지 않으며, 더 낮은 사용량이 필요하면
  1080p 또는 낮은 비트레이트 영상을 선택해야 한다.

## Hikari v0.1.3 (4) — 2026-08-16

### 이슈와 영향

- unlock의 보조 playback 확인이 display recovery까지 실행해 desktop 영상 surface를
  세 번 재생성했다. Lock Screen 전환 중 이 재생성은 검은 프레임 플래시를 만들 수
  있었다.

### 조치

- unlock 뒤에는 delayed playback state 확인만 실행한다. desktop surface 재생성은
  실제 잠자기 복귀, 디스플레이 변경 및 Space 전환에만 남긴다.

### 검증

- `swift build`, native 로컬 앱 빌드와 ad-hoc 서명 검증을 통과한다.
- unlock 경로가 `scheduleRecovery`를 호출하지 않고 delayed state 확인만 예약하는지
  코드 검사를 수행한다.

### 남은 제약

- 실제 잠금·unlock 전환의 화면 품질은 사용자 수동 확인이 필요하다.

## Hikari v0.1.2 (3) — 2026-08-16

### 이슈와 영향

- unlock 알림 뒤 약 120ms에 `WallpaperAgent`를 재시작해 Lock Screen의 퇴장
  surface와 겹치면서 데스크톱이 번쩍일 수 있었다.
- 기존 Native Lock export는 fast-start를 끈 채 movie header를 media 뒤에 두어,
  고비트레이트 영상의 첫 프레임 준비가 지연될 수 있었다.

### 조치

- unlock 뒤 2초 동안 Lock Screen 전환이 안정될 때까지 기다린 다음 renderer를 한 번
  새로 시작한다. 잠금 중이면 pending 상태를 유지해 다음 안전한 unlock 뒤 처리한다.
- 새 Native Lock 영상은 passthrough 품질을 유지하면서 fast-start MOV로 export한다.
  기존 active transaction의 hash-보호 영상은 자동 변경하지 않는다.

### 검증

- `swift build`, native 로컬 앱 빌드와 ad-hoc 서명 검증을 통과한다.
- 실제 활성 4K 영상에서 movie header가 media 뒤에 있음을 확인하고, 새 export 경로가
  fast-start 옵션을 사용하는 것을 코드·native compilation으로 검증한다.

### 남은 제약

- 기존 적용 영상은 Restore 후 동일 영상을 다시 Apply해야 fast-start layout으로
  교체된다. 실제 잠금·unlock 전환 품질은 사용자 수동 확인이 필요하다.

## Hikari v0.1.1 (2) — 2026-08-16

### 이슈와 영향

- macOS 26 user Aerial backend는 활성 transaction이어도 앱 시작과 unlock 뒤
  `WallpaperAgent` 재시작을 건너뛰었다. 이전 video renderer가 고착되면 다음
  잠금 화면이 검게 표시될 수 있었다.

### 조치

- backend와 무관하게, active transaction의 시작·unlock refresh 요청은
  `WallpaperAgent`를 한 번 새로 시작한다. choice mapping을 재조정해 이미 agent를
  교체한 경우에는 중복으로 재시작하지 않는다.

### 검증

- macOS 26의 실제 active transaction에서 새 Hikari를 실행해 `WallpaperAgent`가
  새 PID로 다시 시작했고, 모든 `Linked` choice가 Hikari asset ID를 유지하는 것을
  확인한다.
- `swift build`, native 로컬 앱 빌드 및 ad-hoc 서명 검증을 통과한다.

### 남은 제약

- 실제 잠금 → unlock → 다음 잠금의 영상 표시 검증은 잠금 세션을 조작하므로
  사용자 수동 확인이 필요하다.

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

- 당시 Hikari는 source-only 로컬 빌드였으며 앱 내 업데이트, artifact, GitHub Release 또는
  전용 태그를 만들지 않았다. 다음 Hikari 변경 전 `HIKARI_MARKETING_VERSION`과
  `HIKARI_BUILD_NUMBER`을 함께 올린다.

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
- 디스플레이 변경 복구는 WindowServer가 topology를 만드는 동안 초기 확인에서
  display membership와 geometry만 동기화하고, 최종 안정화 확인에서만 wallpaper
  surface를 한 번 재생성한다. 재생 중인 영상의 위치와 재생 의도도 보존한다.
- Space 변경의 초기 두 확인에서는 창의 all-Spaces 소속만 다시 확인하고, 최종 안정화
  확인에서만 재생 상태를 보존해 wallpaper 창과 `AVPlayerLayer`를 한 번 재생성한다.
- 표준 CI의 대표 macOS 15 job에서 `Lumina` XCTest coverage를 Codecov에 보고하되,
  macOS 26 compatibility job과 Native Local compile/test-only workflow는 중복
  upload나 artifact를 만들지 않는다.
- Native Local 직접 빌드는 compiler 도구, 소스·resource 입력, plist와 Hikari 버전의
  읽기 전용 preflight를 먼저 수행한다. macOS가 관리하는 `entries.json`과
  `Index.plist`는 bundle 입력으로 취급하지 않는다.
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
- 디스플레이 복구 정책과 모든 session의 playback position 복원 단위 테스트를 추가하고,
  전체 Xcode 환경의 SwiftPM 57개 테스트와 `LuminaNative` 57개 XCTest를 실패 없이
  실행했다. 표준 `Lumina` coverage XCTest도 35개가 모두 통과했다.
- Native Local build script의 `zsh -n`, plist lint, Swift build 및 workflow YAML
  구문 검사를 통과했다. 실제 `/Applications` 설치와 privileged Native Apply는
  system-write guardrail에 따라 실행하지 않았다.
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
- 당시 Native Local은 소스 전용이며 GitHub release artifact나 앱 내 업데이트로 배포하지
  않았다. 현재 Hikari ad-hoc release channel은 일반 Portable 앱과 분리된다.
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
