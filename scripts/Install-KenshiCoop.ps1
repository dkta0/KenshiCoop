<#
.SYNOPSIS
  Installs or updates KenshiCoop from a GitHub release without risking the
  currently installed mod.

.DESCRIPTION
  Downloads KenshiCoop-kit.zip plus its published SHA-256, validates the kit and
  embedded DLL provenance, stages the new mod beside the target, preserves the
  existing coop_config.json, and only then swaps directories. An existing mod is
  copied to a timestamped backup first. Any failure after the old directory is
  moved restores it before returning an error.
#>
[CmdletBinding()]
param(
    [string]$KenshiPath,
    [string]$Repository = "dkta0/KenshiCoop",
    [string]$Tag,
    [ValidateSet("stable", "playtest")]
    [string]$Channel = "stable",
    [string]$ArchivePath,
    [string]$BackupRoot,
    [switch]$NonInteractive
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "[KenshiCoop] $Message"
}

function Get-Sha256([string]$Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "")
    } finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Get-SteamRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $candidates = @()
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "Steam")
    }
    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles "Steam")
    }
    try {
        $steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath
        if ($steam) { $candidates += $steam }
    } catch {}

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate) -and
            -not $roots.Contains([string]$candidate)) {
            $roots.Add([string]$candidate)
        }
    }

    $libraries = New-Object System.Collections.Generic.List[string]
    foreach ($root in $roots) {
        $libraries.Add($root)
        $vdf = Join-Path $root "steamapps\libraryfolders.vdf"
        if (-not (Test-Path -LiteralPath $vdf)) { continue }
        foreach ($line in Get-Content -LiteralPath $vdf -ErrorAction SilentlyContinue) {
            if ($line -match '^\s*"path"\s*"([^"]+)"') {
                $path = $Matches[1] -replace '\\\\', '\'
                if ($path -and -not $libraries.Contains($path)) { $libraries.Add($path) }
            }
        }
    }
    return $libraries.ToArray()
}

function Test-KenshiRoot([string]$Path) {
    if (-not $Path) { return $false }
    return Test-Path -LiteralPath (Join-Path $Path "kenshi_x64.exe") -PathType Leaf
}

