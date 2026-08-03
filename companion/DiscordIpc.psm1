Set-StrictMode -Version 2

function New-DiscordIpcAdapter([string]$ClientId) {
    if ($ClientId -notmatch '^[0-9]{10,24}$') { throw 'Discord ClientId must contain 10-24 decimal digits.' }
    [pscustomobject]@{ ClientId = $ClientId; Pipe = $null; Sequence = 0 }
}

function Write-DiscordFrame($Adapter, [int]$Opcode, $Payload) {
    $json = $Payload | ConvertTo-Json -Compress -Depth 8
    $body = [Text.Encoding]::UTF8.GetBytes($json)
    $header = New-Object byte[] 8
    [BitConverter]::GetBytes([int]$Opcode).CopyTo($header, 0)
    [BitConverter]::GetBytes([int]$body.Length).CopyTo($header, 4)
    $Adapter.Pipe.Write($header, 0, 8); $Adapter.Pipe.Write($body, 0, $body.Length); $Adapter.Pipe.Flush()
}

function Connect-DiscordIpc($Adapter) {
    Disconnect-DiscordIpc $Adapter
    for ($i = 0; $i -lt 10; $i++) {
        $pipe = New-Object IO.Pipes.NamedPipeClientStream('.', "discord-ipc-$i", [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::None)
        try {
            $pipe.Connect(100)
            $Adapter.Pipe = $pipe
            Write-DiscordFrame $Adapter 0 ([ordered]@{ v = 1; client_id = $Adapter.ClientId })
            return $true
        } catch { $pipe.Dispose() }
    }
    return $false
}

function Disconnect-DiscordIpc($Adapter) {
    if ($Adapter.Pipe) { try { $Adapter.Pipe.Dispose() } catch {}; $Adapter.Pipe = $null }
}

function Set-DiscordPresence($Adapter, $Activity) {
    if (-not $Adapter.Pipe -or -not $Adapter.Pipe.IsConnected) { if (-not (Connect-DiscordIpc $Adapter)) { return $false } }
    $Adapter.Sequence++
    try {
        Write-DiscordFrame $Adapter 1 ([ordered]@{
            cmd = 'SET_ACTIVITY'
            args = [ordered]@{ pid = $PID; activity = $Activity }
            nonce = "$PID-$($Adapter.Sequence)"
        })
        return $true
    } catch { Disconnect-DiscordIpc $Adapter; return $false }
}

Export-ModuleMember -Function New-DiscordIpcAdapter,Connect-DiscordIpc,Disconnect-DiscordIpc,Set-DiscordPresence
