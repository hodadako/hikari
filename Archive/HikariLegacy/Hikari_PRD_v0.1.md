# Hikari PRD

> **Native Live Wallpaper & Screen Saver for macOS**
> **Tagline:** Bring your desktop to life.

- 문서 버전: v0.1
- 제품 단계: MVP Draft
- 프로젝트 유형: Open Source macOS Application
- 저장소 권장명: `hikari-macos`
- 라이선스: MIT
- 대상 플랫폼: macOS
- 초기 콘텐츠 형식: MP4

---

## 1. 제품 개요

Hikari는 하나의 MP4 영상을 macOS의 **라이브 배경화면**과 **화면 보호기**에서 공통으로 사용할 수 있게 해주는 네이티브 오픈소스 앱이다.

사용자는 로컬 MP4 파일을 Hikari에 추가하고, 메뉴바에서 현재 콘텐츠와 재생 상태를 관리할 수 있다. 같은 콘텐츠는 평상시 데스크톱 배경에서 재생되며, 화면 보호기가 시작되면 화면 보호기 전용 프로세스에서 재생된다.

Hikari의 초기 목표는 기능 수를 늘리는 것이 아니라 다음 세 가지를 안정적으로 달성하는 것이다.

1. macOS 기본 기능처럼 자연스러운 사용 경험
2. 장시간 실행해도 부담이 적은 메모리·CPU·GPU 사용량
3. 배경화면과 화면 보호기 사이에서 일관된 콘텐츠 경험

---

## 2. 비전

macOS 사용자가 동영상 배경화면을 사용하기 위해 무겁거나 이질적인 앱을 실행하지 않아도 되도록 한다.

Hikari는 단순한 동영상 플레이어가 아니라 다음 원칙을 따르는 macOS 네이티브 도구를 지향한다.

- **Native First:** Swift, SwiftUI, AppKit, AVFoundation 기반
- **Resource Conscious:** 불필요한 디코딩, 중복 프로세스, 백그라운드 작업 최소화
- **Simple by Default:** 설치 후 몇 번의 클릭만으로 적용
- **Open Source:** 구현과 의사결정을 공개하고 외부 기여를 받음
- **Extensible Later:** 초기 버전은 MP4에 집중하되 이후 Renderer 확장 가능

---

## 3. 문제 정의

현재 macOS에서 라이브 배경화면과 화면 보호기를 함께 관리하려면 다음 문제가 발생한다.

- 배경화면과 화면 보호기 설정이 서로 분리되어 있다.
- 동영상 배경 앱은 시스템 UI와 어울리지 않는 경우가 많다.
- 장시간 실행 시 메모리와 배터리 사용량이 부담될 수 있다.
- 사용자가 선택한 영상 파일의 접근 권한과 저장 위치를 안정적으로 관리하기 어렵다.
- 다중 모니터, 절전, 화면 잠금, Space 전환 등 macOS 특유의 상태 변화에 대응해야 한다.
- 배경화면과 화면 보호기가 동시에 영상을 재생하면 자원이 중복 사용될 수 있다.

Hikari는 하나의 콘텐츠 라이브러리와 공용 설정을 제공하고, 시스템 상태에 따라 필요한 재생기만 활성화해 이 문제를 해결한다.

---

## 4. 제품 목표

### 4.1 사용자 목표

사용자는 다음 작업을 쉽게 수행할 수 있어야 한다.

- 로컬 MP4 파일을 추가한다.
- 영상을 라이브 배경화면으로 적용한다.
- 같은 영상을 화면 보호기로 사용한다.
- 메뉴바에서 재생, 일시정지, 콘텐츠 변경을 수행한다.
- 영상 표시 방식을 Fill 또는 Fit으로 변경한다.
- 로그인 시 Hikari를 자동 실행하도록 설정한다.
- 배터리 사용 시 자동 정지 여부를 설정한다.
- 화면 보호기 설치 상태를 확인하고 시스템 설정으로 이동한다.

### 4.2 제품 목표

