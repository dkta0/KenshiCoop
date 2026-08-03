[CmdletBinding()]
param([string]$OutDir='')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
if(-not $OutDir){$OutDir=Join-Path $repo 'dist'}
$stage=Join-Path ([IO.Path]::GetTempPath()) ('KenshiCoop-presence-'+[guid]::NewGuid())
$zip=Join-Path $OutDir 'KenshiCoop-presence-companion.zip'
try{
 New-Item -ItemType Directory -Force -Path $stage,$OutDir|Out-Null
 foreach($name in @('KenshiCoop-Presence.cmd','KenshiCoop-Presence.ps1','KenshiCoop.Presence.psm1','DiscordIpc.psm1')){Copy-Item -LiteralPath (Join-Path $repo "companion\$name") -Destination $stage}
 if(Test-Path $zip){Remove-Item $zip -Force}
 Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
 Write-Host "Presence companion built: $zip"
}finally{if(Test-Path $stage){Remove-Item $stage -Recurse -Force}}
