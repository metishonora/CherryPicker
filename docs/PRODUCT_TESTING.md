# CherryPicker 로컬 웹 제품 테스트

- 상태: 현재 기준
- 관련 문서: [제품 아키텍처](PRODUCT_ARCHITECTURE.md), [제품 MVP](PRODUCT_MVP.md)

## 자동 테스트

Core, Server, SQLite와 HTTP 변경의 기본 검증:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
```

테스트는 변경된 제품 흐름의 관찰 가능한 결과를 확인한다. 최소 제품에서는
다음을 우선한다.

- 합성 이벤트 저장과 파싱 실패 원문 보존
- 동일 eventId 재전송 멱등성
- 10분 거래 중복 규칙
- 디스크 SQLite 재오픈 후 데이터 보존
- exact-login 거절
- 기본 웹·JSON·오류의 민감정보 비노출

## 운영 도구

설치 도구를 실행하기 전에 shell 문법, plist와 임시 fixture 렌더링을
검증한다. 검증 명령은 사용자의 LaunchAgent, Tailscale 설정이나 운영
데이터를 변경하지 않아야 한다.

실제 LaunchAgent 설치·시작, Tailscale Serve 변경과 제거는 사용자가 승인한
별도 인수 단계에서만 수행한다.

## 수동 인수

#8의 최소 수동 흐름:

1. 임시 SQLite 위치로 서버를 시작한다.
2. 개인정보가 없는 합성 이벤트 한 건을 보낸다.
3. localhost 웹에서 안전한 요약을 확인한다.
4. 서버를 종료하고 같은 DB로 다시 시작한다.
5. 거래가 남아 있고 동일 이벤트 재전송이 중복을 만들지 않는지 확인한다.

실제 iPhone, 카드 문자, 잠금 상태와 Outbox 삭제 권한 검증은 #9에서만
수행한다.

## 완료 보고

- 실행한 명령과 통과·실패 결과
- 수동으로 확인한 제품 흐름
- 실행하지 않은 실기기 또는 운영 변경
- 민감정보를 사용하지 않았다는 경계
