param(
    [string]$InstallDirectory = 'D:\tools\Godot\4.6.1',
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$BuildName = 'I-See-Me-0.1.0-demo-windows-x64'
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$install = [IO.Path]::GetFullPath($InstallDirectory)
if ([IO.Path]::GetPathRoot($install) -ieq 'C:\') {
    throw 'Keep the portable Godot installation outside C:.'
}
$engine = Join-Path $install 'Godot_v4.6.1-stable_win64_console.exe'
$template = Join-Path $install 'editor_data\export_templates\4.6.1.stable\windows_release_x86_64.exe'
foreach ($required in @($engine, (Join-Path $install '_sc_'), $template)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing: $required. See docs/windows-release.md." }
}
$output = Join-Path $project "dist\$BuildName"
$archive = "$output.zip"
if ((Test-Path -LiteralPath $output) -or (Test-Path -LiteralPath $archive)) {
    throw 'This build already exists. Choose another -BuildName; existing builds are never overwritten.'
}
$licenseSource = Join-Path $project 'docs\release\licenses'
foreach ($name in @('Godot-LICENSE.txt', 'Godot-COPYRIGHT.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $licenseSource $name))) { throw "Missing license: $name" }
}

$previous = @{}
$variables = @{
    APPDATA = Join-Path $install 'runtime\roaming'
    LOCALAPPDATA = Join-Path $install 'runtime\local'
    TEMP = Join-Path $install 'runtime\temp'
    TMP = Join-Path $install 'runtime\temp'
}
foreach ($name in $variables.Keys) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    New-Item -ItemType Directory -Force -Path $variables[$name] | Out-Null
    [Environment]::SetEnvironmentVariable($name, $variables[$name], 'Process')
}
$logs = Join-Path $project ".local\logs\$BuildName"
New-Item -ItemType Directory -Force -Path $logs | Out-Null
New-Item -ItemType Directory -Path $output | Out-Null

function Assert-Run {
    param([string]$LogPath, [int]$Code)
    if ($Code -ne 0) { throw "Godot exited with $Code. See $LogPath" }
    if (Select-String -LiteralPath $LogPath -Pattern '^\s*(SCRIPT ERROR:|ERROR:)' -Quiet) {
        throw "Godot reported errors. See $LogPath"
    }
}

try {
    $importLog = Join-Path $logs 'import.log'
    & $engine --headless --path $project --log-file $importLog --editor --import --quit
    Assert-Run $importLog $LASTEXITCODE
    $uvLog = Join-Path $logs 'prepare-uv2.log'
    & $engine --headless --path $project --log-file $uvLog --script res://tools/prepare_export_uv2.gd
    Assert-Run $uvLog $LASTEXITCODE
    $exportLog = Join-Path $logs 'export.log'
    $exe = Join-Path $output 'I See Me.exe'
    & $engine --headless --path $project --log-file $exportLog --export-release 'Windows Desktop' $exe
    Assert-Run $exportLog $LASTEXITCODE
    foreach ($name in @('I See Me.exe', 'I See Me.pck')) {
        if (-not (Test-Path -LiteralPath (Join-Path $output $name))) { throw "Export omitted $name" }
    }
    $startupLog = Join-Path $logs 'startup.log'
    $startup = Start-Process -FilePath $exe -ArgumentList @('--headless', '--quit-after', '30', '--log-file', "`"$startupLog`"") -WorkingDirectory $output -WindowStyle Hidden -PassThru
    if (-not $startup.WaitForExit(60000)) {
        $startup.Kill()
        throw "Exported game did not finish startup validation. See $startupLog"
    }
    Assert-Run $startupLog $startup.ExitCode
    Copy-Item -LiteralPath (Join-Path $project 'docs\release\README.txt') -Destination $output
    Copy-Item -LiteralPath (Join-Path $project 'docs\release\THIRD-PARTY-NOTICES.txt') -Destination $output
    Copy-Item -LiteralPath $licenseSource -Destination (Join-Path $output 'licenses') -Recurse
    Copy-Item -LiteralPath (Join-Path $project 'assets\characters\quaternius\LICENSE-CC0-1.0.txt') -Destination (Join-Path $output 'licenses\Quaternius-LICENSE-CC0-1.0.txt')
    $revision = (& git -C $project rev-parse HEAD 2>$null)
    $changes = @(& git -C $project status --porcelain --untracked-files=no 2>$null)
    $builtAt = [DateTimeOffset]::Now.ToString('o')
    @("Build: $BuildName", "Built: $builtAt", 'Engine: Godot 4.6.1 stable / Windows x86_64 / release / Compatibility', "Source base: $revision", "Tracked working-tree changes: $($changes.Count)", 'Entry: res://scenes/classroom_dialogue.tscn', 'Unsigned Demo; source base plus local release changes, not a tagged final release.') |
        Set-Content -LiteralPath (Join-Path $output 'BUILD-INFO.txt') -Encoding UTF8
    $hashes = Get-ChildItem -LiteralPath $output -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($output.Length + 1).Replace('\', '/')
        '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $relative
    }
    $hashes | Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding UTF8
    Compress-Archive -LiteralPath $output -DestinationPath $archive -CompressionLevel Optimal
    $archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    "$archiveHash  $BuildName.zip" | Set-Content -LiteralPath "$archive.sha256" -Encoding ASCII
    Write-Output "Created: $archive"
    Write-Output "SHA256: $archiveHash"
}
finally {
    foreach ($name in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
}
