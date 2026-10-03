<#
.SYNOPSIS
Prepare and launch the local exercise issuer plus three SafeMesh emulators.
.DESCRIPTION
Reuses the private key in .cache/demo-authority; never rotates it. A missing or
different app public pin is explicitly adopted and always forces a build.
Existing matching keys leave the bundled fixtures untouched. Private material
and the operator token are never printed or passed in process arguments.
.PARAMETER SkipBuild
Requests reuse of a HAP previously built by this helper. Reuse requires a matching
public-pin/app-version build receipt and an unchanged HAP hash. Otherwise a full
build runs, including after first preparation or a pin change.
.PARAMETER EmulatorA
Existing issuer emulator name, resolved to exactly one local emulator serial.
Only this device receives reverse port 8768. Choosing role A alone does not
authorize publication.
.PARAMETER EmulatorB
Existing recipient emulator name, passed to start-mesh-lab.ps1.
.PARAMETER EmulatorC
Existing recipient emulator name, passed to start-mesh-lab.ps1.
.PARAMETER DeviceTimeoutSeconds
How long the mesh launcher waits for the three named devices (15 to 600 seconds).
.EXAMPLE
$env:DEVECO_CLI_STUDIO_PATH = 'C:\Users\user\DevEcoStudio'
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-authority-demo.ps1
.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-authority-demo.ps1 -SkipBuild
.NOTES
Requires Windows, Node, DevEco CLI and three existing emulator instances. Delegates
build/deployment to start-mesh-lab.ps1. Does not click UI, rotate keys, accept
licences, clear app data, kill existing services or change global settings.
This is a local exercise signing station, not a production authority identity.
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
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
$projectRoot = Split-Path -Parent $PSScriptRoot
if (@(@($EmulatorA, $EmulatorB, $EmulatorC) | Sort-Object -Unique).Count -ne 3) {
    throw 'Choose three different existing emulator names.'
}
if (-not $env:DEVECO_CLI_STUDIO_PATH) { throw 'Set DEVECO_CLI_STUDIO_PATH to your DevEco Studio installation.' }
$studioRoot = (Resolve-Path -LiteralPath $env:DEVECO_CLI_STUDIO_PATH).Path
$nodePath = (Get-Command node.exe -ErrorAction Stop).Source
$cliPath = (Get-Command devecocli.cmd -ErrorAction Stop).Source
$powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$hdcPath = Join-Path $studioRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$authorityScript = Join-Path $PSScriptRoot 'demo-authority-server.mjs'
$prepareScript = Join-Path $PSScriptRoot 'prepare-demo-authority.mjs'
$generatorScript = Join-Path $PSScriptRoot 'generate-demo-alerts.mjs'
$meshScript = Join-Path $PSScriptRoot 'start-mesh-lab.ps1'
foreach ($required in @($powerShellPath, $hdcPath, $authorityScript, $prepareScript, $generatorScript, $meshScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required file missing: $required" }
}
$authorityDirectory = Join-Path $projectRoot '.cache\demo-authority'
$authorityFile = Join-Path $authorityDirectory 'authority.json'
$tokenPath = Join-Path $authorityDirectory 'session-token.txt'
$pinPath = Join-Path $projectRoot 'entry\src\main\ets\model\DemoTrust.ets'
$appMetadataPath = Join-Path $projectRoot 'AppScope\app.json5'
$hapPath = Join-Path $projectRoot 'entry\build\default\outputs\default\entry-default-unsigned.hap'
$buildReceiptPath = Join-Path $authorityDirectory 'authority-build.json'
$sessionDirectory = Join-Path $authorityDirectory ('launcher-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
[void](New-Item -ItemType Directory -Path $sessionDirectory -Force)
$script:authorityCommandNumber = 0

function Invoke-AuthorityCommand {
    param([string]$Executable, [string[]]$Arguments, [string]$Label, [int]$TimeoutSeconds = 30)
    $script:authorityCommandNumber++
    $prefix = '{0:D2}-{1}' -f $script:authorityCommandNumber, $Label
    $stdoutPath = Join-Path $sessionDirectory ($prefix + '.stdout.log')
    $stderrPath = Join-Path $sessionDirectory ($prefix + '.stderr.log')
    # Arguments are serialized data, never interpolated PowerShell code. This
    # wrapper also keeps CLI spinners on stderr from becoming terminating errors.
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
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command.Replace('__PAYLOAD__', $encodedPayload)))
    Write-Host "[$Label]"
    $process = Start-Process -FilePath $powerShellPath -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encodedCommand) `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $processHandle = $process.Handle
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        # Stop only this newly created command's child tree, never an existing daemon.
        & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID $process.Id /T /F *> $null
        throw "$Label exceeded ${TimeoutSeconds}s. Logs: $sessionDirectory"
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "$Label failed ($($process.ExitCode)). Logs: $sessionDirectory" }
    return [string](Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue)
}

function Read-AuthorityPublicMetadata {
    try {
        if ((Get-Item -LiteralPath $authorityFile).Length -gt 16384) { throw 'Oversized local metadata' }
        $local = Get-Content -LiteralPath $authorityFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($local.protocol -ne 1 -or $local.keyId -cne 'safemesh-demo-authority-v1' -or
            $local.publicKeyDer -cnotmatch '^[A-Za-z0-9+/]{100,200}={0,2}$') { throw 'Invalid local metadata' }
        # prepare-demo-authority validates the private key. Only public fields
        # leave this function, and exceptions never include the JSON contents.
        return [pscustomobject]@{ KeyId = [string]$local.keyId; PublicKeyDer = [string]$local.publicKeyDer }
    } catch { throw 'Unable to read valid local authority public metadata; private contents were not printed.' }
}

function Test-AuthorityPin {
    param($Metadata)
    if (-not (Test-Path -LiteralPath $pinPath -PathType Leaf)) { return $false }
    $source = Get-Content -LiteralPath $pinPath -Raw -Encoding UTF8
    $keyId = [regex]::Match($source, 'DEMO_KEY_ID\s*:\s*string\s*=\s*"([^"]+)"')
    $publicKey = [regex]::Match($source, 'DEMO_PUBLIC_KEY_DER\s*:\s*string\s*=\s*"([^"]+)"')
    return ($keyId.Success -and $publicKey.Success -and $keyId.Groups[1].Value -ceq $Metadata.KeyId -and
        $publicKey.Groups[1].Value -ceq $Metadata.PublicKeyDer)
}

function Find-AuthorityListener {
    $listeners = @(Get-NetTCPConnection -LocalPort 8768 -State Listen -ErrorAction SilentlyContinue)
    if ($listeners.Count -eq 0) { return $null }
    if (@($listeners | Where-Object { $_.LocalAddress -ne '127.0.0.1' }).Count -gt 0 -or
        @($listeners.OwningProcess | Sort-Object -Unique).Count -ne 1) {
        throw 'Port 8768 has an unexpected listener or a non-loopback binding; no service was stopped.'
    }
    $listenerPid = [int]$listeners[0].OwningProcess
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $listenerPid" -ErrorAction Stop
    $commandPattern = '(?i)(?:^|\s)"?(?:' + [regex]::Escape($authorityScript) +
        '|(?:\.[\\/])?scripts[\\/]demo-authority-server\.mjs)"?\s*$'
    if ($null -eq $process -or $process.ExecutablePath -ine $nodePath -or $process.CommandLine -notmatch $commandPattern) {
        throw 'Port 8768 is owned by an unrecognized process; it was not contacted with an operator credential or stopped.'
    }
    return $listenerPid
}

function Read-AuthorityResponse {
    param([string]$Path, [string]$Token = '')
    $request = [Net.HttpWebRequest]::Create('http://127.0.0.1:8768' + $Path)
    $request.Proxy = $null
    $request.AllowAutoRedirect = $false
    $request.Timeout = 2000
    $request.ReadWriteTimeout = 2000
    if ($Token.Length -gt 0) { $request.Headers.Add('Authorization', 'Bearer ' + $Token) }
    $response = $null
    $reader = $null
    try {
        $response = $request.GetResponse()
        if ([int]$response.StatusCode -ne 200) { throw 'Unexpected status' }
        $reader = New-Object IO.StreamReader($response.GetResponseStream())
        $buffer = New-Object char[] 4097
        $length = $reader.ReadBlock($buffer, 0, $buffer.Length)
        if ($length -lt 1 -or $length -gt 4096) { throw 'Invalid response size' }
        return (ConvertFrom-Json -InputObject (-join $buffer[0..($length - 1)]))
    } catch { throw 'Authority health/session verification failed. No credentials or HTTP response contents were printed.' }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
    }
}

function Confirm-AuthorityService {
    param($Metadata)
    $listenerPid = Find-AuthorityListener
    if ($null -eq $listenerPid) { throw 'No authority service is listening on loopback port 8768.' }
    $health = Read-AuthorityResponse '/health'
    if ($health.service -cne 'safemesh-demo-authority' -or $health.protocol -ne 1 -or $health.exerciseOnly -ne $true) {
        throw 'Port 8768 did not identify the expected exercise service.'
    }
    $token = ''
    try {
        if ((Get-Item -LiteralPath $tokenPath).Length -gt 128) { throw 'Invalid token file size' }
        $token = (Get-Content -LiteralPath $tokenPath -Raw -Encoding UTF8).Trim()
        if ($token -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid token file format' }
        $session = Read-AuthorityResponse '/session' $token
        if ($session.service -cne 'safemesh-demo-authority' -or $session.protocol -ne 1 -or
            $session.exerciseOnly -ne $true -or $session.authorized -ne $true -or
            $session.keyId -cne $Metadata.KeyId -or $session.publicKeyDer -cne $Metadata.PublicKeyDer -or
            $session.expiresInMinutes.min -ne 15 -or $session.expiresInMinutes.max -ne 1440) {
            throw 'Session public identity mismatch'
        }
    } catch { throw 'Existing authority does not match the prepared local key/token. Inspect its private cache; this script will not replace or stop it.' }
    finally { $token = '' }
    return $listenerPid
}

function Start-OrReuseAuthority {
    param($Metadata)
    $listenerPid = Find-AuthorityListener
    if ($null -ne $listenerPid) {
        $listenerPid = Confirm-AuthorityService $Metadata
        Write-Host 'Reusing the verified local exercise authority.'
    } else {
        $stdoutPath = Join-Path $sessionDirectory 'authority.stdout.log'
        $stderrPath = Join-Path $sessionDirectory 'authority.stderr.log'
        $process = Start-Process -FilePath $nodePath -ArgumentList @(('"{0}"' -f $authorityScript)) `
            -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $process.Id | Set-Content -LiteralPath (Join-Path $authorityDirectory 'server.pid') -Encoding ASCII
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        do {
            if ($process.HasExited) { throw "Authority process exited. Logs: $sessionDirectory" }
            $listenerPid = Find-AuthorityListener
            if ($null -ne $listenerPid) {
                if ($listenerPid -ne $process.Id) { throw 'Another process claimed port 8768 during startup; no process was stopped.' }
                $listenerPid = Confirm-AuthorityService $Metadata
                break
            }
            Start-Sleep -Milliseconds 200
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($null -eq $listenerPid) { throw "Authority did not become ready. Inspect server.pid and $sessionDirectory" }
    }
    $listenerPid | Set-Content -LiteralPath (Join-Path $authorityDirectory 'server.pid') -Encoding ASCII
    @{ service = 'safemesh-demo-authority'; protocol = 1; pid = $listenerPid; host = '127.0.0.1'; port = 8768 } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $sessionDirectory 'authority-session.json') -Encoding UTF8
}

