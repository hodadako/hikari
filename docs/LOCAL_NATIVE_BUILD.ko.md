# 다른 Mac에서 Hikari Native Local 빌드하기

Hikari Native Local은 소스에서 직접 빌드하는 실험용 버전입니다. Portable 다운로드나
앱 내 업데이트에 포함되지 않으므로, 사용할 Mac에서 직접 빌드하세요. 다른 기기에서
만든 앱을 복사해 사용하는 방식은 지원하지 않습니다.

Native Lock은 관리자 승인을 받은 뒤 macOS가 관리하는 비공개 영상 선택 데이터를
바꿉니다. 먼저 Mac을 백업하고 Restore 동작을 사용할 수 있게 두세요. 같은 macOS
영상 선택 저장소를 수정하는 다른 프로그램과 동시에 실행해서는 안 됩니다.

## 지원 환경

- Native Lock 작업용 Hikari는 macOS 15 또는 macOS 26에서만 지원합니다. 두 버전은
  서로 다른 저장소 경로를 사용하며, 다른 major 버전은 형식을 검토하기 전까지 Native
  Lock 쓰기를 의도적으로 차단합니다.
- **macOS 15**는 `/Library/Application Support/com.apple.idleassetsd/Customer/entries.json`의
  관리자 권한 구형 system catalog를 사용합니다. Apply와 Restore마다 one-shot helper의
  관리자 승인이 필요합니다.
- **macOS 26**은 `~/Library/Application Support/com.apple.wallpaper/aerials/`의 현재 사용자
  Aerial catalog를 사용합니다. 관리자 승인은 필요 없지만, 먼저 Apple Aerial wallpaper를
  한 번 내려받아 catalog를 초기화해야 합니다.
- 직접 빌드 스크립트에는 macOS 15 SDK 이상이 포함된 Swift toolchain이 필요합니다.
  Xcode 빌드와 테스트에는 전체 Xcode 설치본이 필요합니다.
- Hikari는 소스 전용입니다. 일반 Lumina Portable 릴리스는 별도 앱이며 Native Lock을
  포함하지 않습니다.

직접 빌드 스크립트는 출력을 만들기 전에 compiler 도구, 소스 디렉터리, localization과
아이콘, `LuminaNative-Info.plist`, Hikari 버전 값을 읽기 전용으로 사전 점검합니다.
`entries.json`과 `Index.plist`는 빌드 입력이 아닙니다. macOS의 사용자 또는 system
wallpaper 저장소가 소유하며, 실행 중인 Native Lock transaction이 시작된 뒤 검증하고
snapshot합니다. 빌드 스크립트는 이 runtime 파일을 bundle 안에 만들거나 복사하지 않습니다.

### macOS 26 Aerial catalog 초기화

macOS 26에서 Aerial catalog는 Apple Aerial wallpaper를 한 번 선택하거나 내려받은 뒤에만
생깁니다. Hikari가 **Initialize Apple Aerial wallpapers first**를 표시하면 다음 순서로
초기화하세요.

1. **시스템 설정 → 배경화면**을 엽니다.
2. Apple **Aerial** wallpaper 하나를 선택하고 다운로드가 끝날 때까지 기다립니다.
3. Hikari의 **Lock Screen**으로 돌아가 `Ready to apply locally` 상태인지 확인합니다.

catalog를 직접 만들거나 편집하지 마세요. Hikari는 Apple이 초기화한 manifest만 transaction의
기준으로 사용합니다.

Hikari에는 현재 Apple wallpaper index 안에 이미 존재하는 Lock Screen `Linked` choice도
필요합니다. Hikari는 이 choice를 추측해 만들거나 기존 `Desktop`/`Idle` choice를 대체하지
않습니다. 그렇게 하면 일반 배경화면 또는 화면 보호기 선택을 덮어쓸 수 있기 때문입니다.
Apply에서 **No wallpaper choices were found to update**가 나오면 **Restore Previous
Wallpaper**로 실패한 transaction을 먼저 복원하고 중지하세요. macOS가 실제 Linked Lock
Screen choice를 만들기 전에는 현재 topology에서 Native Lock을 안전하게 적용할 수 없습니다.

## 1. Mac 준비

