# Hikari

[English](README.md) | [한국어](README.ko.md)

[![CI](https://github.com/hodadako/lumina/actions/workflows/ci.yml/badge.svg)](https://github.com/hodadako/lumina/actions/workflows/ci.yml)
[![Codecov](https://codecov.io/gh/hodadako/lumina/branch/main/graph/badge.svg)](https://codecov.io/gh/hodadako/lumina)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/hodadako/lumina)

**데스크톱에 생동감을 더하세요.**

Hikari는 macOS용 네이티브 라이브 배경화면 앱입니다. 영상을 가져와 연결된
디스플레이에서 재생하고, 원하면 선택한 영상을 macOS Native Lock Screen 경로에
적용할 수 있습니다.

> Hikari 릴리스 빌드는 ad-hoc 서명되며 Apple 공증을 받지 않습니다.

## 주요 기능

- AVFoundation 영상 검증, 관리 폴더 복사, 메타데이터·중복 검사 및 썸네일 생성
- 연결된 디스플레이와 Space에서 저부하 반복 재생
- 채우기/맞추기 배율, 음소거, 배터리 일시정지, 로그인 시 실행, 라이브러리 관리
- 메뉴 막대 재생 및 콘텐츠 제어
- macOS 26에서 영상 선택 시 자동 Native Lock Screen 적용, transaction 복구 및 Restore
- 기본·사용자 지정 앱 아이콘과 메뉴 막대 아이콘
- 일반 `vX.Y.Z` 릴리스 채널의 checksum 검증 앱 업데이트

## 요구 사항

- macOS 15 이상
- Xcode 16 이상
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Xcode 스킴과 XCTest 전체 실행에는 전체 Xcode 설치가 필요합니다.

## Native Lock Screen 기능 고지

Native Lock은 문서화되지 않은 macOS wallpaper/Aerial 상태를 변경합니다. 형식은
예고 없이 바뀔 수 있으며 실패한 작업은 복구가 필요할 수 있습니다. macOS 15에서는
관리자 인증을 요청할 수 있고, macOS 26에서는 현재 사용자의 Aerial 저장소를
사용합니다.

검증된 백업을 준비하고 관리형 Mac이나 복구하기 어려운 장비에서는 사용하지
마세요. Hikari는 transaction journal을 만들며, 앱 업데이트 전 또는 recovery-required
transaction을 바꾸기 전에는 **Restore**를 요구합니다. macOS 26에서는 다른 영상을
선택하면 active Aerial transaction을 자동으로 교체합니다. Native Lock 활성 중에는
macOS 서비스가 읽을 수 있는 root-readable 재생 복사본이 생길 수 있습니다.

## 다운로드

[최신 릴리스](https://github.com/hodadako/lumina/releases/latest)에서
`Hikari-macOS-portable.zip`을 내려받아 압축을 풀고 `Hikari.app`을 응용 프로그램
폴더로 옮기세요.

앱은 ad-hoc 서명되며 공증되지 않았습니다. 처음 실행할 때 `Hikari.app`을
Control-클릭하고 **열기**를 선택해 확인하세요. 실행 전에 checksum을 확인할 수
있습니다.

```sh
shasum -a 256 -c Hikari-macOS-portable.zip.sha256
```

## 저장소 마이그레이션

Hikari는 기존 `~/Library/Application Support/Lumina`를 canonical 라이브러리로
유지합니다. 첫 실행 시 이전
`~/Library/Application Support/LuminaNative`에서 없는 콘텐츠·설정·아이콘·Native
Lock transaction을 합친 뒤 원본 폴더를 복구 가능한 `.archived` 폴더로 이동합니다.
충돌 시 기존 canonical 파일을 우선하며 원본 영상은 삭제하지 않습니다.

## 빌드

```sh
brew install xcodegen
xcodegen generate
open Hikari.xcodeproj
```

Xcode에서 `Hikari` 스킴을 선택하세요. 명령줄에서는 다음을 사용합니다.

```sh
xcodebuild \
  -project Hikari.xcodeproj \
  -scheme Hikari \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

로컬 ad-hoc 설치는 다음 스크립트로 만들 수 있습니다.

```sh
scripts/build-hikari.sh
```

스크립트는 `/Applications/Hikari.app`을 빌드·설치합니다. macOS 26에서는 General에서
영상을 바꾸면 Native Lock Screen Aerial도 자동 적용됩니다. Restore는 transaction
복구가 필요한 경우에만 General에 표시됩니다. daemon이나 persistent privileged helper는
설치하지 않습니다.

## 테스트

```sh
swift test
xcodebuild \
  -project Hikari.xcodeproj \
  -scheme Hikari \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 릴리스

일반 `vX.Y.Z` 태그는 Hikari만 빌드하고
`Hikari-macOS-portable.zip`과 SHA-256 checksum을 게시합니다. 태그가 아닌
빌드는 검증과 테스트만 수행하며 패키징·게시 작업은 태그에서만 실행됩니다.

## 프로젝트 구조

```text
Sources/
├── LuminaApp/          Hikari 메뉴 막대 UI, 설정, 배경화면 창
├── LuminaCore/         모델, 저장소, 가져오기, 정책, 렌더러
├── LuminaNativeLock/   Native Lock transaction·백업·적용·복원 엔진
└── LuminaNativeTool/   관리자 인증 one-shot 시스템 작업
Archive/LuminaLegacy/   폐기된 Lumina 화면 보호기·event-tap 소스
Tests/
├── LuminaCoreTests/
└── LuminaNativeLockTests/
```

## 현재 제한 사항

- 영상 지원 범위는 설치된 macOS의 AVFoundation 기능에 따릅니다.
- 모든 디스플레이에 같은 영상을 표시하며 디스플레이별 콘텐츠는 지원하지 않습니다.
- 재생목록, 온라인 갤러리, 디스플레이별 콘텐츠는 지원하지 않습니다.
- 릴리스는 ad-hoc 서명되며 Apple 공증을 받지 않습니다.
- Native Lock은 문서화되지 않은 macOS 동작을 사용하므로 macOS 버전별 복구
  테스트가 필요합니다.

## 기여 및 라이선스

[CONTRIBUTING.md](CONTRIBUTING.md)를 확인하세요. 보안 제보는
[SECURITY.md](SECURITY.md)를 따라 주세요.

Hikari는 [MIT License](LICENSE)로 배포됩니다.
