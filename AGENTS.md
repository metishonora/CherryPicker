# CherryPicker Agent Guide

## Working style

- Keep `main` deployable. For non-trivial issue implementation, prefer a dedicated issue branch and worktree so the user's existing checkout remains undisturbed.
- Merge issue branches into `main` only when the user explicitly requests that merge.
- Preserve captured message originals and user overrides. Do not expose sensitive originals in default UI, logs, analytics, CloudKit, or external services.
- Treat the latest explicit user decision as authoritative, followed by the current issue acceptance criteria, approved prototypes, and accepted ADRs or product documentation.
- Follow `docs/PRODUCT_ARCHITECTURE.md` and the accepted ADRs. Treat feature-policy decisions left open there as issue-level decisions; do not invent them during implementation.
- Keep the active product boundary in the Swift package: Swift 6, Hummingbird 2, SQLite, `CherryPickerCore`, `CherryPickerServer`, and `CherryPickerLocalServer` serving the local web UI and HTTP API.
- Treat the native iOS prototype and SwiftData as retired legacy evidence, not as current product constraints or migration sources. The Swift/Hummingbird local web implementation and its operations documentation are the current product path.

## Prototype workflow

- Use isolated web prototypes to resolve material UI, interaction, or visual decisions before product implementation. Small explicitly specified changes may proceed directly.
- Keep prototypes aligned with approved product direction and target viewports. Use only the fixture state needed for review, and keep review controls outside the product-like screen.
- Use synthetic fixtures until an issue explicitly authorizes real card messages.
- Treat an approved prototype as the visual acceptance baseline for later production work. Prototype approval does not replace verification through the production entry and runtime.
- Treat the Issue #7 reports as historical spike evidence, not as current product paths or names.

## Prototype server lifecycle

- For requested prototype servers, use `web_server_operator` when available; otherwise invoke the shared manager directly with the manifest-approved `prototype` profile. Agent unavailability must not block server operations.
- Use only `node Scripts/test-server-manager.mjs` for prototype-server start, status, keep, release, reconcile, and stop operations. Do not improvise Python HTTP server, detached-process, port-selection, or process-termination commands.
- `.codex/web-server.json` owns the approved launch command, issue-derived port policy, `0.0.0.0` binding, process ownership, logs, HTTP verification, and Tailscale IPv4 URL.
- Never terminate a process not recorded and verified by the shared manager.
- Stop a session-owned prototype server on the next user turn by default. Preserve it only when the user explicitly requests continued operation.

## Installed product server recovery

- For requests to recover or start the installed CherryPicker product server after a Mac restart, use `cherrypicker_server_manager`.

## Verification

- For isolated prototypes, run focused checks sufficient to show that the approved states load and interactions work at the target viewports.
- Prototype review scenarios may serve as acceptance evidence; automated test-first coverage is not required unless the prototype contains reusable production logic.
- For `CherryPickerCore` changes, run `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`.
- For server, HTTP, SQLite, or Swift package changes, run the full Swift package test suite.
- For operational script changes, run shell syntax checks, template validation, and fixture-only validation before installation.
- Changes to the managed server manifest or shared lifecycle integration require the shared lifecycle tests and a real prototype start/HTTP/stop smoke test.
- Require explicit user approval before changing Tailscale Serve or using real message data.

## Completion

- Before declaring code changes complete, run the relevant checks, review the complete diff, and leave the changes ready for user review.
- Do not apply the full completion workflow to questions, planning, research, isolated prototypes, or documentation-only changes unless explicitly requested.
