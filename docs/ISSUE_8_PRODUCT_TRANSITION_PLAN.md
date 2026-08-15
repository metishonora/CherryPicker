# 이슈 #8 로컬 웹 제품 전환 계획

- 상태: 운영 인수 완료, 코드 검토·병합 대기
- 기준일: 2026-08-15
- 선행 검증: #7 Tailscale Outbox 스파이크
- 후속 기능: #5 거래 검토 웹 UI, #9 실제 문자 수집, #4 현황 대시보드

## 1. 이 작업을 하는 이유

기존 iOS 앱은 문자 수집 가능성을 확인하기 위한 미완성 프로토타입이었다.
앞으로 사용할 제품 경로는 iPhone 파일 Outbox, Mac 로컬 서버, SQLite,
Tailscale 내부 웹이다.

프로토타입의 SwiftData 구조와 네이티브 앱 빌드 호환성을 새 제품의
제약으로 가져가지 않는다. 먼저 처음부터 끝까지 동작하는 작은 제품을
만들고, 실제 화면과 사용 흐름을 확인한 뒤 세부 정책을 정한다.

## 2. 전체 제품 그림

```text
카드 문자
  → iPhone 단축어가 로컬 Outbox 파일로 먼저 저장
  → 연결 가능할 때 Mac 로컬 서버로 전송
  → Mac SQLite에 원문과 파싱 결과 저장
  → Tailscale 내부 웹에서 조회·검토
  → 사용자 판정으로 카드 현황 계산
```

- iPhone은 Mac이 꺼져 있어도 원문을 Outbox에 보존한다.
- Mac SQLite는 앞으로 수집하는 거래의 기준 저장소다.
- 웹과 API는 localhost에만 바인딩하고 Tailscale Serve를 통해 접근한다.
- 공개 호스팅, 별도 회원가입과 다중 사용자는 만들지 않는다.

## 3. 이슈 #8의 목표

#8은 모든 데이터 모델과 운영 정책을 미리 완성하는 기반 공사가 아니다.
다음 최소 수직 흐름을 실제 제품 경로와 이름으로 실행 가능하게 만드는
작업이다.

1. Mac에서 CherryPicker 서버를 실행한다.
2. 합성 Outbox 이벤트 한 건을 HTTP API로 보낸다.
3. 서버가 원문을 SQLite에 저장하고 가능한 값을 파싱한다.
4. 브라우저에서 저장된 거래와 파싱 상태를 확인한다.
5. 서버를 재시작해도 같은 거래가 남는다.
6. 같은 이벤트를 다시 보내도 거래가 중복 생성되지 않는다.
7. LaunchAgent 설치 후 Mac 로그인으로 서버가 다시 시작된다.
8. 승인된 Tailscale 로그인만 웹과 API를 사용할 수 있다.

이 흐름이 보인 뒤 거래 검토·수정은 #5, 실제 카드 문자 자동화는 #9,
현황 계산은 #4에서 확장한다.

## 4. 먼저 제거할 레거시 범위

계획을 문서와 이슈에 먼저 기록한 뒤 다음 항목을 저장소에서 제거한다.
Git 기록에는 남으므로 필요하면 복원할 수 있다.

- `CherryPickerApp/`의 Xcode 프로젝트, SwiftUI 화면, App Intent
- 네이티브 SwiftData 모델과 저장소
- 네이티브 앱 전용 테스트
- 폐기된 네이티브 구현 계획
- SwiftData와 ModelActor만을 위한 ADR 및 테스트 지침

다음 항목은 유지한다.

- 서버가 재사용하는 `CherryPickerCore` 파서와 날짜·카드 정책
- #7의 검증 코드, 테스트 및 역사적 스파이크 기록
- 승인취소와 사용자 판정 등 제품 도메인 결정

저장소 정리는 사용자의 Mac이나 iPhone에 설치된 앱 또는 기존 SwiftData
파일을 찾아서 읽거나 삭제하는 작업을 포함하지 않는다.

## 5. 구현 순서

### 단계 A: 제품 경계 정리

- 네이티브 앱 소스와 전용 문서를 제거한다.
- 기준 아키텍처, MVP, 테스트 가이드를 로컬 웹 제품 기준으로 바꾼다.
- Swift Package의 Core·Server·실행 파일을 현역 제품 경계로 명시한다.

상태: 완료.

### 단계 B: 최소 제품 실행 경로

- #7의 `spike`, `Issue7` 명칭과 임시 설치 경로를 제품 명칭으로 교체한다.
- 제품용 데이터 경로와 LaunchAgent를 정의한다.
- 합성 이벤트 저장, 조회, 재시작 보존과 eventId 멱등성을 유지한다.
- 기본 웹은 원문, 이름, 잔액과 인증 identity를 노출하지 않는다.

제품 경로는 `~/Library/Application Support/CherryPicker`, LaunchAgent
label은 `dev.cherrypicker.localserver`를 사용한다.

상태: 완료.

### 단계 C: 조합 검증

- Core·Server 자동 테스트를 실행한다.
- 임시 위치의 디스크 SQLite를 닫았다 다시 열어 데이터를 확인한다.
- 설치 도구가 네이티브 앱이나 SwiftData 경로를 참조하지 않는지 검사한다.
- 실제 LaunchAgent 설치와 Tailscale 변경은 별도 승인된 인수 단계에서만 수행한다.

