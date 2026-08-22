# 변경 금지·주의 사항

이 문서는 검증된 사용자 기대와 운영 제약을 보존한다. 변경하려면 사용자 승인, 재현 가능한 근거, 회귀 검증을 함께 남긴다.

## 사용자 경험

- 설정 창의 빨간 닫기 버튼은 Lumina를 종료하지 않고 설정 창만 숨긴다. 메뉴 막대 아이콘과 앱 기능은 계속 유지되어야 한다.
- 메뉴 막대 팝오버만 외부 클릭에 반응해 닫는다. 별도 설정 창은 앱 비활성화나 외부 클릭으로 숨기지 않고 사용자가 빨간 닫기 버튼을 눌렀을 때만 숨긴다.
- 메뉴 막대 아이콘은 기존 디스플레이 아이콘 크기를 유지한다. 반짝임은 아이콘을 가리지 않도록 현재의 소폭 위쪽 오프셋만 유지한다.
- 다른 앱에서 Hikari 설정으로 돌아오는 일반 앱 활성화는 배경 창 또는 영상 레이어를 재생성하지 않는다. 실제 잠자기 복귀, 디스플레이 변경, Space 전환만 해당 복구를 시작할 수 있다.
- `Fill`은 화면을 꽉 채우고 가장자리를 잘라낼 수 있는 모드이며, `Fit`은 영상 전체를 보이게 하는 모드다. 두 동작을 혼동해 바꾸지 않는다.
- Hikari의 설정은 `General`과 `Lock Screen`으로 단순화한다. 모양·재생·관리 영상 라이브러리는 `General`에 두며, 라이브러리는 하나만 유지한다. Lock Screen은 현재 선택 영상을 적용·복원하는 데만 사용하고, 활성 transaction 중에는 새 적용을 Restore 뒤까지 막는다.

## 화면 보호기·재생

- 화면 보호기 프로세스는 자체 컨테이너 기본 경로로 콘텐츠를 해석한다. 앱 프로세스 경로를 강제 주입하지 않는다.
- 잠금/화면 보호기에서 돌아올 때 재생 상태 복구를 유지한다.
- 별도 설치된 `~/Library/Screen Savers/Lumina.saver`는 앱 내장 번들과 독립적이다. 관련 문제를 조사하거나 릴리스할 때 두 버전을 함께 확인한다.
- `.saver`를 교체한 뒤 실행 중인 `legacyScreenSaver`가 이전 바이너리를 메모리에 유지할 수 있다. 실제 프로세스의 매핑 버전으로 확인한다.
- 사용자가 Lumina 화면 보호기를 갱신할 때 Lumina가 선택돼 있다면, 설치 직후 기존 `legacyScreenSaver` 호스트를 종료한다. 다음 미리보기·자동 실행은 새 설치본으로 시작해야 한다.

## 권한·보안·배포

