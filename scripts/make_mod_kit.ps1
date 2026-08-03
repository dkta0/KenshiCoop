<#
.SYNOPSIS
  Package the player mod kit plus a separate one-click installer/updater. The
  player kit remains a single folder called "KenshiCoop" that can be copied
  straight into <Kenshi>\mods\.

.DESCRIPTION
  Assembles dist\mod-kit\ as:
    KenshiCoop\                 <- the drop-in mod folder (copy this into mods\)
      KenshiCoop.dll              the plugin (protocol-version-matched; a mismatch
                                  is rejected at handshake by design)
      KenshiCoop.mod              mod-list entry so it shows in Kenshi's Mods menu
      RE_Kenshi.json              tells RE_Kenshi to load the plugin
      coop_config.json            only needed for LAN/direct-UDP; Steam play is
                                  configured entirely in-game (F2)
    README.txt                  <- plain copy-the-folder instructions (NOT copied
                                  into mods, so it never clutters the game folder)
  ...then zips it to dist\KenshiCoop-kit.zip (the release artifact the README
  and the GitHub release point at).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\make_mod_kit.ps1

.EXAMPLE
  # Reuse the current build instead of recompiling.
  powershell -ExecutionPolicy Bypass -File scripts\make_mod_kit.ps1 -SkipBuild
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    # Where to find KenshiCoop.mod / RE_Kenshi.json if they aren't in dist\mods.
    [string]$HostDir = "C:\Program Files (x86)\Steam\steamapps\common\Kenshi"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Split-Path -Parent $scriptDir

