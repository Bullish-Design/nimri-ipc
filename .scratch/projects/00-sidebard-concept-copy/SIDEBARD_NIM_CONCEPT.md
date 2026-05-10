# SIDEBARD — Nim Library Concept

## What this replaces

This supersedes the Python-based `SIDEBARD_CONCEPT.md` and `SIDEBARD_SCHEMA.md` with a Nim-only design. The architecture, profile model, and keyboard engine ideas carry forward. The language, packaging, config format, and IPC approach change.

---

## Design summary

A Nim library (`libsidebard`) that provides:

1. **Native niri IPC** — direct socket connection to niri for window tracking and commands
2. **Kanata IPC** — TCP connection for layer switching and event subscription
3. **TOML configuration** with hierarchical override (global → plugin → instance)
4. **Profile-driven state machine** — one active profile drives size, keybinds, overlay, and Kanata layer
5. **Keyboard engine** — command trie with prefix tracking and next-key resolution

Two binaries share the library:

- **`sidebarctl`** — CLI tool, works standalone or delegates to the daemon
- **`sidebard`** — long-running daemon, owns state aggregation and IPC

---

## Why Nim-only

- `sidebarctl` is already 350 lines of working Nim
- Nim compiles to a static binary — no runtime dependencies in the session
- Nim's async/await is sufficient for the event loop, socket I/O, and TCP
- One language for the entire subsystem means one build, one packaging path, one debug workflow
- TOML parsing is available via `parsetoml` or similar Nim packages

---

## Library architecture

```
src/
├── libsidebard/
│   ├── types.nim              # core types: WindowId, SidebarState, ProfileId, etc.
│   ├── config.nim             # TOML loading + hierarchical merge
│   ├── niri.nim               # native niri IPC: socket connect, window ops, event stream
│   ├── kanata.nim             # kanata TCP: layer switch, fake keys, event subscription
│   ├── ownership.nim          # single-owner semantics (extracted from sidebarctl)
│   ├── profile.nim            # profile resolution from focus + ownership + plugin match
│   ├── keymap.nim             # command trie, prefix state, next-key resolution
│   ├── state.nim              # aggregated shell state (the "single source of truth")
│   ├── events.nim             # internal event types and bus
│   └── ipc.nim                # unix socket JSON-RPC server/client
├── sidebarctl.nim             # CLI frontend (evolved from current sidebarctl)
└── sidebard.nim               # daemon frontend
```

### Module responsibilities

#### `types.nim`
Shared value types used across all modules. No logic, no I/O.

```nim
type
  WindowId* = distinct int64

  SidebarState* = enum
    ssCollapsed, ssInactive, ssActive, ssFocused, ssHidden

  SizeMode* = enum
    smPx, smRatio

  PanelSize* = object
    mode*: SizeMode
    width*: float          # ratio 0..1 or px value
    height*: float
    minWidth*: int
    maxWidth*: int
    visiblePx*: int        # edge sliver when collapsed

  SidebarInstance* = object
    id*: string            # "left", "right", "bottom"
    position*: string      # "left", "right", "bottom"
    state*: SidebarState
    windowIds*: seq[WindowId]
    focusedWindowId*: Option[WindowId]
    hidden*: bool

  PluginId* = distinct string
  ProfileId* = distinct string
  CommandId* = distinct string
```

#### `niri.nim` — native niri IPC

Direct connection to niri's Unix socket (`$NIRI_SOCKET` or `$XDG_RUNTIME_DIR/niri/...`).

Capabilities:

- **Query:** list windows, get focused window, get workspaces
- **Command:** focus window, resize column, close window, move window to workspace
- **Subscribe:** window opened/closed/focused events (niri event stream)

This is the generic "talk to niri" layer. It knows nothing about sidebars.