function Resolve-KenshiRoot([string]$Requested, [bool]$NoPrompt) {
    if ($Requested) {
        $resolved = [System.IO.Path]::GetFullPath($Requested)
        if (-not (Test-KenshiRoot $resolved)) {
            throw "Kenshi was not found at '$resolved' (kenshi_x64.exe is missing)."
        }
        return $resolved.TrimEnd('\', '/')
    }

    $found = New-Object System.Collections.Generic.List[string]
    foreach ($steam in Get-SteamRoots) {
        $candidate = Join-Path $steam "steamapps\common\Kenshi"
        if ((Test-KenshiRoot $candidate) -and -not $found.Contains($candidate)) {
            $found.Add($candidate)
        }
    }
    $joinCopy = Join-Path $env:USERPROFILE "Kenshi-Join"
    if ((Test-KenshiRoot $joinCopy) -and -not $found.Contains($joinCopy)) {
        $found.Add($joinCopy)
    }

    if ($found.Count -eq 1) { return $found[0] }
    if ($NoPrompt) {
        throw "KenshiPath is required when no single Kenshi installation can be discovered."
    }

    if ($found.Count -gt 1) {
        Write-Host "Found Kenshi installations:"
        for ($i = 0; $i -lt $found.Count; ++$i) {
            Write-Host "  $($i + 1)) $($found[$i])"
        }
        $choice = Read-Host "Choose a number, or paste another Kenshi folder"
        $number = 0
        if ([int]::TryParse($choice, [ref]$number) -and
            $number -ge 1 -and $number -le $found.Count) {
            return $found[$number - 1]
        }
        $Requested = $choice
    } else {
        $Requested = Read-Host "Paste your Kenshi installation folder"
    }
    return Resolve-KenshiRoot $Requested $true
}

function Get-ReleaseKit([string]$Repo, [string]$ReleaseTag,
                        [string]$ReleaseChannel, [string]$WorkRoot) {
    if ($Repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
        throw "Invalid GitHub repository '$Repo'. Expected owner/name."
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ "User-Agent" = "KenshiCoop-Installer"; "Accept" = "application/vnd.github+json" }

    if ($ReleaseTag) {
        $escapedTag = [Uri]::EscapeDataString($ReleaseTag)
        $uri = "https://api.github.com/repos/$Repo/releases/tags/$escapedTag"
        Write-Step "Reading GitHub release $Repo (tag $ReleaseTag) ..."
        $release = Invoke-RestMethod -Uri $uri -Headers $headers -UseBasicParsing
    } elseif ($ReleaseChannel -eq "stable") {
        $uri = "https://api.github.com/repos/$Repo/releases/latest"
        Write-Step "Reading latest stable GitHub release for $Repo ..."
        $release = Invoke-RestMethod -Uri $uri -Headers $headers -UseBasicParsing
    } else {
        $uri = "https://api.github.com/repos/$Repo/releases?per_page=30"
        Write-Step "Reading latest playtest GitHub release for $Repo ..."
        $releases = @(Invoke-RestMethod -Uri $uri -Headers $headers -UseBasicParsing)
        $release = $releases |
            Where-Object { $_.draft -eq $false -and $_.prerelease -eq $true } |
            Select-Object -First 1
        if (-not $release) {
            throw "No playtest release is published. Use the stable installer or ask the host for a tagged test kit."
        }
    }

    $kitAsset = @($release.assets) | Where-Object { $_.name -eq "KenshiCoop-kit.zip" } | Select-Object -First 1
    $shaAsset = @($release.assets) | Where-Object { $_.name -eq "KenshiCoop-kit.zip.sha256" } | Select-Object -First 1
    if (-not $kitAsset) { throw "Release '$($release.tag_name)' has no KenshiCoop-kit.zip asset." }
    if (-not $shaAsset) { throw "Release '$($release.tag_name)' has no KenshiCoop-kit.zip.sha256 asset." }

    $zip = Join-Path $WorkRoot "KenshiCoop-kit.zip"
    $shaFile = Join-Path $WorkRoot "KenshiCoop-kit.zip.sha256"
    Write-Step "Downloading release $($release.tag_name) ..."
    Invoke-WebRequest -Uri $kitAsset.browser_download_url -Headers $headers -UseBasicParsing -OutFile $zip
    Invoke-WebRequest -Uri $shaAsset.browser_download_url -Headers $headers -UseBasicParsing -OutFile $shaFile
    $expected = ((Get-Content -LiteralPath $shaFile -Raw).Trim() -split '\s+')[0].ToUpperInvariant()
    if ($expected -notmatch '^[0-9A-F]{64}$') { throw "Published kit checksum is malformed." }
    $actual = (Get-Sha256 $zip).ToUpperInvariant()
    if ($actual -ne $expected) {
        throw "Downloaded kit SHA-256 mismatch: expected $expected, got $actual."
    }
    return @{
        Path = $zip
        Tag = [string]$release.tag_name
        Channel = if ($ReleaseTag) { "tag" } else { $ReleaseChannel }
        Sha256 = $actual
    }
}

function Expand-AndValidateKit([string]$Zip, [string]$WorkRoot) {
    if (-not (Test-Path -LiteralPath $Zip -PathType Leaf)) {
        throw "Release archive not found: $Zip"
    }
    $unpack = Join-Path $WorkRoot "unpacked"
    New-Item -ItemType Directory -Path $unpack | Out-Null
    Expand-Archive -LiteralPath $Zip -DestinationPath $unpack -Force

    $required = @(
        "KenshiCoop\KenshiCoop.dll",
        "KenshiCoop\KenshiCoop.mod",
        "KenshiCoop\RE_Kenshi.json",
        "KenshiCoop\coop_config.json",
        "PROVENANCE.json"
    )
    foreach ($relative in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $unpack $relative) -PathType Leaf)) {
            throw "Release archive is missing '$relative'; nothing was installed."
        }
    }
    $provenance = Get-Content -LiteralPath (Join-Path $unpack "PROVENANCE.json") -Raw | ConvertFrom-Json
    if (-not $provenance.dllSha256 -or $provenance.dllSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "Release provenance has no valid DLL SHA-256."
    }
    $dll = Join-Path $unpack "KenshiCoop\KenshiCoop.dll"
    $actualDll = Get-Sha256 $dll
    if ($actualDll -ne ([string]$provenance.dllSha256).ToUpperInvariant()) {
        throw "Packaged DLL does not match PROVENANCE.json."
    }
    return @{ Mod = (Join-Path $unpack "KenshiCoop"); Protocol = $provenance.protocolVersion; DllSha256 = $actualDll }
}

