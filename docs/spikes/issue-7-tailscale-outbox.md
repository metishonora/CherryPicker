# Issue #7 Tailscale Outbox Spike

- Status: go for file-Outbox follow-up; native cutover remains a no-go
- Issue: https://github.com/metishonora/CherryPicker/issues/7
- Scope: disposable local-first reliability spike; not a production migration

## Goal

Determine whether an iPhone personal automation can durably capture a synthetic
card message into a local per-event Outbox file before attempting the network,
then reliably deliver it through Tailscale HTTPS to a Mac-local Swift server and
SQLite store without loss or duplicate transactions.

The spike precedes issues #4 and #5. It does not delete, migrate, or disable the
existing native app or its SwiftData store.

## Accepted decisions

- Keep source, automated tests, setup instructions, Shortcut recipes, and the
  final report in the repository. Remove only synthetic runtime data and
  installed temporary services when the spike is complete.
- Retry immediately, when joining the selected home Wi-Fi, when connecting a
  charger, and at least once daily. The eventual-delivery target is 24 hours
  after the Mac service becomes reachable without manual input.
- Mac restart recovery may occur after the user logs in. The target is for the
  server and Tailscale Serve route to be available within two minutes.
- First test the Message automation by sending a uniquely marked synthetic
  message from the iPhone to its own number. If iOS does not treat that as a
  received-message trigger, repeat with a separate test sender. Self-send
  failure alone does not reject the Outbox architecture.
- The validation web page reports server-side receipt, deduplication, and parse
  results. Reporting the current number of files remaining on the iPhone is out
  of scope.
- Use Swift for the Mac server so it can reuse `CherryPickerCore`. Use the
  system SQLite library for the temporary database.

## Event contract

Each Outbox file contains one JSON object:

```json
{
  "schemaVersion": 1,
  "eventId": "00000000-0000-0000-0000-000000000000",
  "capturedAt": "2026-08-11T12:34:56+09:00",
  "originalMessage": "synthetic fixture only"
}
```

- `eventId` is generated once on the iPhone and is also the file name.
- `capturedAt` is the iPhone capture time and is immutable.
- The server receipt time must not replace `capturedAt` in date inference or
  the ten-minute transaction duplicate rule.
- Files are deleted only after an item result of `accepted` or `duplicate`.
  Transport failure and `rejected` preserve the file.

The batch response distinguishes transport idempotency from transaction
deduplication:

- A previously committed `eventId` returns `duplicate`.
- A new `eventId` with the same normalized message within ten minutes returns
  `accepted` with disposition `transactionDuplicate` and references the
  existing transaction.
- A durably stored message that cannot be parsed returns `accepted` with
  disposition `parseFailed`.
- An invalid envelope returns `rejected` with a non-sensitive reason code.

The SQLite model therefore keeps event receipts separate from canonical
transactions. Logs must not contain original messages, request bodies, or
identity values.

## Validation gates

Current evidence status:

- Gate 1 is substantially covered by repeated locked and other-app captures.
  The literal `Shortcuts visible` state was not separately repeated; the final
  recommendation treats this as a low-risk waiver because the more restrictive
  background and locked states passed.
- Gate 2 passed through the automated server and HTTP suite, including mixed
  results, exact replay, response-loss retry, parse failure, identity rejection,
  redaction, and disk reopen behavior.
- Gate 3 passed immediate delivery, one Mac-offline locked/LTE charger
  recovery-and-delete path, and full post-login recovery with an authenticated
  LTE browser check. Home-Wi-Fi and daily retries are configured; the first
  scheduled daily fire was not separately observed.

### Gate 1: local capture

With networking absent from the capture Shortcut, verify that one independent
JSON file is created while the iPhone is:

1. unlocked with Shortcuts visible;
2. unlocked with another app active;
3. locked.

Repeat each state enough times to detect confirmation prompts or intermittent
failures. Use synthetic messages without names or balances.

### Gate 2: deterministic server behavior

Automated tests must cover, before real-device synchronization:

- accepted event and stored parse result;
- exact `eventId` replay;
- different `eventId` with the same fingerprint inside ten minutes;
- the same fingerprint outside ten minutes;
- parse failure accepted with original preserved in SQLite;
- mixed accepted, duplicate, and rejected batch results;
- retry after a committed write whose response was lost;
- authorization rejection without logging message contents.

### Gate 3: end-to-end recovery

Verify immediate delivery, Mac offline capture, automatic retry, partial batch
success, response loss, Tailscale VPN On Demand from an external network,
identity allowlisting, and post-login Mac restart recovery.