```nim
type
  NiriConn* = ref object
    socket: AsyncSocket
    # ...

  NiriWindow* = object
    id*: WindowId
    appId*: string
    title*: string
    workspaceId*: int
    isFloating*: bool
    isFocused*: bool

  NiriEvent* = object
    case kind*: NiriEventKind
    of nekWindowOpened, nekWindowClosed, nekWindowFocused:
      windowId*: WindowId
    of nekWorkspaceChanged:
      workspaceId*: int
    # ...

proc connect*(path: string = ""): Future[NiriConn]
proc listWindows*(c: NiriConn): Future[seq[NiriWindow]]
proc getFocusedWindow*(c: NiriConn): Future[Option[NiriWindow]]
proc focusWindow*(c: NiriConn, id: WindowId): Future[void]
proc resizeColumn*(c: NiriConn, widthChange: string): Future[void]
proc moveWindowToWorkspace*(c: NiriConn, id: WindowId, ws: int): Future[void]
proc subscribe*(c: NiriConn): Future[AsyncIter[NiriEvent]]
```

#### `kanata.nim` — Kanata TCP bridge

TCP connection to Kanata's server port.

```nim
type
  KanataConn* = ref object
    socket: AsyncSocket
    currentLayer*: string
    connected*: bool

  KanataEvent* = object
    case kind*: KanataEventKind
    of kekLayerChanged:
      oldLayer*, newLayer*: string
    of kekReloaded:
      success*: bool
    of kekMessage:
      message*: string

proc connect*(host: string = "127.0.0.1", port: int = 6666): Future[KanataConn]
proc changeLayer*(c: KanataConn, layer: string): Future[void]
proc getCurrentLayer*(c: KanataConn): Future[string]
proc actOnFakeKey*(c: KanataConn, key: string): Future[void]
proc subscribe*(c: KanataConn): Future[AsyncIter[KanataEvent]]
```

#### `config.nim` — TOML config with hierarchical merge

Loads and merges configuration from the three-level hierarchy.

```nim
type
  SidebardConfig* = object
    daemon*: DaemonConfig
    plugins*: seq[PluginConfig]
    instances*: seq[InstanceConfig]

  DaemonConfig* = object
    socketPath*: string
    kanataHost*: string
    kanataPort*: int
    pollIntervalMs*: int
    overlayTimeoutMs*: int

  PluginConfig* = object
    id*: string
    title*: string
    priority*: int
    matchAppIds*: seq[string]     # regex patterns
    matchTitles*: seq[string]     # regex patterns
    profiles*: seq[ProfileConfig]
    commands*: seq[CommandConfig]

  ProfileConfig* = object
    id*: string
    title*: string
    kanataLayer*: string
    collapsed*: PanelSize
    inactive*: PanelSize
    active*: PanelSize
    focused*: Option[PanelSize]   # falls back to active if unset

  CommandConfig* = object
    id*: string
    title*: string
    description*: string
    category*: string
    tags*: seq[string]
    sequence*: seq[string]        # e.g. ["Leader", "R"]
    whenStates*: set[SidebarState]
    action*: string               # shell command or RPC method
    dangerous*: bool

  InstanceConfig* = object
    id*: string                   # "left", "right", "bottom"
    defaultPlugin*: string
    overrides*: Table[string, ProfileConfig]  # plugin_id -> overridden profile
```

##### Merge rules

Resolution order: `config.toml` → `plugins/*.toml` → `instances/*.toml`

- Scalars: last writer wins
- Sequences: replace (not append)
- Tables/objects: recursive merge

Instance overrides are keyed by plugin ID, so `instances/right.toml` can say:

```toml
[overrides.chat.active]
width = 0.38  # wider than the plugin default
```

#### `ownership.nim` — single-owner window tracking

Extracted from the current `sidebarctl.nim` logic. This is the part that reads `state.json` files, resolves which instance owns a window, and enforces single-owner semantics.

```nim
proc findOwner*(instances: seq[SidebarInstance], windowId: WindowId): Option[string]
proc resolveTarget*(instances: seq[SidebarInstance], focused: Option[WindowId],
                    activeInstance: string): string
proc claimWindow*(instance: string, windowId: WindowId): void
proc releaseWindow*(instance: string, windowId: WindowId): void
```

