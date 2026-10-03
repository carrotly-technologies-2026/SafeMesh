[CmdletBinding()]
param(
    [string]$Device = '127.0.0.1:5555',
    [switch]$RefreshDrill,
    [switch]$NoRun
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $env:DEVECO_CLI_STUDIO_PATH) {
    $studioCandidate = Join-Path $env:USERPROFILE 'DevEcoStudio'
    if (Test-Path -LiteralPath $studioCandidate) {
        $env:DEVECO_CLI_STUDIO_PATH = $studioCandidate
    } else {
        throw 'Set DEVECO_CLI_STUDIO_PATH to your DevEco Studio installation.'
    }
}
if (-not (Get-Command devecocli.cmd -ErrorAction SilentlyContinue)) {
    throw 'Install the hackathon DevEco CLI setup and open a new terminal first.'
}

Push-Location -LiteralPath $projectRoot
try {
    if ($RefreshDrill) {
        & node scripts/generate-demo-alerts.mjs
        if ($LASTEXITCODE -ne 0) { throw 'Exercise fixture generation failed.' }
    }
    # DevEco reports nonfatal warnings on stderr; rely on its process exit code.
    $ErrorActionPreference = 'Continue'
    & devecocli.cmd build --modules entry --build-mode debug
    $buildExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($buildExit -ne 0) { throw "Build failed ($buildExit)." }

    $hap = Join-Path $projectRoot 'entry/build/default/outputs/default/entry-default-unsigned.hap'
    if (-not (Test-Path -LiteralPath $hap)) {
        throw 'Expected unsigned emulator HAP is missing. If you configured signing, use the signed output from DevEco Studio.'
    }
    $dist = Join-Path $projectRoot 'dist'
    New-Item -ItemType Directory -Path $dist -Force | Out-Null
    $destination = Join-Path $dist 'SafeMesh-demo.hap'
    Copy-Item -LiteralPath $hap -Destination $destination -Force
    $digest = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    "$digest  SafeMesh-demo.hap" | Set-Content -LiteralPath (Join-Path $dist 'SHA256SUMS.txt') -Encoding ascii

    if (-not $NoRun) {
        $ErrorActionPreference = 'Continue'
        & devecocli.cmd run --skip-build --module entry --device $Device
        $runExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($runExit -ne 0) { throw "Emulator deployment failed ($runExit)." }
    }
    Write-Output "Ready: $destination"
} finally {
    Pop-Location
}
