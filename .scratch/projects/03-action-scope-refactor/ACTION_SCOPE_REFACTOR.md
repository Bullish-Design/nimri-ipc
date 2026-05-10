# ACTION_SCOPE_REFACTOR.md

## Purpose
This document defines the remaining work required to bring `nimri-ipc` action support to full protocol scope (targeting the complete Niri action surface, ~120 variants as referenced in the implementation guide).

It is a refactor and completion plan focused on:
- exhaustive action model coverage,
- exact wire-format compatibility,
- deterministic serialization,
- comprehensive tests that prevent coverage regressions.

## Current Gap Summary
The current implementation provides:
- core unit actions,
- representative parameterized actions,
- basic action-to-request wrapping,
- passing tests for implemented subset.

What remains:
- full action variant enumeration is incomplete,
- constructor surface is incomplete,
- wire-name mapping is incomplete,
- parameterized payload shapes are incomplete,
- exhaustive tests and completeness guards are missing.

## Constraints
- `actions.nim` must remain pure (no transport/I/O imports).
- `actions.nim` should depend only on `codec.nim`, `models.nim`, stdlib JSON/options.
- `requests.nim` should wrap actions one-way (`requests -> actions`), no reverse coupling.
- JSON encoding must match Rust serde externally-tagged enum format exactly.

## Refactor Goals
1. Complete `NiriActionKind` to full protocol scope.
2. Add exported constructor proc for every action variant.
3. Expand/validate compile-time wire-name mapping for every variant.
4. Implement exact `toJson` branch coverage for all parameterized actions.
5. Add missing action parameter helper types in `models.nim` as needed.
6. Build exhaustive tests with a completeness guard that fails when variants are unmapped/unhandled.
7. Verify request nesting for all action families.

## Step-by-Step Work Plan

### Step A: Protocol Inventory Freeze
Create a canonical action inventory source-of-truth file in scratch:
- `.scratch/projects/02-initial-implementation/template/action_inventory.md`

For each action include:
- `ActionName` (wire name),
- Category (focus/move/layout/workspace/window/process/system/etc.),
- Unit or parameterized,
- Payload schema,
- Optional/nullable fields,
- Related model types.

Output requirement:
- A complete checkbox table that can be marked as implemented/tested.

### Step B: Action Type Surface Expansion
Update `src/nimri_ipc/actions.nim`:
- Expand `NiriActionKind` to include all inventory actions.
- Keep declaration grouped by category for readability and maintenance.

Design requirement:
- One variant per wire action.
- Avoid overloaded semantics in one variant.

### Step C: Constructor Coverage
For every `NiriActionKind` variant, add one exported constructor proc.

Constructor policy:
- Unit actions: zero-arg constructor.
- Parameterized actions: strongly-typed params with sensible defaults only when protocol semantics are explicit.
- Optional IDs should default to `none(...)` only where protocol supports null target behavior.

Acceptance check:
- Every variant has a constructor.
- Constructor naming is idiomatic and stable.

### Step D: Wire Name Mapping Completion
Expand `ActionWireNames` (or equivalent) to full variant cardinality.

Hard rule:
- Mapping strings must exactly match protocol wire names (PascalCase, exact spelling).

Safety check:
- Add compile-time/static assertion (or test) ensuring mapping cardinality equals enum cardinality.

### Step E: Payload Encoding Completion
Complete `toJson*(a: NiriAction)` for all variants.

Encoding requirements:
- Unit variant -> JSON string.
- Parameterized variant -> single-key object `{ "ActionName": payload }`.
- Nested parameter unions must use externally-tagged format where required.
- Nullable fields must encode as explicit `null` when required by protocol.

Refactor recommendation:
- Use small private payload helper procs per action family to reduce giant-case complexity.
- Keep one centralized switch for action dispatch to avoid duplicate wire logic.

