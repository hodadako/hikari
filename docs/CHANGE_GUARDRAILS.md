# 변경 금지·주의 사항

이 문서는 검증된 사용자 기대와 운영 제약을 보존한다. 변경하려면 사용자 승인, 재현 가능한 근거, 회귀 검증을 함께 남긴다.

## 사용자 경험

- 설정 창의 빨간 닫기 버튼은 Hikari를 종료하지 않고 설정 창만 숨긴다. 메뉴 막대 아이콘과 앱 기능은 계속 유지되어야 한다.
- 메뉴 막대 팝오버만 외부 클릭에 반응해 닫는다. 별도 설정 창은 앱 비활성화나 외부 클릭으로 숨기지 않고 사용자가 빨간 닫기 버튼을 눌렀을 때만 숨긴다.
- 메뉴 막대의 **Settings**를 선택하면 transient 팝오버를 먼저 닫고 별도 설정 창을 연다. 설정 창과 메뉴 막대 근처에 팝오버가 동시에 남지 않아야 한다.
- 메뉴 막대 아이콘은 기존 디스플레이 아이콘 크기를 유지한다. 반짝임은 아이콘을 가리지 않도록 현재의 소폭 위쪽 오프셋만 유지한다.
- 다른 앱에서 Hikari 설정으로 돌아오는 일반 앱 활성화는 배경 창 또는 영상 레이어를 재생성하지 않는다. 실제 잠자기 복귀, 디스플레이 변경, Space 전환만 해당 복구를 시작할 수 있다.
- `Fill`은 화면을 꽉 채우고 가장자리를 잘라낼 수 있는 모드이며, `Fit`은 영상 전체를 보이게 하는 모드다. 두 동작을 혼동해 바꾸지 않는다.
- Hikari의 설정은 `General`과 `Lock Screen`으로 단순화한다. 모양·재생·관리 영상 라이브러리는 `General`에 두며, 라이브러리는 하나만 유지한다. macOS 26의 active user Aerial transaction에서는 General의 영상 선택을 즉시 Lock Screen에도 transactionally 교체한다. macOS 15의 root catalog 경로와 recovery-required transaction은 명시적 Apply/Restore를 유지한다.

## 재생·legacy 보존

- Hikari는 화면 보호기와 전역 event-tap 잠금 경로를 제공하지 않는다. 해당 소스와 plist는 `Archive/LuminaLegacy`에 보존하며 Hikari target에는 포함하지 않는다.
- 잠금·잠자기·디스플레이·Space 변경 뒤 데스크톱 영상의 재생 상태와 display topology 복구를 유지한다.
- 디스플레이 연결·해제에서 파생된 Space 알림은 건강한 모든 데스크톱 surface를 다시
  만들지 않고 topology와 all-Spaces membership만 확인한다. 디스플레이 전환과 무관한
  실제 Space 변경의 settled surface 복구는 유지한다.
- 다중 디스플레이 데스크톱 wallpaper는 하나의 `AVPlayer`를 화면별 `AVPlayerLayer`로 공유한다. 화면별 독립 디코더·버퍼를 다시 도입하지 않으며, display/Space 복구 때도 공유 player의 재생 위치와 의도를 유지한다.

## 권한·보안·배포

