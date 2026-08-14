# Issue #7 iPhone Shortcut recipe

Status: real-device setup in progress. This recipe is for synthetic spike data
only and must not be enabled for ordinary messages until all three local
capture states have passed.

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

One real iPhone Message automation created a JSON file at 20:31 in
`On My iPhone/CherryPickerOutbox`. The file had the valid schema version,
`eventId`, `capturedAt`, and `originalMessage` fields. Posting that exact file
through the production HTTP endpoint returned `accepted` with disposition
`stored`; replaying the exact file returned `duplicate` with the same
transaction ID. Authenticated HTML omitted the full original marker while
including the safely parsed merchant field.

The 20:31 capture occurred while the iPhone was unlocked on the Home Screen
with Shortcuts not open. Classify it as passed `unlocked/background with
Shortcuts not visible` evidence. Home Screen is close background evidence, but
it is not the original gate's literal `unlocked with another app active`
state. A second synthetic file, with eventId
`20260814-2120-4146-8654-000000000000` and capturedAt
`2026-08-14T21:20:14+09:00`, was created after message arrival while the
iPhone was locked; the locked-state capture passed. The
unlocked-in-Shortcuts and literal unlocked-in-another-app states remain to be
explicitly verified, so the matrix remains pending and Gate 1 is not
complete.

## Observed tailnet-only Serve delivery — 2026-08-15

The Mac client posted copies of the two user-approved synthetic Outbox JSON
files through the tailnet-only Serve route. The first copy returned
`accepted`/`stored`; its exact replay returned `duplicate` with the same
transaction ID; the locked-state copy returned `accepted`/`stored`.
Authenticated HTML omitted `CHERRYPICKER-SELFTEST` while showing
`Synthetic Merchant` as the parsed merchant.

This was delivery of Mac-side copies, not execution of the iPhone sync
shortcut. The end-to-end retry gate remains pending.

## Observed iCloud sync shortcut preparation — 2026-08-15

The iCloud shortcut `CherryPicker Outbox 동기화` was created and saved on the
Mac. Its configured workflow filters only `.json` files, sorts by name
ascending, POSTs one event at a time, and immediately deletes that exact
source item only when the first result status is `accepted` or `duplicate`.
Rejected, missing-result, and error paths do not delete a file.

The first `Get Folder Contents` folder remains intentionally unresolved:
the Mac cannot bind `On My iPhone/CherryPickerOutbox`. Selecting that folder
on the iPhone and completing one real-device sync/retry run remain pending.
This preparation evidence is not an end-to-end iPhone sync result.

## Outbox sync

Create a second shortcut named `CherryPicker Outbox 동기화`. Configure its
base URL only after the local server health check and the separately approved
Tailscale Serve route are active.

For every `.json` file in the Outbox folder, in a stable order:

1. Read and decode the file as a Dictionary.
2. Wrap it in `{ "events": [event] }` and POST it as JSON to
   `/api/v1/events/batch` over the private Tailscale HTTPS address.
3. Inspect the first result item. Delete that one source file only when status
   is `accepted` or `duplicate`.
4. Preserve the file on transport failure, malformed response, missing result,
   or `rejected`. Do not print or notify with the original message body.

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
