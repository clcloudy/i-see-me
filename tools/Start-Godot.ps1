param(
    [ValidateSet('Editor', 'Play', 'Check', 'Capture')]
    [string]$Mode = 'Editor',
    [string]$InstallDirectory = 'D:\tools\Godot\4.6.1'
)

$ErrorActionPreference = 'Stop'

function Assert-GodotLog {
    param([string]$Path)
    if (Select-String -LiteralPath $Path -Pattern '^(SCRIPT ERROR:|ERROR:)' -Quiet) {
        throw "Godot reported an error. See $Path."
    }
}

$project = Split-Path -Parent $PSScriptRoot
$install = [System.IO.Path]::GetFullPath($InstallDirectory)
if ([System.IO.Path]::GetPathRoot($install) -ieq 'C:\') {
    throw 'Godot must be installed outside C:.'
}
$console = Join-Path $install 'Godot_v4.6.1-stable_win64_console.exe'
$editor = Join-Path $install 'Godot_v4.6.1-stable_win64.exe'
if (-not (Test-Path -LiteralPath $console) -or -not (Test-Path -LiteralPath $editor)) {
    throw "Godot 4.6.1 is not installed at $install. See docs/setup.md."
}
if (-not (Test-Path -LiteralPath (Join-Path $install '_sc_'))) {
    throw 'Missing _sc_ portable-mode marker. See docs/setup.md.'
}

$variables = @{
    APPDATA = Join-Path $install 'runtime\roaming'
    LOCALAPPDATA = Join-Path $install 'runtime\local'
    TEMP = Join-Path $install 'runtime\temp'
    TMP = Join-Path $install 'runtime\temp'
}
$previous = @{}
foreach ($name in $variables.Keys) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    New-Item -ItemType Directory -Force -Path $variables[$name] | Out-Null
    [Environment]::SetEnvironmentVariable($name, $variables[$name], 'Process')
}
New-Item -ItemType Directory -Force -Path (Join-Path $project '.local\logs') | Out-Null
$log = Join-Path $project ".local\logs\$($Mode.ToLower()).log"

try {
    switch ($Mode) {
        'Editor' {
            Start-Process -FilePath $editor -ArgumentList @('--path', "`"$project`"", '--log-file', "`"$log`"", '--editor') -WorkingDirectory $project
        }
        'Play' {
            Start-Process -FilePath $editor -ArgumentList @('--path', "`"$project`"", '--log-file', "`"$log`"") -WorkingDirectory $project
        }
        'Check' {
            $importLog = Join-Path $project '.local\logs\import.log'
            & $console --headless --path $project --log-file $importLog --editor --import --quit
            if ($LASTEXITCODE -ne 0) { throw 'Godot project import failed.' }
            Assert-GodotLog -Path $importLog
            & $console --headless --path $project --log-file $log --script res://tests/smoke.gd
            if ($LASTEXITCODE -ne 0) { throw 'Prototype smoke check failed.' }
            Assert-GodotLog -Path $log
            foreach ($stage in @('intro', 'l1', 'l2', 'l3', 'complete', 'transition', 'paused-transition')) {
                $quitLog = Join-Path $project ".local\logs\quit-$stage.log"
                & $console --headless --path $project --log-file $quitLog --script res://tests/smoke.gd -- --quit-check $stage
                if ($LASTEXITCODE -ne 0) { throw "Prototype quit check failed at $stage." }
                Assert-GodotLog -Path $quitLog
            }
        }
        'Capture' {
            & $console --path $project --log-file $log --resolution 1280x720 --script res://tests/smoke.gd -- --capture
            if ($LASTEXITCODE -ne 0) { throw 'Prototype render check failed.' }
            Assert-GodotLog -Path $log
        }
    }
}
finally {
    foreach ($name in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
}
