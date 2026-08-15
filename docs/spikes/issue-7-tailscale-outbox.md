# Issue #7 Tailscale Outbox Spike

- Status: spike implementation with partial real-device validation
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
iPhone was locked; the locked-state capture passed. The
Later synthetic captures sent while the iPhone was unlocked in Messages
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
leaving the response parsing and deletion condition in place. This passes
manual real-device delivery and selective deletion for already-stored events,
but does not complete Gate 3.
Scheduled unattended execution, Mac-offline automatic retry, partial success,
response-loss recovery, external-network VPN On Demand, identity allowlisting,
full post-login restart recovery, and the 24-hour target remain unverified.
Gate 1 also remains incomplete as noted above.

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
sync path were available. The immediate invocation failure is still
unexplained, and Gate 3 remains pending.

### Observed immediate automatic delivery — 2026-08-15

After the final Run Shortcut action was confirmed visible on the iPhone, a
second fresh synthetic marker message was sent while the iPhone was unlocked
in Messages. The capture shortcut saved locally first and then invoked the
sync shortcut without a manual run. After 20 seconds the Outbox was empty,
SQLite had increased to 5 canonical transactions and 5 receipts, and the
latest receipt was `accepted`/`stored`.

This passes the immediate fresh-event capture, automatic delivery, and
`accepted` deletion subcase. It also passes the unlocked-in-another-app local
capture state. Separate Wi-Fi, charger, and daily retry triggers, offline
recovery, and the 24-hour target remain unverified, so Gate 3 remains pending.

The in-progress real-device capture, sync, retry, and cleanup recipe is in
[`issue-7-iphone-shortcuts.md`](issue-7-iphone-shortcuts.md).

## Go/no-go report

The final report records observed reliability, the privacy boundary, operating
burden, native-data migration implications, unresolved failure modes, and a
recommendation to keep the native app or proceed toward the local web system.