## Implemented Mac spike component

The branch contains a macOS 14+ executable named `CherryPickerLocalServer`.
It binds only to `127.0.0.1` and defaults to port `8765`.

Required runtime configuration:

- `CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN`: exact login accepted from the
  `Tailscale-User-Login` header. Startup fails closed when it is missing.
- `CHERRYPICKER_DB_PATH`: optional absolute SQLite path. The default is
  `~/Library/Application Support/CherryPickerSpike/events.sqlite`.
- `CHERRYPICKER_PORT`: optional local port. The default is `8765`.

The executable sets an owner-only process umask before creating SQLite files.
The HTTP application provides:

- `GET /healthz`: public, non-sensitive local health response;
- `POST /api/v1/events/batch`: authenticated batch ingestion;
- `GET /api/v1/transactions`: authenticated redacted transaction JSON;
- `GET /`: authenticated minimal HTML with parse and sync-receipt results.

The report JSON and HTML deliberately omit original messages, card suffixes,
account balances, parser failure reasons, request bodies, and identity values.
The server has no CORS middleware and installs no request-body logger.

Automated verification uses disk-backed SQLite and in-process HTTP tests:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/cherrypicker-clang-cache \
swift test --disable-sandbox
```

### Observed localhost installation gate — 2026-08-12

The release executable was installed for the current user with the Issue #7
LaunchAgent while Tailscale Serve remained disabled. The following synthetic-
only checks passed on the test Mac:

- the agent was running and `GET http://127.0.0.1:8765/healthz` returned `ok`;
- an incorrect identity returned HTTP `401` without a write;
- one synthetic event returned `accepted` with disposition `stored`;
- after a forced agent restart, health returned within the one-second
  measurement resolution;
- replaying the committed event returned `duplicate` and the canonical
  transaction count remained one;
- the install directory was mode `0700`, generated configuration and SQLite
  files (including WAL/SHM) were mode `0600`, and the executable was `0755`;
- stdout/stderr contained neither the synthetic message sentinel nor the
  configured login; and
- `tailscale serve status --json` remained empty, so no tailnet or public
  route was enabled by this gate.

This validates the localhost service and post-launch restart behavior, not the
two-minute recovery target across a full Mac logout/reboot and subsequent user
login. It also leaves one disposable synthetic transaction in the spike
database for the later end-to-end replay test.

### Observed real-device capture and delivery — 2026-08-14

One real iPhone automation-created JSON file had valid schema,
`eventId`, `capturedAt`, and `originalMessage` fields. Posting that exact file
through the running spike HTTP endpoint returned `accepted`/`stored`; replaying
the exact file returned `duplicate` with the same transaction ID.
Authenticated HTML omitted the full original marker while safely including
the parsed merchant.

The first capture occurred while the iPhone was unlocked on the Home Screen
with Shortcuts not open. Classify it as passed `unlocked/background with
Shortcuts not visible` evidence. Home Screen is close background evidence, but
it is not the original gate's literal `unlocked with another app active`
state. A second synthetic file was created after message arrival while the
iPhone was locked; the locked-state capture passed. Later synthetic captures
sent while the iPhone was unlocked in Messages
passed the literal unlocked-in-another-app state. The unlocked-in-Shortcuts
state remains to be explicitly verified, so the matrix remains pending and
Gate 1 is not complete.

### Observed tailnet-only Serve delivery — 2026-08-15

Tailscale Serve was enabled as a background tailnet-only HTTPS route on port
443 to `http://127.0.0.1:8765` with `--bg`. Plain Funnel status explicitly
reported tailnet-only access. `/healthz` returned `ok`, and an authenticated
request to `/` returned HTTP `200` through Serve.

From a Mac client, copies of the two user-approved synthetic iPhone Outbox
JSON files were posted through that Serve route. The first copy returned
`accepted`/`stored`; its exact replay returned `duplicate` with the same
transaction ID; the locked-state copy returned `accepted`/`stored`. Installed
SQLite totals increased from 1 canonical transaction and 1 receipt to 3 of
each. Authenticated HTML omitted the original payload while showing only
safely parsed, non-sensitive fields.

This was Mac-client delivery of copies, not the iPhone sync shortcut or the
end-to-end retry gate. It does not close the remaining Gate 1 state matrix or
Gate 3.

### Observed real-device iPhone sync and deletion — 2026-08-15