- macOS 기본 앱과 어울리는 메뉴, 문구, 창 구성 제공
- 장시간 실행 시 안정적인 메모리 사용량 유지
- 화면 보호기 실행 중 배경화면 재생 중단
- 잠금, 절전, 디스플레이 변경 이후 정상 상태 복구
- MP4 재생 실패 시 앱 전체가 종료되지 않는 오류 처리
- 오픈소스 기여자가 구조를 쉽게 이해할 수 있는 모듈 구성

---

## 5. MVP 범위

### 5.1 포함

#### 콘텐츠

- 로컬 MP4 파일 가져오기
- 가져온 파일을 Hikari 관리 디렉터리에 복사
- 콘텐츠 제목 및 썸네일 표시
- 콘텐츠 선택 및 삭제
- 현재 선택된 콘텐츠 저장

#### 라이브 배경화면

- MP4 무한 반복 재생
- 모든 macOS Space에서 표시
- 데스크톱 아이콘 및 일반 앱 창의 사용을 방해하지 않음
- 마우스 입력 무시
- Fill 표시 방식
- Fit 표시 방식
- 단일 모니터 지원
- 다중 모니터에서 동일 콘텐츠 표시
- 메뉴바에서 재생 및 일시정지

#### 화면 보호기

- 별도 `.saver` Target 제공
- 현재 선택된 MP4 재생
- 시스템 설정의 미리보기 영역 지원
- 전체 화면 화면 보호기 지원
- 메인 앱에서 설치 상태 표시
- 사용자 동작을 통한 화면 보호기 설치
- 시스템 설정의 화면 보호기 페이지로 이동

#### 시스템 상태 대응

- 화면 잠금 시 배경화면 재생 중단
- 화면 보호기 실행 시 배경화면 재생 중단
- 절전 진입 시 재생 중단
- 화면 깨우기 및 잠금 해제 후 상태 복구
- 모니터 연결, 해제, 해상도 변경 시 배경 Window 재구성
- 앱 종료 시 모든 Window 및 Player 정리

#### 설정

- 로그인 시 자동 실행
- 오디오 음소거
- 배터리 사용 시 자동 정지
- Fill / Fit 선택
- 화면 보호기 설치 상태
- 현재 콘텐츠 정보

### 5.2 제외

다음 기능은 초기 버전에서 지원하지 않는다.

- MOV 및 기타 동영상 형식
- Web, HTML, WebGL Renderer
- Metal Shader Renderer
- 오디오 반응형 콘텐츠
- 온라인 콘텐츠 다운로드
- 커뮤니티 갤러리
- 플러그인 설치 UI
- Wallpaper Marketplace
- iCloud 동기화
- 모니터별 서로 다른 콘텐츠
- 여러 모니터를 하나의 영상으로 이어 붙이는 Span 모드
- 재생 목록 및 시간대별 자동 전환
- AI 배경화면 생성
- 사용자 계정 및 서버
- DRM 콘텐츠

---

## 6. 핵심 사용자 시나리오

### 6.1 첫 실행

```text
앱 실행
→ 간단한 소개 화면
→ MP4 선택
→ Hikari 라이브러리로 복사
→ 썸네일 생성
→ 배경화면 적용
→ 화면 보호기 설치 안내
→ 메뉴바 앱으로 전환
```

### 6.2 배경화면 변경

```text
메뉴바 아이콘 선택
→ 콘텐츠 변경
→ 기존 콘텐츠 또는 새 MP4 선택
→ 재생기 교체
→ 새 콘텐츠 적용
```

### 6.3 화면 보호기 설치

```text
Hikari 설정
→ 화면 보호기 설치
→ 사용자 Library의 Screen Savers 디렉터리에 설치
→ 시스템 설정 열기
→ 사용자가 Hikari 선택
```

### 6.4 화면 보호기 실행

```text
화면 보호기 시작 감지
→ 메인 앱의 배경화면 재생 중단
→ Hikari.saver가 공용 설정 조회
→ 선택된 MP4 재생
→ 화면 보호기 종료
→ saver Player 해제
→ 메인 앱이 배경화면 재생 복구
```

### 6.5 절전 및 복구

