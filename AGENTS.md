# CherryPicker Agent Guide

## Working style

- Keep `main` deployable. For non-trivial issue implementation, prefer a dedicated issue branch and worktree so the user's existing checkout remains undisturbed.
- Merge issue branches into `main` only after explicit user acceptance.
- Follow `docs/ARCHITECTURE.md` and the accepted ADRs. Treat feature-policy decisions left open there as issue-level decisions; do not invent them during implementation.
- Preserve captured message originals and user overrides. Do not expose sensitive originals in default UI, logs, analytics, CloudKit, or external services.
- For SwiftData schema changes, use `VersionedSchema` and `SchemaMigrationPlan`. Never delete or replace the existing store as a migration fallback.

## Prototype workflow

- Use an isolated SwiftUI prototype or preview when a native UI decision needs review. Use only the fixture state needed for that decision.
- Prototype approval validates UI and interaction decisions only. Production acceptance must use the real app and runtime.
- Skip full regression testing for isolated prototypes. Run focused checks when production code, project configuration, persistence, or shared components change.

## Verification

- For `CherryPickerCore` changes, run `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`.
- For relevant app, persistence, or UI changes, run `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project CherryPickerApp/CherryPicker.xcodeproj -scheme CherryPicker -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- If the named simulator is unavailable, use an available simulator for the project's supported iOS version and report the substitution.
- A branch or worktree does not isolate simulator or device app data. Use a dedicated simulator for branch testing, and use a distinct Derived Data path when concurrent worktree builds could overlap.
- For SwiftData migration changes, test both a fresh store and a disk-backed V1 fixture upgraded to the current schema. Verify transaction count and IDs, originals, user overrides and decisions, and expected relationship backfills.
- Exercise the upgrade path on a dedicated simulator by installing the V1 app, creating representative data, and installing the new build over it with the same bundle identifier without uninstalling first. Do not use the user's only device store as the first migration test.
- Require actual-device verification only when acceptance depends on App Intent, Shortcuts automation, background or locked-device execution, signing, or migration of existing device data. Obtain explicit user approval before migrating existing device data.

## Completion

- Before declaring code changes complete, run the relevant checks, review the complete diff, and leave the changes ready for user review.
- Do not apply the full completion workflow to questions, planning, research, isolated prototypes, or documentation-only changes unless explicitly requested.
- When closing an issue, add the smallest practical regression coverage for changed behavior. State why when none is added.