The iCloud shortcut `CherryPicker Outbox 동기화` was bound on the iPhone to
`On My iPhone/CherryPickerOutbox` and run against the private Serve route. It
filtered `.json` files, sorted by name, decoded each source Dictionary,
explicitly extracted `schemaVersion`, `eventId`, `capturedAt`, and
`originalMessage`, and sent a JSON `events` array containing one Dictionary.
After the run, the configured `accepted` or `duplicate` deletion path removed
each exact source file and the Outbox folder became empty. Both events had
already been stored and the server transaction and receipt counts remained
unchanged, so this is consistent with the expected `duplicate` response; the
successful response status itself was not separately recorded.

The temporary response viewer used for this diagnosis was removed afterward,
and the shortcut checks the response text for `accepted` or `duplicate` before
entering the deletion condition. This passes manual real-device delivery and
selective deletion for already-stored events, but does not complete Gate 3.
Later observations cover immediate unattended delivery, one locked/LTE
charger recovery subcase, and post-login restart recovery. Partial success,
response-loss recovery, and other-user rejection are covered by the automated
and configuration evidence described in the final report. Gate 1 retains the
explicit low-risk waiver noted above.

### Observed capture-to-sync configuration — 2026-08-15

In the Mac Shortcuts editor, the iCloud capture shortcut `CherryPicker Outbox`
was configured so its final action runs `CherryPicker Outbox 동기화`. The run
action is ordered after the local Save File action, retaining local capture as
the first durable step.

The configuration was later visible on the iPhone and passed one fresh
automatic capture-to-sync run, as recorded below.

### Observed failed immediate automatic delivery — 2026-08-15

After briefly opening Shortcuts on the iPhone, one fresh synthetic marker
message was sent. Without manually running the sync shortcut, exactly one new
Outbox file remained after 15 seconds. At that time, the Mac server was running
and listening, while SQLite remained at 3 canonical transactions and 3
receipts; no corresponding request reached and committed on the server.

This is a failed observation of immediate automatic delivery. A subsequent
manual run of the sync shortcut delivered that preserved file; the server
recorded `accepted`/`stored`, SQLite increased to 4 canonical transactions and
4 receipts, and the exact source file was deleted. This passes the fresh
real-device `accepted` deletion path and confirms that the server and manual
sync path were available. The first immediate invocation failure was not
explained, but it did not recur after the final Run Shortcut action propagated
to the iPhone.

### Observed immediate automatic delivery — 2026-08-15

After the final Run Shortcut action was confirmed visible on the iPhone, a
second fresh synthetic marker message was sent while the iPhone was unlocked
in Messages. The capture shortcut saved locally first and then invoked the
sync shortcut without a manual run. After 20 seconds the Outbox was empty,
SQLite had increased to 5 canonical transactions and 5 receipts, and the
latest receipt was `accepted`/`stored`.

This passes the immediate fresh-event capture, automatic delivery, and
`accepted` deletion subcase. It also passes the unlocked-in-another-app local
capture state. Later observations cover Mac-offline charger recovery, and the
home-Wi-Fi and daily retry automations were subsequently configured.

### Observed Mac-offline charger recovery and deletion — 2026-08-15

In an earlier manual run, the shortcut reached its successful-response
condition, but the default Delete Files behavior could not move the local
Outbox JSON file to Recently Deleted. The file was preserved and the shortcut
displayed an error. Enabling `Delete Immediately` in the action details and
manually rerunning then removed that file.

The Mac test server was intentionally stopped before a locked iPhone received
a synthetic message. One Outbox JSON file was preserved locally. After the
server restarted, `/healthz` returned `ok` and SQLite held 6 canonical
transactions and 6 receipts before recovery began.

While the iPhone was locked and showed LTE rather than Wi-Fi, its charger
automation sent the preserved event without a manual run. SQLite increased to
7 canonical transactions and 7 receipts. The request reached the successful
response condition, but iOS displayed a deletion confirmation, so the source
file remained in the Outbox.

The user then enabled
`설정 > 앱 > 단축어 > 고급 > 확인 없이 삭제 허용`. A retry completed without
a deletion alert and left the Outbox empty. One additional fresh real-device
test also completed without an alert, left the Outbox empty, and brought
SQLite to a final 9 canonical transactions and 9 receipts while server health
remained `ok`.

Immediate deletion is not recoverable, so the action must remain strictly
inside the `accepted` or `duplicate` condition. This passes the locked/LTE
charger unattended delivery-and-delete subcase and the Mac-offline local
preservation and recovery-trigger subcase. The selected home-Wi-Fi and daily
retry automations were subsequently configured. The first scheduled daily fire
was not separately observed.

