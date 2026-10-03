[CmdletBinding()]
param([switch]$Build)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $env:DEVECO_CLI_STUDIO_PATH) {
    $studioCandidate = Join-Path $env:USERPROFILE 'DevEcoStudio'
    if (Test-Path -LiteralPath $studioCandidate) { $env:DEVECO_CLI_STUDIO_PATH = $studioCandidate }
    else { throw 'Set DEVECO_CLI_STUDIO_PATH to the DevEco Studio installation.' }
}
Push-Location -LiteralPath $projectRoot
try {
    $testFiles = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests') -Filter '*.test.mjs' -File |
        Sort-Object Name | ForEach-Object { $_.FullName })
    if ($testFiles.Count -eq 0) { throw 'No host test suites found.' }
    $ErrorActionPreference = 'Continue'
    & node --test @testFiles
    $testExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($testExit -ne 0) { throw "Host tests failed ($testExit)." }

    $ErrorActionPreference = 'Continue'
    & devecocli.cmd check arkts --project $projectRoot
    $arktsExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($arktsExit -ne 0) { throw "ArkTS check failed ($arktsExit)." }

    $ErrorActionPreference = 'Continue'
    & devecocli.cmd check lint --format json $projectRoot
    $lintExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($lintExit -ne 0) { throw "Code Linter failed ($lintExit)." }

    if ($Build) {
        $ErrorActionPreference = 'Continue'
        & devecocli.cmd build --modules entry --build-mode debug
        $buildExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        Write-Output "DEVECOCLI_BUILD_EXIT_CODE=$buildExit"
        if ($buildExit -ne 0) { throw "HAP build failed ($buildExit)." }
    }
    Write-Output 'CHECKS: PASS'
} finally { Pop-Location }
