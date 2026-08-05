# CherryPicker 테스트 운영 가이드

- 문서 역할: 반복 가능한 테스트 절차와 인수 증거 기록
- 적용 범위: 기능 브랜치, UI 검토, SwiftData 마이그레이션, 실기기 인수 테스트
- 관련 기준: [`ARCHITECTURE.md`](ARCHITECTURE.md), [`MVP_REQUIREMENTS.md`](MVP_REQUIREMENTS.md)

이 문서는 에이전트의 일반 작업 원칙이 아니라 프로젝트의 테스트 운영 방법을 기록한다. 구현 세션은 변경 범위에 맞는 경로만 선택하고, 수행하지 못한 검증은 완료한 것처럼 보고하지 않는다.

## 1. 테스트 경로

| 경로 | 목적 | 확인하지 못하는 것 |
|---|---|---|
| 자동 테스트 | 도메인 정책, 저장 명령, 관계, 마이그레이션 회귀 | 실제 단축어와 네이티브 화면 체감 |
| 브라우저 프로토타입 | 화면 구성, 문구, 입력 흐름의 빠른 원격 검토 | SwiftUI, SwiftData, App Intent의 실제 동작 |
| 내부 TestFlight | 외부 네트워크에서 실제 iPhone 앱과 업데이트 검증 | 디버거가 필요한 저수준 진단 |
| Xcode 실기기 실행 | App Intent, 단축어, 백그라운드·잠금 및 서명 진단 | 원격·상시 접근성 |

자동 테스트는 모든 비단순 동작 변경의 기본 경로다. 브라우저 프로토타입은 중요한 UI 결정을 검토할 때만 사용한다. 네이티브 인수 조건은 프로토타입 승인으로 대체하지 않는다.

## 2. 자동 테스트

### CherryPickerCore

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
```

### 앱·SwiftData·UI 관련 변경

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test \
  -project CherryPickerApp/CherryPicker.xcodeproj \
  -scheme CherryPicker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /private/tmp/CherryPicker-derived-data \
  CODE_SIGNING_ALLOWED=NO
```

- 기능 브랜치는 전용 시뮬레이터와 고유 Derived Data 경로를 사용한다.
- 시뮬레이터 이름을 바꿨다면 최종 결과에 실제 이름과 OS 버전을 기록한다.
- SwiftData 스키마 변경은 빈 저장소와 디스크 기반 V1 fixture 업그레이드를 모두 검증한다.
- 마이그레이션 검증은 거래 수와 UUID, 원문, 사용자 override·판정·메모, 관계 backfill을 비교한다.

## 3. 브라우저 UI 검토

브라우저 프로토타입은 실제 앱을 웹으로 포팅하는 작업이 아니다. 해당 이슈의 UI 결정에 필요한 화면과 상태만 별도 fixture로 표현한다.

- 실제 문자 원문, 이름, 잔액이나 기기 저장소를 사용하지 않는다.
- 로컬 개발 서버만 외부에 노출하고 저장소·디버거 포트를 노출하지 않는다.
- Tailscale Serve를 사용할 때는 tailnet 내부 접근으로 제한하고 검토가 끝나면 route를 비활성화한다.
- Serve가 비활성화된 tailnet에서는 서버를 Mac의 Tailscale IP에만 바인딩하는 임시 HTTP 경로를 사용할 수 있다. `0.0.0.0`에는 바인딩하지 않는다.
- 승인 결과에는 확인한 화면·상태와 프로토타입이라 확인하지 못한 네이티브 항목을 함께 기록한다.

예시 흐름:

```text
격리된 fixture 기반 웹 프로토타입
  → localhost 개발 서버
  → Tailscale Serve의 tailnet 전용 HTTPS 주소
  → 외부 브라우저에서 UI와 입력 흐름 검토
```

Tailscale은 네트워크 연결만 제공한다. 현재 SwiftUI 앱 자체는 웹 서버가 아니므로 포트를 여는 것만으로 브라우저에서 앱을 조작할 수 없다.

Serve를 사용할 수 없을 때의 임시 경로:

