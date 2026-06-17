Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$BinDir = Join-Path $Root "bin"
$Daemon = Join-Path $BinDir "daemon.exe"
$AgentdVersion = "v0.3.0-alpha"
$ReleaseUrl = "https://github.com/podofun/agent.d/releases/download/$AgentdVersion/agentd-x86_64-windows.zip"

function Install-Agentd {
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

    $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    $Archive = Join-Path $TempDir "agentd-windows.zip"

    try {
        New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

        Write-Host "Downloading agent.d $AgentdVersion..."
        Invoke-WebRequest -Uri $ReleaseUrl -OutFile $Archive

        Expand-Archive -Path $Archive -DestinationPath $TempDir -Force

        Copy-Item -Force (Join-Path $TempDir "daemon.exe") (Join-Path $BinDir "daemon.exe")
        Copy-Item -Force (Join-Path $TempDir "agentctl.exe") (Join-Path $BinDir "agentctl.exe")
    } finally {
        if (Test-Path $TempDir) {
            Remove-Item -Recurse -Force $TempDir
        }
    }
}

if (-not (Test-Path $Daemon)) {
    Install-Agentd
}

$DaemonArgs = @(
    "--init", (Join-Path $Root "agents\init.lua"),
    "--grants-file", (Join-Path $Root "agents\grants.toml"),
    "--trace-file", (Join-Path $Root "agentd-trace.jsonl"),
    "--addr", "127.0.0.1:7777",
    "--no-auth"
)

& $Daemon @DaemonArgs
exit $LASTEXITCODE
