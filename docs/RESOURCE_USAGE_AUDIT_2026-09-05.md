# 2026-09-05 Hikari CPU·메모리 실측

## 범위와 방법

- macOS 26.6.2, M4 Pro, 내장 디스플레이 1대(3024×1964 Retina).
- `/Applications/Hikari.app` 0.3.2 (12), ARM64. 실행본의 bundle ID는
  `com.hodadako.Lumina.NativeLocal`이며 현재 checkout과 다른 구형 구현이다.
  실행 UI에 General·Lock Screen·About 3개 탭이 있고, 저장소는 기존
  `~/Library/Application Support/Lumina`다. 현재 소스의 2개 탭·canonical
  Hikari 저장소 및 최적화가 모두 설치돼 있다고 전제하지 않는다.
- 같은 선택 영상 유지: H.264 3840×2160, nominal 60fps, video bitrate 약
  39.48Mbps, 길이 약 13.966초, 음소거. 라이브러리는 영상 2개다.
- `top -l 16 -s 1`의 프로세스별 15개 interval 표본에서 최초 0.0% 행을
  제외했다. 최종 복구 확인은 20개 interval이다. CPU 100%는 코어 1개 기준이다.
- 메모리는 `top` MEM 및 `vmmap -summary` physical footprint 기준이다.
  RSS, 가상 주소 공간 크기, 공유 메모리의 프로세스별 단순 합계와 구별한다.
- 상태는 순차 비교했다. 다른 앱 사용과 시스템 메모리 압력이 통제된 실험실
  benchmark는 아니다. CPU 표본과 5초 stack sample·leaks 검사는 분리했다.
  일부 표본에서 read-only vmmap snapshot을 함께 수집했다.
- 설정 창을 실제로 열고 닫았고, 동일 설치본을 정상 종료·재실행했다.
  일시정지는 메뉴 자동화가 작동하지 않아 정상 종료 후 settings의
  playbackPreference 한 항목을 paused로 바꿔 재실행했다. 따라서 재생→일시정지의
  동일 프로세스 즉시 전환에 따른 버퍼 반환량을 측정한 것은 아니다.

## 결과

| 상태 | Hikari 평균 CPU | 최대 CPU | Hikari footprint |
| --- | ---: | ---: | ---: |
| 약 4일 20시간 실행, 설정 숨김, 재생 | 10.80% | 20.7% | 400~412MiB |
| 같은 프로세스, 설정 열기 | 8.81% | 17.7% | 401~418MiB |
| 같은 프로세스, 설정 다시 닫기 | 11.28% | 20.8% | 402~415MiB |
| 같은 앱 재시작, 설정 열림, 재생 | 8.39% | 11.0% | 161~170MiB |
| 재시작 후 설정 닫기, 재생 | 8.02% | 12.6% | 161~174MiB |
| 별도 재시작, 일시정지, General 열림 | 0.59% | 3.2% | 약 130MiB |
| 일시정지, Lock Screen 탭 열림 | 0.58% | 3.3% | 131~133MiB |
| 일시정지, 설정 닫기 | 0.57% | 3.5% | 약 131MiB |
| 원래 재생 설정 복구·재시작, 설정 닫힘 | 9.99% | 14.8% | 159~171MiB |

디코더는 장기 실행 표본에서 보통 314~326MiB, 재시작 후 재생에서 대체로
261~279MiB였다. 짧은 순간 428~535MiB까지 오르는 표본도 있어 한 번의 최고값을
상시 사용량으로 해석하지 않는다. 일시정지 시작에서는 약 18~19MiB 및 CPU 0%였다.
원래 디코더 PID 73983과 Hikari의 통신은 stack sample의
`MemoryOriginServer(73983)-messages`에서 확인했다. 재시작 후 PID는 기존 서비스의
종료·생성 시점 및 재생/정지별 활동으로 식별했다. 시스템 전체 WindowServer CPU를
Hikari에 귀속하거나 두 프로세스의 footprint를 독립 비용처럼 합산하지 않는다.

## 메모리 보유 및 CPU 해석

- 재시작 전 Hikari footprint는 약 401MiB, 실행 이후 peak는 656.1MiB였다.
  DefaultMallocZone의 bytes allocated는 약 244.6MiB, 약 136만 allocation이었다.
  재시작 후에는 같은 zone이 약 41.6~44.3MiB, 약 18~20만 allocation이었다.
  동일 영상에서 약 240MiB의 프로세스 상태가 재시작으로 정리됐다. 정확히 어떤
  객체·이벤트가 장기 보유를 만들었는지는 아직 특정하지 못했다.
- `CG image` 영역 약 52MiB는 재시작 후와 일시정지 중에도 남았다. 모든 비용을
  4K decode surface로 설명할 수 없다. 반대로 이 영역 전부가 썸네일이라고도
  단정할 수 없다. 사용자 App/Menu icon 파일은 둘 다 1024×1024였다.
- 구형 실행본에서 창을 닫기만 해서는 footprint가 뚜렷하게 떨어지지 않았다.
  일시정지 상태에서 설정 열기·닫기 10회 후에도 약 132.3MiB로,
  수백 MiB 증가를 짧은 창 반복만으로 재현하지 못했다.
- 재생 CPU의 대부분은 이 비교에서 영상 처리와 연결된다. 일시정지 상태에서도
  약 5초마다 CPU 2~3.5% 표본이 남는다. 초기 stack sample에는 SwiftUI layout 및
  Observation tracking 작업이 나타났다. 유지보수의 무조건적인 UI invalidation은
  조사 후보지만, 타이머·UI·파일 해석 각각의 정확한 점유율은 분리하지 않았다.
