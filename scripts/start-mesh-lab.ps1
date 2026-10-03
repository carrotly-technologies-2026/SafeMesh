<#
.SYNOPSIS
Build once and launch SafeMesh on three existing local emulators.
.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-mesh-lab.ps1
.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-mesh-lab.ps1 -SkipBuild
.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-mesh-lab.ps1 -RefreshDrill
.NOTES
Requires DEVECO_CLI_STUDIO_PATH, Node, DevEco CLI and three existing emulator instances.
Does not create/download emulators, accept licences, uninstall apps, or change global settings.
The WebSocket hub is a loopback test link; this does not exercise physical NearLink radio.
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$RefreshDrill,
    [ValidatePattern('^[\p{L}\p{N}][\p{L}\p{N} ._-]{0,79}$')]
    [string]$EmulatorA = 'HackYeahPhone',
    [ValidatePattern('^[\p{L}\p{N}][\p{L}\p{N} ._-]{0,79}$')]
    [string]$EmulatorB = 'SafeMeshB',
    [ValidatePattern('^[\p{L}\p{N}][\p{L}\p{N} ._-]{0,79}$')]
    [string]$EmulatorC = 'SafeMeshC',
    [ValidateRange(15, 600)]
    [int]$DeviceTimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($SkipBuild -and $RefreshDrill) {
    throw '-RefreshDrill requires a new build; do not combine it with -SkipBuild.'
}
$requestedNames = @($EmulatorA, $EmulatorB, $EmulatorC)
if (@($requestedNames | Sort-Object -Unique).Count -ne 3) {
    throw 'Choose three different existing emulator names for A, B and C.'
}
if (-not $env:DEVECO_CLI_STUDIO_PATH) {
    throw 'Set DEVECO_CLI_STUDIO_PATH to your DevEco Studio installation before running this script.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$studioRoot = (Resolve-Path -LiteralPath $env:DEVECO_CLI_STUDIO_PATH).Path
$hdcPath = Join-Path $studioRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$cliPath = (Get-Command devecocli.cmd -ErrorAction Stop).Source
$nodePath = (Get-Command node.exe -ErrorAction Stop).Source
$powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$hubScript = Join-Path $PSScriptRoot 'mesh-lab-server.mjs'
foreach ($required in @($hdcPath, $hubScript, $powerShellPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required file missing: $required" }
}
$labCache = Join-Path $projectRoot '.cache\mesh-lab'
$sessionId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$sessionDirectory = Join-Path $labCache $sessionId
[void](New-Item -ItemType Directory -Path $sessionDirectory -Force)
$script:commandNumber = 0

function Invoke-LabCommand {
    param([string]$Executable, [string[]]$Arguments, [string]$Label, [int]$TimeoutSeconds = 60)
    $script:commandNumber++
    $prefix = '{0:D2}-{1}' -f $script:commandNumber, $Label
    $stdoutPath = Join-Path $sessionDirectory ($prefix + '.stdout.log')
    $stderrPath = Join-Path $sessionDirectory ($prefix + '.stderr.log')
    # Argument data is encoded separately from code. No emulator name or path is
    # interpolated into a shell command, and no caller PATH is modified.
    $payload = @{ file = $Executable; arguments = @($Arguments); directory = $projectRoot } | ConvertTo-Json -Compress
    $encodedPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $command = @'
$ErrorActionPreference = 'Stop'
try {
    $call = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__')) | ConvertFrom-Json
    Set-Location -LiteralPath $call.directory
    $arguments = @($call.arguments | ForEach-Object { [string]$_ })
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = 0
    & $call.file @arguments
    exit $LASTEXITCODE
} catch { Write-Error $_; exit 1 }
'@
    $command = $command.Replace('__PAYLOAD__', $encodedPayload)
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    Write-Host "[$Label]"
    $process = Start-Process -FilePath $powerShellPath -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encodedCommand) `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    # Retain the native handle so Windows PowerShell can read ExitCode after exit.
    $processHandle = $process.Handle
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        # Only this command's newly created child tree is stopped on timeout.
        & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID $process.Id /T /F *> $null
        throw "$Label exceeded ${TimeoutSeconds}s. Logs: $sessionDirectory"
    }
    $process.WaitForExit()
    $output = [string](Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue)
    $errorOutput = [string](Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue)
    $exitCode = $process.ExitCode
    if ($exitCode -ne 0) {
        if ($Label -like 'start-emulator*') {
            throw "$Label failed ($exitCode). Check the logs and accept any required emulator licence yourself in DevEco/CLI. This script never accepts agreements. Logs: $sessionDirectory"
        }
        throw "$Label failed ($exitCode). Logs: $sessionDirectory"
    }
    return [pscustomobject]@{ Output = $output; ErrorOutput = $errorOutput; ExitCode = $exitCode }
}

function Read-CliArray {
    param([string[]]$Arguments, [string]$Label, [int]$TimeoutSeconds = 30)
    $result = Invoke-LabCommand $cliPath $Arguments $Label $TimeoutSeconds
    try {
        $json = $result.Output -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
        $parsed = ConvertFrom-Json -InputObject $json
        return @($parsed)
    } catch { throw "$Label did not return valid JSON. Logs: $sessionDirectory" }
}

function Test-HubPort {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $connect = $client.ConnectAsync('127.0.0.1', 8765)
        return ($connect.Wait(1000) -and $client.Connected)
    } catch { return $false }
    finally { $client.Dispose() }
}

function Read-HubState {
    # Redirects and proxies are disabled: health checks remain on loopback.
    $request = [Net.HttpWebRequest]::Create('http://127.0.0.1:8765/state')
    $request.Proxy = $null
    $request.AllowAutoRedirect = $false
    $request.Timeout = 2000
    $request.ReadWriteTimeout = 2000
    $response = $null
    $reader = $null
    try {
        $response = $request.GetResponse()
        if ([int]$response.StatusCode -ne 200) { throw 'Unexpected HTTP status' }
        $reader = New-Object IO.StreamReader($response.GetResponseStream())
        $buffer = New-Object char[] 65537
        $length = $reader.ReadBlock($buffer, 0, $buffer.Length)
        if ($length -gt 65536) { throw 'Oversized hub state' }
        $state = ConvertFrom-Json -InputObject (-join $buffer[0..($length - 1)])
        if ($state.protocol -ne 1 -or $state.transport -ne 'local-emulator-websocket' -or
            $state.host -ne '127.0.0.1' -or $state.port -ne 8765 -or $state.limits.clients -ne 3) {
            throw 'Unexpected service identity'
        }
        return $state
    } catch {
        throw 'Port 8765 is occupied by an invalid or unavailable SafeMesh hub. Inspect that service; the launcher will not replace or stop it.'
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
    }
}

function Start-OrReuseHub {
    if (Test-HubPort) {
        $state = Read-HubState
        @{ reused = $true; pid = $null; url = 'http://127.0.0.1:8765/state' } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $sessionDirectory 'hub-session.json') -Encoding UTF8
        Write-Host 'Reusing the existing verified loopback hub; its current test controls are preserved.'
        return $state
    }
    $stdoutPath = Join-Path $sessionDirectory 'hub.stdout.log'
    $stderrPath = Join-Path $sessionDirectory 'hub.stderr.log'
    $hubProcess = Start-Process -FilePath $nodePath -ArgumentList @(('"{0}"' -f $hubScript)) `
        -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $hubProcess.Id | Set-Content -LiteralPath (Join-Path $labCache 'hub.pid') -Encoding ASCII
    @{ reused = $false; pid = $hubProcess.Id; url = 'http://127.0.0.1:8765/state';
        stdout = $stdoutPath; stderr = $stderrPath } | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $sessionDirectory 'hub-session.json') -Encoding UTF8
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($hubProcess.HasExited) { throw "Local hub exited ($($hubProcess.ExitCode)). Logs: $sessionDirectory" }
        if (Test-HubPort) { return Read-HubState }
        Start-Sleep -Milliseconds 200
    }
    throw "Local hub did not become ready in 10 seconds. Its PID and logs are in $sessionDirectory"
}

