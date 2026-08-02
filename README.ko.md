# Lumina

[English](README.md) | [한국어](README.ko.md)

**데스크톱에 생동감을 더하세요.**

Lumina는 macOS용 네이티브 오픈 소스 라이브 배경화면 및 화면 보호기입니다.
MP4 하나를 가져오면 연결된 모든 디스플레이의 배경화면과 Lumina 화면
보호기에서 함께 사용할 수 있습니다.

> Lumina 0.1은 초기 MVP입니다. 개발과 직접 테스트에는 사용할 수 있지만,
> 아직 Apple 공증을 받은 배포판은 아닙니다.

## 주요 기능

- MP4 검증, 관리 폴더 복사, 메타데이터 추출, 중복 검사 및 썸네일 생성
- `AVQueuePlayer`와 `AVPlayerLooper`를 이용한 저부하 반복 재생
- 모든 Space와 연결된 디스플레이를 지원하는 테두리 없는 배경화면 창
- 투명 메뉴 막대와 잠금 화면을 위한 대표 프레임 동기화
- 채우기 및 맞추기 화면 배율
- 메뉴 막대의 재생 및 콘텐츠 제어
- 음소거, 배터리 일시정지, 로그인 시 실행, 라이브러리 관리 설정
- 잠자기, 화면 잠금, 화면 보호기 및 디스플레이 변경 시 일시정지와 복구
- 미리보기와 전체 화면 재생을 지원하는 별도 `.saver` 번들
- 1분 후 Lumina 화면 보호기를 실행하는 선택형 잠금 화면 재생
- 즉시 영상을 실행하는 Lumina 잠금과 선택형 ^ + Command + Q 재정의
- `~/Library/Application Support/Lumina`의 원자적 JSON 저장소
- macOS 시스템 언어를 따르는 영어 및 한국어 UI
- 블루, 핑크, 퍼플 및 사용자 이미지 앱 아이콘 선택

## 요구 사항

- macOS 13 Ventura 이상
- Xcode 15 이상
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

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

## 현재 제한 사항

- MP4만 지원
- 모든 디스플레이에 같은 영상 표시
- 재생목록, 온라인 갤러리 및 디스플레이별 콘텐츠 미지원
- Portable 배포판은 Apple 공증되지 않음
- 장시간 성능 기준은 Instruments를 이용한 직접 테스트 필요

## 기여 및 라이선스

[CONTRIBUTING.md](CONTRIBUTING.md)를 확인하세요. Lumina는
[MIT License](LICENSE)로 배포됩니다.