```text
시스템 절전 진입
→ Player 일시정지
→ 렌더링 중단
→ 시스템 깨우기
→ 디스플레이 상태 재확인
→ 사용자 설정에 따라 재생 복구
```

---

## 7. 기능 요구사항

### FR-01. MP4 가져오기

- 사용자는 파일 선택기를 통해 MP4 파일을 선택할 수 있어야 한다.
- Hikari는 선택한 파일이 읽을 수 있는 MP4인지 검증해야 한다.
- 파일은 App Group 또는 Application Support의 관리 디렉터리로 복사해야 한다.
- 원본 파일이 이동되거나 외장 디스크가 분리되어도 가져온 콘텐츠는 재생 가능해야 한다.
- 같은 파일을 중복으로 가져올 경우 중복 여부를 사용자에게 알려야 한다.

### FR-02. 콘텐츠 메타데이터

Hikari는 다음 정보를 저장해야 한다.

- 내부 콘텐츠 ID
- 표시 이름
- 저장된 상대 경로
- 파일 크기
- 영상 길이
- 영상 해상도
- 코덱 정보
- 생성일
- 썸네일 경로

### FR-03. 라이브 배경화면 재생

- 영상은 `AVFoundation` 기반으로 재생한다.
- 영상은 기본적으로 음소거한다.
- 영상 종료 후 끊김을 최소화하며 반복 재생한다.
- 사용자가 재생을 중단하면 디코딩 및 렌더링 작업도 중단해야 한다.
- 배경 Window는 키보드 및 마우스 포커스를 가져가면 안 된다.
- Window는 일반 앱 창보다 뒤에 위치해야 한다.
- Window는 모든 Space에서 일관되게 표시되어야 한다.

### FR-04. 표시 방식

- Fill: 화면을 가득 채우며 일부 영역이 잘릴 수 있다.
- Fit: 전체 영상을 표시하며 여백이 생길 수 있다.
- 설정 변경은 가능한 한 즉시 반영한다.
- 초기 기본값은 Fill이다.

### FR-05. 다중 모니터

- 연결된 모든 모니터에 동일 콘텐츠를 표시한다.
- 모니터별 화면 크기와 배율을 반영한다.
- 모니터 연결 상태가 변경되면 배경 Window를 다시 구성한다.
- 초기 구현에서는 안정성을 위해 디스플레이 변경 시 세션 전체를 재생성할 수 있다.

### FR-06. 화면 보호기

- 화면 보호기는 메인 앱과 별도 Target 및 프로세스로 동작한다.
- 메인 앱과 같은 콘텐츠 설정을 읽어야 한다.
- 시스템 설정의 작은 Preview와 실제 전체 화면을 모두 지원한다.
- 콘텐츠 파일을 읽을 수 없으면 검은 화면 또는 기본 Fallback을 표시해야 한다.
- 화면 보호기 종료 시 Player, Observer, Timer를 모두 해제해야 한다.

### FR-07. 프로세스 간 상태 조정

- 화면 보호기 실행 중에는 메인 앱의 동영상 재생을 중단한다.
- 화면 보호기 종료 후 사용자 설정과 시스템 상태를 다시 확인하고 배경화면 재생을 복구한다.
- 프로세스 간 알림이 누락되어도 잠금 해제, Wake, 앱 활성화 시 상태를 재검증한다.
- 배경화면과 화면 보호기가 장시간 동시에 디코딩하지 않도록 한다.

### FR-08. 메뉴바 앱

메뉴바에서 다음 기능을 제공한다.

- 현재 콘텐츠 썸네일 및 이름
- 재생
- 일시정지
- 콘텐츠 변경
- 설정 열기
- 화면 보호기 설치 상태
- 시스템 설정 열기
- 앱 종료

Dock 아이콘은 기본적으로 표시하지 않는다.

### FR-09. 설정 저장

다음 설정은 앱 재시작 후에도 유지해야 한다.

- 현재 콘텐츠 ID
- 재생 상태
- 표시 방식
- 음소거
- 배터리 사용 시 자동 정지
- 로그인 시 자동 실행
- 화면 보호기 설치 상태의 마지막 확인값

