# CherryPicker 로컬 서버 운영

- 상태: #8 최소 제품 경로
- 대상: macOS 14 이상
- 관련 테스트: [제품 테스트](PRODUCT_TESTING.md)

## 빌드와 사전 검증

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift build --configuration release --product CherryPickerLocalServer

Scripts/LocalServer/validate-launch-agent.sh
```

검증 스크립트는 shell 문법과 plist fixture만 검사한다. LaunchAgent를
설치하거나 실행하지 않고 Tailscale 설정도 변경하지 않는다.

## 제품 경로

| 항목 | 경로 |
|---|---|
| 실행 파일 | `~/Library/Application Support/CherryPicker/bin/CherryPickerLocalServer` |
| SQLite | `~/Library/Application Support/CherryPicker/cherrypicker.sqlite` |
| 로컬 설정 | `~/Library/Application Support/CherryPicker/config/local-server-config.plist` |
| LaunchAgent | `~/Library/LaunchAgents/dev.cherrypicker.localserver.plist` |
| 로그 | `~/Library/Logs/CherryPicker/` |

앱 소스, iPhone 또는 기존 SwiftData 경로는 운영 도구의 대상이 아니다.

## 설치

release binary의 절대 경로를 구하고 허용할 Tailscale 로그인을 환경으로
전달한다.

```sh
BINARY_PATH="$(swift build --show-bin-path --configuration release)/CherryPickerLocalServer"
export CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN='REPLACE_WITH_EXACT_TAILNET_LOGIN'
Scripts/LocalServer/install-launch-agent.sh "$BINARY_PATH"
unset CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN
```

이 명령은 파일만 설치한다. 검토 후 실제로 시작할 때만 `--start`를
사용한다.

```sh
export CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN='REPLACE_WITH_EXACT_TAILNET_LOGIN'
Scripts/LocalServer/install-launch-agent.sh --start "$BINARY_PATH"
unset CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN
```

반복 실행하면 binary와 설정을 같은 제품 경로에 갱신한다. SQLite는
덮어쓰지 않는다.

## 확인

```sh
curl --fail --silent http://127.0.0.1:8765/healthz
```

응답은 `ok`다. 인증이 필요한 웹과 API는 Tailscale Serve가 전달하는
`Tailscale-User-Login`이 정확히 허용된 값과 같아야 한다.

## iPhone 문자 자동화

`CherryPicker Outbox` 단축어는 전달받은 문자 원문을 카드 종류와 무관하게
로컬 Outbox에 저장한다. 실제 수집 대상은 iPhone의 개인용 `메시지` 자동화
발신자 조건에서 제한한다.

- 발신자에 `1599-9000`과 `1800-1111`을 모두 추가한다. 여러 발신자는
  어느 하나와 일치하면 자동화를 실행한다.
- `메시지 포함` 조건은 비워 둔다. 카드 종류 구분은 서버의 발신자 및 본문
  식별 규칙이 담당한다.
- 자동화 동작은 받은 메시지를 입력으로 `CherryPicker Outbox`를 실행한다.
- `즉시 실행`을 사용하고 실행 전 확인은 끈다.

개인용 자동화는 기기별 설정이며 다른 Apple 기기의 단축어 앱으로 동기화되지
않는다. 따라서 이 변경은 실제 수집에 사용하는 iPhone에서 수행하고, 두
발신자의 새 승인 문자 각각이 별도 Outbox 파일로 생성되는지 확인한다.

## Mac 재시작 후 복구

설치된 binary, 설정과 LaunchAgent plist를 검증만 하려면 다음 명령을
실행한다. 서비스 등록이나 시작은 하지 않는다.

```sh
Scripts/LocalServer/recover-launch-agent.sh --check
```

설치 상태를 검증하고 필요한 경우에만 LaunchAgent를 등록·시작한 뒤
localhost health 응답까지 기다리려면 다음 명령을 실행한다.

```sh
Scripts/LocalServer/recover-launch-agent.sh
```

이미 등록된 서버가 정상이라면 재시작하지 않는다. 서버가 등록되지 않았거나
health 응답이 없을 때만 `launchctl bootstrap` 또는 `kickstart`를 수행한다.
이 스크립트는 binary나 설정을 다시 설치하지 않고 SQLite, 로그와 Tailscale
Serve를 변경하지 않는다. 설치 파일이 없거나 서로 일치하지 않으면 변경 없이
실패하므로 위 설치 절차를 별도로 검토해야 한다.

## Tailscale Serve

Serve 변경은 설치 스크립트와 분리한다. 사용자가 경로를 검토하고 승인한
뒤 loopback 서버만 tailnet 내부에 노출한다.

```sh
tailscale serve --bg --https=443 http://127.0.0.1:8765
```

Funnel을 사용하지 않는다. 설치·업데이트·제거 스크립트는 다른 Serve
경로를 변경하거나 전체 설정을 reset하지 않는다.

## 제거

```sh
Scripts/LocalServer/uninstall-launch-agent.sh
```

실행 파일, LaunchAgent와 생성된 설정만 제거한다. SQLite와 로그는 항상
남긴다. 현재 #8은 자동 백업·보존 정책이나 데이터 삭제 명령을 제공하지
않는다.
