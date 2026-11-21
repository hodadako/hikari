# Native Lock 영상·빠른 재잠금 점검 — 2026-11-21

## 목적과 범위

보고 환경은 Hikari 0.5.7, Tahoe 26.6.2/M4 Pro다. 해제 후 1초 이내
재잠금하면 두 번째 잠금 화면이 검게 남고, 해제 후 데스크톱은 정상이다.
이번 점검은 현재 Mac의 **macOS 27.2.1 (26B131), Apple M1, Xcode 26.6/SDK 26.5**에서
임시 영상으로 실행했다. 15·26의 실제 OS 실행이나 Native Lock 재현으로 기록하지 않는다.
실제 잠금 알림, wallpaper 파일 변경, process restart, Apply/Restore 및 root 작업은 없었다.

## 실제 영상 비교

320×180, 30fps, 60프레임의 밝은 H.264 영상(2초)을 생성했다. 15 경로와 같은
passthrough, 기존 26과 같은 Main10 writer 설정(진단용 작은 canvas), PR #83의
실제 `AerialTemporalEncoder`를 비교했다. 원본 사용자 영상은 읽거나 변환하지 않았다.

| 준비 방식 | codec | temporal 정보가 있는 프레임 | sublayer access key | temporal level |
| --- | --- | --- | --- | --- |
| 15 방식 passthrough | H.264 | 0/60 | 0/60 | 없음 |
| 기존 26 방식 Main10 | HEVC Main10 | 0/60 | 0/60 | 없음 |
| 26/27 후보 temporal | HEVC Main10 | 60/60 | 30/60 | 0, 1 |

세 사본 모두 길이 2초, compressed sample 60개를 유지했다. 각각 EOF까지 읽고
새 reader로 재개하는 검사를 3회 실행했다. 각 회차의 실제 decode도 60프레임,
생성한 단색 프레임의 첫 pixel 기준 검정 프레임 0개였다. temporal 사본은 세 회차
모두 60/60 프레임에 실제 CoreMedia temporal 정보를 제공했다.

이는 **일반 decode 성공과 temporal 정보의 유무가 별개**임을 확인한다.
`AVAssetReader` EOF/reopen은 macOS의 비공개 Aerial reader가 수행하는 loop나
unlock ramp-down의 재현이 아니다. 짧은 영상 loop 오류가 해결됐다고 결론내리지 않는다.

[Apple passthrough 설명](https://developer.apple.com/documentation/avfoundation/avassetexportpresetpassthrough)은
원본 형식 유지이며, [CoreMedia temporal attachment](https://developer.apple.com/documentation/coremedia/kcmsampleattachmentkey_hevctemporallevelinfo)는
계층 의존 정보다. 해당 공개 API 설명은 Apple의 Native Lock 호환성 보증이 아니다.
원본이 이미 적합한 HEVC인 경우도 있으므로 모든 macOS 15 사본에 정보가 없다고 일반화하지 않는다.

## 공통 재잠금 스케줄

실제 `NativeLockMaintenanceSchedule`에 0.2, 0.8, 1.99, 2.0, 3.0초 간격을 넣었다.
2초 미만에서는 유지보수가 허용되지 않았고, 재잠금 취소 후에는 요청이 남지 않았다.
다음 unlock은 새 2초를 기다리며 이전 deadline으로 0.65초 만에 우회하지 않았다.
이는 OS별 3회 실행이 아니라 15/26/27이 공유하는 동일 Core 모델의 5개 입력 검사다.

잠금 중 재시작을 피하는 현재 정책은 정상이다. 다만 이미 macOS reader가 고착됐다면
1초 안의 다음 잠금 전에 이를 재시작할 기회가 없다는 복구 한계는 남는다.
시간을 줄이거나 잠금 중 재시작하는 방법은 채택하지 않는다.

## 회귀 검사와 남은 범위

- 기존 hardware encoder 테스트를 보강했다. box 이름 검사에 더해 압축 sample의
  실제 temporal attachment와 계층, sublayer access를 EOF/reopen 3회 모두 확인한다.
- 로컬 `swift test --filter AerialTemporalEncoderTests`: 4개 통과, 실패·skip 0.
- 로컬 `xcodebuild ... -only-testing:HikariCoreTests/AerialTemporalEncoderTests test`:
  4개 통과, 실패·skip 0. 제품 runtime 소스는 이번 점검에서 변경하지 않았다.
- 15.7.9의 과거 Code 4 기록과 현재 passthrough 경로를 함께 보면 15도 후속 점검 대상이다.
  15의 root Apply/Restore와 영상 준비 정책은 그대로이며 temporal 전환을 활성화하지 않았다.
- 26.6.2/M4 Pro의 실제 1초 재잠금, 15의 새 인코딩 적합성, 27의 반복 잠금,
  실제 loop/ramp-down 및 물리 Intel 인코딩은 이 점검으로 통과 판정할 수 없다.
- 다음 실기기 점검은 같은 영상으로 짧은 재잠금과 3초 이상 대기를 비교하고,
  영상 끝을 넘기는 잠금 시간도 분리한다. Code 4, EOF/샘플 오류, refresh 시각을 대조한다.

## 안전한 재현 도구

`scripts/diagnostics/NativeLockMediaAudit.swift`는 앱 target에 포함되지 않는 점검 도구다.
실제 Core 소스를 직접 컴파일하므로 검사된 framework나 LLVM coverage runtime에 의존하지 않는다.
출력은 기존 부모가 있는 **새 임시 디렉터리**만 허용한다. 기존 출력·일반 저장소 경로·
임시 경로 밖으로 나가는 symlink를 거부한다. 인자 누락까지 네 거부 검사를 통과했고,
거부 후 기존 진단 결과의 모든 file hash가 유지됐다.

저장소 루트에서 실행한다. 전체 비교에는 호환되는 hardware HEVC encoder가 필요하며,
없으면 실패로 종료한다. 이 실패는 Native Lock 미지원이나 실기기 검증 성공을 뜻하지 않는다.

```sh
audit_directory="$(mktemp -d "${TMPDIR:-/tmp}/hikari-native-media-audit.XXXXXX")"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macosx15.0" \
  scripts/diagnostics/NativeLockMediaAudit.swift \
  Sources/HikariCore/AerialTemporalEncoder.swift \
  Sources/HikariCore/AerialTemporalSampleGroups.swift \
  Sources/HikariCore/VideoPreparationControl.swift \
  Sources/HikariCore/NativeLockMaintenanceSchedule.swift \
  -o "${audit_directory}/audit"
"${audit_directory}/audit" "${audit_directory}/output"
```

결과는 출력 디렉터리의 `report.json`과 생성 영상으로 남는다. 이번 원시 결과는
`/private/tmp/hikari-native-media-audit-20261121/output-3/report.json`, source 직접 컴파일과
실행 로그·거부 검사 기록은 그 상위 디렉터리에 있다. 임시 자료의 영구 보존은 보장하지 않는다.