### FR-10. 오류 처리

- 재생 불가능한 파일은 적용 전에 차단한다.
- 파일 복사 실패 시 원인을 사용자에게 안내한다.
- 화면 보호기에서 파일을 찾지 못해도 시스템 화면 보호기 프로세스를 종료시키면 안 된다.
- 배경 Window 생성 실패 시 다른 모니터의 재생을 가능한 범위에서 유지한다.
- 사용자에게는 기술적인 Stack Trace 대신 복구 가능한 안내를 표시한다.

---

## 8. 비기능 요구사항

### 8.1 메모리

낮은 메모리 사용량은 Hikari MVP의 핵심 품질 기준이다.

#### 목표 예산

아래 수치는 개발 중 성능 회귀를 탐지하기 위한 제품 목표이며, 영상 코덱과 해상도에 따라 달라질 수 있다.

- 1080p H.264, 단일 모니터, 안정 상태 RSS: **150MB 이하 목표**
- 4K 영상, 단일 모니터, 안정 상태 RSS: **250MB 이하 목표**
- 일시정지 후 10초 이내 불필요한 버퍼와 리소스 반환
- 콘텐츠를 10회 연속 교체해도 메모리가 지속 증가하지 않아야 함
- 화면 보호기 종료 후 saver 프로세스가 보유하던 영상 자원 해제
- 배경화면과 화면 보호기의 동시 장기 재생 금지

#### 구현 원칙

- 전체 MP4 파일을 메모리에 적재하지 않는다.
- AVFoundation의 스트리밍 및 하드웨어 디코딩 경로를 우선 사용한다.
- 불필요한 영상 프레임 복사와 Bitmap 변환을 피한다.
- 썸네일은 원본 해상도로 보관하지 않는다.
- 재생기, Layer, Observer, Notification Token을 명시적으로 해제한다.
- 동일 콘텐츠 적용 시 불필요한 Player 재생성을 피한다.
- 주기적인 Polling Timer보다 시스템 Notification을 우선 사용한다.
- 백그라운드 상태에서 불필요한 SwiftUI View Tree를 유지하지 않는다.

### 8.2 CPU 및 GPU

- 1080p H.264 단일 모니터 재생 시 평균 CPU 사용률을 낮게 유지한다.
- 하드웨어 디코딩 가능한 파일은 시스템 디코더를 활용한다.
- 일시정지, 잠금, 절전 상태에서는 지속적인 프레임 렌더링을 하지 않는다.
- 화면 보호기 종료 후 별도 렌더링 루프가 남지 않아야 한다.
- 디버그용 성능 로그는 Release 빌드에서 기본 비활성화한다.

### 8.3 배터리

- 배터리 모드에서 자동 일시정지를 선택할 수 있어야 한다.
- Low Power Mode 감지 가능 여부를 검토한다.
- 화면이 꺼졌거나 잠긴 상태에서는 재생하지 않는다.
- 전원 상태 변경 시 즉시 재생 정책을 다시 평가한다.

### 8.4 응답성

- 메뉴바 열기: 체감 지연 없이 표시
- 재생 및 일시정지 명령: 300ms 이내 반응 목표
- 기존 콘텐츠 선택 후 화면 전환 시작: 1초 이내 목표
- 앱 시작 후 메뉴바 아이콘 표시: 2초 이내 목표
- 화면 보호기 Preview 진입 시 Fallback 또는 첫 화면을 빠르게 표시

### 8.5 안정성

- 잘못된 영상 파일 하나가 앱 전체 종료로 이어지지 않아야 한다.
- Sleep/Wake를 반복해도 중복 Player가 생성되지 않아야 한다.
- 모니터를 반복 연결·해제해도 Window가 누적되지 않아야 한다.
- Space를 변경해도 배경 Window가 일반 앱 위로 올라오지 않아야 한다.
- 앱을 장시간 실행한 뒤에도 메모리와 Thread 수가 지속 증가하지 않아야 한다.

### 8.6 네이티브 UX

