KenshiCoop - co-op mod
======================

This zip contains ONE folder: "KenshiCoop". That folder IS the mod.

INSTALL (every player)
----------------------
  1. Right-click the downloaded zip > Properties > Unblock (if shown), then
     extract it.
  2. Copy the "KenshiCoop" folder into your Kenshi mods folder:
       <Kenshi>\mods\
     so you end up with:
       <Kenshi>\mods\KenshiCoop\KenshiCoop.dll   (and the other files)
     The default Steam path is:
       C:\Program Files (x86)\Steam\steamapps\common\Kenshi\mods\
  3. Launch Kenshi and enable "KenshiCoop" in the Mods menu.

PREREQUISITES (every player)
----------------------------
  1. Kenshi 1.0.65 (Steam), set to WINDOWED mode.
  2. RE_Kenshi 0.3.1+:
     https://www.nexusmods.com/kenshi/mods/847
  3. Steam running and online. No port forwarding or guest IPs are needed.

PLAY (Steam - recommended)
--------------------------
  1. Press F2. The panel works at the main menu and in-game.
  2. HOST: click "Copy my Steam ID" and share that one ID with every guest.
     Load a save with one squad tab and character per player. Set Role: HOST,
     leave Transport on STEAM, and set Connection to ONLINE.
  3. EACH GUEST: from the main menu, copy the host's ID, click
     "Paste host's Steam ID", set Role: JOIN, and go ONLINE. The host streams
     its current world; guests do not need the save beforehand.
  4. The host's status line shows the connected guest count. One guest leaving
     does not disconnect the others.

  Capacity defaults to 8 total players. Edit "maxPlayers" in coop_config.json
  before hosting to choose 2..32. Practical capacity depends on the host, save,
  NPC density, and network. The included Wanderer x2 start has two ready squad
  tabs; recruit and split more characters before adding more players.

PLAY (LAN / direct UDP - advanced)
----------------------------------
  Skip the Steam ID swap. Open <Kenshi>\mods\KenshiCoop\coop_config.json in
  Notepad, set "transport": "udp", and put the host's address in "ip" (and
  "port" if you changed it). In the panel set Transport: UDP, pick Host/Join,
  and go ONLINE. ip/port are re-read whenever you go ONLINE, so no restart is
  needed after an edit.

UNINSTALL
---------
  Delete <Kenshi>\mods\KenshiCoop. Nothing else is touched.

TROUBLESHOOTING
---------------
  * "The co-op plugin has not started": RE_Kenshi didn't load it. Check
    <Kenshi>\RE_Kenshi_log.txt for 'KenshiCoop'; reinstalling RE_Kenshi
    usually fixes it.
  * No connection (Steam): Steam must be ONLINE everywhere. Every guest pastes
    the HOST's ID; the host never pastes guest IDs. Look for
    '[steam] session ... active=1' in <Kenshi>\KenshiCoop_*.log.
  * "protocol mismatch": one player has an older/newer build; both should use
    the same release.