#### `profile.nim` — profile resolution

Determines the active profile from the current state.

```nim
type
  ResolvedProfile* = object
    id*: ProfileId
    pluginId*: PluginId
    instanceId*: string
    title*: string
    state*: SidebarState
    size*: PanelSize
    kanataLayer*: string
    commands*: seq[CommandConfig]
    badge*: Option[BadgeState]

proc resolve*(
  config: SidebardConfig,
  focusedWindow: Option[NiriWindow],
  activeInstance: string,
  instanceStates: Table[string, SidebarInstance]
): ResolvedProfile
```

Resolution order (first match wins):

1. Focused window app-id matches a plugin's `matchAppIds` + window is in a sidebar → that plugin's profile
2. Active sidebar instance has a `defaultPlugin` → that plugin's profile
3. Global fallback profile

No 6-level merge cascade. A plugin declares its full profile. An instance override replaces specific fields. That's two levels, and it's enough.

#### `keymap.nim` — command trie and prefix engine

The keyboard engine. Builds a trie from the active profile's commands and answers prefix queries.

```nim
type
  TrieNode = object
    children: Table[string, TrieNode]
    commandIds: seq[string]

  KeymapState* = object
    profileId*: string
    prefix*: seq[string]
    filterText*: string
    allCommands*: seq[CommandConfig]
    availableCommands*: seq[CommandConfig]
    nextKeys*: seq[string]
    exactMatch*: Option[CommandConfig]

proc buildTrie*(commands: seq[CommandConfig]): TrieNode
proc advance*(state: var KeymapState, key: string): void
proc reset*(state: var KeymapState): void
proc filter*(state: var KeymapState, text: string): void
proc getNextKeys*(state: KeymapState): seq[string]
proc getAvailableCommands*(state: KeymapState): seq[CommandConfig]
```

This module is pure computation — no I/O, no async. Easy to test.

#### `state.nim` — aggregated shell state

The "single source of truth" that the concept document described. Combines all inputs into one canonical object.

```nim
type
  ShellState* = object
    activeInstance*: string
    instances*: Table[string, SidebarInstance]
    focusedWindow*: Option[NiriWindow]
    resolvedProfile*: ResolvedProfile
    keymapState*: KeymapState
    kanataLayer*: string
    kanataConnected*: bool
    overlayVisible*: bool
    overlayExpiry*: MonoTime
```

Updated by the daemon's event loop whenever any input changes. All outputs (IPC responses, future renderer snapshots) derive from this.

#### `events.nim` — internal event bus

Simple typed event dispatch for the daemon.

```nim
type
  EventKind* = enum
    evNiriFocusChanged
    evNiriWindowOpened
    evNiriWindowClosed
    evSidebarStateChanged
    evProfileResolved
    evKanataLayerChanged
    evKeymapPrefixChanged
    evOverlayRequested
    evOverlayExpired
    evConfigReloaded

  Event* = object
    kind*: EventKind
    timestamp*: MonoTime
    # payload fields per kind...

type EventHandler* = proc(ev: Event) {.async.}
proc subscribe*(bus: EventBus, kind: EventKind, handler: EventHandler)
proc emit*(bus: EventBus, ev: Event) {.async.}
```

#### `ipc.nim` — Unix socket JSON-RPC

Server (for sidebard) and client (for sidebarctl and scripts).

Methods:

**Read:**
- `state.get` — full ShellState snapshot
- `profile.current` — resolved active profile
- `keymap.snapshot` — current keymap state (prefix, next keys, available commands)
- `commands.list` — all commands for the active profile
- `sidebar.status` — per-instance state summary

**Action:**
- `sidebar.activate {instance}` — set active sidebar
- `sidebar.toggle {instance}` — toggle visibility
- `command.run {id}` — execute a command by ID
- `keymap.prefix.advance {key}` — push a key onto the prefix
- `keymap.prefix.reset` — clear prefix
- `keymap.filter {text}` — set filter text
- `kanata.layer.change {layer}` — request layer change
- `config.reload` — reload TOML config

