# NIRIP Integration Analysis

How the nirip (niri-profile) concept relates to sidebard, and whether/how they should integrate.

---

## Executive summary

Nirip and sidebard are **complementary layers** that share infrastructure but solve different problems:

| | sidebard | nirip |
|---|---|---|
| **Core problem** | "What commands are available right now?" | "Get my workspace layout into this shape" |
| **Runtime model** | Long-running daemon, event-reduced | CLI-first, run-and-exit (with optional daemon) |
| **Primary output** | Reactive state + keymap + push notifications | Compositor actions (spawn, move, resize) |
| **Time horizon** | Continuous (reacts to every focus change) | Episodic (load a profile, freeze a snapshot) |
| **Language** | Nim | Python |
| **Niri relationship** | Consumes events, issues occasional actions | Issues many actions in orchestrated sequences |

They overlap in exactly one place: **Niri IPC consumption and window/workspace state tracking**. Everywhere else they diverge.

The strongest integration is **nirip as a sidebard effect target** — sidebard knows *when* to act (context changed, command invoked), nirip knows *how* to orchestrate complex multi-step workspace layouts. Sidebard should not absorb nirip's reconciler logic, and nirip should not absorb sidebard's reactive state loop.

---

## Shared infrastructure

### Niri IPC client

Both need:
- Connect to `$NIRI_SOCKET`
- Send JSON requests (Windows, Workspaces, FocusedWindow, Action)
- Subscribe to EventStream
- Parse window/workspace metadata

**Current sidebard design:** Nim async adapter in `adapters/niri.nim`, thin typed wrapper over the socket.

**Nirip design:** Python async client with typed Pydantic models.

**Integration options:**

1. **Separate clients, no sharing.** Each project maintains its own Niri IPC layer. Simple, no coupling. The protocols are stable enough that this isn't much duplicated effort.

2. **Sidebard exposes enriched state over RPC; nirip consumes it.** Instead of nirip connecting directly to Niri for window/workspace state, it could query sidebard's `state` RPC method which already maintains a live, enriched view (with ownership, profiles, etc). Nirip still connects to Niri directly for *actions* but reads state from sidebard.

3. **Shared Niri client library in Nim, with Python bindings.** Over-engineered. Don't do this.

**Recommendation:** Option 2 for state queries, direct Niri connection for actions. This avoids sidebard becoming a bottleneck for nirip's orchestration sequences while still giving nirip richer context (which sidebar owns which window, what profile is active).

### Window tracking

Both maintain a table of windows with metadata. But they care about different aspects:

| Concern | sidebard | nirip |
|---|---|---|
| Window existence | Yes (event-driven) | Yes (snapshot or event-driven) |
| Focus tracking | Primary (drives profiles) | Secondary (for focus-sensitive actions) |
| Sidebar ownership | Primary | Irrelevant |
| Layout position (column/tile) | Not tracked currently | Primary (for freeze/load) |
| App matching by regex | Not needed (uses appId for plugin match) | Primary (score-based matcher) |
| Process lineage | Not tracked | Useful for launch correlation |

**Key insight:** Sidebard tracks *semantic identity* (which sidebar, which profile). Nirip tracks *spatial identity* (which column, which position, which workspace). These are orthogonal views of the same windows.

---

## Where nirip enriches sidebard

### 1. Project-aware profile resolution

Currently, sidebard resolves profiles based on:
- Focused window's appId → plugin match
- Active sidebar instance → default plugin

Nirip introduces a stronger concept: **named project profiles** that describe entire workspace layouts. If sidebard knew which nirip profile is "active" (i.e., the user loaded `backend-dev` and is working in those workspaces), profile resolution could factor that in:

```
Focus in workspace "backend:code" + nirip profile "backend-dev" active
  → sidebard profile = "code/backend" (workspace-scoped commands)
```

This is exactly the reserved `workspaceMatch` field in the refined concept. Nirip profiles give it teeth — instead of hand-configuring workspace matchers per sidebard plugin, sidebard could read nirip profile metadata to know which workspaces belong to which project.

### 2. Richer workspace context

The refined sidebard concept reserves `OutputId` and `workspaceMatch` but doesn't wire them. Nirip's workspace model is much richer:
- Workspaces have names, outputs, column structure
- Windows have spatial positions
- Projects span multiple workspaces

If sidebard can query "which nirip profile owns workspace X?", it gets project context for free without maintaining its own workspace taxonomy.

### 3. Launch orchestration as a command action

Sidebard commands currently resolve to `ActionSpec` (shell, niri action, kanata key, internal RPC). A natural extension:

```toml
[[commands]]
id = "project.load_backend"
title = "Load backend layout"
sequence = ["Leader", "P", "B"]
action = { nirip = "load", profile = "backend-dev" }
```

This makes nirip's `load` a first-class sidebard action target. The user presses a key chord → sidebard invokes nirip → nirip orchestrates the workspace layout.

### 4. Freeze as a command

Similarly:

```toml
[[commands]]
id = "project.freeze"
title = "Freeze current layout"
sequence = ["Leader", "P", "F"]
action = { shell = "nirip freeze --all > ~/.config/niri-profiles/frozen-$(date +%s).yaml" }
```

