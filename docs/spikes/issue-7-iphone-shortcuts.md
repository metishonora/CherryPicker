# Issue #7 iPhone Shortcut recipe

Status: real-device capture, manual sync, and immediate automatic sync
confirmed; broader retry validation remains in progress. This recipe is for
synthetic spike data only and must not be enabled for ordinary messages until
all three local capture states have passed.

## Local Outbox capture

Create a shortcut named `CherryPicker Outbox 저장` that accepts text as
Shortcut Input and performs no network request:

1. Set `capturedDate` to the built-in Current Date value.
2. Format `capturedDate` with the custom format
   `yyyyMMdd-HHmm-4ssS-8SSS-000000000000` and set the result to `eventId`.
   This retains millisecond resolution while producing a UUID-shaped value
   accepted by the server contract.
3. Format the same `capturedDate` as ISO 8601 with time included and set the
   result to `capturedAt`.
4. Set `originalMessage` to Shortcut Input.
5. Build a Dictionary with these exact keys and types:

   - `schemaVersion`: Number `1`
   - `eventId`: Text variable `eventId`
   - `capturedAt`: Text variable `capturedAt`
   - `originalMessage`: Text variable `originalMessage`

6. Convert the Dictionary to JSON text, name it `<eventId>.json`, and save it
   as a new file under `On My iPhone/CherryPickerOutbox`. Create this folder
   directly under `On My iPhone` when a `Shortcuts` folder is not present. Do
   not ask where to save, do not overwrite an existing file, and do not make a
   network request.

The timestamp-derived UUID is an idempotency key, not a secret or a random
security token. The synthetic test sends one message at a time; two captures
in the same millisecond would collide and must be treated as a failed local-
capture test rather than overwriting a file.

## Message automation

Create a personal Message automation that:

- matches message text containing `CHERRYPICKER-SELFTEST`;
- runs immediately without asking;
- passes the received message text to `CherryPicker Outbox 저장`.

Start without a sender filter. First send a uniquely marked synthetic message
from the test iPhone to its own number. If self-send does not produce a
received-message trigger, repeat with a separate test sender; that self-send
limitation does not by itself reject the Outbox approach.

Verify that exactly one independent JSON file appears with the expected four
keys while the iPhone is (1) unlocked in Shortcuts, (2) unlocked in another
app, and (3) locked. The message must contain no real name, balance, account
identifier, or transaction.

## Observed real-device evidence — 2026-08-14

One real iPhone Message automation created a JSON file in
`On My iPhone/CherryPickerOutbox`. The file had the valid schema version,
`eventId`, `capturedAt`, and `originalMessage` fields. Posting that exact file
through the running spike HTTP endpoint returned `accepted` with disposition
`stored`; replaying the exact file returned `duplicate` with the same
transaction ID. Authenticated HTML omitted the full original marker while
including the safely parsed merchant field.

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

## Observed tailnet-only Serve delivery — 2026-08-15

The Mac client posted copies of the two user-approved synthetic Outbox JSON
files through the tailnet-only Serve route. The first copy returned
`accepted`/`stored`; its exact replay returned `duplicate` with the same
transaction ID; the locked-state copy returned `accepted`/`stored`.
Authenticated HTML omitted the original payload while showing only safely
parsed, non-sensitive fields.

This was delivery of Mac-side copies, not execution of the iPhone sync
shortcut. The end-to-end retry gate remains pending.

## Observed real-device iPhone sync and deletion — 2026-08-15

The iCloud shortcut `CherryPicker Outbox 동기화` was bound on the iPhone to
`On My iPhone/CherryPickerOutbox` and run against the private Serve route. For
each source file, it decoded the Dictionary, explicitly extracted
`schemaVersion`, `eventId`, `capturedAt`, and `originalMessage`, and built a
JSON `events` array containing one Dictionary. After the run, the configured
`accepted` or `duplicate` deletion path removed each exact source file and the
Outbox folder became empty. Both events had already been stored and the server
transaction and receipt counts remained unchanged, so this is consistent with
the expected `duplicate` response; the successful response status itself was
not separately recorded.

This confirms manual real-device delivery and selective deletion for an
already-stored event. The temporary response viewer used for this diagnosis
was removed afterward. The shortcut checks the response text for `accepted`
or `duplicate` before entering the deletion condition. This manual observation
alone does not verify unattended recovery or delivery within 24 hours.

