# ADR-0003: 모든 쓰기를 ModelActor 저장소 경계로 통합한다

- 상태: 승인됨
- 날짜: 2026-08-05

## 맥락

현재 App Intent는 ModelActor 저장소를 사용하지만 거래 상세 UI는 메인 ModelContext의 영속 모델을 직접 변경한다. 두 경로가 검증과 불변조건을 다르게 적용할 수 있고, App Intent는 앱과 다른 실행 환경에서 호출될 수 있다.

## 결정

SwiftData를 애플리케이션 포트의 구현 어댑터로 제한한다.

- 모든 생성·수정·삭제·연결은 `@ModelActor` 명령 저장소를 통과한다.
- 영속 모델은 ModelActor 또는 ModelContext 밖으로 전달하지 않고 Sendable Snapshot으로 변환한다.
- SwiftUI는 draft를 Command로 제출하며 영속 모델을 직접 변경하지 않는다.
- App Intent와 SwiftUI는 동일한 Use Case를 호출한다.
- Composition Root가 VersionedSchema, SchemaMigrationPlan, 명시적 저장 URL을 만든다.
- 앱과 Intent가 같은 ModelContainer 인스턴스를 공유한다고 가정하지 않고, 각 실행 환경이 동일한 저장 설정을 사용하게 한다.
- UI는 명령 완료와 scene 활성화 시 조회를 갱신한다.

## 결과

- 입력 경로와 관계없이 같은 검증과 불변조건이 적용된다.
- actor 격리와 저장소 생명주기를 한 곳에서 시험할 수 있다.
- SwiftUI의 직접 `@Query` 편집보다 코드가 늘고 명시적인 새로 고침이 필요하다.
- 두 container가 같은 저장소를 사용하는 통합 테스트가 필요하다.

## 고려한 대안

- UI는 ModelContext, Intent만 ModelActor 사용: 구현은 짧지만 쓰기 규칙이 분산돼 제외했다.
- 전역 ModelContainer 인스턴스만 공유: 별도 실행 환경을 포괄하지 못해 제외했다.
- 모든 코드를 MainActor에서 실행: 백그라운드 Intent와 저장 작업 격리에 맞지 않아 제외했다.