Or with a dedicated action type if nirip exposes an RPC interface.

---

## Where sidebard enriches nirip

### 1. Sidebar-aware window matching

Nirip's matcher uses app_id, title, PID, workspace membership, and plugin fingerprints. Sidebard adds another signal: **sidebar ownership**.

If nirip queries sidebard for ownership data, it can:
- Skip sidebar-owned windows when matching workspace layout windows
- Know which windows are "managed" by the sidebar system and shouldn't be moved
- Avoid moving sidebar windows during reconciliation

### 2. Profile-driven sizing

Nirip needs to set column widths during load. Sidebard's active profile already declares `PanelSize` per state. If a sidebar is on the right edge, nirip should account for its width when calculating main content column proportions.

Example: profile says sidebar is 34% active. Nirip should size the main editor column at 66% of remaining space, not 66% of total output width.

### 3. State subscription for reactive nirip

Nirip's Phase 3 mentions a "daemon/watch mode." If nirip becomes long-running, it could subscribe to sidebard's push notifications to react to profile changes:

- Profile changes → nirip adjusts column widths
- Sidebar state changes (collapsed→active) → nirip re-proportions layout
- Active instance changes → nirip re-evaluates which project is "current"

---

## Integration architecture options

### Option A: Loose coupling via CLI/shell

```
sidebard command → shell exec "nirip load backend-dev"
nirip load → direct Niri IPC (ignores sidebard)
```

**Pros:** Zero coupling. Both tools work independently. Integration is just shell commands in TOML config.

**Cons:** Nirip doesn't know about sidebars. No sidebar-aware sizing. No shared state.

**Verdict:** Good enough for v1 of both projects.

### Option B: Nirip as sidebard RPC client

```
sidebard command → effect: efExecuteAction(nirip load)
nirip queries sidebard RPC for enriched state
nirip orchestrates Niri actions directly
nirip reports completion back to sidebard (optional)
```

**Pros:** Nirip gets sidebar ownership and profile context. Sidebard stays reactive and pure. Clean request/response boundary.

**Cons:** Nirip depends on sidebard being running. Adds a startup dependency.

**Verdict:** Good for v2 when both are stable.

### Option C: Nirip as sidebard adapter

```
sidebard adapter layer → nirip client library (Python subprocess or socket)
sidebard reduces nirip events (profile loaded, profile closed)
sidebard emits effects targeting nirip (load profile, freeze)
```

**Pros:** Deepest integration. Sidebard's reducer can react to project load/unload. Full reactive loop.

**Cons:** Cross-language boundary (Nim daemon → Python library). Complexity. Tight coupling.

**Verdict:** Only if nirip exposes a JSON-RPC daemon interface. Premature for now.

### Option D: Shared daemon with nirip as a sidebard "engine"

Absorb nirip's reconciler into sidebard as a Nim module.

**Pros:** Single daemon. Single language. Unified state.

**Cons:** Massive scope expansion. sidebard's design philosophy is "state daemon, not action orchestrator." Nirip's reconciler is inherently complex (multi-step, retry, replanning). Mixing it into the pure reducer would violate invariant #1.

**Verdict:** No. This contradicts both designs.

---

## Recommended integration path

### Phase 1 (now): Document the boundary, no code coupling

- Sidebard and nirip are separate projects
- Integration is shell commands: sidebard commands invoke `nirip load/freeze` via `akShellCmd`
- Both connect to Niri independently
- Document in sidebard config that nirip-style actions are a supported pattern

### Phase 2 (after both have stable v1): Nirip queries sidebard

- Nirip's Python client optionally queries `sidebard state` for enriched context
- Nirip uses sidebar ownership to avoid moving sidebar windows
- Nirip uses active profile sizing to calculate proportions
- Sidebard adds `akNiripAction` to ActionSpec if warranted

### Phase 3 (if nirip grows a daemon): Bidirectional subscription

- Nirip daemon subscribes to sidebard push notifications (profile changes)
- Sidebard subscribes to nirip notifications (project loaded/unloaded)
- Sidebard reducer gains `evProjectLoaded` / `evProjectUnloaded` events
- Profile resolution can factor in active nirip project

---

## What changes in the sidebard concept now

Very little needs to change in the refined sidebard concept to accommodate future nirip integration:

1. **Already done:** `workspaceMatch` reserved in `Profile` type — nirip can inform this.
2. **Already done:** `ActionSpec` variant model — adding `akNiripAction` later is trivial.
3. **Already done:** Push subscription API — nirip can consume it.
4. **Consider adding:** A note in the "excluded" section that workspace orchestration (multi-step spawn/arrange/resize sequences) is nirip's domain, not sidebard's.

The concept is already nirip-integration-ready without modification.

---

## What changes in the nirip concept

If nirip is built with sidebard awareness in mind:

1. **Matching:** Add an optional "query sidebard for sidebar-owned windows" step during matching. Sidebar-owned windows get a negative match signal for workspace layout purposes.