if (-not $SkipBuild) {
    # The PLAYER release ships the Release config: the shipped DLL excludes the
    # scenario harness (~12k lines) and does not define KENSHICOOP_HARNESS
    # (Phase 1 build separation). The test pipeline uses Harness instead.
    Write-Host "=== build plugin (Release / shipped, no scenario harness) ==="
    & cmd.exe /c "`"$scriptDir\build_plugin.cmd`" Release"
    if ($LASTEXITCODE -ne 0) { throw "build failed ($LASTEXITCODE)" }
}

# Resolve the four mod files from the first place each exists.
function Resolve-First([string[]]$candidates, [string]$what) {
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    throw "$what not found (looked in: $($candidates -join '; '))"
}
$dll  = Resolve-First @(
    (Join-Path $repoRoot "src\plugin\x64\Release\KenshiCoop.dll"),
    (Join-Path $repoRoot "dist\mods\KenshiCoop\KenshiCoop.dll")
) "KenshiCoop.dll"

# Canonical shipped-DLL hash (Phase 1 provenance). Package from ONE DLL and
# assert the packaged copy is byte-identical to it, so the release artifact's
# SHA-256 is verifiable rather than a mutable file tracked under dist\.
$canonSha = (Get-FileHash -Algorithm SHA256 $dll).Hash
Write-Host "Canonical Release DLL SHA-256: $canonSha"
Write-Host "  source: $dll"
$json = Resolve-First @(
    (Join-Path $repoRoot "dist\mods\KenshiCoop\RE_Kenshi.json"),
    (Join-Path $HostDir  "mods\KenshiCoop\RE_Kenshi.json")
) "RE_Kenshi.json"
$mod  = Resolve-First @(
    (Join-Path $repoRoot "dist\mods\KenshiCoop\KenshiCoop.mod"),
    (Join-Path $HostDir  "mods\KenshiCoop\KenshiCoop.mod")
) "KenshiCoop.mod"

# Rebuild dist\mod-kit from scratch so no stale install script survives.
$kitDir  = Join-Path $repoRoot "dist\mod-kit"
$modDir  = Join-Path $kitDir "KenshiCoop"
if (Test-Path $kitDir) { Remove-Item -Recurse -Force $kitDir }
New-Item -ItemType Directory -Force -Path $modDir | Out-Null

Write-Host "=== assembling KenshiCoop mod folder ==="
Copy-Item $dll  (Join-Path $modDir "KenshiCoop.dll")
Copy-Item $json (Join-Path $modDir "RE_Kenshi.json")
Copy-Item $mod  (Join-Path $modDir "KenshiCoop.mod")

# coop_config.json. Steam needs only maxPlayers; LAN also uses ip/port.
@'
{
  // Total players including the host. Default 8; supported range 2..32.
  // Prepare at least one squad tab and character per connected player.
  "maxPlayers": 8,

  // Experimental single-authority mode. Set true on the host and EVERY guest.
  // The host authors all state; guests send move/order/job intents.
  "hostAuthority": false,

  // Steam: host shares one Steam ID; every guest pastes that host ID in F2.
  // UDP: set transport/ip/port here, then select UDP in F2.
  "transport": "steam",
  "ip": "127.0.0.1",
  "port": 27800,
  "autoConnect": false
}
'@ | Set-Content (Join-Path $modDir "coop_config.json") -Encoding UTF8

# Top-level README (sibling to the KenshiCoop folder, so it is NOT copied into
# the game). Plain "copy the folder" instructions - no install script.
@'
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
  1. Kenshi 1.0.65 or 1.0.68 (Steam), set to WINDOWED mode.
  2. RE_Kenshi 0.3.4+:
     https://www.nexusmods.com/kenshi/mods/847
     On Kenshi 1.0.68 its installer automatically creates and launches a
     compatible 1.0.65 runtime; do not manually downgrade Kenshi.
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
     does not disconnect the others. With experimental host authority enabled,
     F2 also shows host accepted/rejected command counts or the guest's pending
     commands, last command RTT, and rejection count.

  Capacity defaults to 8 total players. Edit "maxPlayers" in coop_config.json
  before hosting to choose 2..32. Practical capacity depends on the host, save,
  NPC density, and network. Choose Wanderer x3 for host + two guests or
  Wanderer x4 for host + three guests. Each has one wanderer per ready squad
  tab; Wanderer x2 remains available. Recruit and split more characters for
  larger groups.

EXPERIMENTAL HOST AUTHORITY
---------------------------
  Set "hostAuthority": true in coop_config.json on the host and EVERY guest
  before going ONLINE. The host becomes canonical for every squad and the
  world. Guests send reliable move/order/job intents and complete post-action
  inventory results, briefly predict locally, then reconcile to host snapshots.
  Buying, container moves, and gear drop/pickup results cross this validated
  host boundary; combat outcomes and damage remain host-authored. Unhooked UI
  actions are not remote commands. Leave this false for the legacy per-player
  squad-authority mode.

INVENTORY ACCEPTANCE CHECK (experimental)
-----------------------------------------
  Use a disposable Wanderer x3 save with one host and two guests, with
  hostAuthority enabled everywhere. Record each player's item counts and wallet
  plus one shop's stock. On every owned squad, move an item through personal
  inventory, a backpack, and an owned container; split/merge a stack; equip and
  unequip; trade between squads; buy and sell as a guest; then have one guest
  drop a unique item and the other pick it up. Save from a guest, disconnect and
  reconnect one guest, and recheck all inventories, wallets, ground items, and
  shop stock on all three machines. Pass only if everything converges and no
  item or money is added or lost. Keep every KenshiCoop_*.log after a failure.


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
'@ | Set-Content (Join-Path $kitDir "README.txt") -Encoding UTF8

# Provenance: assert the PACKAGED DLL is byte-identical to the canonical build,
# then record the hash next to the kit so the release artifact is verifiable.
$packagedDll = Join-Path $modDir "KenshiCoop.dll"
$packagedSha = (Get-FileHash -Algorithm SHA256 $packagedDll).Hash
if ($packagedSha -ne $canonSha) {
    throw "packaged DLL hash ($packagedSha) != canonical Release DLL hash ($canonSha)"
}
$protoLine = Select-String -Path (Join-Path $repoRoot "src\netproto\Wire.h") `
    -Pattern 'PROTOCOL_VERSION\s*=\s*(\d+)' | Select-Object -First 1
$proto = if ($protoLine) { $protoLine.Matches[0].Groups[1].Value } else { "?" }
@{
    dllSha256       = $canonSha
    protocolVersion = $proto
    builtUtc        = (Get-Date).ToUniversalTime().ToString("o")
    config          = "Release"
} | ConvertTo-Json | Set-Content (Join-Path $kitDir "PROVENANCE.json") -Encoding UTF8
Write-Host "Packaged DLL SHA-256 verified == canonical."

# Zip the mod kit, publish its checksum for the updater, then package the small
# double-click installer separately so it can download this kit from a release.
$zip = Join-Path $repoRoot "dist\KenshiCoop-kit.zip"
$shaFile = Join-Path $repoRoot "dist\KenshiCoop-kit.zip.sha256"
if (Test-Path $zip) { Remove-Item $zip }
if (Test-Path $shaFile) { Remove-Item $shaFile }
Compress-Archive -Path (Join-Path $kitDir "*") -DestinationPath $zip
$zipSha = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLowerInvariant()
"$zipSha  KenshiCoop-kit.zip" | Set-Content $shaFile -Encoding ASCII

$installerDir = Join-Path $repoRoot "dist\installer"
$installerZip = Join-Path $repoRoot "dist\KenshiCoop-installer.zip"
if (Test-Path $installerDir) { Remove-Item -LiteralPath $installerDir -Recurse -Force }
if (Test-Path $installerZip) { Remove-Item -LiteralPath $installerZip -Force }
New-Item -ItemType Directory -Path $installerDir | Out-Null
Copy-Item (Join-Path $scriptDir "Install-KenshiCoop.cmd") $installerDir
Copy-Item (Join-Path $scriptDir "Install-KenshiCoop.ps1") $installerDir
Compress-Archive -Path (Join-Path $installerDir "*") -DestinationPath $installerZip

Write-Host ""
Write-Host "Mod folder: $modDir"
Write-Host "Kit zipped: $zip"
Write-Host "Kit checksum: $shaFile"
Write-Host "Installer zipped: $installerZip"
Get-ChildItem -Recurse $kitDir | ForEach-Object {
    Write-Host ("  " + $_.FullName.Substring($kitDir.Length + 1))
}