function Resolve-AuthorityDevices {
    param([string]$DeviceOutput, [string[]]$Names)
    if ($Names.Count -ne 3 -or @($Names | Sort-Object -Unique).Count -ne 3) {
        throw 'Choose three different existing emulator names.'
    }
    try {
        # Windows PowerShell 5 emits a JSON array as one pipeline object. Assign
        # it first, then enumerate the resulting array; wrapping the pipeline in
        # @() directly would leave a nested array and match every device at once.
        $decoded = ConvertFrom-Json -InputObject ($DeviceOutput -replace '\x1B\[[0-?]*[ -/]*[@-~]', '')
        if ($decoded -isnot [Array]) { throw 'Expected a device array' }
        $devices = @($decoded)
        foreach ($device in $devices) {
            if ($device -isnot [pscustomobject] -or $device.name -isnot [string] -or
                $device.kind -isnot [string] -or $device.serial -isnot [string]) {
                throw 'Invalid device record'
            }
        }
    } catch { throw 'Device inspection did not return a valid flat device array.' }
    $selected = @()
    foreach ($name in $Names) {
        $matching = @($devices | Where-Object { $_.name -ceq $name -and $_.kind -eq 'emulator' })
        if ($matching.Count -ne 1 -or $matching[0].serial -notmatch '^127\.0\.0\.1:\d+$') {
            throw 'Expected exactly one connected local emulator per requested name. No authority reverse port was created.'
        }
        $selected += $matching[0]
    }
    if ($selected.Count -ne 3 -or @($selected.serial | Sort-Object -Unique).Count -ne 3) {
        throw 'Requested emulator names resolved to duplicate serials. No authority reverse port was created.'
    }
    return $selected
}