### Observed full restart and external LTE web recovery — 2026-08-15

The Mac was fully restarted and the user logged in without manually starting
the local server or Tailscale. The system booted at 23:03:19 and the server log
recorded listening at 23:04:57, approximately 98 seconds later and within the
two-minute target. The LaunchAgent was running, `127.0.0.1:8765` was listening,
localhost health returned `ok`, and SQLite retained 9 canonical transactions
and 9 receipts.

With Wi-Fi disabled, the iPhone opened the same private Tailscale root address
in Safari over LTE. The authenticated page displayed `transactions` and
`syncResult`. This passes the composed post-login LaunchAgent, persistent
tailnet-only Serve, Tailscale VPN/external-network, authenticated web, and
existing-DB recovery path.

The in-progress real-device capture, sync, retry, and cleanup recipe is in
[`issue-7-iphone-shortcuts.md`](issue-7-iphone-shortcuts.md).

## Go/no-go report

### Recommendation

**GO** for follow-up development of the file-Outbox and Mac-local web
architecture. **Do not retire the native app or migrate existing SwiftData
yet.** The core loss-prevention and idempotency model worked with synthetic
data, including locked-device Mac-offline recovery over LTE and full post-login
recovery. Remaining items are cleanup and explicitly recorded low-risk waivers,
not known data-integrity defects.

### Reliability observed

- Local capture completed before networking and preserved one independent JSON
  file while the Mac service was unavailable.
- Immediate automatic delivery passed with a fresh event. A charger automation
  later retried a preserved event while the iPhone was locked on LTE, without a
  manual Shortcut run.
- The Mac stored the recovered event before deletion. After the required iOS
  deletion permission was enabled, the Outbox became empty without a prompt;
  an additional fresh run repeated that result.
- Exact event replay returned `duplicate` without another canonical
  transaction. Per-file requests prevent one result from deleting an unrelated
  source file.
- The automated suite covers mixed accepted/duplicate/rejected results,
  response loss after commit, transaction deduplication, parse failure with
  original preservation, exact identity authorization, and redacted HTTP
  output. The final 2026-08-15 run passed all 35 tests.

### Privacy boundary

- Synthetic originals remained in the iPhone-local Outbox until the Mac
  acknowledged durable storage, then in the Mac-local SQLite store. They were
  not placed in iCloud Drive, GitHub, public hosting, logs, or default web
  output.
- The server binds only to loopback. Tailscale Serve provides tailnet-only
  HTTPS, Funnel is not used, and the application requires the exact configured
  Tailscale login.
- `Delete Immediately` is intentionally confined to the `accepted` or
  `duplicate` branch. It is not recoverable. The iOS
  `Allow Deleting Without Confirmation` setting is device-wide, so enabling it
  increases the deletion authority of every Shortcut on that iPhone and is an
  ongoing operational risk.

### Operating burden and unresolved risks

- The Mac must be powered, logged in, connected to Tailscale, and reachable
  often enough to meet the delivery target. Full restart followed by login
  recovered the service in approximately 98 seconds, but this remains an
  operating dependency rather than an availability guarantee.
- The locked/LTE charger retry passed, and the selected home-Wi-Fi and daily
  automations are configured. The first scheduled daily fire was not separately
  observed; the immediate and charger paths provide the actual unattended-run
  evidence.
- The global unattended-delete permission, iOS automation behavior after OS
  updates, and Tailscale VPN On Demand remain dependencies that need periodic
  smoke tests.
- A real second tailnet identity was not exercised. Tailnet-only exposure,
  loopback binding, deployed wrong-identity rejection, and exact-login tests
  provide sufficient spike evidence, with integrated other-user testing left
  as residual risk.
- Mac SQLite backup, restore, retention, and monitoring are not defined. The
  spike database is not yet an operational system of record.

### Native-data implications

This spike intentionally did not read, alter, export, or delete the existing
SwiftData store. Keep the native app and its data unchanged. If the conditional
go is accepted, define export/import, reconciliation, backup, and rollback in a
separate migration issue before any cutover.

### Remaining closure checks

1. Accept the low-risk Gate 1 waiver recorded above or perform one literal
   capture with Shortcuts visible. The more restrictive background and locked
   states already passed repeatedly.
2. Optionally observe one locked scheduled-daily fire; immediate and charger
   triggers already prove unattended execution, so this is not a data-integrity
   blocker.
3. After the decision, disable the synthetic automations and remove synthetic
   runtime data and installed temporary services using the documented cleanup
   procedure. Keep the source, tests, scripts, and report.