```sh
tailscale ip -4
npm run dev -- --hostname <tailscale-ip> --port 3001
```

공유 주소는 `http://<tailscale-ip>:3001/`이다. 이 경로는 HTTPS가 아니고 실행 중인 프로세스에 의존하므로 fixture 외 데이터는 다루지 않으며, 검토 후 서버를 종료한다.

## 4. 내부 TestFlight

외부에서 실제 iPhone 앱을 반복 검토해야 한다면 내부 TestFlight를 기본 네이티브 배포 경로로 사용한다.

선행 조건:

- 유료 Apple Developer Program 가입과 App Store Connect 접근 권한
- App Store Connect 앱 레코드
- 프로덕션 또는 기존 개발 앱과 분리된 안정적인 베타 bundle identifier
- 내부 테스터 그룹과 기기의 TestFlight 앱
- 업로드마다 증가하는 build number

권장 운영:

- 모든 커밋이 아니라 기능 검토 지점이나 하루 마감 빌드를 올린다.
- 베타 앱은 실제 데이터와 분리된 저장소를 사용한다.
- 마이그레이션 인수 테스트는 같은 베타 bundle identifier의 V1을 설치해 대표 데이터를 만든 후 V2로 업데이트한다.
- V2 설치 전에 V1 앱을 삭제하지 않는다.
- 업데이트 후 거래 수와 UUID, 원문, 수정값·판정·메모, 카드 관계를 확인한다.
- 배포가 반복적으로 안정화된 뒤에만 Xcode Cloud 같은 자동 업로드를 고려한다.

프로젝트 기록상 현재 실기기 서명은 Apple 개인 개발 팀으로 수행했다. TestFlight 구성을 시작하기 전에 유료 프로그램 및 App Store Connect 사용 가능 여부를 확인한다.

## 5. Tailscale을 통한 Xcode 기기 연결

이미 페어링된 iPhone의 Tailscale IP를 Xcode Device Hub의 IP 연결 대상으로 사용하는 방법은 보조 실험으로만 취급한다.

- iPhone의 개발자 모드와 Tailscale VPN이 켜져 있어야 한다.
- 기기는 깨어 있고 필요할 때 잠금을 해제할 수 있어야 한다.
- 연결 성공 여부는 네트워크와 iOS 상태에 영향을 받으므로 필수 배포 경로로 의존하지 않는다.
- 실패하면 TestFlight 또는 같은 네트워크에서의 Xcode 실행으로 전환한다.

## 6. 머지 전 인수 기준

변경 범위에 해당하는 항목만 적용한다.

- 관련 자동 테스트가 모두 통과한다.
- UI 결정이 있었다면 승인된 프로토타입 또는 실제 앱 화면과 구현이 일치한다.
- SwiftData 변경은 V1 fixture와 같은 bundle identifier 덮어 설치 경로를 검증한다.
- App Intent, 단축어, 백그라운드·잠금 동작이 인수 조건이면 실제 iPhone에서 확인한다.
- 기존 실기기 데이터를 처음 마이그레이션하기 전에는 사용자 승인을 받는다.
- 결과에는 실행 명령, 환경, 통과·실패 수, 수동 확인 항목과 미검증 항목을 남긴다.

인수 결과 예시:

```text
자동: CherryPickerCore 15/15, 앱 22/22 통과
환경: iOS 27 전용 시뮬레이터, 별도 Derived Data
수동: TestFlight V1 → V2 덮어 설치, 거래 2건과 UUID·수정값 보존 확인
미검증: 잠금 상태 App Intent — 실제 기기 접근 가능 시 확인 예정
```

## 7. 참고 문서

- [Apple: App Store Connect에 빌드 업로드](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Apple: 내부 TestFlight 테스터 추가](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)
- [Apple: 무선 기기에서 앱 실행](https://help.apple.com/xcode/mac/current/en.lproj/dev3e2f4ee6d.html)
- [Tailscale: Serve로 로컬 서버 공개](https://tailscale.com/docs/reference/examples/serve)
