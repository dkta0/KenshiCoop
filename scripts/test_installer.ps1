$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$installer = Join-Path $PSScriptRoot "Install-KenshiCoop.ps1"
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("KenshiCoop-installer-test-" + [Guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Label) {
    if (-not $Condition) { throw "FAIL: $Label" }
    Write-Host "PASS $Label"
}

function New-TestKit([string]$ZipPath, [string]$DllText, [string]$ConfigText) {
    $source = Join-Path $root ("kit-" + [Guid]::NewGuid().ToString("N"))
    $mod = Join-Path $source "KenshiCoop"
    New-Item -ItemType Directory -Force -Path $mod | Out-Null
    Set-Content -LiteralPath (Join-Path $mod "KenshiCoop.dll") -Value $DllText -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $mod "KenshiCoop.mod") -Value "mod" -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $mod "RE_Kenshi.json") -Value "{}" -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $mod "coop_config.json") -Value $ConfigText -Encoding UTF8
    $hash = (Get-FileHash -LiteralPath (Join-Path $mod "KenshiCoop.dll") -Algorithm SHA256).Hash
    @{ protocolVersion = 51; dllSha256 = $hash } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $source "PROVENANCE.json") -Encoding UTF8
    Compress-Archive -Path (Join-Path $source "*") -DestinationPath $ZipPath -Force
    Remove-Item -LiteralPath $source -Recurse -Force
}

function New-FakeGame([string]$Name) {
    $game = Join-Path $root $Name
    New-Item -ItemType Directory -Force -Path (Join-Path $game "mods") | Out-Null
    Set-Content -LiteralPath (Join-Path $game "kenshi_x64.exe") -Value "fixture" -Encoding ASCII
    return $game
}

function File-Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