Push-Location -LiteralPath $projectRoot
try {
    Write-Host "SafeMesh local exercise authority launcher. Logs: $sessionDirectory"
    $existingListener = Find-AuthorityListener
    if ($null -ne $existingListener -and -not (Test-Path -LiteralPath $authorityFile -PathType Leaf)) {
        throw 'An authority is running but its local credential file is missing. Existing services and keys were not replaced.'
    }
    [void](Invoke-AuthorityCommand $nodePath @($prepareScript) 'prepare-authority')
    $metadata = Read-AuthorityPublicMetadata
    if ($null -ne $existingListener) { [void](Confirm-AuthorityService $metadata) }
    $pinChanged = -not (Test-AuthorityPin $metadata)
    if ($pinChanged) {
        Write-Host 'Adopting the local exercise public key and forcing a new app build.'
        [void](Invoke-AuthorityCommand $nodePath @($generatorScript, '--update-public-key') 'adopt-public-pin')
        if (-not (Test-AuthorityPin $metadata)) { throw 'Generated app pin does not match the prepared authority.' }
    }
    $pinHash = (Get-FileHash -LiteralPath $pinPath -Algorithm SHA256).Hash
    $metadataHash = (Get-FileHash -LiteralPath $appMetadataPath -Algorithm SHA256).Hash
    $canSkipBuild = $false
    if ($SkipBuild -and -not $pinChanged -and (Test-Path -LiteralPath $buildReceiptPath -PathType Leaf) -and
        (Test-Path -LiteralPath $hapPath -PathType Leaf)) {
        try {
            $receipt = Get-Content -LiteralPath $buildReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $canSkipBuild = ($receipt.protocol -eq 1 -and $receipt.pinSha256 -eq $pinHash -and
                $receipt.appMetadataSha256 -eq $metadataHash -and
                $receipt.hapSha256 -eq (Get-FileHash -LiteralPath $hapPath -Algorithm SHA256).Hash)
        } catch { $canSkipBuild = $false }
    }
    if ($SkipBuild -and -not $canSkipBuild) { Write-Host 'SkipBuild cannot confirm this HAP uses the current key/version; a full build will run.' }
    $meshArguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $meshScript,
        '-EmulatorA', $EmulatorA, '-EmulatorB', $EmulatorB, '-EmulatorC', $EmulatorC,
        '-DeviceTimeoutSeconds', [string]$DeviceTimeoutSeconds)
    if ($canSkipBuild) { $meshArguments += '-SkipBuild' }
    $meshOutput = Invoke-AuthorityCommand $powerShellPath $meshArguments 'mesh-build-deploy' (1200 + $DeviceTimeoutSeconds)
    # Includes the reused hub's topology/loss-control warning. The delegated
    # mesh launcher never receives the authority key or operator credential.
    Write-Host $meshOutput
    if ($meshOutput -notmatch 'MESH_LAB_READY=1') { throw "Mesh launcher did not report readiness. Logs: $sessionDirectory" }
    if (-not (Test-AuthorityPin $metadata) -or $pinHash -ne (Get-FileHash -LiteralPath $pinPath -Algorithm SHA256).Hash -or
        $metadataHash -ne (Get-FileHash -LiteralPath $appMetadataPath -Algorithm SHA256).Hash) {
        throw 'App pin or version changed while building; repeat the launcher to build consistent sources.'
    }
    @{ protocol = 1; pinSha256 = $pinHash; appMetadataSha256 = $metadataHash;
        hapSha256 = (Get-FileHash -LiteralPath $hapPath -Algorithm SHA256).Hash } | ConvertTo-Json |
        Set-Content -LiteralPath $buildReceiptPath -Encoding UTF8

    $deviceOutput = Invoke-AuthorityCommand $cliPath @('device', 'list', '--format', 'json') 'verify-devices'
    $selectedDevices = @(Resolve-AuthorityDevices $deviceOutput @($EmulatorA, $EmulatorB, $EmulatorC))
    $issuerDevice = [string]$selectedDevices[0].serial
    # Inspect all three target devices before granting A. Existing unexpected
    # authority grants cause a failure; the helper never removes other mappings.
    foreach ($device in $selectedDevices) {
        $serial = [string]$device.serial
        $ports = Invoke-AuthorityCommand $hdcPath @('-t', $serial, 'fport', 'ls') ('inspect-authority-ports-' + $device.name)
        $grants = [regex]::Matches($ports, '(?m)^\s*(\S+)\s+(tcp:\d+)\s+(tcp:\d+)\s+\[Reverse\]\s*$')
        foreach ($grant in $grants) {
            if ($grant.Groups[3].Value -eq 'tcp:8768' -and
                ($grant.Groups[1].Value -ne $issuerDevice -or $grant.Groups[2].Value -ne 'tcp:8768')) {
                throw 'An unexpected reverse mapping already grants authority access. Inspect it manually; no mapping was removed.'
            }
            if ($grant.Groups[1].Value -eq $issuerDevice -and $grant.Groups[2].Value -eq 'tcp:8768' -and
                $grant.Groups[3].Value -ne 'tcp:8768') { throw 'Issuer remote port 8768 is occupied by a different reverse mapping.' }
        }
    }
    Start-OrReuseAuthority $metadata
    $pattern = '(?m)^\s*' + [Regex]::Escape($issuerDevice) + '\s+tcp:8768\s+tcp:8768\s+\[Reverse\]\s*$'
    $ports = Invoke-AuthorityCommand $hdcPath @('-t', $issuerDevice, 'fport', 'ls') 'issuer-ports'
    if ($ports -notmatch $pattern) {
        [void](Invoke-AuthorityCommand $hdcPath @('-t', $issuerDevice, 'rport', 'tcp:8768', 'tcp:8768') 'issuer-rport')
        $ports = Invoke-AuthorityCommand $hdcPath @('-t', $issuerDevice, 'fport', 'ls') 'verify-issuer-rport'
        if ($ports -notmatch $pattern) { throw 'Authority reverse port was not confirmed for emulator A.' }
    }
    Write-Host 'A: open the authority console and authorize it with the separately provisioned operator token.'
    Write-Host "Operator token file (its contents are not printed): $tokenPath"
    Write-Host 'Connect A, B and C with their corresponding roles and keep the apps in the foreground. Create an exercise alert on A; B/C verify and forward automatically.'
    Write-Host "Only named emulator A [$issuerDevice] has issuer port 8768. The private signing key remains on this computer."
    Write-Host "AUTHORITY_DEMO_READY=1 | Logs: $sessionDirectory"
} finally { Pop-Location }