Hikari는 다음 디자인 원칙을 따른다.

- SwiftUI의 기본 Form, Toggle, Picker, MenuBarExtra를 우선 사용한다.
- 시스템 폰트와 SF Symbols를 사용한다.
- 불필요한 커스텀 타이틀바와 웹 기반 UI를 사용하지 않는다.
- macOS 용어와 동작 방식을 따른다.
- 삭제, 종료, 화면 보호기 설치처럼 영향이 큰 작업만 명확한 확인을 제공한다.
- 설정 항목은 기능 중심으로 묶고 지나치게 많은 옵션을 노출하지 않는다.
- Light/Dark Mode와 시스템 Accent Color를 자연스럽게 따른다.
- 접근성 Label과 Keyboard Navigation을 지원한다.
- Dock에 상주하기보다 메뉴바 중심의 조용한 앱 경험을 제공한다.

---

## 9. 성공 지표

### 기능 지표

- 지원 MP4 적용 성공률: 99% 이상 목표
- 화면 보호기 Preview 실행 성공률: 99% 이상 목표
- Sleep/Wake 이후 재생 복구 성공률: 99% 이상 목표
- 모니터 연결 변경 이후 Window 복구 성공률: 99% 이상 목표

### 성능 지표

- 1080p 단일 모니터 재생 시 메모리 목표 충족
- 8시간 연속 실행 후 메모리 증가율 10% 이내
- 콘텐츠 10회 교체 후 기준 메모리로 회복
- 일시정지 상태에서 불필요한 영상 디코딩 없음
- 화면 보호기와 배경화면의 장기 중복 재생 없음

### 사용성 지표

- 첫 실행에서 배경화면 적용까지 3분 이내
- 핵심 작업을 메뉴바에서 2단계 이내 수행
- 화면 보호기 설치 상태와 다음 행동을 사용자가 이해할 수 있음

---

## 10. 제품 구조

```text
Hikari
├── HikariApp
│   ├── MenuBar
│   ├── Settings
│   ├── ContentLibrary
│   ├── WallpaperEngine
│   └── SystemState
│
├── HikariScreenSaver
│   └── ScreenSaverView
│
├── HikariCore
│   ├── Models
│   ├── VideoRenderer
│   ├── SettingsStore
│   ├── ContentStore
│   ├── SharedContainer
│   └── Diagnostics
│
└── HikariTests
    ├── UnitTests
    ├── IntegrationTests
    └── PerformanceTests
```

### Target 구성

```text
Hikari.app
Hikari.saver
HikariCore
```

- `Hikari.app`: 메뉴바, 설정, 콘텐츠 관리, 라이브 배경화면
- `Hikari.saver`: 시스템 화면 보호기
- `HikariCore`: 영상 재생, 모델, 공용 저장소, 설정

---

## 11. 기술 방향

| 구분 | 선택 |
|---|---|
| 언어 | Swift |
| UI | SwiftUI |
| macOS Window | AppKit |
| 영상 재생 | AVFoundation |
| 반복 재생 | AVQueuePlayer + AVPlayerLooper 검토 |
| 화면 보호기 | ScreenSaver Framework |
| 설정 공유 | App Group UserDefaults 또는 JSON |
| 파일 저장 | App Group Container / Application Support |
| 썸네일 | AVAssetImageGenerator |
| 로그인 실행 | ServiceManagement |
| 패키지 관리 | Swift Package Manager |
| 단위 테스트 | XCTest / Swift Testing 검토 |
| 성능 분석 | Instruments, XCTest Metrics |
| CI | GitHub Actions |
| 배포 | GitHub Releases 우선 |

### 기술 선택 원칙

- 초기 버전에서는 WebView를 사용하지 않는다.
- 영상 재생은 AVFoundation의 시스템 최적화를 우선 활용한다.
- 배경화면과 화면 보호기는 렌더링 코드를 공유하되 Lifecycle은 분리한다.
- 저장소는 초기에는 단순한 구조를 사용하고 SwiftData 도입을 필수로 하지 않는다.
- 추상화는 실제 두 번째 Renderer가 필요해질 때 확장할 수 있도록 최소 수준으로 둔다.