---

## Config file format

### `~/.config/sidebard/config.toml`

Global daemon settings.

```toml
[daemon]
socket_path = "/run/user/1000/sidebard.sock"
poll_interval_ms = 5000

[kanata]
host = "127.0.0.1"
port = 6666
reconnect_interval_ms = 3000

[defaults]
overlay_timeout_ms = 1200
collapsed_visible_px = 28
```

### `~/.config/sidebard/plugins/chat.toml`

One file per plugin.

```toml
id = "chat"
title = "Chat"
priority = 200

[match]
app_ids = ['^vesktop$', '^org\.telegram\.desktop$']

[profile]
id = "default"
title = "Chat"
kanata_layer = "sidebar-chat"

[profile.collapsed]
mode = "px"
visible_px = 30

[profile.inactive]
mode = "ratio"
width = 0.20

[profile.active]
mode = "ratio"
width = 0.34

[profile.focused]
mode = "ratio"
width = 0.42

[[commands]]
id = "chat.quick_reply"
title = "Quick reply"
description = "Reply to the selected conversation"
category = "messaging"
tags = ["reply", "chat", "message"]
sequence = ["Leader", "R"]
when_states = ["active", "focused"]

[[commands]]
id = "chat.next_unread"
title = "Next unread"
description = "Jump to the next unread conversation"
category = "messaging"
tags = ["nav", "unread", "chat"]
sequence = ["Leader", "J"]
when_states = ["active", "focused"]

[[commands]]
id = "chat.mark_read"
title = "Mark read"
description = "Mark the selected thread as read"
category = "messaging"
tags = ["read", "inbox"]
sequence = ["Leader", "M"]
when_states = ["active", "focused"]
```

### `~/.config/sidebard/instances/right.toml`

Per-instance config. Overrides plugin defaults for this instance.

```toml
id = "right"
default_plugin = "chat"

[overrides.chat.active]
width = 0.38

[overrides.chat.focused]
width = 0.45
```

---

## Niri IPC protocol

Niri exposes a Unix socket that accepts JSON commands and returns JSON responses. The socket path is in `$NIRI_SOCKET`.

### What sidebard needs from niri

| Operation | Niri command | Use case |
|---|---|---|
| List windows | `"Windows"` | Build window-to-sidebar mapping |
| Get focused window | `"FocusedWindow"` | Determine active context |
| Focus a window | `{"FocusWindow": {"id": N}}` | Sidebar focus commands |
| Close a window | `{"CloseWindow": {"id": N}}` | Sidebar close commands |
| Event subscription | `"EventStream"` | Real-time focus/window tracking |
| List workspaces | `"Workspaces"` | Context for profile resolution |

### Event stream

Niri's event stream sends newline-delimited JSON events:

- `WindowOpenedOrChanged` — window appeared or properties changed
- `WindowClosed` — window gone
- `WindowFocusChanged` — focus moved
- `WorkspaceActivated` — workspace switch

sidebard subscribes to the event stream on startup and uses it as the primary trigger for state updates. No polling for focus changes.

### Window management operations

The niri IPC layer in `niri.nim` should expose these as typed async procedures. This makes the library useful beyond sidebars — any Nim program that wants to talk to niri can import `libsidebard/niri`.

---

## Kanata integration

### Protocol

Kanata's TCP server accepts JSON messages:

- `{"ChangeLayer": {"new": "sidebar-chat"}}` — switch layer
- `{"RequestLayerNames": {}}` — get available layers
- `{"ActOnFakeKey": {"name": "vk-reply", "action": "Tap"}}` — trigger virtual key

And sends notifications:

- `{"LayerChange": {"old": "base", "new": "sidebar-chat"}}` — layer switched

### How prefix tracking works

This was flagged as the critical design gap in the review. The answer for v1:

