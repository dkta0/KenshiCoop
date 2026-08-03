# KenshiCoop

Setup + Demo: [https://www.youtube.com/watch?v=OqwVRRZEYGM](https://www.youtube.com/watch?v=OqwVRRZEYGM)

Experimental **co-op multiplayer for [Kenshi](https://lofigames.com/)**, built as an
[RE_Kenshi](https://github.com/BFrizzleFoShizzle/RE_Kenshi) /
[KenshiLib](https://github.com/BFrizzleFoShizzle/KenshiLib) plugin.

One player hosts their world; multiple friends can connect over LAN, direct UDP,
or Steam P2P and play separate squads inside it. The plugin replicates squads,
NPCs, combat, inventory and equipment, direct trades between players' squads,
items dropped on the ground, base building and container contents, money, game
speed, and more. Saves are coordinated: a player-initiated save becomes one
shared save, streamed to every machine automatically.

> **Status: work in progress.** This is a hobby project under active
> development. Expect rough edges, desyncs, and crashes. Multiplayer transport
> uses a host-routed star topology; practical capacity is workload-bound.

## How it works

- `KenshiCoop.dll` is loaded into the game by RE_Kenshi. It hooks the engine via
  KenshiLib and drives all game mutation on the main thread.
- Networking is [ENet](https://github.com/lsalzman/enet) over UDP, with an
  optional Steam P2P tunnel (no port forwarding needed).
- By default, squad authorship is partitioned between players. The optional
  experimental `hostAuthority` mode instead makes the host canonical for every
  squad and lets guests send control intents. See `docs/API_REFERENCE.md` for
  the full engine-control surface and wire protocol.

```
src/plugin/       The KenshiCoop plugin (net, sync/replication, engine facade, scenarios)
src/netproto/     Shared wire-protocol headers (plain C++03, compiled by everything)
src/nettest/      Standalone ENet console app (transport de-risking)
src/netsim/       Protocol simulator
src/prototest/    Wire-protocol unit tests
src/sessiontest/   Portable host + two-client topology/relay smoke test
src/tunneltest/   Steam-tunnel socket-hook tests
scripts/          Build, deploy, session, and automated-test tooling (PowerShell)
docs/             Build guide, engine/API reference, replication pitfalls
third_party/      ENet patches, VC10 compat shim (deps are fetched, not committed)
```

## Try it (play with friends)

One host can accept multiple joining players (eight total players by default,
configurable up to 32). Configure the session **inside the game** with the
**F2** panel. For Steam, the host shares one Steam ID and every guest pastes
that same host ID; guest IDs are not needed. `coop_config.json` is optional for
changing capacity and is also used for LAN/direct-UDP addresses.

### Before you start (every player)

1. **Kenshi 1.0.65 or 1.0.68 (Steam)**, set to windowed mode: launch Kenshi
   once, then Options > Video > un-check **Full Screen**.
2. **[RE_Kenshi 0.3.4+](https://www.nexusmods.com/kenshi/mods/847)** installed
   (free Nexus mod - it loads the co-op plugin into the game). On Kenshi
   1.0.68, its installer automatically creates and launches a compatible
   1.0.65 runtime; do not manually downgrade Kenshi.
3. **Steam running and online** on both machines. That's the whole network
   setup: the connection is Steam P2P, so there's no port forwarding, no
   router configuration, and no IP addresses. (A direct-UDP mode is also
   available for LAN / port-forwarded games.)

### 1. Install the mod

Download `KenshiCoop-installer.zip` from the
[latest release](https://github.com/dkta0/KenshiCoop/releases/latest), extract
it, and double-click **`Install-KenshiCoop.cmd`**. Accept the Windows elevation
prompt. The installer finds Kenshi, downloads and verifies the latest mod kit,
then installs it. On later runs it updates the mod while preserving
`coop_config.json`; the replaced directory is checksum-verified at
`%LOCALAPPDATA%\KenshiCoop\backups\` before the swap.

For a manual install, download `KenshiCoop-kit.zip` from the same release and
copy its **`KenshiCoop`** folder into the Kenshi `mods` directory so you end up
with `<Kenshi>\mods\KenshiCoop\KenshiCoop.dll` (default Steam path:
`C:\Program Files (x86)\Steam\steamapps\common\Kenshi\mods\`). Then launch
Kenshi and enable **KenshiCoop** in the Mods menu.

### 2. Connect in-game (press F2)

The Co-op panel works at the **main menu** and in-game. Guests do not load a
save first.

1. The **host** clicks **Copy my Steam ID** once and shares that ID with every
   guest (Steam chat, Discord, etc.). Each **guest** copies the host's ID and
   clicks **Paste host's Steam ID**. Nothing is written to disk, so guests
   re-paste it after relaunching Kenshi.
2. Leave **Transport** on **STEAM**.
3. **Host:** prepare a save with at least one distinct squad tab and controllable
   character per player, load it, choose **Role: HOST**, and set **Connection:
   ONLINE**. Choose the start matching the party: **Multiplayer (Wanderer x3)**
   for a host and two guests, or **Multiplayer (Wanderer x4)** for a host and
   three guests. Each wanderer starts in a separate squad tab; x2 remains
   available for two-player sessions.
4. **Guests:** from the main menu, choose **Role: JOIN** and set **Connection:
   ONLINE**. Repeat on every guest machine using the same host Steam ID. The host
   streams its world to each guest.
5. The host's white status line shows the live guest count. With experimental
   host authority enabled, it also shows accepted/rejected commands; each guest
   sees pending commands, last command RTT, and rejections. Any player can toggle
   **Connection: OFFLINE** independently; the remaining session stays online.

The host capacity defaults to eight total players. Before going online, edit
`"maxPlayers"` in `coop_config.json` to any value from 2 through 32. Practical
capacity depends on the host machine, save, NPC density, and network quality.

**LAN / direct-UDP (advanced):** skip the Steam ID swap. Open
`<Kenshi>\mods\KenshiCoop\coop_config.json`, set `"transport": "udp"`, and put
the host's address in `"ip"` / `"port"`. Then in the panel set **Transport: UDP**
and go ONLINE. The `ip`/`port` are re-read whenever you go ONLINE, so no restart
is needed after an edit.

### Good to know

- **One squad tab per player.** Player slot 0 (host) is assigned squad-tab rank
  0; each WELCOME-assigned guest slot N is assigned rank N. In the default mode,
  that player authors the assigned squad. In `hostAuthority` mode, the rank is
  the guest's command boundary and the host authors the resulting state. A
  player needs an existing character in that tab: recruit and split enough
  characters on the host save before connecting more guests.
- **Two-, three-, and four-player starts included.** The matching
  **Multiplayer (Wanderer xN)** start provides N wanderers in N separate tabs.
  Wanderer x4 is ready for a host plus three guests. For larger sessions,
  recruit and split additional characters before connecting more players.
- **Experimental single-authority mode.** Set `"hostAuthority": true` in
  `coop_config.json` for the host and every guest before going online. The host
  becomes canonical for all squad and world state. Guests send reliable
  move/order/job intents and complete post-action inventory results, apply a
  brief local presentation prediction, then reconcile to host snapshots. The
  host authenticates the player's squad, validates unchanged transaction
  baselines and exact item conservation, commits player/vendor/wallet changes,
  and broadcasts canonical snapshots. Gear drop/pickup results use the same
  host boundary. Combat outcomes and damage remain host-authored; unhooked UI
  actions are not remote commands.
- **Guests don't need the host's save.** Each new guest receives the host's
  current world on connect. An identical local save skips the transfer.
- **Saving is coordinated.** A save initiated by any connected player is
  host-authored and distributed to the session. To resume, the host loads that
  save and goes online; guests reconnect from the menu.

### If something goes wrong

- **"The co-op plugin has not started"** - RE_Kenshi didn't load it. Check
  `<Kenshi>\RE_Kenshi_log.txt` for `KenshiCoop`; reinstalling
  [RE_Kenshi](https://www.nexusmods.com/kenshi/mods/847) usually fixes it.
- **No connection (Steam)** - Steam must be online on every machine. Every guest
  must paste the **host's** ID; the host does not paste guest IDs. Confirm all
  installs use the same build and look for `[steam] session ... active=1` in
  `<Kenshi>\KenshiCoop_*.log`.
- **"protocol mismatch" in the log** - one of you has an older build; both
  players should re-install from the same release.

The kit's `README.txt` has the full setup + troubleshooting list.

## Building

The plugin must be compiled with the **Visual C++ 2010 (v100) x64 toolset** (a
KenshiLib requirement). Full toolchain setup, gotchas, and install steps are in
[docs/BUILD_SETUP.md](docs/BUILD_SETUP.md). Short version, once prerequisites
are in place:

```bash
cmd //c scripts/build_plugin.cmd
```

Dependencies are fetched, not committed:

- KenshiLib + precompiled libs: clone
  [KenshiLib_Examples_deps](https://github.com/BFrizzleFoShizzle/KenshiLib_Examples_deps)
  into `third_party/KenshiLib_deps/`
- ENet: clone [lsalzman/enet](https://github.com/lsalzman/enet) into
  `third_party/enet/enet/` and apply the patches in `third_party/enet/patches/`
  (see `third_party/enet/README.md`)

## Development and testing

`cmd /c scripts\build_prototest.cmd` builds both the wire/layout unit layer and
the portable `sessiontest.exe` host + two-client ownership/relay smoke. The
Windows `dev_cycle.ps1` harness still drives two real local game installs for
named gameplay scenarios. `regress.ps1` runs both fast layers before its
scenario matrix. See [docs/BUILD_SETUP.md](docs/BUILD_SETUP.md) Parts D-E.

## Credits

- [BFrizzleFoShizzle](https://github.com/BFrizzleFoShizzle) - RE_Kenshi and
  KenshiLib, which make plugins like this possible
- [lsalzman/enet](https://github.com/lsalzman/enet) - UDP networking library
- [zeroit789](https://github.com/zeroit789) - the "Multiplayer (Wanderer x2)"
  co-op game start ([#15](https://github.com/nhoral/KenshiCoop/pull/15))
- Lo-Fi Games - Kenshi

## License

[AGPL-3.0](LICENSE). KenshiLib and RE_Kenshi are GPLv3; this plugin links
KenshiLib under GPLv3 section 13 (GPL/AGPL combination). Not affiliated with
Lo-Fi Games. Non-commercial fan project.
