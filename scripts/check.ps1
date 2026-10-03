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

    # DevEco CLI 1.3.4 checks only src/main and cannot resolve target sourceRoots imports
    # ('entry/transport/NearLinkTransport'). Check each product's source set in a temporary mirror
    # with the adapter placed in src/main, as hvigor compiles it for that target.
    foreach ($variant in @('harmonyos', 'oniro')) {
        $mirror = Join-Path ([IO.Path]::GetTempPath()) ("safemesh-arkts-$variant-" + [Guid]::NewGuid().ToString('N'))
        try {
            [void](New-Item -ItemType Directory -Path $mirror -Force)
            foreach ($item in @('build-profile.json5', 'oh-package.json5', 'hvigorfile.ts', 'code-linter.json5')) {
                Copy-Item -LiteralPath (Join-Path $projectRoot $item) -Destination (Join-Path $mirror $item)
            }
            foreach ($directory in @('AppScope', 'hvigor')) {
                Copy-Item -LiteralPath (Join-Path $projectRoot $directory) -Destination (Join-Path $mirror $directory) -Recurse
            }
            $mirrorEntry = Join-Path $mirror 'entry'
            [void](New-Item -ItemType Directory -Path (Join-Path $mirrorEntry 'src') -Force)
            foreach ($item in @('build-profile.json5', 'oh-package.json5', 'hvigorfile.ts')) {
                Copy-Item -LiteralPath (Join-Path $projectRoot "entry\$item") -Destination (Join-Path $mirrorEntry $item)
            }
            Copy-Item -LiteralPath (Join-Path $projectRoot 'entry\src\main') -Destination (Join-Path $mirrorEntry 'src\main') -Recurse
            $adapter = Get-Content -LiteralPath (Join-Path $projectRoot "entry\src\$variant\transport\NearLinkTransport.ets") -Raw -Encoding UTF8
            $adapter = $adapter.Replace("'../../main/ets/transport/RelayTransport'", "'./RelayTransport'")
            [IO.File]::WriteAllText((Join-Path $mirrorEntry 'src\main\ets\transport\NearLinkTransport.ets'), $adapter, [Text.UTF8Encoding]::new($false))
            $relayPath = Join-Path $mirrorEntry 'src\main\ets\viewmodel\RelayViewModel.ets'
            $relay = (Get-Content -LiteralPath $relayPath -Raw -Encoding UTF8).Replace("'entry/transport/NearLinkTransport'", "'../transport/NearLinkTransport'")
            [IO.File]::WriteAllText($relayPath, $relay, [Text.UTF8Encoding]::new($false))
            Write-Output "ArkTS check: $variant source set"
            $ErrorActionPreference = 'Continue'
            & devecocli.cmd check arkts --project $mirror
            $arktsExit = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            if ($arktsExit -ne 0) { throw "ArkTS check failed for the $variant source set ($arktsExit)." }
        } finally {
            Remove-Item -LiteralPath $mirror -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

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
