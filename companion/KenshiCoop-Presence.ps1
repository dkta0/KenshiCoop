[CmdletBinding()]
param([string]$ClientId=$env:KENSHICOOP_DISCORD_CLIENT_ID,[string[]]$LogRoot=@(),[switch]$FakeDiscord,[switch]$Once,[int]$PollMilliseconds=1000)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'KenshiCoop.Presence.psm1') -Force
if(-not $FakeDiscord){Import-Module (Join-Path $PSScriptRoot 'DiscordIpc.psm1') -Force}
if(-not $ClientId -and -not $FakeDiscord){throw 'Set KENSHICOOP_DISCORD_CLIENT_ID or pass -ClientId. This public application ID is not a secret.'}
if($LogRoot.Count -eq 0){$LogRoot=@((Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\common\Kenshi'),(Join-Path $env:USERPROFILE 'Kenshi-Join'),(Get-Location).Path)}
$adapter=if($FakeDiscord){$null}else{New-DiscordIpcAdapter $ClientId};$state=New-KenshiCoopState;$currentPath=$null;[long]$offset=0;$lastActivity=''
Write-Host 'KenshiCoop Discord presence companion started. Close this window to stop.'
try{do{
    $log=Find-KenshiCoopLog $LogRoot
    if($log){
        if($currentPath -ne $log.FullName){$currentPath=$log.FullName;$offset=0;$state=New-KenshiCoopState}
        $delta=Read-KenshiCoopLogDelta $currentPath $offset
        if($delta.Truncated){$state=New-KenshiCoopState}
        $offset=$delta.Offset;foreach($line in $delta.Lines){[void](Update-KenshiCoopState $state $line)}
    }elseif($currentPath){$currentPath=$null;$offset=0;$state=New-KenshiCoopState}
    $activity=ConvertTo-KenshiCoopActivity $state
    if(-not(Test-KenshiCoopActivitySafe $activity)){throw 'Presence safety check rejected generated activity.'}
    $json=$activity|ConvertTo-Json -Compress -Depth 4
    if($json -ne $lastActivity){if($FakeDiscord){Write-Output $json}elseif(-not(Set-DiscordPresence $adapter $activity)){Write-Warning 'Discord is unavailable; retrying.'};$lastActivity=$json}
    elseif(-not $FakeDiscord -and(-not $adapter.Pipe -or -not $adapter.Pipe.IsConnected)){[void](Set-DiscordPresence $adapter $activity)}
    if(-not $Once){Start-Sleep -Milliseconds $PollMilliseconds}
}while(-not $Once)}finally{if(-not $FakeDiscord -and $adapter){Disconnect-DiscordIpc $adapter}}