---

## 12. 데이터 모델 초안

```swift
struct LiveContent: Codable, Identifiable {
    let id: UUID
    var title: String
    let relativePath: String
    let fileSize: Int64
    let duration: Double
    let width: Int
    let height: Int
    let codec: String?
    let thumbnailRelativePath: String?
    let createdAt: Date
}
```

```swift
struct HikariSettings: Codable {
    var selectedContentID: UUID?
    var playbackState: PlaybackState
    var scalingMode: ScalingMode
    var isMuted: Bool
    var pauseOnBattery: Bool
    var launchAtLogin: Bool
}
```

```swift
enum ScalingMode: String, Codable {
    case fill
    case fit
}
```

---

## 13. 저장 구조

```text
Hikari Shared Container
├── settings.json
├── contents.json
├── Media
│   └── <content-id>.mp4
└── Thumbnails
    └── <content-id>.jpg
```

### 저장 원칙

- 공용 설정과 콘텐츠는 앱과 화면 보호기 모두 읽을 수 있어야 한다.
- 외부 파일 경로를 장기적으로 직접 참조하지 않는다.
- 삭제 시 원본 파일은 건드리지 않고 Hikari가 복사한 파일만 삭제한다.
- 쓰기 작업은 원자적으로 수행해 파일 손상을 방지한다.
- 화면 보호기는 콘텐츠와 설정을 읽기 전용으로 사용한다.

---

## 14. 상태 모델

```text
Stopped
Loading
Playing
PausedByUser
PausedByBattery
PausedByScreenLock
PausedByScreenSaver
PausedBySleep
Failed
```

재생 상태는 단순 Boolean이 아니라 정지 이유를 구분해야 한다.

예를 들어 사용자가 직접 일시정지한 상태에서 잠금 해제되었다고 자동으로 재생을 시작하면 안 된다. 시스템 이벤트가 해제되었을 때는 다른 정지 사유가 없는지 확인한 뒤 재생을 복구해야 한다.

---

## 15. 성능 검증 계획

### 필수 테스트 시나리오

1. 1080p H.264 영상을 8시간 연속 재생
2. 4K 영상을 1시간 재생
3. 콘텐츠를 10회 연속 교체
4. Sleep/Wake 20회 반복
5. 화면 잠금/해제 20회 반복
6. 화면 보호기 진입/종료 20회 반복
7. 외부 모니터 연결/해제 10회 반복
8. Space 전환 및 전체 화면 앱 진입 반복
9. MP4 파일 삭제 또는 손상 상태에서 화면 보호기 실행
10. 앱 종료 후 Player, Window, Observer 잔존 여부 확인

### 측정 항목

- Resident Memory
- Allocations
- Leaks
- CPU Time
- GPU Utilization
- Energy Impact
- Thread Count
- File Handle Count
- 재생 시작 시간
- 반복 재생 구간의 끊김
- 이벤트 이후 Player 및 Window 개수

### 도구

- Xcode Instruments
  - Allocations
  - Leaks
  - Time Profiler
  - Energy Log
  - Core Animation
- Activity Monitor
- XCTest Performance Metrics
- Debug 전용 상태 로그

---

## 16. 화면 구성 초안

### 16.1 메뉴바

```text
[현재 콘텐츠 썸네일]
Ocean Loop

재생 / 일시정지
콘텐츠 변경
설정
화면 보호기 설정
종료
```

### 16.2 설정

#### General

- Launch Hikari at Login
- Pause While on Battery
- Mute Video

#### Appearance

- Scaling: Fill / Fit
- Current Content

#### Screen Saver

- 설치 상태
- Install / Reinstall
- Open System Settings

#### About

- Version
- GitHub Repository
- License
- Open Source Acknowledgements

---

## 17. 오픈소스 운영 원칙

### 라이선스

MIT License를 기본안으로 한다.

### 저장소 기본 문서