Push-Location -LiteralPath $projectRoot
try {
    Write-Host 'SafeMesh: three emulator apps over a local test link (not physical NearLink).'
    Write-Host "Logs: $sessionDirectory"
    $instances = @(Read-CliArray @('emulator', 'list', '--format', 'json') 'emulator-list')
    foreach ($name in $requestedNames) {
        $matchingInstances = @($instances | Where-Object { $_.name -eq $name })
        if ($matchingInstances.Count -ne 1) {
            throw "Expected exactly one existing emulator named '$name'. Create/select it in DevEco first; this script does not create or download images."
        }
    }
    # Reject an unrelated listener before building or changing any running app.
    if (Test-HubPort) { [void](Read-HubState) }
    if ($RefreshDrill) {
        [void](Invoke-LabCommand $nodePath @((Join-Path $PSScriptRoot 'generate-demo-alerts.mjs')) 'refresh-drill' 30)
    }
    if (-not $SkipBuild) {
        $build = Invoke-LabCommand $cliPath @('build', '--modules', 'entry', '--build-mode', 'debug') 'build' 600
        if (($build.Output + $build.ErrorOutput) -notmatch 'BUILD SUCCESSFUL|Build completed successfully') {
            throw "Build exited without a success marker. Logs: $sessionDirectory"
        }
        Write-Host 'DEVECOCLI_BUILD_EXIT_CODE=0'
    }
    $toStart = @($instances | Where-Object { $_.name -in $requestedNames -and $_.status -ne 'running' } |
        ForEach-Object { [string]$_.name })
    if ($toStart.Count -gt 0) {
        [void](Invoke-LabCommand $cliPath (@('emulator', 'start') + $toStart) 'start-emulators' 120)
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($DeviceTimeoutSeconds)
    $mapping = @()
    do {
        $remaining = [Math]::Max(1, [int][Math]::Ceiling(($deadline - [DateTime]::UtcNow).TotalSeconds))
        $devices = @(Read-CliArray @('device', 'list', '--format', 'json') 'device-list' ([Math]::Min(20, $remaining)))
        $mapping = @()
        for ($index = 0; $index -lt $requestedNames.Count; $index++) {
            $matchingDevices = @($devices | Where-Object { $_.name -eq $requestedNames[$index] -and $_.kind -eq 'emulator' })
            if ($matchingDevices.Count -gt 1) { throw "Ambiguous connected emulator: $($requestedNames[$index])" }
            if ($matchingDevices.Count -eq 1 -and $matchingDevices[0].serial -match '^127\.0\.0\.1:\d+$') {
                $mapping += [pscustomobject]@{
                    Node = @('A', 'B', 'C')[$index]; Name = $requestedNames[$index]
                    Serial = $matchingDevices[0].serial; RemotePort = 8765 + $index
                }
            }
        }
        if ($mapping.Count -eq 3) { break }
        if ([DateTime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Milliseconds 1000
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($mapping.Count -ne 3) {
        throw "Not all three named emulators connected within ${DeviceTimeoutSeconds}s. Open DevEco Device Manager and inspect their startup. Logs: $sessionDirectory"
    }
    if (@($mapping.Serial | Sort-Object -Unique).Count -ne 3) { throw 'Emulator names resolved to duplicate device serials.' }
    $mapping | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $sessionDirectory 'devices.json') -Encoding UTF8

    $state = Start-OrReuseHub
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $sessionDirectory 'hub-state.json') -Encoding UTF8
    foreach ($device in $mapping) {
        # DevEco CLI has no reverse-port wrapper. SDK hdc help documents
        # rport <remote> <local> and fport ls; no unrelated mapping is removed.
        # Distinct remote ports avoid hdc reverse-task collisions between emulators.
        # EmulatorTransport selects A=8765, B=8766, C=8767; all reach host port 8765.
        $remoteEndpoint = 'tcp:' + $device.RemotePort
        $pattern = '(?m)^\s*' + [Regex]::Escape($device.Serial) + '\s+' +
            [Regex]::Escape($remoteEndpoint) + '\s+tcp:8765\s+\[Reverse\]\s*$'
        $ports = Invoke-LabCommand $hdcPath @('-t', $device.Serial, 'fport', 'ls') ('ports-' + $device.Node) 20
        if ($ports.Output -notmatch $pattern) {
            [void](Invoke-LabCommand $hdcPath @('-t', $device.Serial, 'rport', $remoteEndpoint, 'tcp:8765') ('rport-' + $device.Node) 20)
            $ports = Invoke-LabCommand $hdcPath @('-t', $device.Serial, 'fport', 'ls') ('verify-rport-' + $device.Node) 20
            if ($ports.Output -notmatch $pattern) { throw "Reverse port was not confirmed for node $($device.Node). Logs: $sessionDirectory" }
        }
        $run = Invoke-LabCommand $cliPath @('run', '--skip-build', '--module', 'entry', '--device', $device.Serial) ('run-' + $device.Node) 120
        if (($run.Output + $run.ErrorOutput) -notmatch 'Smoke:\s*PASS') {
            throw "Node $($device.Node) did not report Smoke: PASS. Logs: $sessionDirectory"
        }
        Write-Host "Node $($device.Node): installed and launched on $($device.Name) [$($device.Serial)]."
    }

    Write-Host ($mapping | Format-Table -AutoSize | Out-String)
    $currentLinks = @($state.links | ForEach-Object { @($_) -join '-' } | Sort-Object)
    Write-Host ('Hub links: ' + ($currentLinks -join ', '))
    if (($currentLinks -join ',') -ne 'A-B,B-C' -or @($state.dropNext).Count -gt 0) {
        Write-Warning 'The reused hub has custom topology or pending packet-loss controls. Inspect GET /state before the demo.'
    }
    Write-Host 'On each emulator: open Relay / Lacznosc, choose the emulator test link, then select its A/B/C role.'
    Write-Host 'Start A and B. Load a signed drill on A and share it. Start C later to test forwarding from B.'
    Write-Host 'The hub stays running on 127.0.0.1:8765. This launcher does not click UI controls or clear app data.'
    Write-Host "MESH_LAB_READY=1 | Logs: $sessionDirectory"
} finally { Pop-Location }
