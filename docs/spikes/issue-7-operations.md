# Issue #7 local server operations

This is a disposable macOS 14+ operations path for the Issue #7 spike. It
does not change the native app or its SwiftData store. The launch agent is
intentionally opt-in: installing files does not start a process or configure
Tailscale.

## Build

Build the macOS executable from the repository checkout:

```sh
swift build --configuration release --product CherryPickerLocalServer
BINARY_PATH="$(swift build --show-bin-path --configuration release)/CherryPickerLocalServer"
```

`BINARY_PATH` must be an absolute, executable file path. The install script
also accepts that path through `CHERRYPICKER_LOCAL_SERVER_BINARY`; an explicit
argument and an environment value must agree when both are supplied.

Before touching a user launch-agent directory, run the fixture-only check:

```sh
Scripts/Issue7/validate-launch-agent.sh
```

It runs `bash -n`, lints both templates, and renders replacements into a
temporary directory. It does not write under `$HOME`, call `launchctl`, start
the server, or configure Tailscale.

## Install and start manually

Set the exact Tailscale login accepted by the server in the environment. Do
not pass it as a command-line argument, put it in a committed file, or paste
it into a log. Replace the value below with the account shown by the local
Tailscale installation:

```sh
export CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN='REPLACE_WITH_EXACT_TAILNET_LOGIN'
Scripts/Issue7/install-launch-agent.sh "$BINARY_PATH"
```

The script trims surrounding whitespace and rejects an empty login. It renders
the plist with `/usr/bin/plutil` key-path replacements, validates the result,
and installs the executable plus owner-only generated configuration files at
these explicit paths:

| Artifact | Location |
| --- | --- |
| copied executable | `~/Library/Application Support/CherryPickerSpike/bin/CherryPickerLocalServer` |
| generated config (no login value) | `~/Library/Application Support/CherryPickerSpike/config/launch-agent-config.plist` |
| generated LaunchAgent plist | `~/Library/LaunchAgents/dev.cherrypicker.localserver.spike.plist` |
| SQLite database | `~/Library/Application Support/CherryPickerSpike/events.sqlite` |
| standard output log | `~/Library/Logs/CherryPickerSpike/localserver.stdout.log` |
| standard error log | `~/Library/Logs/CherryPickerSpike/localserver.stderr.log` |

The app-support and log directories are mode `0700`; the executable is mode
`0755`, and the generated plist/config files are mode `0600`.

The generated plist sets `RunAtLoad`, `KeepAlive`, port `8765`, and decimal
`Umask` `63`. Its environment contains the exact login and the fixed local
database path. The copied executable is not launched by the command above.
To explicitly bootstrap and kickstart the agent after reviewing the rendered
plist, invoke the same script with `--start`:

```sh
Scripts/Issue7/install-launch-agent.sh --start "$BINARY_PATH"
```

After all install invocations, clear the shell variable when it is no longer
needed:

```sh
unset CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN
```

Only that explicit `--start` path invokes `launchctl`. A repeated `--start`
boots out the exact existing service before bootstrapping the newly rendered
plist, so an updated login or path takes effect. The service runs after the
user logs in and the executable listens only on `127.0.0.1`.

Check the local listener without sending an authenticated event:

```sh
curl --fail --silent http://127.0.0.1:8765/healthz
```

The expected response is `ok`. A failure here should be resolved before any
Tailscale route is enabled.

### Observed full restart recovery — 2026-08-15

The test Mac was fully restarted and the user logged in without manually
starting the local server or Tailscale. The system booted at 23:03:19 and the
server log recorded listening at 23:04:57, approximately 98 seconds later and
within the two-minute target. The LaunchAgent was running, localhost health
returned `ok`, and the disk-backed SQLite store retained 9 canonical
transactions and 9 receipts. An iPhone on LTE then opened the authenticated
private Tailscale web page and saw `transactions` and `syncResult`, confirming
that the composed Serve route also recovered.

## Tailscale Serve (separate approval)

Tailscale configuration is deliberately outside the scripts. After reviewing
the tailnet ACL, the exact identity allowlist, and the synthetic-only test
scope, a user may expose the loopback service with the locally supported
Tailscale CLI, for example:

```sh
tailscale serve --bg --https=443 http://127.0.0.1:8765
```

This is a separate, user-approved network change. It must target
`127.0.0.1:8765`; do not bind the Swift server to `0.0.0.0`. Confirm plain
Funnel status reports tailnet-only access before testing. Record the resulting
HTTPS address only in private test notes. The install and uninstall scripts
neither enable nor reset Serve. If the route is no longer needed, review it
and remove it separately with the current Tailscale CLI (for example,
`tailscale serve --https=443 off`). Use `tailscale serve reset` only when
clearing every Serve route is explicitly intended.

## Privacy and logs

The server's default reports and logs omit original messages, request bodies,
card suffixes, balances, parser failure details, and identity values. The
LaunchAgent plist necessarily contains the configured allowlist value so the
process can authorize requests; it is installed with owner-only permissions.
Do not upload the plist, SQLite file, or logs to an issue or external service.
Use synthetic messages without names, balances, or other personal data.

## Uninstall and cleanup

Uninstall boots out the exact per-user service when it is loaded, then removes
the copied executable, generated plist, and generated config. It is safe to
repeat. By default it preserves the SQLite database and logs:

```sh
Scripts/Issue7/uninstall-launch-agent.sh
```

Only for disposable synthetic data, after confirming the service is stopped,
request permanent removal of the SQLite file and its `-wal`/`-shm` sidecars:

```sh
Scripts/Issue7/uninstall-launch-agent.sh --delete-synthetic-data
```

That flag reports that the database deletion is irreversible. It does not
remove the native app's store and does not change a Tailscale Serve route.
Review and clean up the separate Tailscale route and any preserved logs using
the current, explicitly chosen paths.

## Validation commands

From the repository root, the operational asset checks are:

```sh
/bin/bash -n Scripts/Issue7/install-launch-agent.sh
/bin/bash -n Scripts/Issue7/uninstall-launch-agent.sh
/bin/bash -n Scripts/Issue7/validate-launch-agent.sh
Scripts/Issue7/validate-launch-agent.sh
/usr/bin/plutil -lint Scripts/Issue7/dev.cherrypicker.localserver.spike.plist.template
/usr/bin/plutil -lint Scripts/Issue7/launch-agent-config.plist.template
git diff --check
```

These checks do not install a service, launch a process, configure Tailscale,
or touch runtime data.
