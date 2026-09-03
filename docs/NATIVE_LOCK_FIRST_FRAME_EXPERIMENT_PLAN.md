# Native Lock 첫 프레임 개선 실험 계획

## 목적과 현재 상태

목표는 Hikari Native Lock에서 잠금 직후 첫 영상 프레임이 보일 때까지의 시간을
줄이는 것이다. 데스크톱 wallpaper 원본의 화질·해상도·재생 경로는 이 실험의
대상이 아니다.

2026-08-17 조사 시 활성 transaction의 `media.mov`는 약 66MB, 3840×2160 H.264이며
`moov` movie header가 byte 24에 있었다. 따라서 기존 fast-start 처리는 이미 적용돼
있고, 남은 지연의 주요 후보는 macOS가 Lock Screen video extension을 cold start하고
4K 첫 프레임을 디코드하는 과정이다.

unlock 뒤의 2초 renderer refresh는 데스크톱을 기다리게 하는 로딩 지연이 아니다.
Lock Screen 퇴장 surface와 renderer 재시작이 겹쳐 검은 프레임이 보이는 회귀를 막기
위한 비동기 안전 지연이다. 약 120ms로 재시작했을 때의 flash 회귀가 이미 확인됐으므로,
그 값을 근거 없이 즉시 줄이지 않는다.

## 실험 순서

### 1. 잠금 전용 최적화 영상 사본

가장 먼저 시도할 후보다.

- General에서 영상을 처음 선택할 때 별도 MOV를 백그라운드 준비해 private cache에
  원자적으로 게시한다. cache가 준비된 뒤에만 Native Lock transaction이 이를 재사용한다.
  General 라이브러리의 원본과 데스크톱 wallpaper 재생에는 절대 사용하지 않는다.
- 1080p H.264, 낮은 비트레이트, 앞쪽 `moov`, 시작부 keyframe을 갖는 profile을
  준비한다. 정확한 bit rate·frame rate·keyframe 간격은 측정 후 결정하며, 임의의
  기본값으로 고정하지 않는다.
- 현재 passthrough export는 보존하고, 최적화 profile이 실패하거나 결과를 검증하지
  못하면 기존 fast-start passthrough 결과를 사용한다.
- transaction journal에는 실제로 사용한 media profile과 media SHA-256을 기록한다.
  Apply·Restore의 hash 검증, 원본 bytes 보관, 선택적 복원 규칙은 변경하지 않는다.

성공 기준은 첫 프레임 지연이 기준 영상보다 일관되게 짧아지고, 데스크톱 원본 화질이
변하지 않으며, lock → unlock → 다음 lock 반복에서 검은 프레임이 생기지 않는 것이다.

### 2. unlock renderer refresh 지연의 단계적 측정

첫 실험이 충분하지 않은 경우에만 수행한다.

- 현재 2초를 기준값으로 두고 1.5초, 1.0초, 0.75초를 각각 독립 build에서 시험한다.
- 각 값은 Lock Screen 퇴장 뒤 `WallpaperAgent`를 한 번 새로 띄우는 시점만 바꾼다.
  잠금 중 재시작하거나 고정 주기로 renderer를 재시작하지 않는다.
- flash, 데스크톱 검은 프레임, 다음 잠금의 첫 프레임 누락 중 하나라도 재현되면 해당
  값은 채택하지 않고 직전 안전 값으로 되돌린다.

이 실험은 사용자가 해제 직후 다시 잠글 때의 준비 시간을 줄일 가능성은 있지만,
영상의 실제 첫 프레임 디코드 자체를 빠르게 만드는 수단은 아니다.

### 3. 지원되지 않는 prewarm은 시도하지 않음

macOS가 소유한 Lock Screen video extension을 비공개 API나 상시 background process로
미리 실행하는 방법은 사용하지 않는다. Hikari는 persistent privileged helper 또는
daemon을 추가하지 않으며, 기존의 unlock 뒤 단 한 번 renderer refresh 규칙을 넘지
않는다.

## 측정과 안전 검증

각 후보는 source-built Native Local에서만 시험한다.

1. 기준 build와 후보 build에서 잠금 요청부터 첫 비검은 프레임까지의 시간을 같은
   영상으로 기록한다.
2. 각 build에서 lock → unlock → 다음 lock을 최소 20회 반복해 첫 프레임, unlock
   flash, 다음 잠금의 재생 여부를 수동 확인한다.
3. Apply 뒤 모든 `Linked` choice가 transaction asset ID를 유지하는지 확인하고,
   manifest·media SHA-256과 journal phase를 검증한다.
4. 각 후보 시험이 끝나면 Restore를 실행해 원본 manifest/index bytes와 현재 topology의
   외부 choice가 보존되는지 확인한다.

실험 중 mapping drift, renderer 오류, 불완전한 Restore 또는 화면 품질 회귀가 보이면
즉시 추가 조정을 멈추고 Restore 후 증거와 원인을
`FAILED_APPROACHES_AND_RESOLUTIONS.md`에 기록한다. 검증된 구현을 채택해 버전을 올릴
때만 `VERSION_ISSUES.md`에 사용자 영향과 검증 결과를 추가한다.
