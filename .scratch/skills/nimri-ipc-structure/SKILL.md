# Skill: nimri-ipc Structure Navigation

## Purpose
Quickly place changes in the correct `nimri-ipc` library layer and trace dependency boundaries between public API, transport, typed models, requests/actions, and events.

## Use This Skill When
- A task is ambiguous about where code belongs.
- You need to map repo architecture before implementation.
- You need to add/adjust module boundaries without creating coupling.

## Mental Model
- Public API: `src/nimri_ipc.nim`
- Transport: `src/client.nim`
- Domain models: `src/models.nim`
- Request builders: `src/requests.nim`
- Action constructors/helpers: `src/actions.nim`
- Event parsing/types: `src/events.nim`
- Fixtures/tests: `tests/**`

## Workflow
1. Start at the public API.
- Identify which symbols are exported.
- Confirm whether the task is API-facing or internal.

2. Place the change.
- Socket/session behavior -> `client`.
- JSON schema/type mapping -> `models` / `events`.
- Command payload construction -> `requests` / `actions`.
- Cross-module integration surface -> `nimri_ipc`.

3. Enforce separation.
- Keep raw JSON parsing at boundaries.
- Avoid injecting orchestration logic into IPC modules.

4. Confirm references.
- Use `rg` to find all call sites before changing exported types.

## Handy Commands
- `rg --files src tests`
- `rg "proc\s+|type\s+|export|\*" src -n`
- `rg "Niri|Event|Request|Action|Result" src tests -n`

## Done Criteria
- Change is in the correct module.
- Public/internal boundaries remain clean.
- No duplicated protocol ownership introduced.