Xcode 16 이상 전체 설치본을 설치하고 한 번 실행한 다음 라이선스를 승인하세요.
활성 개발자 경로가 Command Line Tools를 가리키면 Xcode로 바꿉니다.

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license
xcodebuild -version
```

`sudo xcodebuild -license`는 Terminal에서 내용을 읽고 승인하는 대화형 명령입니다.
관리형 Mac에서는 권한 없이 실행하지 마세요.

Git을 설치하세요. 직접 빌드 스크립트에는 Homebrew와 XcodeGen이 필수는 아니지만,
Xcode 프로젝트를 생성하려면 XcodeGen이 필요합니다.

```sh
brew install xcodegen
```

## 2. 소스 받기

```sh
git clone https://github.com/hodadako/lumina.git
cd lumina
git status --short
```

Native Lock을 켜기 전에 소스와 `docs/` 문서를 확인하세요. `git status --short`의
출력이 비어 있으면 checkout에 로컬 변경이 없다는 뜻입니다.

## 3. Hikari 빌드 및 설치

직접 빌드 스크립트는 Hikari를 빌드하고 ad-hoc 서명·검증·설치한 뒤 Launch Services와
Spotlight에 등록합니다.

```sh
scripts/build-native-local.sh
codesign --verify --deep --strict /Applications/Hikari.app
open -a Hikari
```

기본 설치 위치는 `/Applications/Hikari.app`입니다. 현재 사용자가 `/Applications`에
쓸 수 없다면 해당 사용자의 Applications 폴더에 설치하세요.

```sh
mkdir -p "$HOME/Applications"
LUMINA_NATIVE_INSTALL_DIRECTORY="$HOME/Applications" \
  scripts/build-native-local.sh
open "$HOME/Applications/Hikari.app"
```

Hikari는 agent 앱이므로 Dock 대신 메뉴 막대에 나타납니다. 스크립트가 끝나면
Spotlight에서 `Hikari`를 찾을 수 있습니다. Spotlight 색인이 끝나기 전에는 위의
`open` 명령으로 직접 실행할 수 있습니다.

## 4. 선택: Xcode 빌드와 테스트

코드를 변경했거나 해당 Mac의 toolchain을 검증할 때 사용하세요. 이 단계는 빌드와
테스트만 수행하며 Native Lock을 켜거나 macOS 설정을 바꾸지 않습니다.

```sh
xcodegen generate
xcodebuild \
  -project Lumina.xcodeproj \
  -scheme LuminaNative \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project Lumina.xcodeproj \
  -scheme LuminaNative \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 5. Native Lock을 안전하게 사용하기

1. Hikari를 실행하고 **General**에서 영상을 가져옵니다.
2. **Lock Screen**에서 safety status를 읽은 뒤에만 선택 영상을 적용합니다.
3. Apply와 Restore는 매번 macOS 관리자 승인을 요청합니다.
4. 사용하기 전에 lock → unlock → 다음 lock을 직접 시험합니다.
5. macOS major 업데이트 전, Hikari를 삭제하기 전, 또는 실험이 끝났을 때는 반드시
   **Restore**를 사용합니다.

Native Lock transaction이 활성인 동안에는 Hikari를 실행해 둬야 사용자 수준 mapping을
확인하고 필요한 복구를 수행할 수 있습니다. transaction 파일을 직접 수정하지 마세요.

## 문제 해결

| 증상 | 안전한 조치 |
| --- | --- |
| `xcodebuild`가 라이선스 미승인을 알림 | `sudo xcodebuild -license`를 실행하고 대화형 승인을 완료합니다. |
| 도구가 `/Library/Developer/CommandLineTools`를 사용함 | `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`로 전체 Xcode를 선택합니다. |
| 설치 단계에서 `/Applications` 쓰기 실패 | 위의 `LUMINA_NATIVE_INSTALL_DIRECTORY="$HOME/Applications"` 방식을 사용합니다. |
| Spotlight에 Hikari가 아직 안 보임 | `open /Applications/Hikari.app` 또는 `$HOME/Applications`의 해당 경로로 실행하고 색인이 끝날 때까지 기다립니다. |
| Hikari가 Native Lock 쓰기를 사용할 수 없다고 표시 | macOS 15 또는 26인지 확인하세요. 운영체제 안전 차단을 우회하지 마세요. |
| macOS 26에서 `Clear Failed Preparation`이 보임 | 구형 빌드가 system write 전에 거절된 기록입니다. 이 버튼은 적용 hash가 전혀 없는 정확한 실패 기록만 정리합니다. 누른 뒤 Lock Screen에서 선택 영상을 다시 Apply하세요. |
| macOS 26에서 구형 transaction Restore가 실패함 | system 또는 user mapping이 적용된 기록이라면 macOS 15에서 Hikari를 실행해 Restore하세요. journal이나 wallpaper 파일을 직접 삭제하지 마세요. |
| Apply 또는 잠금 화면 시험이 이상함 | 추가 시험을 멈추고 Restore를 실행한 뒤, 다른 변경을 하기 전에 transaction/error 정보를 보존합니다. |

Apply 또는 Restore 진단은 다음 명령으로 확인할 수 있습니다.

```sh
log stream --level info \
  --predicate 'subsystem == "com.hodadako.Lumina.NativeLocal"'
```
