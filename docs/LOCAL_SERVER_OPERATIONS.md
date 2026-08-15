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