상태: 자동·격리 검증과 실제 LaunchAgent·Tailscale 운영 인수 완료.

## 6. 지금 결정하지 않는 것

다음 항목은 최소 제품을 보고 필요해질 때 결정한다.

- 자동 백업 일정, 보존 세대와 외부 백업
- 완성형 카드·거래 SQLite 스키마
- 거래 검토 화면의 세부 필드와 배치
- 운영 데이터가 생긴 뒤의 장기 스키마 migration 전략
- 모니터링과 알림
- 두 번째 카드와 추가 카드사 파서

기존 SwiftData 자료는 새 SQLite로 이전하지 않는다. 수동 SQLite 파일 복사
외의 백업 기능도 #8의 완료 조건으로 두지 않는다.

## 7. #8 완료 조건

- 네이티브 앱이 빌드·테스트·설계 제약에서 제거된다.
- 제품 이름과 경로를 사용하는 Mac 서버가 localhost에서 실행된다.
- 합성 이벤트의 저장, 파싱, 안전한 웹 조회가 한 흐름으로 동작한다.
- 서버 재시작 후 데이터가 유지된다.
- 응답 유실을 가정한 동일 eventId 재전송에도 canonical 거래가 하나다.
- exact-login 인증, loopback 바인딩과 기본 응답 비노출 테스트가 통과한다.
- 제품 설치·검증 도구와 문서가 남고 #7의 임시 경로를 사용하지 않는다.
- 기존 앱이나 SwiftData 파일을 읽거나 삭제하지 않았음을 변경 범위로 확인한다.

## 8. 후속 결정 시점

- 최소 웹 거래 화면을 본 뒤: 검토·수정 필드와 Card 관계를 #5에서 결정
- 실제 Outbox 흐름을 연결할 때: 운영 자동화와 재시도 조건을 #9에서 결정
- 판정 데이터가 쌓인 뒤: 카드 현황과 집계 표시를 #4에서 결정
- 실제 데이터의 손실 비용이 커진 뒤: 백업과 장기 migration 정책을 별도 이슈로 결정

## 9. 격리 검증 결과 — 2026-08-16

- Core 16개와 Server 23개, 총 39개 자동 테스트가 통과했다.
- release `CherryPickerLocalServer` 빌드가 통과했다.
- 제품 LaunchAgent shell·plist·fixture 검증이 통과했다.
- 임시 HOME 설치에서 제품 binary는 0755, 설정과 LaunchAgent는 0600으로
  생성됐고 `CherryPickerSpike`와 네이티브 앱 경로는 생성되지 않았다.
- 임시 HOME 제거 시험에서 binary·설정·LaunchAgent만 제거되고 SQLite와
  로그는 보존됐다.
- 임시 SQLite와 localhost 포트 18765에서 합성 이벤트를 저장한 뒤 서버를
  재시작해 같은 거래가 남는 것을 확인했다.
- 같은 eventId 재전송은 최초 transactionId를 유지한 `duplicate`였고
  SQLite에는 canonical 거래 1건과 receipt 1건만 남았다.
- identity 없는 거래 조회는 HTTP 401이었고 인증된 기본 웹과 JSON에는
  원문, 카드 끝 네 자리와 identity가 나타나지 않았다.

검증에 사용한 임시 SQLite, 설치 fixture와 로그는 삭제했다. 실제 사용자
LaunchAgent, Tailscale Serve, 기존 앱과 SwiftData는 변경하지 않았다.

## 10. 운영 인수 결과 — 2026-08-16

- 설치 전 제품 데이터·로그·LaunchAgent 경로와 기존 Tailscale Serve 설정이
  비어 있음을 확인했다.
- release 서버를 실제 제품 경로에 설치했고 LaunchAgent
  `dev.cherrypicker.localserver`가 `running` 상태로 시작됐다.
- 제품 디렉터리는 0700, binary는 0755, 설정과 LaunchAgent plist는
  0600으로 설치됐다.
- Tailscale Serve의 HTTPS 443을 `http://127.0.0.1:8765` 한 경로에
  연결했고 Funnel은 사용하지 않았다.
- tailnet HTTPS의 인증된 거래 조회는 HTTP 200, identity 없는 localhost
  직접 조회는 HTTP 401이었다.
- 실제 제품 SQLite에 합성 이벤트를 저장하고 LaunchAgent를 재시작해도
  같은 transactionId가 유지되는 것을 확인했다.
- 같은 eventId 재전송은 같은 transactionId의 `duplicate`였고 receipt와
  canonical 거래는 각각 1건이었다.
- 실제 웹과 JSON에는 원문, 카드 끝 네 자리와 Tailscale identity가
  노출되지 않았다.
- 검증용 합성 receipt와 거래만 정확한 ID로 제거했다. 최종 SQLite의 두
  테이블은 비어 있고 LaunchAgent와 Tailscale Serve는 실행 중이다.

기존 앱, SwiftData와 그 밖의 사용자 데이터는 읽거나 변경하지 않았다.