**sidebard does not track physical keypresses.** It tracks prefix state through explicit IPC calls.

The flow:

1. Kanata receives a leader key press.
2. Kanata's config includes a `push-msg` action that sends `{"prefix": "Leader"}` to sidebard (via a small bridge script or direct TCP message).
3. sidebard updates its keymap engine prefix state.
4. Any connected UI queries `keymap.snapshot` and renders accordingly.
5. On timeout or completion, Kanata sends another message to clear the prefix.

If `push-msg` is too complex for v1, the alternative is:

- sidebard exposes `keymap.prefix.advance` and `keymap.prefix.reset` over IPC
- A small wrapper script (or Kanata `cmd` action) calls `sidebard-ctl keymap prefix advance Leader`
- This is one line in the Kanata config per prefix key

Either way, the keymap engine itself is pure — it doesn't listen to hardware. It receives prefix changes through its API.

---

## Daemon lifecycle

### Startup

1. Load config from TOML hierarchy
2. Connect to niri socket, subscribe to event stream
3. Connect to Kanata TCP (retry on failure — not fatal)
4. Read current sidebar instance state from `state.json` files
5. Resolve initial profile
6. Start IPC server on Unix socket
7. Enter event loop

### Event loop

```
niri event stream ──┐
kanata events ──────┤
IPC requests ───────┤──→ update ShellState ──→ emit internal events
timers (overlay) ───┘
```

On each state change:

1. Re-resolve active profile
2. If profile changed → send Kanata `ChangeLayer`
3. If overlay requested → start overlay timer
4. Respond to any pending IPC requests

### Degraded modes

| Dependency | If missing |
|---|---|
| Niri socket | Fatal — cannot function without compositor |
| Kanata | Non-fatal — skip layer switching, retry every N seconds |
| Plugin config | Use empty defaults — no commands, no custom sizes |
| IPC clients | None required — daemon runs independently |

### Shutdown