- 재시작한 일시정지 프로세스의 `leaks` 결과는 280 nodes / 14,000 bytes였고,
  표시된 root cycle은 NSXPCConnection/AppIntents 관련이었다. 도구는 동시에
  non-debuggable process의 메모리 접근 제한을 경고했다. 재시작 전 프로세스의
  누수 검사는 하지 않았으므로 수백 MiB의 누수가 없다고 결론내리지 않는다.

## 재검토한 우선순위

1. 먼저 설치본과 현재 소스를 구분한다. 현재 소스에는 설정 창의 hosting controller
   해제, 256px 메뉴 아이콘, 160px 썸네일 decode 등이 있지만 이번 실측은 그 소스를
   새로 빌드·설치한 결과가 아니다. 최신 빌드의 실측 A/B는 별도 작업이다.
2. 상태가 같으면 Native Lock record 재대입 및 추가 objectWillChange 알림을 피하고,
   숨겨진 popover의 UI 보유도 점검한다. 현재 코드의 popover는 한 번 생성한
   NSHostingController를 닫힌 뒤에도 보유한다. 5초 복구 감시 자체는 유지한다.
3. 동일 빌드·영상에서 장시간 allocation 추적을 해 보유 객체와 증가 trigger를
   특정한다. 재시작에 의존하는 주기적인 강제 정리는 제품 해결책으로 채택하지 않는다.
4. 더 큰 재생 CPU 절감은 선택형 1080p/30fps 사본이 후보지만 이번에는 인코딩하거나
   화질을 변경하지 않았다. 정확한 절감률은 아직 측정하지 않았다.
5. 썸네일 cache 한도와 Native 준비 작업 동시성 제한은 여전히 개선 후보지만,
   영상 2개의 구형 실행본에서 관측한 장기 메모리 증가의 원인으로 확정하지 않는다.

## 원상 복구와 남은 범위

- 최종 상태는 같은 영상 재생·음소거·Fill, 설정 창 닫힘이다.
- settings.json의 SHA-256은 측정 전후
  `ee6c8da944eb1f788062938f8e84ff179c78eb6abcff739aba6d1e22e49b07b2`로 같고,
  저장한 원본과 cmp도 일치했다.
- Native Lock active marker, active journal 및 Aerial manifest의 SHA-256은
  측정 전후 일치했다. 기존 transaction은 active이고 78/78 Linked choice가
  기존 asset ID를 가리키는 것을 읽기 전용 검증했다.
- macOS Index.plist의 전체 hash는 agent 재시작 후 달라졌다. 원본 bytes 전체가
  그대로라고 주장하지 않는다. Apply/Restore나 수동 index write는 실행하지 않았다.
- 코드·앱 번들·영상은 변경하지 않았다. 자동 재시작 시 앱에 기존 구현된 one-shot
  WallpaperAgent refresh가 실행됐으며, 잠금·해제 및 실제 Lock Screen 영상 품질은
  이번 비교의 검증 범위가 아니다.
- CPU 원본 표본 및 read-only 검증 스크립트는 이 Mac의 임시
  `/tmp/hikari-resource-audit.056wdU/`에 있고, 초기 stack sample은
  `/tmp/hikari-resource-sample-20260905.txt`다. 임시 경로는 영구 보관을 보장하지 않는다.

## 2026-09-06 03:41 KST 후속 관찰

- 사용자 요청으로 작업을 이어갈 때 최종 복구 프로세스 PID 20288과 디코더
  PID 20305가 그대로 실행 중이었다. 시작 후 약 5시간 51분 경과한 표본이다.
  이 사이의 사용자 조작·sleep 이력은 기록하지 않았으므로 6시간 연속 활성 재생을
  통제한 soak test로 표현하지 않는다. 추가 재시작이나 설정 변경은 하지 않았다.
- Hikari physical footprint는 snapshot 151.8MiB, 20개 CPU interval에서
  148~164MiB였다. CPU 평균 6.36%, 범위 2.3~9.5%다.
- DefaultMallocZone allocated bytes는 25.1MiB, 약 16.5만 allocation이었다.
  재시작 직후의 41.6~44.3MiB보다 작으며 과거 약 244.6MiB 상태로 다시
  증가하지 않았다. 따라서 단순 경과 시간만으로 지속 증가하는 누수는 이번
  후속 표본에서 재현되지 않았다. 특정 UI·영상 선택·display/Space·잠금 전환
  등의 trigger 및 multi-day behavior는 아직 분리하지 못했다.
- 디코더 snapshot footprint는 267.5MiB, CPU 평균 4.67%였다. 실행 이후
  peak 704MiB는 누적 최고값이며 현재 상시 사용량을 의미하지 않는다.
- settings·active marker·journal·Aerial manifest hash는 초기 값과 계속
  일치했다. 선택 영상은 같은 4K60 원본, playing·muted 상태이며 active
  transaction의 Linked choice도 78/78 일치했다.
- 이 후속 결과는 추가 코드 최적화의 효과가 아니라 같은 설치본의 시간차
  관찰이다. 현재 상태에서 대규모 지속 누수를 단정하는 대신 특정 동작에 따른
  보유 증가를 우선 재현하고, 최신 소스의 빌드와 별도로 비교해야 한다.