- Hikari는 전역 event-tap 잠금 단축키를 설치하지 않는다. macOS의 Native Lock 경로와 명시적 Restore를 사용한다.
- 현재 다른 앱 컨테이너에 직접 쓰는 저장 방식은 macOS 개인정보 접근 알림의 원인이다. 이 알림을 없애려면 단순 서명 변경이 아니라 App Group 등 공유 저장소 구조로 이전해야 한다.
- Developer ID 서명과 notarization은 배포 정체성을 안정화하지만 TCC 권한을 자동으로 부여하거나 우회하지 않는다.
- ad-hoc 서명으로 앱 정체성이 바뀌면 사용자가 시스템 권한을 다시 부여해야 할 수 있다. 서명 방식을 바꿀 때는 업데이트·권한 흐름을 실제 장비에서 검증한다.
- 문서화되지 않은 macOS wallpaper/aerial 상태를 변경하는 Native Lock은 Hikari의 유일한 제품 경로로 유지한다. Hikari는 일반 `vX.Y.Z` 릴리스의 ad-hoc·비공증 asset으로 제공하며, release notes에는 macOS 15/26 지원 범위와 ad-hoc·비공증 상태를 명시한다. 이전 Lumina의 전역 event-tap 단축키와 화면 보호기 경로는 `Archive/LuminaLegacy`에 보존하되 Hikari 빌드에는 포함하지 않는다.
- native 잠금 화면 실험은 관리자 승인, 변경 전 검증 가능한 백업, 단계별 transaction journal, 조건부 rollback 및 명시적인 제거 경로가 마련되기 전에는 실제 system write를 수행하지 않는다. CI 빌드 성공은 이 root 변경의 런타임 안전성을 보증하지 않는다.
- Native Local의 root 작업은 앱 번들에서 매번 관리자 승인을 받아 실행하는 고정 인자 one-shot 도구로만 수행한다. 상시 daemon, LaunchDaemon 또는 persistent privileged helper로 바꾸지 않는다.
- root-owned legacy catalog write는 확인된 macOS 15 및 manifest schema version 1에서만 허용한다. 새 macOS major version에서는 이 경로를 활성화하지 않는다.
- macOS 26에서 system/user mapping hash가 전혀 없는 구형 macOS 15 transaction은 Native Lock state를 소유하지 않은 실패 기록으로 취급한다. 해당 로컬 journal·staged media는 자동 제거하되, applied hash가 있는 legacy catalog transaction이나 root catalog 파일은 제거·수정하지 않는다.
- macOS 26 Native Lock은 root catalog를 사용하지 않고, 현재 사용자의 `com.apple.wallpaper/aerials` manifest·media store만 transaction으로 변경한다. 적용 전 `entries.json`과 `Index.plist` 원본 bytes를 보관한다. 사용자가 요청한 자동 적용에서는 `Linked`가 아직 없을 때에만, 기존 Apple Aerial manifest의 실제 로컬 asset과 현재 Space/display 식별자로 macOS가 materialize한 topology를 transaction 안에서 준비한 뒤 Hikari asset/category와 `Linked` choice를 적용한다. `Desktop`·`Idle`의 값을 fallback으로 재사용하지 않으며, 다른 도구가 소유한 manifest record는 바꾸지 않는다.
- macOS 26 user Aerial transaction은 manifest/media를 먼저 원자적으로 준비한 뒤 `WallpaperAgent`와 `WallpaperAerialsExtension`을 정지한 상태에서 `Linked` choice를 바꾸고, 재시작 뒤 30초 안정화 동안 모든 `Linked` choice가 Hikari asset ID를 유지하는지 검증한다. 알려진 외부 writer인 `BackdropWallpaper`가 실행 중이면 해당 renderer만 적용 직전에 종료하며, Backdrop의 manifest/media record는 건드리지 않는다. Restore는 원본 bytes가 적용 hash와 맞을 때만 전체 복원하고, 그 외에는 Hikari-owned asset/category/choice만 선택적으로 제거한다.
- macOS 26 `Linked` choice의 `Content.EncodedOptionValues`는 문자열 `$null`로 되돌리지 않는다. 기존 바이너리 placement option을 보존하고, 새 topology를 materialize할 때는 바이너리 plist의 `FillScreen` placement를 기록해 Aerial renderer의 비율 fallback을 피한다. 이 modern placement option을 macOS 15 전체 choice에 확장하지 않는다.
- macOS 26에 넣는 Hikari 영상은 세로 원본을 Aerial renderer에 그대로 전달하지 않는다. 준비 단계에서 Apple Aerial과 같은 16:9 가로 canvas로 aspect-fit 합성하고, 검은 letterbox를 허용하되 non-uniform stretch와 source crop은 금지한다. source preferred transform은 합성 transform에 한 번만 반영한다.
- 16:9 합성의 `AVAssetReaderVideoCompositionOutput` 입력은 identity preferred transform의 중립 `AVMutableCompositionTrack`으로 만든다. 원본 `AVAssetTrack`의 source-space origin을 직접 layer instruction에 전달하거나, 특정 영상에만 맞는 pixel translation 보정값을 넣어 중앙 정렬을 맞추지 않는다.
- 미완료 Native Lock transaction이 있으면 설정에 macOS major 업데이트 전 Restore 경고를 표시한다. `restored` 전에는 새 major version으로의 이동이 안전하다고 안내하지 않는다.
- 사용자 wallpaper index를 바꿀 때는 실행 중인 `WallpaperAgent`를 먼저 정지하고 원자적 교체가 끝난 뒤 종료·재시작한다. 파일을 먼저 쓴 다음 에이전트를 종료하는 순서로 되돌리지 않는다. 재시작 뒤 모든 기존 choice가 같은 transaction asset ID를 유지하는지도 확인한다.
- Native Local의 주기 유지보수는 사용자 wallpaper choice만 읽고 drift가 있을 때만 조정한다. 관리자 승인, privileged helper, system manifest/media 쓰기를 주기적으로 실행하지 않는다. 새 display/Space choice를 자동 적용하기 전에는 exact topology path별 원래 choice를 restore overlay에 먼저 저장하며, 이후 복원은 현재 topology를 보존하는 선택적 병합을 사용한다.
- active Native transaction이 있을 때 앱 시작과 unlock 뒤 `WallpaperAgent`를 한 번 새로 띄워 이전 `WallpaperVideoExtension`의 sample-reader 오류가 다음 잠금까지 남지 않게 한다. 잠금 중 반복 종료하거나 고정 주기로 renderer를 재시작하지 않는다.
- root manifest 적용 뒤 user index를 바꾸기 전에 `idleassetsd`의 SQLite/WAL에 새 transaction asset ID가 인덱싱됐는지 확인한다. 최초 일치만 보고 성공 처리하지 말고 에이전트 재시작 뒤 30초 안정화 구간 동안 모든 choice를 계속 검증한다.
- root manifest·cache transaction 중에는 기존 `idleassetsd`를 먼저 정지하고 작업 종료 시 강제 종료해 launchd가 새 상태로 재시작하게 한다. 실행 중인 서비스와 cache 파일을 동시에 이동하는 순서로 되돌리지 않는다.
- 복원 시 현재 파일이 적용 직후 hash와 같으면 원본 전체를 복원하고, 외부 변경이 있으면 Hikari가 소유한 asset/category/choice만 선택적으로 제거한다. hash가 다른 media/preview 파일은 자동 삭제하지 않는다.
- backup, transaction journal, active marker 및 원자적으로 교체한 system/user 파일은 파일과 상위 디렉터리의 `fsync`가 성공한 뒤에만 다음 phase로 진행한다.
- Native Local의 user support root와 transaction staging은 현재 사용자 전용 권한으로 유지한다. system playback copy는 macOS 서비스 접근 때문에 root 소유 0644이며 활성 중 같은 Mac의 다른 로컬 계정이 읽을 수 있다는 고지를 유지한다. 복원은 hash가 일치하는 system copy만 제거한다.
- Hikari의 canonical 사용자 저장소는 기존 `~/Library/Application Support/Lumina`다. 이전 Hikari Native Local의 `LuminaNative` 저장소는 첫 실행에 콘텐츠·설정·아이콘·transaction을 idempotent하게 병합하고, 원본을 삭제하지 않고 `.archived` 경로로 이동한다. canonical 파일과 충돌하는 경우 canonical 파일을 보존한다.
- 일반 CI는 Hikari만 빌드·테스트한다. PR에서는 대표 macOS 15 runner에서 Debug build/test만 실행하고, `main` push와 정상 `vX.Y.Z` tag에서는 macOS 15/26 ARM64·Intel 전체 build/test와 bundle 검사를 실행한다. 정상 `vX.Y.Z` tag에서만 Hikari ad-hoc asset과 checksum을 패키징·업로드·릴리스하며, 별도 `hikari-v*` release channel은 만들지 않는다. release coverage는 macOS 15/26의 ARM64·Intel 결과를 Codecov flag로 올린다.
- 같은 system wallpaper/aerial 저장소를 수정하는 다른 도구와 native 잠금 화면 실험을 동시에 실행하지 않는다.

## 릴리스

- 이미 push한 태그는 이동하거나 재사용하지 않는다. 후속 수정은 새 버전과 새 태그로 릴리스한다.
- 릴리스 전에 `project.yml`의 마케팅 버전, 태그, 릴리스 JSON 해석, 설치된 화면 보호기 업데이트 흐름을 함께 점검한다.
- Hikari의 정상 release 버전은 `MARKETING_VERSION`과 `CURRENT_PROJECT_VERSION`으로 관리한다. `vX.Y.Z` tag는 `MARKETING_VERSION`과 정확히 일치해야 하며, 로컬 빌드·Xcode 빌드·CI bundle plist·release asset의 Hikari 버전이 모두 일치해야 한다.
- Updater는 `Hikari.app`, Hikari bundle identifier, Hikari executable, `Hikari-macOS-portable.zip`, SHA-256 checksum 및 ad-hoc code signature를 검증한다. Native Lock transaction이 `restored`가 아니거나 storage migration이 실패한 동안에는 업데이트를 시작하지 않는다.
