$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'KenshiCoop.Presence.psm1') -Force
$script:passed=0
function Assert-Equal($Actual,$Expected,[string]$Name){if("$Actual" -ne "$Expected"){throw "$Name expected '$Expected', got '$Actual'"};$script:passed++}
function Assert-True($Value,[string]$Name){if(-not $Value){throw "$Name expected true"};$script:passed++}

$s=New-KenshiCoopState
@(
'[2026-08-03 12:00:00.000] [HOST] INFO KenshiCoop: build Aug  3 2026 11:59:01',
'[2026-08-03 12:00:00.001] [HOST] INFO KenshiCoop: role=HOST proto=v45 port=27800 save=''private-save''',
'[2026-08-03 12:00:00.002] [HOST] INFO [coop-ui] connect: role=HOST transport=steam peer=76561198000000000 ownRanks={0} src=role',
'[2026-08-03 12:00:01.000] [HOST] INFO handshake: peer present id=2 local=0 players=3/8',
'[2026-08-03 12:00:02.000] [HOST] INFO unknown ip=203.0.113.8 token=secret path=C:\Users\private save=private-save'
)|ForEach-Object{[void](Update-KenshiCoopState $s $_)}
Assert-Equal $s.Role 'host' 'host role';Assert-Equal $s.Transport 'STEAM' 'transport';Assert-Equal $s.Protocol 45 'protocol';Assert-Equal $s.Players 3 'players'
$a=ConvertTo-KenshiCoopActivity $s;$json=$a|ConvertTo-Json -Compress
Assert-True (Test-KenshiCoopActivitySafe $a) 'generated activity safety'
Assert-True (-not($json -match '76561|203\.0\.113|private-save|Users|secret')) 'redaction allowlist'
[void](Update-KenshiCoopState $s '[x] [HOST] INFO handshake: peer left id=2');Assert-Equal $s.Players 2 'departure'
[void](Update-KenshiCoopState $s '[x] [HOST] INFO [coop-ui] disconnect');Assert-Equal $s.Role 'offline' 'offline';Assert-Equal $s.Players 0 'offline players'

$temp=Join-Path ([IO.Path]::GetTempPath()) ('kenshicoop-presence-'+[guid]::NewGuid())
New-Item -ItemType Directory $temp|Out-Null
try{
 $one=Join-Path $temp 'KenshiCoop_host.log';[IO.File]::WriteAllText($one,"one`r`n",[Text.Encoding]::UTF8);$d=Read-KenshiCoopLogDelta $one 0;Assert-Equal $d.Lines.Count 1 'initial tail'
 [IO.File]::AppendAllText($one,"two`r`n",[Text.Encoding]::UTF8);$d2=Read-KenshiCoopLogDelta $one $d.Offset;Assert-Equal $d2.Lines[0] 'two' 'append tail'
 [IO.File]::WriteAllText($one,"x`r`n",[Text.Encoding]::UTF8);$d3=Read-KenshiCoopLogDelta $one $d2.Offset;Assert-True $d3.Truncated 'truncation'
 Start-Sleep -Milliseconds 20;$two=Join-Path $temp 'KenshiCoop_join.log';[IO.File]::WriteAllText($two,'new',[Text.Encoding]::UTF8);Assert-Equal (Find-KenshiCoopLog @($temp)).Name 'KenshiCoop_join.log' 'rotation'
 $smoke=& (Join-Path $PSScriptRoot 'KenshiCoop-Presence.ps1') -FakeDiscord -Once -LogRoot $temp|Select-Object -Last 1
 Assert-True ($smoke -match '"details"') 'fake adapter smoke'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
Write-Host "COMPANION TESTS PASS ($script:passed assertions)"