- `README.md`
- `LICENSE`
- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`
- `SECURITY.md`
- `ARCHITECTURE.md`
- `PERFORMANCE.md`
- Issue Template
- Pull Request Template

### 기여 범위

초기에는 다음 기여를 우선적으로 받는다.

- macOS 버전별 동작 검증
- 다중 모니터 버그 수정
- 메모리 누수 및 성능 개선
- 접근성 개선
- 번역
- 테스트 영상 및 재현 절차
- 설치 및 코드 서명 문서 개선

### 성능 관련 Pull Request 기준

재생 경로를 변경하는 Pull Request는 가능하면 다음을 포함한다.

- 변경 전후 메모리 측정
- CPU 및 Energy Impact 비교
- 테스트한 macOS 및 하드웨어 정보
- 단일 및 다중 모니터 결과
- 장시간 실행 결과

---

## 18. 출시 기준

다음 조건을 만족하면 v0.1 MVP를 출시할 수 있다.

- MP4 가져오기 및 삭제가 정상 동작한다.
- 단일 및 다중 모니터에 라이브 배경화면을 표시한다.
- Fill과 Fit이 정상 동작한다.
- 화면 보호기를 설치하고 Preview 및 전체 화면에서 재생할 수 있다.
- 화면 보호기 실행 중 배경화면 재생이 중단된다.
- 잠금, 절전, Wake, 모니터 변경 이후 재생 상태가 복구된다.
- 8시간 연속 재생에서 치명적인 메모리 누수가 없다.
- 콘텐츠를 반복 변경해도 Player와 Window가 누적되지 않는다.
- 기본 메뉴 및 설정 UI가 macOS Light/Dark Mode와 어울린다.
- GitHub Actions에서 빌드와 테스트가 통과한다.
- README와 설치 문서가 작성되어 있다.

---

## 19. 초기 개발 우선순위

### Phase 1. Core Playback

- MP4 검증
- VideoRenderer
- 반복 재생
- Player Lifecycle
- 기본 성능 측정

### Phase 2. Wallpaper

- 데스크톱 Window
- 모든 Space 지원
- Fill / Fit
- 다중 모니터
- 메뉴바 제어

### Phase 3. Shared Storage

- 콘텐츠 가져오기
- 썸네일
- 설정 저장
- App Group 공유

### Phase 4. Screen Saver

- `.saver` Target
- Preview
- 전체 화면
- 메인 앱과 상태 조정
- 설치 흐름

### Phase 5. Native UX

- 온보딩
- 설정 UI
- 로그인 시 실행
- 시스템 설정 이동
- 접근성

### Phase 6. Performance Hardening

- Instruments 측정
- 장시간 재생 테스트
- Sleep/Wake 테스트
- 메모리 회귀 테스트
- 코드 및 문서 정리

---

## 20. 향후 로드맵

### v0.2

- MOV 지원 검토
- 모니터별 콘텐츠
- 플레이리스트
- 시간대별 전환
- 화면 보호기 설정 개선

### v0.3

- Web Renderer 실험
- 콘텐츠 패키지 포맷
- Renderer Capability 정의

### v0.4

- Metal / Shader Renderer
- 개발자 SDK
- Sample Renderer

### v1.0

- 안정화된 Renderer API
- 플러그인 문서
- 다국어 지원
- 안정적인 자동 업데이트 및 배포 체계

---

## 21. 핵심 의사결정 요약

- Hikari v0.1은 **MP4만 지원한다.**
- 라이브 배경화면과 화면 보호기를 **초기 버전에 함께 제공한다.**
- 기능 수보다 **낮은 메모리 사용량과 안정성**을 우선한다.
- 영상 재생은 **AVFoundation 기반 네이티브 구현**을 사용한다.
- 앱은 **메뉴바 중심**으로 동작하며 macOS 기본 UI를 따른다.
- 배경화면과 화면 보호기는 별도 프로세스지만 콘텐츠와 설정을 공유한다.
- 두 프로세스가 동시에 영상을 장시간 재생하지 않도록 상태를 조정한다.
- 초기에는 플랫폼 확장보다 완성도 높은 VideoRenderer 구현에 집중한다.