New-Item -ItemType Directory -Path $root | Out-Null
try {
    $v1 = Join-Path $root "kit-v1.zip"
    $v2 = Join-Path $root "kit-v2.zip"
    New-TestKit $v1 "dll-v1" '{ "hostAuthority": false, "maxPlayers": 8 }'
    New-TestKit $v2 "dll-v2" '{ "hostAuthority": false, "maxPlayers": 8, "newDefault": true }'

    # Fresh install: no backup is needed and the complete mod appears at the target.
    $fresh = New-FakeGame "fresh"
    $freshBackups = Join-Path $root "fresh-backups"
    & $installer -KenshiPath $fresh -ArchivePath $v1 -BackupRoot $freshBackups -NonInteractive
    $freshMod = Join-Path $fresh "mods\KenshiCoop"
    Assert-True (Test-Path -LiteralPath (Join-Path $freshMod "KenshiCoop.dll")) "fresh install writes required mod"
    Assert-True (-not (Test-Path -LiteralPath $freshBackups)) "fresh install creates no unnecessary backup"

    # Successful update: preserve operator config and verify the backup byte-for-byte.
    $customConfig = '{ "hostAuthority": true, "maxPlayers": 12, "transport": "steam" }'
    Set-Content -LiteralPath (Join-Path $freshMod "coop_config.json") -Value $customConfig -Encoding UTF8
    $oldDllHash = File-Hash (Join-Path $freshMod "KenshiCoop.dll")
    $oldConfigHash = File-Hash (Join-Path $freshMod "coop_config.json")
    & $installer -KenshiPath $fresh -ArchivePath $v2 -BackupRoot $freshBackups -NonInteractive
    Assert-True ((Get-Content -LiteralPath (Join-Path $freshMod "KenshiCoop.dll") -Raw) -match 'dll-v2') "update installs new DLL"
    Assert-True ((File-Hash (Join-Path $freshMod "coop_config.json")) -eq $oldConfigHash) "update preserves coop_config.json"
    $backupDirs = @(Get-ChildItem -LiteralPath $freshBackups -Directory)
    Assert-True ($backupDirs.Count -eq 1) "update creates one timestamped backup"
    Assert-True ((File-Hash (Join-Path $backupDirs[0].FullName "KenshiCoop.dll")) -eq $oldDllHash) "backup preserves prior DLL"
    Assert-True ((File-Hash (Join-Path $backupDirs[0].FullName "coop_config.json")) -eq $oldConfigHash) "backup preserves prior config"

    # Re-running the same release is a no-op: no churn, no second backup.
    & $installer -KenshiPath $fresh -ArchivePath $v2 -BackupRoot $freshBackups -NonInteractive
    Assert-True (@(Get-ChildItem -LiteralPath $freshBackups -Directory).Count -eq 1) "same release creates no redundant backup"
    Assert-True ((File-Hash (Join-Path $freshMod "coop_config.json")) -eq $oldConfigHash) "same release preserves coop_config.json"
    Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $fresh "mods") -Force |
        Where-Object { $_.Name -like '.KenshiCoop.*' }).Count -eq 0) "same release leaves no staging directories"

    # Malformed release: validation fails before backup/swap and leaves target unchanged.
    $badSource = Join-Path $root "bad-source"
    New-Item -ItemType Directory -Path $badSource | Out-Null
    Set-Content -LiteralPath (Join-Path $badSource "not-a-mod.txt") -Value "bad" -Encoding ASCII
    $bad = Join-Path $root "bad.zip"
    Compress-Archive -Path (Join-Path $badSource "*") -DestinationPath $bad
    $beforeBad = File-Hash (Join-Path $freshMod "KenshiCoop.dll")
    $badRejected = $false
    try {
        & $installer -KenshiPath $fresh -ArchivePath $bad -BackupRoot $freshBackups -NonInteractive
    } catch { $badRejected = $true }
    Assert-True $badRejected "malformed release is rejected"
    Assert-True ((File-Hash (Join-Path $freshMod "KenshiCoop.dll")) -eq $beforeBad) "malformed release leaves installed mod unchanged"
    Assert-True (@(Get-ChildItem -LiteralPath $freshBackups -Directory).Count -eq 1) "malformed release creates no backup"

    # Failure after moving the old directory: restore it and retain the verified backup.
    $rollback = New-FakeGame "rollback"
    $rollbackBackups = Join-Path $root "rollback-backups"
    & $installer -KenshiPath $rollback -ArchivePath $v1 -BackupRoot $rollbackBackups -NonInteractive
    $rollbackMod = Join-Path $rollback "mods\KenshiCoop"
    Set-Content -LiteralPath (Join-Path $rollbackMod "coop_config.json") -Value $customConfig -Encoding UTF8
    $rollbackDllHash = File-Hash (Join-Path $rollbackMod "KenshiCoop.dll")
    $rollbackConfigHash = File-Hash (Join-Path $rollbackMod "coop_config.json")
    $rollbackTriggered = $false
    $env:KENSHICOOP_INSTALL_TEST_FAIL_AFTER_OLD_MOVE = "1"
    try {
        & $installer -KenshiPath $rollback -ArchivePath $v2 -BackupRoot $rollbackBackups -NonInteractive
    } catch { $rollbackTriggered = $true }
    finally { Remove-Item Env:\KENSHICOOP_INSTALL_TEST_FAIL_AFTER_OLD_MOVE -ErrorAction SilentlyContinue }
    Assert-True $rollbackTriggered "post-swap failure is surfaced"
    Assert-True ((File-Hash (Join-Path $rollbackMod "KenshiCoop.dll")) -eq $rollbackDllHash) "rollback restores prior DLL"
    Assert-True ((File-Hash (Join-Path $rollbackMod "coop_config.json")) -eq $rollbackConfigHash) "rollback restores prior config"
    Assert-True (@(Get-ChildItem -LiteralPath $rollbackBackups -Directory).Count -eq 1) "rollback retains verified backup"
    Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $rollback "mods") -Force |
        Where-Object { $_.Name -like '.KenshiCoop.*' }).Count -eq 0) "rollback removes swap staging directories"

    Write-Host "INSTALLER RESULT PASS fresh=1 update=1 malformed=rejected rollback=restored"
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
