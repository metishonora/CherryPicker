# Issue #7 Tailscale Outbox Spike

- Status: accepted experiment plan
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

The localhost server and tests do not by themselves satisfy Gate 1 or Gate 3.
Tailscale Serve, launchd recovery, and iPhone Shortcuts remain real-device
validation work.

The in-progress real-device capture, sync, retry, and cleanup recipe is in
[`issue-7-iphone-shortcuts.md`](issue-7-iphone-shortcuts.md).

## Go/no-go report

The final report records observed reliability, the privacy boundary, operating
burden, native-data migration implications, unresolved failure modes, and a
recommendation to keep the native app or proceed toward the local web system.