## Observed capture-to-sync configuration — 2026-08-15

In the Mac Shortcuts editor, the iCloud capture shortcut `CherryPicker Outbox`
was configured so its final action runs `CherryPicker Outbox 동기화`. That run
action appears only after the local Save File action, preserving the required
local-first ordering.

The configuration was later visible on the iPhone and passed one fresh
automatic capture-to-sync run, as recorded below.

## Observed failed immediate automatic delivery — 2026-08-15

After briefly opening Shortcuts on the iPhone, one fresh synthetic marker
message was sent. Without manually running the sync shortcut, exactly one new
Outbox file remained after 15 seconds. During the same observation, the Mac
server was running and listening, while SQLite remained at 3 canonical
transactions and 3 receipts; no corresponding request reached and committed
on the server.

This is a failed observation of immediate automatic delivery. A subsequent
manual run of the sync shortcut delivered that preserved file; the server
recorded `accepted`/`stored`, SQLite increased to 4 canonical transactions and
4 receipts, and the exact source file was deleted. This passes the fresh
real-device `accepted` deletion path and confirms that the server and manual
sync path were available. It does not identify why the immediate automatic
invocation failed or pass Gate 3.

## Observed immediate automatic delivery — 2026-08-15

After the final Run Shortcut action was confirmed visible on the iPhone, a
second fresh synthetic marker message was sent while the iPhone was unlocked
in Messages. The capture shortcut saved locally first and then invoked the
sync shortcut without a manual run. After 20 seconds the Outbox was empty,
SQLite had increased to 5 canonical transactions and 5 receipts, and the
latest receipt was `accepted`/`stored`.

This passes the immediate fresh-event capture, automatic delivery, and
`accepted` deletion subcase. It also passes the unlocked-in-another-app local
capture state. Wi-Fi and daily retry triggers and the 24-hour target remain
unverified, so Gate 3 remains pending.

## Observed Mac-offline charger recovery and deletion — 2026-08-15

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
preservation and recovery-trigger subcase. Wi-Fi and daily retry, the 24-hour
target, full reboot recovery, and other-user cases remain unverified, so Gate
3 remains pending.

## Outbox sync

Create a second shortcut named `CherryPicker Outbox 동기화`. Configure its
base URL only after the local server health check and the separately approved
Tailscale Serve route are active.

For every `.json` file in the Outbox folder, in a stable order:

1. Read and decode the file as a Dictionary, then explicitly extract
   `schemaVersion`, `eventId`, `capturedAt`, and `originalMessage`.
2. In the JSON request editor, create an `events` Array with one Dictionary
   containing those four values, then POST it to `/api/v1/events/batch` over
   the private Tailscale HTTPS address.
3. For this one-file request, check the response text for `accepted` or
   `duplicate`. Delete that one source file only inside that condition, with
   Delete Files configured to `Delete Immediately`.
4. Preserve the file on transport failure, malformed response, missing result,
   or `rejected`. Do not print or notify with the original message body.

For unattended deletion, enable
`Settings > Apps > Shortcuts > Advanced > Allow Deleting Without Confirmation`
on the test iPhone. This is a device-wide permission that increases the
deletion authority of every Shortcut, not only CherryPicker. Keep Delete Files
configured as `Delete Immediately` strictly inside the `accepted` or
`duplicate` condition, and validate the permission with synthetic data before
depending on a locked automation.

Use small per-file requests for the spike so a partial response cannot delete
an unrelated file. Exact event replay is safe because the server commits its
receipt before returning success.

## Retry automations

Run `CherryPicker Outbox 동기화`:

- immediately after a successful local capture;
- when joining the selected home Wi-Fi;
- when connecting a charger;
- once daily.

The sync shortcut must remain safe when the folder is empty and when the Mac,
Tailscale route, or Internet connection is unavailable. The acceptance target
is delivery within 24 hours after the Mac service becomes reachable, without
manual intervention.

## Cleanup

After the spike, disable the personal automations before removing synthetic
Outbox files. Keep this recipe and the automated server tests, but do not
commit exported Shortcuts containing a private Tailscale address or identity.