function Get-TreeFingerprint([string]$Root) {
    $full = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return @(Get-ChildItem -LiteralPath $full -Recurse -Force |
        Where-Object { -not $_.PSIsContainer } |
        ForEach-Object {
            $relative = $_.FullName.Substring($full.Length).TrimStart('\', '/')
            $hash = Get-Sha256 $_.FullName
            "$relative|$($_.Length)|$hash"
        } | Sort-Object)
}

function Assert-TreeCopy([string]$Original, [string]$Copy) {
    $difference = Compare-Object (Get-TreeFingerprint $Original) (Get-TreeFingerprint $Copy)
    if ($difference) { throw "Backup verification failed; the installed mod was not touched." }
}

function Test-ManagedFilesMatch([string]$SourceMod, [string]$InstalledMod) {
    if (-not (Test-Path -LiteralPath (Join-Path $InstalledMod "coop_config.json") -PathType Leaf)) {
        return $false
    }
    foreach ($name in @("KenshiCoop.dll", "KenshiCoop.mod", "RE_Kenshi.json")) {
        $source = Join-Path $SourceMod $name
        $installed = Join-Path $InstalledMod $name
        if (-not (Test-Path -LiteralPath $installed -PathType Leaf)) { return $false }
        if ((Get-Sha256 $source) -ne (Get-Sha256 $installed)) { return $false }
    }
    return $true
}

function Install-ValidatedMod([string]$SourceMod, [string]$GameRoot,
                              [string]$RequestedBackupRoot) {
    $mods = Join-Path $GameRoot "mods"
    New-Item -ItemType Directory -Force -Path $mods | Out-Null
    $target = Join-Path $mods "KenshiCoop"
    $token = [Guid]::NewGuid().ToString("N")
    $stage = Join-Path $mods (".KenshiCoop.install-" + $token)
    $oldSwap = Join-Path $mods (".KenshiCoop.previous-" + $token)
    $hadExisting = Test-Path -LiteralPath $target -PathType Container
    $backup = $null

    try {
        New-Item -ItemType Directory -Path $stage | Out-Null
        Get-ChildItem -LiteralPath $SourceMod -Force |
            Copy-Item -Destination $stage -Recurse -Force

        $oldConfig = Join-Path $target "coop_config.json"
        if ($hadExisting -and (Test-Path -LiteralPath $oldConfig -PathType Leaf)) {
            Copy-Item -LiteralPath $oldConfig -Destination (Join-Path $stage "coop_config.json") -Force
            Write-Step "Preserved existing coop_config.json."
        }

        foreach ($name in @("KenshiCoop.dll", "KenshiCoop.mod", "RE_Kenshi.json", "coop_config.json")) {
            if (-not (Test-Path -LiteralPath (Join-Path $stage $name) -PathType Leaf)) {
                throw "Staged mod is missing '$name'."
            }
        }

        if ($hadExisting -and (Test-ManagedFilesMatch $stage $target)) {
            Write-Step "The installed mod already matches this release; no backup or file swap is needed."
            return @{ Target = $target; Backup = $null; Updated = $false }
        }

        if ($hadExisting) {
            $backupBase = if ($RequestedBackupRoot) {
                [System.IO.Path]::GetFullPath($RequestedBackupRoot)
            } else {
                Join-Path $env:LOCALAPPDATA "KenshiCoop\backups"
            }
            $targetFull = [System.IO.Path]::GetFullPath($target).TrimEnd('\', '/')
            if ($backupBase.StartsWith($targetFull, [StringComparison]::OrdinalIgnoreCase)) {
                throw "BackupRoot cannot be inside the installed KenshiCoop directory."
            }
            New-Item -ItemType Directory -Force -Path $backupBase | Out-Null
            $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $backup = Join-Path $backupBase ("KenshiCoop-$stamp-" + $token.Substring(0, 8))
            Write-Step "Backing up the current mod to $backup ..."
            Copy-Item -LiteralPath $target -Destination $backup -Recurse
            Assert-TreeCopy $target $backup
            Write-Step "Backup verified."
        }

        if ($hadExisting) { Move-Item -LiteralPath $target -Destination $oldSwap }
        if ($env:KENSHICOOP_INSTALL_TEST_FAIL_AFTER_OLD_MOVE -eq "1") {
            throw "Injected installer rollback test failure."
        }
        Move-Item -LiteralPath $stage -Destination $target
        foreach ($name in @("KenshiCoop.dll", "KenshiCoop.mod", "RE_Kenshi.json", "coop_config.json")) {
            if (-not (Test-Path -LiteralPath (Join-Path $target $name) -PathType Leaf)) {
                throw "Installed mod verification failed: '$name' is missing."
            }
        }
        if (Test-Path -LiteralPath $oldSwap) { Remove-Item -LiteralPath $oldSwap -Recurse -Force }
        return @{ Target = $target; Backup = $backup; Updated = $true }
    } catch {
        $failure = $_
        if (Test-Path -LiteralPath $oldSwap -PathType Container) {
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
            Move-Item -LiteralPath $oldSwap -Destination $target
            Write-Step "Update failed; restored the previous mod directory."
        }
        throw $failure
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
        if (Test-Path -LiteralPath $oldSwap) { Remove-Item -LiteralPath $oldSwap -Recurse -Force }
    }
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("KenshiCoop-install-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $game = Resolve-KenshiRoot $KenshiPath ([bool]$NonInteractive)
    Write-Step "Target Kenshi: $game"

    if ($ArchivePath) {
        $archive = [System.IO.Path]::GetFullPath($ArchivePath)
        $archiveSha = Get-Sha256 $archive
        $release = @{ Path = $archive; Tag = "local archive"; Channel = "local"; Sha256 = $archiveSha }
    } else {
        $release = Get-ReleaseKit $Repository $Tag $Channel $work
    }
    $kit = Expand-AndValidateKit $release.Path $work
    Write-Step "Validated protocol $($kit.Protocol), DLL SHA-256 $($kit.DllSha256)."
    $result = Install-ValidatedMod $kit.Mod $game $BackupRoot

    Write-Host ""
    if ($result.Updated) {
        Write-Host "KenshiCoop installed successfully." -ForegroundColor Green
    } else {
        Write-Host "KenshiCoop is already up to date." -ForegroundColor Green
    }
    Write-Host "  Release: $($release.Tag)"
    Write-Host "  Channel: $($release.Channel)"
    Write-Host "  Archive SHA-256: $($release.Sha256)"
    Write-Host "  Installed at: $($result.Target)"
    if ($result.Backup) { Write-Host "  Previous version backed up to: $($result.Backup)" }
    Write-Host ""
    Write-Host "Launch Kenshi and enable KenshiCoop in the Mods menu."
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
