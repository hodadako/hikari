# Lumina

[English](README.md) | [한국어](README.ko.md)

[![Codecov](https://codecov.io/gh/hodadako/lumina/branch/main/graph/badge.svg)](https://codecov.io/gh/hodadako/lumina)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/hodadako/lumina)

**데스크톱에 생동감을 더하세요.**

Lumina는 macOS용 네이티브 오픈 소스 라이브 배경화면 및 화면 보호기입니다.
AVFoundation에서 재생 가능한 영상(MP4, MOV, M4V 등)을 가져오면 연결된 모든
디스플레이의 배경화면과 Lumina 화면 보호기에서 함께 사용할 수 있습니다.

> Lumina 0.3은 여전히 실험적 프로젝트입니다. Portable 빌드는 ad-hoc
> 서명되며 Apple 공증을 받지 않습니다.

## 주요 기능

- AVFoundation 재생 가능 영상 검증, 원본 컨테이너 확장자를 보존한 관리 폴더
  복사, 메타데이터 추출, 중복 검사 및 썸네일 생성
- `AVQueuePlayer`와 `AVPlayerLooper`를 이용한 저부하 반복 재생
- 모든 Space와 연결된 디스플레이를 지원하는 테두리 없는 배경화면 창
- 연결된 모든 디스플레이에서 독립 플레이어로 동시 재생하며 macOS 바탕화면과
  메뉴 막대는 변경하지 않음
- 채우기 및 맞추기 화면 배율
- 메뉴 막대의 재생 및 콘텐츠 제어
- 음소거, 배터리 일시정지, 로그인 시 실행, 라이브러리 관리 설정
- 잠자기, 화면 잠금, 화면 보호기 및 디스플레이 변경 시 일시정지와 복구
- 화면 보호기 설치/업데이트와 잠금 화면 재생은 사용자가 명시적으로 선택한
  경우에만 수행하며 기존 시작 시간을 정확히 복원
- 미리보기와 전체 화면 재생을 지원하는 별도 `.saver` 번들
- 1분 후 Lumina 화면 보호기를 실행하는 선택형 잠금 화면 재생
- 즉시 영상을 실행하는 Lumina 잠금과 선택형 ^ + Command + Q 재정의
- `~/Library/Application Support/Lumina`의 원자적 JSON 저장소
- macOS 시스템 언어를 따르는 영어 및 한국어 UI
- Finder, Spotlight 및 앱 전환기에 적용되는 블루, 핑크, 퍼플 및 사용자 지정 앱 아이콘
- 앱 아이콘과 별도로 선택할 수 있는 기본 제공 및 사용자 지정 메뉴 막대 아이콘
- 최신 릴리스 확인 및 checksum 검증 후 앱 내 업데이트

## 요구 사항

- macOS 13 Ventura 이상
- Xcode 15 이상
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Xcode 스킴과 XCTest 전체 실행에는 전체 Xcode가 필요합니다. Native Local은
macOS 15 SDK가 포함된 toolchain(Xcode 16 또는 대응 Apple Command Line Tools)도
필요합니다. Native Local 직접 빌드 스크립트는 Command Line Tools만으로도
컴파일할 수 있지만, 이 환경은 저장소의 XCTest 타깃을 실행하지 못합니다.

## 실험적 native 잠금 화면 기능 고지

사용자 지정 영상을 macOS native 잠금 화면에 표시하는 실험 기능은 Hikari의 별도
ad-hoc·비공증 release workflow로 게시할 수 있으며, 지원되는 Lumina Portable 배포판이나 앱 내
업데이트 경로에는 포함하지 않습니다. macOS 15에서는 관리자 인증을 요청하고 macOS 26은
현재 사용자 Aerial 저장소를 사용합니다. 이 기능은 문서화되지 않은 macOS wallpaper/aerial
상태를 변경할 수 있으며, 해당 형식은 예고 없이 바뀔 수 있습니다. 작업이 실패하면
사용자가 배경화면 설정을 직접 복구해야 할 수 있습니다.

transaction staging 폴더는 현재 사용자만 접근할 수 있습니다. 하지만 Native
잠금이 활성화된 동안 macOS 시스템 서비스가 읽을 수 있도록 root 소유의
system-readable 재생 복사본이 존재하므로, 같은 Mac의 다른 로컬 계정도 이 파일을
읽을 수 있습니다. 명시적인 복원 작업은 hash가 확인된 시스템 복사본을 제거합니다.

기능을 켜기 전에 소스를 로컬에서 직접 빌드하고 변경 내용을 확인하세요. 검증된
백업과 복구 경로를 준비하고, 관리형 Mac이나 복구하기 어려운 장비에서는 사용하지
마세요. 같은 system wallpaper/aerial 저장소를 수정하는 다른 도구와 동시에
실행해서도 안 됩니다. GitHub Actions는 계속 Lumina를 빌드하고 테스트하지만,
CI 성공이나 다운로드 가능한 artifact가 사용자 Mac에서의 root 변경을 검증하거나
보증한다는 의미는 아닙니다. 일반 라이브 배경화면과
`ScreenSaver.framework` 기능은 이 실험과 별개입니다. `LuminaNative`는 명시적
관리자 승인 뒤 번들 내부의 one-shot 도구만 실행하며, 활성화 전에 사용자 및
root 소유 백업과 transaction journal을 만들고 결과를 검증합니다. 명시적인 복원
버튼도 제공합니다. 상시 daemon이나 persistent privileged helper는 설치하지
않습니다.

## Portable 앱 다운로드

[최신 릴리스](https://github.com/hodadako/lumina/releases/latest)에서
`Lumina-macOS-portable.zip`을 내려받아 압축을 풀고 `Lumina.app`을
응용 프로그램 폴더로 옮기세요.

Portable 빌드는 ad-hoc 서명되지만 Apple 공증은 받지 않았습니다. 처음
실행할 때 `Lumina.app`을 Control-클릭하고 **열기**를 선택한 다음 다시
**열기**를 확인하세요. Lumina는 Dock이 아닌 메뉴 막대에 나타납니다.

릴리스에 포함된 SHA-256 파일은 다음과 같이 확인할 수 있습니다.

```sh
shasum -a 256 -c Lumina-macOS-portable.zip.sha256
```

## 빌드

```sh
brew install xcodegen
xcodegen generate
open Lumina.xcodeproj
```

Xcode에서 `Lumina` 스킴을 선택해 실행하세요. 명령줄에서는 다음 명령을
사용할 수 있습니다.

```sh
xcodegen generate
xcodebuild \
  -project Lumina.xcodeproj \
  -scheme Lumina \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

빌드된 앱에는 `Lumina.saver`가 포함됩니다. Lumina 설정 → 화면 보호기에서
설치한 뒤 macOS 시스템 설정에서 Lumina를 직접 선택해야 합니다.

macOS 15 또는 macOS 26에서 별도 로컬 전용 버전을 확인하려면 `LuminaNative` 스킴을
선택하세요. `Hikari.app`은 bundle ID
`com.hodadako.Lumina.NativeLocal`과
`~/Library/Application Support/LuminaNative` 저장소를 사용합니다. 시스템
소유 `Control-Command-Q` 잠금 경로를 그대로 지원하며 자동 업데이트는 사용하지
않습니다. 일반 Lumina 타깃은 기존 선택형 event-tap 단축키 재정의를 유지합니다.
Native Local은 별도 GitHub Actions에서 compile/test만 하며, 별도 Hikari Release
workflow가 `hikari-vX.Y.Z` tag에서 ad-hoc release artifact를 패키징·업로드합니다.

Xcode를 열지 않고 로컬 ad-hoc 앱을 만들려면 다음 스크립트를 실행하세요.

```sh
scripts/build-native-local.sh
```

스크립트는 ad-hoc 서명된 앱을 `/Applications/Hikari.app`에 설치하고 Launch
Services와 Spotlight에 등록한 뒤 해당 경로를 출력합니다. Spotlight에서 `Hikari`를
검색해 실행하고 영상을 가져온 뒤
설정 → Lock Screen → 선택한 영상 적용을 사용합니다. macOS 15에서는 적용과 복원 때마다
관리자 승인이 필요하고, macOS 26 user Aerial transaction은 현재 사용자 권한으로 실행됩니다.
system write는 검토된 macOS 15와 macOS 26의 별도 경로에서만
허용하며, 다른 major 버전은 해당 형식을 다시 검토하기 전까지 read-only입니다. 새 Mac
준비, 빌드, 검증과 복원까지의 전체 절차는
[다른 Mac에서 Hikari Native Local 빌드하기](docs/LOCAL_NATIVE_BUILD.ko.md)를 확인하세요.

로컬 적용·복원 진단 시 다른 Terminal 창에서 transaction과 one-shot 도구 로그를
확인할 수 있습니다.

```sh
log stream --level info \
  --predicate 'subsystem == "com.hodadako.Lumina.NativeLocal"'
```

## 테스트

```sh
swift test
```

전체 Xcode 테스트:

```sh
xcodebuild \
  -project Lumina.xcodeproj \
  -scheme Lumina \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

`LuminaNative` 스킴의 Native Local 테스트도 같은 방식으로 실행할 수 있습니다.
이 CI와 테스트는 앱을 실행하거나 macOS system wallpaper 상태를 변경하지
않습니다.

## 현재 제한 사항

- 영상 container와 codec 지원 범위는 현재 macOS의 AVFoundation 기능을 따르며
  일반적인 MP4, MOV, M4V 파일을 지원
- 모든 디스플레이에 같은 영상을 독립 플레이어로 표시하지만 디스플레이별
  콘텐츠는 지원하지 않음
- 재생목록, 온라인 갤러리 및 디스플레이별 콘텐츠 미지원
- Portable 배포판은 Apple 공증되지 않음
- Native Local은 별도 ad-hoc·비공증 바이너리 artifact로 게시할 수 있으며 앱 내 자동 업데이트는 없음
- 장시간 성능 기준은 Instruments를 이용한 직접 테스트 필요

## 기여 및 라이선스

[CONTRIBUTING.md](CONTRIBUTING.md)를 확인하세요. Lumina는
[MIT License](LICENSE)로 배포됩니다.