1. Close IPC server
2. Disconnect from Kanata
3. Disconnect from niri
4. No state to persist (instance state is in niri-sidebar's `state.json`)

---

## sidebarctl evolution

### Current role

`sidebarctl` is a synchronous CLI dispatcher. It reads state files, resolves targets, shells out to wrapper scripts.

### New role

With `libsidebard`, sidebarctl becomes a thin CLI that:

- **When sidebard is running:** Sends RPC over the Unix socket. Fast, consistent with daemon state.
- **When sidebard is not running:** Falls back to direct state-file reads + wrapper invocation (current behavior). Still works without the daemon.

This means sidebard is **optional**. You can run just sidebarctl and get the same sidebar management you have today. sidebard adds the daemon layer (profiles, keymap, Kanata) on top.

### Subcommand mapping

| Current command | With daemon | Without daemon |
|---|---|---|
| `sidebarctl activate right` | RPC `sidebar.activate` | Direct (as today) |
| `sidebarctl toggle-window` | RPC `sidebar.toggle` | Direct (as today) |
| `sidebarctl status` | RPC `sidebar.status` | Direct (as today) |
| `sidebarctl keymap` | RPC `keymap.snapshot` | N/A (needs daemon) |
| `sidebarctl profile` | RPC `profile.current` | N/A (needs daemon) |

---

## Nix integration

### Package

One Nim package builds both binaries:

```nix
# modules/home/desktop/niri/sidebar/package.nix
stdenv.mkDerivation {
  pname = "sidebard";
  src = ./src;
  nativeBuildInputs = [ nim ];
  buildPhase = ''
    nim c -d:release -o:$out/bin/sidebarctl src/sidebarctl.nim
    nim c -d:release -o:$out/bin/sidebard src/sidebard.nim
  '';
}
```

### Config generation

The Nix module generates TOML config files from the declarative options:

```nix
# modules/home/desktop/niri/sidebar/default.nix
xdg.configFile."sidebard/config.toml".text = generators.toTOML {} {
  daemon = {
    socket_path = "/run/user/${uid}/sidebard.sock";
  };
  kanata = {
    host = "127.0.0.1";
    port = cfg.kanataPort;
  };
};

# Per-plugin files from appRules + plugin definitions
xdg.configFile."sidebard/plugins/chat.toml".text = generators.toTOML {} { ... };

# Per-instance files from instances config
xdg.configFile."sidebard/instances/right.toml".text = generators.toTOML {} { ... };
```

### Systemd service

```nix
systemd.user.services.sidebard = {
  Unit = {
    Description = "sidebard shell daemon";
    After = [ "niri-sidebar-left.service" "niri-sidebar-right.service" "niri-sidebar-bottom.service" ];
  };
  Service = {
    ExecStart = "${pkg}/bin/sidebard";
    Restart = "on-failure";
    RestartSec = 2;
  };
  Install.WantedBy = [ "graphical-session.target" ];
};
```

---

## Implementation phases

### Phase 0: Library skeleton

- Set up Nim project with nimble
- `types.nim` — core types
- `config.nim` — TOML loading (just global config, no merge yet)
- Compile and test

Checkpoint: `nim c src/sidebarctl.nim` builds with the new library imported.

### Phase 1: Niri IPC

- `niri.nim` — connect to socket, list windows, get focused window
- Event stream subscription
- Replace sidebarctl's current `niri msg` shell-outs with native calls

Checkpoint: `sidebarctl status` works using native niri IPC instead of shelling out.

### Phase 2: Daemon + state

- `sidebard.nim` — async event loop
- `state.nim` — aggregated state
- `ownership.nim` — extracted from current sidebarctl
- `events.nim` — internal event bus
- `ipc.nim` — Unix socket server

Checkpoint: `sidebard` runs, tracks focus changes, and responds to `state.get` over IPC.

### Phase 3: Profiles + config hierarchy

- `profile.nim` — resolution logic
- `config.nim` — full merge from plugins/*.toml + instances/*.toml
- Profile changes emit events

Checkpoint: `sidebarctl profile` shows the resolved profile for the current focus context.

### Phase 4: Kanata bridge

- `kanata.nim` — TCP connect, layer switch, event subscription
- Profile changes trigger `ChangeLayer`
- Kanata events update shell state

Checkpoint: Focusing a chat window switches Kanata to the `sidebar-chat` layer.

### Phase 5: Keymap engine

- `keymap.nim` — trie construction, prefix tracking, filtering
- IPC methods for `keymap.snapshot`, `keymap.prefix.advance`, `keymap.prefix.reset`

Checkpoint: `sidebarctl keymap` shows available commands and next keys for the active profile.

### Phase 6: UI surface (TBD)

- Renderer choice still open (TUI in Ghostty, layer-shell widget, etc.)
- Consumes `keymap.snapshot` and `state.get` over IPC
- Purely a consumer — no state logic

---

## What this does NOT cover (v2+)

- Full terminal emulator surface
- Multiple keyboard layouts
- Fuzzy ranking / scoring weights
- Per-monitor placement rules
- Project-local `.sidebard/` directory overrides
- Generated Kanata config synthesis
- Plugin scripts (state.py equivalent in Nim)
- Overlay/badge rendering

---

## Dependency summary

### Nim packages needed

| Package | Purpose |
|---|---|
| `parsetoml` | TOML config loading |
| `asyncdispatch` | Async I/O (stdlib) |
| `asyncnet` | Socket I/O (stdlib) |
| `json` | JSON serialization (stdlib) |
| `re` or `regex` | App-id matching |
| `options` | Option types (stdlib) |

No external frameworks. The standard library covers async, sockets, and JSON. Only TOML parsing and regex are external.

### System dependencies

| Dependency | Required | Notes |
|---|---|---|
| Niri compositor | Yes | Provides Unix socket at `$NIRI_SOCKET` |
| niri-sidebar instances | Yes | Provides per-instance state.json |
| Kanata | No | Graceful degradation if unavailable |
