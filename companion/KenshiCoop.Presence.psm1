Set-StrictMode -Version 2
function New-KenshiCoopState { [pscustomobject]@{ Role='offline'; Transport=$null; Protocol=$null; Build=$null; Players=0 } }
function Copy-KenshiCoopState($State) { [pscustomobject]@{ Role=$State.Role; Transport=$State.Transport; Protocol=$State.Protocol; Build=$State.Build; Players=[int]$State.Players } }
function Update-KenshiCoopState($State,[string]$Line) {
    if ($Line -match 'KenshiCoop: build ([A-Z][a-z]{2} +[ 0-9][0-9] 20[0-9]{2}) ([0-9]{2}:[0-9]{2}:[0-9]{2})') { $State.Build="$($Matches[1].Trim()) $($Matches[2])" }
    if ($Line -match 'KenshiCoop: role=(HOST|JOIN) proto=v([0-9]+) ') { $State.Role=$Matches[1].ToLowerInvariant(); $State.Protocol=[int]$Matches[2]; $State.Players=1 }
    if ($Line -match '\[coop-ui\] connect: role=(HOST|JOIN) transport=(steam|udp) ') { $State.Role=$Matches[1].ToLowerInvariant(); $State.Transport=$Matches[2].ToUpperInvariant(); $State.Players=1 }
    elseif ($Line -match '\[net\] transport=steam \(ENet tunnelled over Steam P2P\)') { $State.Transport='STEAM' }
    elseif ($Line -match '\[net\] (hosting|connecting|reconnecting)$' -and -not $State.Transport) { $State.Transport='UDP' }
    if ($Line -match 'handshake: peer present id=[0-9]+ local=[0-9]+ players=([0-9]+)/[0-9]+') { $State.Players=[int]$Matches[1] }
    elseif ($Line -match '\[net\] peer (connected|disconnected) id=[0-9]+ players=([0-9]+)/[0-9]+') { $State.Players=[int]$Matches[2] }
    elseif ($Line -match 'handshake: peer left id=[0-9]+') { $State.Players=[Math]::Max(1,$State.Players-1) }
    elseif ($Line -match 'KenshiCoop: session DEFERRED|\[coop-ui\] disconnect') { $State.Role='offline'; $State.Transport=$null; $State.Players=0 }
    $State
}
function ConvertTo-KenshiCoopActivity($State) {
    $details=if($State.Role -eq 'host'){'Hosting a co-op session'}elseif($State.Role -eq 'join'){'Joined a co-op session'}else{'Offline'}
    $parts=New-Object System.Collections.Generic.List[string]
    if($State.Role -ne 'offline' -and $State.Transport){$parts.Add($State.Transport)}
    if($State.Role -ne 'offline' -and $State.Protocol -ne $null){$parts.Add("Protocol v$($State.Protocol)")}
    if($State.Role -ne 'offline'){$parts.Add("$($State.Players) player"+$(if($State.Players -eq 1){''}else{'s'}))}
    if($State.Build){$parts.Add("Build $($State.Build)")}
    [ordered]@{details=$details;state=($parts -join ' | ');instance=$false}
}
function Test-KenshiCoopActivitySafe($Activity) {
    $json=$Activity|ConvertTo-Json -Compress -Depth 4
    foreach($term in @('76561','\\',':\\','steamapps','.save','token','http://','https://')){if($json.IndexOf($term,[StringComparison]::OrdinalIgnoreCase)-ge 0){return $false}}
    $true
}
function Find-KenshiCoopLog([string[]]$Roots) {
    $files=@(); foreach($root in $Roots){if($root -and (Test-Path -LiteralPath $root)){$files+=@(Get-ChildItem -LiteralPath $root -Filter 'KenshiCoop_*.log' -File -ErrorAction SilentlyContinue)}}
    $files|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
}
function Read-KenshiCoopLogDelta([string]$Path,[long]$Offset) {
    $stream=New-Object IO.FileStream($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{$truncated=$stream.Length -lt $Offset;if($truncated){$Offset=0};[void]$stream.Seek($Offset,[IO.SeekOrigin]::Begin);$reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true,4096,$true)
        try{$lines=@();while(($line=$reader.ReadLine()) -ne $null){$lines+=$line};$next=$stream.Position}finally{$reader.Dispose()}
        [pscustomobject]@{Lines=$lines;Offset=$next;Truncated=$truncated}
    }finally{$stream.Dispose()}
}
Export-ModuleMember -Function New-KenshiCoopState,Copy-KenshiCoopState,Update-KenshiCoopState,ConvertTo-KenshiCoopActivity,Test-KenshiCoopActivitySafe,Find-KenshiCoopLog,Read-KenshiCoopLogDelta