### Step F: Model Additions for Missing Action Payload Types
If uncovered actions need additional typed parameters:
- add types to `models.nim`,
- add `toJson`/`fromJson` where needed for testability,
- include unknown/fallback behavior when protocol evolution requires it.

Examples of likely additions:
- new reference/addressing tagged unions,
- additional display/layout enum types,
- extended move/resize adjustment structs,
- per-output or per-workspace command payload objects.

### Step G: Exhaustive Action Tests
Expand `tests/test_actions.nim` to cover full action surface.

Test structure:
1. Unit action encoding tests (all unit actions).
2. Parameterized action encoding tests (all payload families).
3. Action constructor sanity tests.
4. Completeness guard tests.

Completeness guard expectations:
- Fail if any enum value has no wire mapping.
- Fail if any mapped variant lacks constructor coverage in test registry.
- Fail if any parameterized variant is missing a payload encoding expectation.

### Step H: Request Integration Coverage
Expand `tests/test_requests.nim` action-nesting section:
- add representative wrapping assertions for every payload family,
- ensure `requestAction(x).toJson` produces exact nested shape.

### Step I: Drift Detection and Maintenance Hooks
Add a maintenance note in scratch documenting update workflow when Niri adds actions.

Recommended file:
- `.scratch/projects/02-initial-implementation/template/action_maintenance.md`

Include:
- where to update inventory,
- how to extend enum/mapping/constructors,
- which tests must be updated,
- final verification command sequence.

## Test Matrix (Required)

### Encoding Matrix
For each action row in inventory, track:
- constructor implemented,
- wire mapping present,
- JSON expectation test present,
- request nesting test present.

All rows must be green before declaring complete.

### Negative / Robustness Tests
Add tests for:
- invalid or unsupported parameter values where applicable,
- explicit null handling behavior,
- serialization stability (no extra keys, no wrong key casing),
- action-to-wire name typo protection.

## Verification Commands
Run in devenv:

```bash
devenv shell -- env NIMBLE_DIR=/tmp/nimble nim c -r tests/test_actions.nim
devenv shell -- env NIMBLE_DIR=/tmp/nimble nim c -r tests/test_requests.nim
devenv shell -- env NIMBLE_DIR=/tmp/nimble nimble test
devenv shell -- env NIMBLE_DIR=/tmp/nimble nim c --hints:off src/nimri_ipc/nimri_ipc.nim
```

## Definition of Done
Action scope refactor is complete when all are true:
1. Inventory file lists full protocol action set.
2. `NiriActionKind` includes every listed action.
3. Every action has constructor proc coverage.
4. `ActionWireNames` is exhaustive and exact.
5. `toJson` supports all variants with exact payload shape.
6. `test_actions` includes exhaustive coverage + completeness guards.
7. `test_requests` covers action request nesting by family.
8. Full suite passes.
9. No forbidden coupling introduced.

## Suggested Commit Chunking
Because this change is large, split commits for reviewability:
1. Inventory + planning docs only.
2. Enum + mapping expansion.
3. Constructors expansion.
4. Encoding payload completion.
5. Model additions.
6. Exhaustive tests + completeness guard.
7. Request integration test expansions.
8. Final cleanup/docs updates.

## Risks and Mitigations
- Risk: Silent wire-name typo causes runtime protocol rejection.
  - Mitigation: table-driven exact string tests for every variant.
- Risk: Missing new variant when protocol evolves.
  - Mitigation: inventory-driven completeness guard test.
- Risk: Huge switch becomes hard to maintain.
  - Mitigation: family-level helper encoders + strict test matrix.
- Risk: Constructor API drift / breaking changes.
  - Mitigation: constructor catalog and stability notes in maintenance doc.

## Implementation Notes for Next Pass
- Prefer deterministic table-driven tests over ad hoc spot checks.
- Keep serialization logic centralized and minimal.
- Do not introduce decode paths in `actions.nim` unless required for tests; encode correctness is primary.
- Maintain existing public constructor names; add missing ones consistently.
