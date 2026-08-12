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
   as a new file under `On My iPhone/Shortcuts/CherryPickerOutbox`. Do not ask
   where to save, do not overwrite an existing file, and do not make a network
   request.

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
