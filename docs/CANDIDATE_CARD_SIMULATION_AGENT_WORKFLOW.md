# 후보 카드 시뮬레이션 에이전트 작업 절차

- 상태: Issue #13 제품 계약
- 기준일: 2026-08-20
- 요청 예시: [`examples/candidate-card-simulation-put-request.json`](examples/candidate-card-simulation-put-request.json)

이 문서는 사용자가 후보 카드 자료와 분석 월을 에이전트에게 전달한 뒤,
CherryPicker의 `카드 시뮬레이션` 화면에서 거래를 선택할 수 있는 초안을 만드는
반복 절차다. 자연어 자료는 에이전트가 해석하고, 금액 계산은 제품의 결정론
계산기가 수행한다.

## 사용자가 전달할 것

- 카드 이름과 카드사
- 공식 상품 설명서, 약관 링크·파일 또는 혜택 조건 전문
- 분석 월 `YYYY-MM`
- 신규 발급 유예처럼 적용 여부를 이미 아는 선택 조건

공식 자료만으로 반올림, 실적 구간, 월 한도, 중복 적용 또는 승인일 기준을
확정할 수 없고 결과가 달라진다면 에이전트가 먼저 질문한다. 조건을 추측해
업로드하지 않는다.

## 에이전트 절차

### 1. 분석 월의 거래 템플릿 받기

인증된 CherryPicker 제품 origin에서 다음 요청을 보낸다.

```http
GET /api/v1/candidate-simulations/template?month=YYYY-MM
```

응답에는 해당 월의 canonical 승인 거래 중 `id`, `occurredAt`, `amount`,
`merchant`만 포함된다. 문자 원문, 현재 보유 카드, 기존 거래 검토와 혜택
판정은 포함되지 않는다. `excluded`는 취소와 그 밖의 제외 건수를 알려준다.

### 2. 카드 정책 구조화하기

정책은 다음을 명시적으로 표현한다.

- 출처와 적용 기준일, 구조화 시각, 새로운 `snapshotID`
- 연회비와 전월 실적 구간
- 실적 가정별 한도 그룹 금액
- 혜택률, 금액 조건, 횟수, 반올림, 한도 그룹과 중복 우선순위
- 실적 제외, 공통 혜택 제외와 혜택별 제외

비율은 basis point로 기록한다. 예를 들어 5%는 `500`, 10%는 `1000`이다.
원 단위 내림은 `{"unit":1,"direction":"floor"}`로 쓴다. 같은 정책을
수정했다면 기존 ID를 재사용하지 말고 새 `snapshotID`를 만든다.

현재 V1 계산기가 정확히 표현하지 못하는 약관 조건이 있으면
`unsupportedPolicyConditions`에 기록하고 업로드를 멈춘 뒤 사용자에게
확인한다. 이 배열이 비어 있지 않은 요청은 제품이 거부한다.

### 3. 모든 승인 거래 분류하기

템플릿의 각 거래 ID마다 분류를 정확히 하나 만든다.

- `performance`: 후보 카드의 실적 `included` 또는 `excluded`
- `benefitIDs`: 적용 가능한 구조화 혜택 ID
- `performanceReason`, `benefitReason`: 화면에서 확인할 짧은 근거

거래 사실만으로 결제 경로나 정기결제 여부를 알 수 없으면 하나의 결론으로
단정하지 않는다. `question`과 둘 이상의 `alternatives`를 만들고 각 선택지에
서로 다른 `id`, 사용자용 `answerLabel`과 가능한 판정을 넣는다. 답변 전에도
제품은 모든 대안을 계산해 최소–최대 범위를 표시한다.

### 4. 현재 초안 교체하기

[`합성 요청 예시`](examples/candidate-card-simulation-put-request.json)와 같은
본문을 다음 경로에 보낸다.

```http
PUT /api/v1/candidate-simulations/current
Content-Type: application/json
X-CherryPicker-CSRF: same-origin
```

`classifications`에는 방금 받은 템플릿의 거래가 중복이나 누락 없이 모두
있어야 한다. 서버는 요청이 보낸 금액·날짜를 신뢰하지 않고 canonical 거래를
다시 읽어 결합한다. 그 사이 월 거래가 바뀌어 ID 집합이 달라졌다면 템플릿을
다시 받아 분류한다.

성공하면 이전의 현재 초안 대신 새 초안이 활성화된다. 선택 거래와 답변은
모두 비어 있고, 사용자는 제품 화면에서 다음을 진행한다.

1. 카드 조건 확인
2. 애매한 거래 답변 또는 미응답 범위 확인
3. 거래 선택과 전월 실적 가정 변경

체크·답변·실적 가정 변경은 다음 경로로 저장되고, 응답의 `calculation`이
항상 전체 입력을 다시 계산한 최신 결과다.

```http
PATCH /api/v1/candidate-simulations/current
X-CherryPicker-CSRF: same-origin
```

PATCH 본문은 화면이 마지막으로 받은 `simulation.id`를 `draftId`로,
`simulation.state` 전체를 `expectedState`로 보내고 그 밖에 바꿀 필드만
추가한다. 새 PUT이나 다른 PATCH가 먼저 반영돼 ID 또는 상태가 달라졌으면 서버는
이전 요청을 거부한다. 이때 현재 초안을 다시 받은 뒤 사용자의 변경을 다시
적용한다.

미응답 혜택 분류가 매우 많아 정확한 한도 조합의 안전 한도를 넘으면 결과를
근사하지 않는다. 결과를 바꾸는 질문에 먼저 답해 대안을 줄인 뒤 다시 계산한다.
실적 포함 여부의 범위는 혜택 한도 조합과 분리해 정확히 계산한다.

## 완료 확인

- `GET /api/v1/candidate-simulations/current`가 방금 만든 카드와 월을 반환한다.
- 제품의 `카드 시뮬레이션`이 `카드 조건 → 확인할 거래 → 거래 선택` 순서로
  열린다.
- 거래를 체크하면 선택액, 예상 혜택과 피킹률이 같은 응답에서 갱신된다.
- 답하지 않은 질문은 단일 0원이 아니라 최소–최대 범위로 표시된다.
- 기존 거래 검토와 보유 카드 대시보드는 전후가 동일하다.

정책 스냅샷, 거래 사실·분류와 사용자 상태를 저장하며 계산 결과는 저장하지
않는다. 제품을 다시 열면 저장된 입력으로 같은 계산기 버전이 결과를
재생성한다.
