# CherryPicker Agent Guide

## Working style

- Keep `main` deployable. For non-trivial issue implementation, prefer a dedicated issue branch and worktree so the user's existing checkout remains undisturbed.
- Merge issue branches into `main` only after explicit user acceptance.
- Follow `docs/PRODUCT_ARCHITECTURE.md` and the accepted ADRs. Treat feature-policy decisions left open there as issue-level decisions; do not invent them during implementation.
- Preserve captured message originals and user overrides. Do not expose sensitive originals in default UI, logs, analytics, CloudKit, or external services.
- The native iOS prototype and its SwiftData store are retired. Do not use them as a product constraint or migration source.
- Keep the active product boundary in the Swift package: `CherryPickerCore`, `CherryPickerServer`, and `CherryPickerLocalServer`.

## Product workflow

- Prefer a thin end-to-end local web slice that exposes a real product flow before making detailed schema or UI policy decisions.
- Use synthetic fixtures until an issue explicitly authorizes real card messages.
- Treat the Issue #7 reports as historical spike evidence, not as current product paths or names.

## Verification

- For `CherryPickerCore` changes, run `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`.
- For server, HTTP, SQLite, or package changes, run the full Swift package test suite.
- For operational script changes, run shell syntax checks, template validation, and fixture-only validation before any installation.
- Require explicit user approval before installing or starting a LaunchAgent, changing Tailscale Serve, or using real message data.
- Require actual-device verification only when acceptance depends on iPhone Shortcuts automation, background or locked-device execution, or local Outbox file behavior.

## Completion

- Before declaring code changes complete, run the relevant checks, review the complete diff, and leave the changes ready for user review.
- Do not apply the full completion workflow to questions, planning, research, isolated prototypes, or documentation-only changes unless explicitly requested.
- When closing an issue, add the smallest practical regression coverage for changed behavior. State why when none is added.