2. **Sizing:** During column width calculation, optionally query sidebard for active sidebar size on the relevant output edge. Deduct sidebar width from available space.

3. **State source:** Allow an optional `--state-source sidebard` flag that queries sidebard's window table instead of hitting Niri directly for state. This gives nirip the enriched view (ownership, profile context) without its own event stream.

4. **Project identity:** Define a stable "project name" concept that sidebard can reference. This is already present (`name` field in profile). Sidebard's `workspaceMatch` can match against nirip project workspace names.

5. **Notification:** If nirip grows a daemon mode, expose a simple notification when profiles are loaded/unloaded. Sidebard can subscribe.

---

## Language boundary consideration

Sidebard is Nim. Nirip is Python.

Cross-language integration options:
- **Shell exec:** Simple, no shared memory, startup cost per invocation. Fine for infrequent actions (load a project profile).
- **Unix socket RPC:** If nirip grows a daemon, JSON-RPC over Unix socket. Same protocol sidebard already uses. Language-agnostic.
- **Subprocess with stdin/stdout JSON:** Nirip CLI with `--json` output. Sidebard can parse results.

The language difference is **not a problem** because:
- The integration boundary is IPC (sockets, CLI), not shared libraries
- Both tools are small enough that the overhead of separate processes is negligible
- The hot path (sidebard's event loop, reducer, push notifications) never touches nirip
- Nirip's hot path (reconciler's action-wait-replan loop) never touches sidebard

---

## Risks of integration

### Over-coupling
If sidebard's profile resolution *depends* on nirip being loaded, the system becomes fragile. Sidebard must always work without nirip. Nirip enrichment should be additive context, never required.

### State conflicts
Both track windows. If sidebard says "window 42 belongs to right sidebar" and nirip says "window 42 should be in workspace backend:code column 1", who wins?

**Resolution:** Sidebar ownership is authoritative for sidebar windows. Nirip should never move sidebar-owned windows. If the user wants to un-sidebar a window and move it to a layout column, they must explicitly release it from the sidebar first.

### Orchestration timing
Nirip's load takes time (spawn, wait, arrange). During that time, sidebard's event loop is processing niri events (windows opening, focus changing). Sidebard will fire profile resolution, keymap rebuilds, and push notifications as nirip works. This is fine — sidebard's reducer is designed to handle events at any time. But UI consumers subscribed to sidebard may see rapid state churn during a nirip load.

**Mitigation:** Sidebard could add an optional "batch mode" flag (set via RPC: `rpc("batch.begin")` / `rpc("batch.end")`) that suppresses `efNotifySubscribers` effects until the batch ends. Nirip (or its sidebard wrapper) signals batch boundaries. Not needed for v1.

### Niri socket contention
Both connect to the same Niri socket. Niri handles this fine (multiple clients supported). But if both issue actions simultaneously, Niri processes them sequentially and the compositor state between nirip's planned actions may be disturbed by sidebard's actions (e.g., sidebar resize changing column widths mid-reconciliation).

**Mitigation:** Sidebard should not issue `efNiriAction` effects during an active nirip reconciliation. This naturally falls out of the "batch mode" concept above, or from nirip's own internal locking.

---

## Comparison of scope boundaries

```
┌───────────────────��─────────────────────────────────────────┐
│                     Desktop runtime                          │
│                                                             │
│  ┌─────────────────┐     ┌─────────────────────────────┐   │
│  │     nirip        │     │         sidebard             │   │
│  │                 │     │                             │   │
│  │  workspace      │     │  sidebar state              │   │
│  │  orchestration  │     │  profile resolution         │   │
│  │                 │     │  keymap engine              │   │
│  │  load profiles  │     │  kanata bridge             │   │
│  │  freeze state   │     │  command dispatch          │   │
│  │  match windows  │     │  push subscriptions        │   │
│  │  arrange layout │     │                             │   │
│  │  column sizing  │     │                             │   │
│  └────────┬────────┘     └──────────────┬──────────────┘   │
│           │                             │                   │
│           │         ┌───────────┐       │                   │
│           └────────►│  Niri IPC │◄──────┘                   │
│                     └───────────┘                           │
│                                                             │
│  Integration surface:                                       │
│  • sidebard commands invoke nirip (shell/RPC)               │
│  • nirip queries sidebard for ownership context             │
│  • sidebard push notifies nirip of profile changes          │
│  • nirip notifies sidebard of project load/unload           │
└─────────────────────────────────────────────────────────────┘
```

---

## Conclusion

Nirip is a strong complement to sidebard. They solve adjacent problems with minimal overlap. The integration is natural:

- **sidebard answers:** "What is the shell state right now? What commands can I run? What layer should kanata be in?"
- **nirip answers:** "How do I get from here to this workspace layout? What changed since I froze?"

The cleanest relationship is: **sidebard is the always-on reactive brain; nirip is the on-demand workspace sculptor.** Sidebard can trigger nirip (via commands), and nirip can read sidebard (via RPC queries). Neither subsumes the other.

Build both. Keep them separate. Let the integration emerge from their public interfaces.
