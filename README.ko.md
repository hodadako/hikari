# Hikari

내 영상을 데스크톱과 잠금 화면의 라이브 배경화면으로 쓰는 macOS 메뉴 막대 앱입니다.

**[macOS용 Hikari 다운로드](https://github.com/hodadako/hikari/releases/latest)** · [English](README.md)

## 설치하고 시작하기

1. 최신 릴리스에서 `Hikari-macOS-portable.zip`을 받아 압축을 풉니다.
2. `Hikari.app`을 응용 프로그램 폴더로 옮기고 실행합니다.
3. 메뉴 막대에서 Hikari를 열고 **콘텐츠 변경 → 영상 가져오기…**를 선택합니다. macOS 26과 27에서는 영상을 선택하면 잠금 화면도 바뀔 수 있습니다.

배포 앱은 ad-hoc 서명 상태이며 Apple 공증을 받지 않았습니다. 첫 실행에 경고가 나오면 [Apple의 다운로드한 앱 열기 안내](https://support.apple.com/ko-kr/102445)를 참고하세요.

<details>
<summary>다운로드 검증 또는 AI로 설치하기</summary>

다운로드한 ZIP을 검증하려면 ZIP과 `.sha256` 파일을 같은 폴더에 저장하고, 그 폴더에서 아래 명령을 실행하세요.

```sh
shasum -a 256 -c Hikari-macOS-portable.zip.sha256
```

AI 어시스턴트로 설치하려면 아래 문장을 복사하세요.

```text
이 Mac에 GitHub 최신 릴리스의 Hikari를 설치해 줘. 영상을 선택하기 전에 나에게 물어봐. macOS 26이나 27에서는 영상 선택 시 macOS 잠금 화면에도 적용될 수 있다고 안내하고 내 동의를 받은 뒤 진행해 줘.
```

</details>

## 주요 기능

- 연결된 디스플레이와 Spaces에서 같은 영상을 반복 재생합니다.
- 메뉴 막대에서 재생을 멈추거나 영상을 바꿀 수 있습니다. 설정에서 채우기·맞추기, 음소거, 배터리 사용 시 일시정지를 고를 수 있습니다.
- 라이브러리에서 영상을 검색하고 즐겨찾기와 제목을 관리할 수 있습니다. 앱·메뉴 막대 아이콘도 바꿀 수 있습니다.

## 지원 환경

| macOS | 지원 기기 | 잠금 화면 |
| --- | --- | --- |
| 15 Sequoia | Apple Silicon·Intel | **설정 → 일반**에서 직접 적용·복원합니다. 관리자 승인이 필요합니다. |
| 26 Tahoe | Apple Silicon·Intel | 영상 선택 시 잠금 화면에도 자동 적용될 수 있습니다. 새 변환에는 호환 HEVC 하드웨어 인코더가 필요합니다. |
| 27 Golden Gate | Apple Silicon | 배경화면 저장소 검사를 통과하면 영상 선택 시 잠금 화면에도 자동 적용될 수 있습니다. 새 변환에는 호환 HEVC 하드웨어 인코더가 필요합니다. |

잠금 화면 기능은 macOS가 관리하는 배경화면 설정을 바꿉니다. 사용 전에 Mac을 백업하고, macOS의 주요 버전을 올리기 전에 **이전 배경화면 복원**을 선택하세요. macOS 15에서는 적용 중 같은 Mac의 다른 계정이 잠금 화면용 사본을 읽을 수 있습니다.

반복 잠금 동작은 실기기에서 추가 확인이 필요합니다. [잠금 화면 조사 기록](docs/NATIVE_LOCK_BLACK_SCREEN.md)

## 개발

<details>
<summary>소스에서 빌드하고 테스트하기</summary>

Xcode 16 이상과 [XcodeGen](https://github.com/yonaskolb/XcodeGen)을 설치하세요. 프로젝트를 생성한 뒤 Xcode에서 **Hikari** 스킴을 빌드하거나 테스트합니다.

```sh
xcodegen generate
open Hikari.xcodeproj
```

패키지 테스트는 `swift test`로 실행합니다.

</details>

[릴리스 노트](https://github.com/hodadako/hikari/releases) · [아키텍처](ARCHITECTURE.md) · [버전별 검증 기록](docs/VERSION_ISSUES.md) · [기여](CONTRIBUTING.md) · [보안 제보](SECURITY.md) · [MIT 라이선스](LICENSE)