- 전역 잠금 단축키에는 Accessibility와 Input Monitoring 권한이 필요하다. 한 권한만 안내하거나 검사하지 않는다.
- ad-hoc 업데이트 뒤 권한이 무효화될 수 있으므로 시작 시 실제 event tap을 재검증하고 실패하면 두 권한의 복구 동선을 제공한다. 앱이 사용자 동의 없이 `tccutil reset`을 실행하거나 매 업데이트마다 권한을 무조건 초기화하지 않는다.
- 현재 다른 앱 컨테이너에 직접 쓰는 저장 방식은 macOS 개인정보 접근 알림의 원인이다. 이 알림을 없애려면 단순 서명 변경이 아니라 App Group 등 공유 저장소 구조로 이전해야 한다.
- Developer ID 서명과 notarization은 배포 정체성을 안정화하지만 TCC 권한을 자동으로 부여하거나 우회하지 않는다.
- ad-hoc 서명으로 앱 정체성이 바뀌면 사용자가 시스템 권한을 다시 부여해야 할 수 있다. 서명 방식을 바꿀 때는 업데이트·권한 흐름을 실제 장비에서 검증한다.
- 문서화되지 않은 macOS wallpaper/aerial 상태를 변경하는 Native Lock은 Hikari 전용으로 유지한다. Hikari는 별도 ad-hoc·비공증 release asset으로도 제공할 수 있지만 일반 Lumina Portable 릴리스와 앱 내 업데이트에는 privileged 기능을 포함하지 않는다. release notes에는 macOS 15/26 지원 범위와 ad-hoc·비공증 상태를 명시한다. 일반 Lumina의 선택적 전역 event-tap 단축키 권한 재승인 안내는 Hikari에 적용하지 않는다.
- native 잠금 화면 실험은 관리자 승인, 변경 전 검증 가능한 백업, 단계별 transaction journal, 조건부 rollback 및 명시적인 제거 경로가 마련되기 전에는 실제 system write를 수행하지 않는다. CI 빌드 성공은 이 root 변경의 런타임 안전성을 보증하지 않는다.
- Native Local의 root 작업은 앱 번들에서 매번 관리자 승인을 받아 실행하는 고정 인자 one-shot 도구로만 수행한다. 상시 daemon, LaunchDaemon 또는 persistent privileged helper로 바꾸지 않는다.
- root-owned legacy catalog write는 확인된 macOS 15 및 manifest schema version 1에서만 허용한다. 새 macOS major version에서는 이 경로를 활성화하지 않는다.
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
- 복원 시 현재 파일이 적용 직후 hash와 같으면 원본 전체를 복원하고, 외부 변경이 있으면 Lumina가 소유한 asset/category/choice만 선택적으로 제거한다. hash가 다른 media/preview 파일은 자동 삭제하지 않는다.
- backup, transaction journal, active marker 및 원자적으로 교체한 system/user 파일은 파일과 상위 디렉터리의 `fsync`가 성공한 뒤에만 다음 phase로 진행한다.
- Native Local의 user support root와 transaction staging은 현재 사용자 전용 권한으로 유지한다. system playback copy는 macOS 서비스 접근 때문에 root 소유 0644이며 활성 중 같은 Mac의 다른 로컬 계정이 읽을 수 있다는 고지를 유지한다. 복원은 hash가 일치하는 system copy만 제거한다.
- 일반 `Lumina`와 Native Local 앱 `Hikari`는 서로 다른 bundle ID와 Application Support 저장소를 사용한다. 두 빌드 모두 `Control-Command-Q` 잠금을 지원한다. 일반 빌드는 선택형 event-tap 재정의를 유지하고, Native Local은 충돌하는 event tap 없이 macOS 소유 시스템 잠금 경로를 사용한다. Native Local은 앱 내 자동 업데이트를 실행하지 않는다.
- 일반 CI는 Lumina Portable을 패키징·업로드·릴리스하고, 별도 Hikari Release workflow는 `hikari-vX.Y.Z` tag에서 Hikari ad-hoc asset과 checksum만 패키징·업로드·릴리스한다. Native Local CI 자체는 계속 compile/test와 번들 격리 검사만 하며 artifact, archive, release 또는 앱 실행을 하지 않는다.
- 같은 system wallpaper/aerial 저장소를 수정하는 다른 도구와 native 잠금 화면 실험을 동시에 실행하지 않는다.

## 릴리스

- 이미 push한 태그는 이동하거나 재사용하지 않는다. 후속 수정은 새 버전과 새 태그로 릴리스한다.
- 릴리스 전에 `project.yml`의 마케팅 버전, 태그, 릴리스 JSON 해석, 설치된 화면 보호기 업데이트 흐름을 함께 점검한다.
- Hikari는 `HIKARI_MARKETING_VERSION`과 `HIKARI_BUILD_NUMBER`으로 Lumina와 독립 관리한다. Hikari 로컬 빌드 또는 ad-hoc release 전에 두 값을 함께 올리고, 로컬 빌드·Xcode 빌드·Native Local CI·Hikari Release workflow의 bundle plist가 그 값과 일치해야 한다. Hikari tag와 release는 일반 Lumina release tag와 분리하며, Hikari는 앱 내 자동 업데이트를 실행하지 않는다.
