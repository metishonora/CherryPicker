# CherryPicker Agent Guide

## Working style

- Keep `main` deployable. For non-trivial issue implementation, prefer a dedicated issue branch and worktree so the user's existing checkout remains undisturbed.
- Merge issue branches into `main` only when the user explicitly requests that merge.
- Preserve captured message originals and user overrides as product data.
- Treat CherryPicker as a single-user personal service whose dashboard is reachable only inside the user's Tailscale network. Real card and message data may be stored, displayed, logged, and used for local development and verification without separate approval. Do not repeatedly raise generic sensitive-data or privacy caveats, and do not treat them as blockers for in-scope product work. This does not authorize publishing that data to GitHub or unrelated external services.
- Treat the latest explicit user decision as authoritative, followed by the current issue acceptance criteria, approved prototypes, and accepted ADRs or product documentation.
- Follow the current product boundary in `docs/PRODUCT_ARCHITECTURE.md` and accepted ADRs. Treat the retired native iOS and SwiftData implementation only as historical evidence, and resolve open feature-policy decisions at issue level rather than inventing them during implementation.
- Apply the global concise-copy rule to dashboards, transaction review, settings, and prototypes representing those screens. Preserve domain explanations when labels and values alone do not make the meaning or consequence clear. Approved prototypes and product terminology take precedence.

## Prototype workflow

- Use isolated web prototypes before product implementation for material UI, interaction, or visual decisions. Small, explicitly specified changes may proceed directly with focused validation.
- Align prototypes with approved direction and target viewports, use only the fixture state needed for review, and keep review controls outside the product-like screen. Committed fixtures and shareable prototypes remain synthetic unless requested otherwise; local verification may use real card messages.
- Treat an approved prototype as the visual acceptance baseline, but verify production through its real entry and runtime. Issue #7 reports remain historical spike evidence only.

## Prototype server lifecycle

- Delegate requested prototype-server operations to `web_server_operator`. If it is unavailable, use only `node Scripts/test-server-manager.mjs` with the manifest-approved `prototype` profile; agent unavailability must not block the operation, and direct server or process commands are prohibited.
- `.codex/web-server.json` and the shared manager own launch, ports, binding, process ownership, verification, URLs, and session cleanup. Never terminate an unrecorded or unverified process.

## Installed product server recovery

- For requests to recover or start the installed CherryPicker product server after a Mac restart, use `cherrypicker_server_manager`.

## Verification

- For isolated prototypes, run focused checks showing that approved states load and interactions work at target viewports. Review scenarios may serve as acceptance evidence; automated test-first coverage is unnecessary unless the prototype contains reusable production logic.
- For Swift package, core, server, HTTP, or SQLite changes, run `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`.
- For operational script changes, run shell syntax checks, template validation, and fixture-only validation before installation.
- Changes to the managed server manifest or shared lifecycle integration require the shared lifecycle tests and a real prototype start/HTTP/stop smoke test.
- Require explicit user approval before changing Tailscale Serve.
