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
    $appMetadata = Get-Content -LiteralPath (Join-Path $projectRoot 'AppScope/app.json5') -Raw -Encoding UTF8
    # Strip JSON5 comments while preserving quoted strings before reading the version.
    $appMetadata = [regex]::Replace($appMetadata, '(?s)/\*.*?\*/|//[^\r\n]*|"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''', {
        param($match)
        if ($match.Value.StartsWith('//') -or $match.Value.StartsWith('/*')) { return ' ' }
        return $match.Value
    })
    $versionMatches = [regex]::Matches($appMetadata, '(?:"versionName"|''versionName''|\bversionName)\s*:\s*["''](?<version>[^"'']+)["'']')
    if ($versionMatches.Count -ne 1) { throw 'AppScope/app.json5 must define exactly one versionName.' }
    $appVersion = $versionMatches[0].Groups['version'].Value
    if ($appVersion -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$') {
        throw 'AppScope/app.json5 versionName must be a valid semantic version for artifact filenames.'
    }
    Write-Output "Building SafeMesh $appVersion for the emulator."
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
    $hapName = "SafeMesh-$appVersion.hap"
    $destination = Join-Path $dist $hapName
    Copy-Item -LiteralPath $hap -Destination $destination -Force
    $digest = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    # This helper's versioned checksum covers only the HAP. Release bundles may
    # maintain a separate manifest containing video/source ZIP checksums too.
    $checksumPath = Join-Path $dist "SafeMesh-$appVersion.sha256.txt"
    "$digest  $hapName" | Set-Content -LiteralPath $checksumPath -Encoding ascii

    if (-not $NoRun) {
        $ErrorActionPreference = 'Continue'
        & devecocli.cmd run --skip-build --module entry --device $Device
        $runExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($runExit -ne 0) { throw "Emulator deployment failed ($runExit)." }
    }
    Write-Output "Ready: $destination"
    Write-Output "HAP-only SHA256 manifest: $checksumPath"
} finally {
    Pop-Location
}
