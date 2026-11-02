<#
.SYNOPSIS
    Prepare a STM32 Keil MDK release in README.md and copy the built HEX.
.DESCRIPTION
    Discover a single STM32 project under Project and its configured HEX output.
    DryRun makes no changes. UV4_PATH or PATH supplies the Keil executable.
    Commit is opt-in and stages only named paths. Push sends that commit to the
    current branch's configured upstream. This script never runs clear.bat.
#>
[CmdletBinding()]
param(
    [string]$RepoPath = '.',
    [Parameter(Mandatory = $true)][ValidatePattern('^\d+(\.\d+)*$')][string]$Version,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Description,
    [string]$Author = 'Maintainer',
    [ValidatePattern('^\d{8}$')][string]$Date = (Get-Date -Format 'yyyyMMdd'),
    [string]$ProjectFile = '',
    [string]$BuiltFile = '',
    [string]$UV4Path = '',
    [string]$ReleaseName = '',
    [switch]$SkipBuild,
    [switch]$Commit,
    [switch]$Push,
    [string[]]$CommitPaths = @(),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
if ($Push -and -not $Commit) { throw '-Push requires -Commit.' }
if ([string]::IsNullOrWhiteSpace($Author)) { $Author = 'Maintainer' }
$repo = (Resolve-Path -LiteralPath $RepoPath).Path
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $repo 'Project'))
if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) { throw 'Project directory not found.' }
$projectPrefix = $projectRoot.TrimEnd([char]'\') + '\'
if ([string]::IsNullOrWhiteSpace($ProjectFile)) {
    $projects = @(Get-ChildItem -LiteralPath $projectRoot -Filter '*.uvprojx' -File -Recurse)
    if ($projects.Count -ne 1) { throw 'Specify -ProjectFile: Project must contain exactly one discoverable .uvprojx.' }
    $ProjectFile = $projects[0].FullName
}
$project = if ([System.IO.Path]::IsPathRooted($ProjectFile)) { $ProjectFile } else { Join-Path $repo $ProjectFile }
$project = (Resolve-Path -LiteralPath $project).Path
if (-not $project.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
    -not $project.EndsWith('.uvprojx', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'ProjectFile must be a .uvprojx under the repository Project directory.'
}
$readme = Join-Path $repo 'README.md'
if (-not (Test-Path -LiteralPath $readme -PathType Leaf)) { throw "README.md not found: $readme" }
if (-not $SkipBuild -and -not $DryRun) {
    if ([string]::IsNullOrWhiteSpace($UV4Path)) { $UV4Path = $env:UV4_PATH }
    if ([string]::IsNullOrWhiteSpace($UV4Path)) {
        $uv4Command = Get-Command UV4.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($uv4Command) { $UV4Path = $uv4Command.Source }
    }
    if ([string]::IsNullOrWhiteSpace($UV4Path) -or -not (Test-Path -LiteralPath $UV4Path -PathType Leaf)) {
        throw 'UV4.exe not found. Supply -UV4Path, set UV4_PATH, or add UV4.exe to PATH.'
    }
}

[xml]$xml = Get-Content -LiteralPath $project -Raw
$targets = @($xml.Project.Targets.Target)
if ($targets.Count -ne 1) { throw 'Project must have exactly one target; select and release a specific target manually.' }
$targetOptions = $targets[0].TargetOption.TargetCommonOption
$device = ([string]$targetOptions.Device).Trim()
if ($device -notmatch '^STM32') { throw 'This skill requires a STM32 device in the Keil target configuration.' }
if (-not $SkipBuild -and [string]$targetOptions.CreateHexFile -ne '1') {
    throw 'Enable Create HEX File in Keil Options for Target > Output before building.'
}
if ([string]::IsNullOrWhiteSpace($BuiltFile)) {
    $outputName = ([string]$targetOptions.OutputName).Trim()
    if ([string]::IsNullOrWhiteSpace($outputName) -or [System.IO.Path]::GetFileName($outputName) -ne $outputName) {
        throw 'Cannot infer the HEX name; specify -BuiltFile.'
    }
    $outputName = $outputName -replace '(?i)\.(axf|elf|hex)$', ''
    $outputDirectory = ([string]$targetOptions.OutputDirectory).Trim()
    if ([string]::IsNullOrWhiteSpace($outputDirectory)) { $outputDirectory = '.' }
    $outputDirectory = if ([System.IO.Path]::IsPathRooted($outputDirectory)) { $outputDirectory } else {
        Join-Path ([System.IO.Path]::GetDirectoryName($project)) $outputDirectory
    }
    $BuiltFile = Join-Path $outputDirectory ($outputName + '.hex')
}
$builtHex = if ([System.IO.Path]::IsPathRooted($BuiltFile)) { $BuiltFile } else { Join-Path $repo $BuiltFile }
$builtHex = [System.IO.Path]::GetFullPath($builtHex)
if (-not $builtHex.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
    -not $builtHex.EndsWith('.hex', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'BuiltFile must be a .hex file under the repository Project directory.'
}
$artifactBase = [System.IO.Path]::GetFileNameWithoutExtension($builtHex)
if ([string]::IsNullOrWhiteSpace($ReleaseName)) { $ReleaseName = "${artifactBase}_v${Version}_${Date}.hex" }
if ([System.IO.Path]::GetFileName($ReleaseName) -ne $ReleaseName -or
    $ReleaseName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
    -not $ReleaseName.EndsWith('.hex', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'ReleaseName must be a single .hex file name.'
}
$releaseHex = Join-Path $repo $ReleaseName
if (Test-Path -LiteralPath $releaseHex) { throw "Release file already exists: $releaseHex" }
if ($Commit) {
    $staged = @(git -C $repo diff --cached --name-only)
    if ($LASTEXITCODE -ne 0) { throw 'Could not read Git staging area.' }
    if ($staged.Count -gt 0) { throw 'Git staging area is not empty; commit manually to avoid mixing changes.' }
}
if ($Push) {
    $branch = @(git -C $repo branch --show-current)
    if ($LASTEXITCODE -ne 0 -or $branch.Count -ne 1 -or [string]::IsNullOrWhiteSpace($branch[0])) {
        throw 'Could not determine the current Git branch; configure a branch before pushing.'
    }
    $branch = $branch[0].Trim()
    $pushRemote = @(git -C $repo config --get "branch.$branch.remote")
    $mergeRef = @(git -C $repo config --get "branch.$branch.merge")
    if ($pushRemote.Count -ne 1 -or [string]::IsNullOrWhiteSpace($pushRemote[0]) -or
        $mergeRef.Count -ne 1 -or $mergeRef[0] -notmatch '^refs/heads/.+' -or $pushRemote[0] -eq '.') {
        throw "Branch '$branch' has no remote tracking branch; configure its upstream before pushing."
    }
    $pushRemote = $pushRemote[0].Trim()
    $mergeRef = $mergeRef[0].Trim()
    git -C $repo remote get-url --push $pushRemote | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Push remote '$pushRemote' is not configured." }
    Write-Host "Push target: $pushRemote $mergeRef"
}

$bytes = [System.IO.File]::ReadAllBytes($readme)
if ($bytes.Length -ge 2 -and (($bytes[0] -eq 255 -and $bytes[1] -eq 254) -or
    ($bytes[0] -eq 254 -and $bytes[1] -eq 255))) { throw 'README.md must use an ASCII-compatible encoding, preferably UTF-8.' }
$ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
$versionPattern = '(?im)^##\s+v' + [regex]::Escape($Version) + '(?:\s|$)'
if ([regex]::IsMatch($ascii, $versionPattern)) { throw "Version already exists in README.md: $Version" }
$heading = [regex]::Match($ascii, '(?im)^##\s+v\d')
if (-not $heading.Success) { throw 'No Markdown version heading found in README.md.' }
$insertAt = $heading.Index
$newline = if ($ascii.Contains("`r`n")) { "`r`n" } else { "`n" }
$dateText = [datetime]::ParseExact($Date, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture).ToString('yyyyMMdd')
$descriptionLines = @($Description -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($descriptionLines.Count -eq 0) { throw 'Description must contain at least one nonempty line.' }
$blockLines = @("## v$Version $dateText $Author")
for ($i = 0; $i -lt $descriptionLines.Count; $i++) { $blockLines += ('{0}. {1}' -f ($i + 1), $descriptionLines[$i].Trim()) }
$block = ($blockLines -join $newline) + $newline + $newline

Write-Host "Repo: $repo"
Write-Host "Project: $project"
Write-Host "STM32 device: $device"
Write-Host "Built HEX: $builtHex"
Write-Host "Release HEX: $releaseHex"
Write-Host "README entry: $($blockLines[0])"
if ($DryRun) { Write-Host 'Dry run: no files changed, no build, commit or push run.'; return }

$buildStart = Get-Date
if (-not $SkipBuild) {
    $buildLog = Join-Path $env:TEMP ("keil_release_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    & $UV4Path -r $project -j0 -o $buildLog | Out-Null
    $exitCode = $LASTEXITCODE
    Write-Host "UV4 exit code: $exitCode; log: $buildLog"
    if ($null -eq $exitCode -or $exitCode -ge 2) { throw "Keil build failed: $exitCode" }
}
if (-not (Test-Path -LiteralPath $builtHex -PathType Leaf)) { throw "Built HEX missing: $builtHex" }
$built = Get-Item -LiteralPath $builtHex
if ($built.Length -le 0) { throw "Built HEX is empty: $builtHex" }
if (-not $SkipBuild -and $built.LastWriteTime -lt $buildStart.AddSeconds(-2)) { throw 'Built HEX was not refreshed by this build.' }

# Insert bytes before the first version heading so all historical README bytes stay intact.
$newBytes = New-Object byte[] ($bytes.Length + [System.Text.Encoding]::UTF8.GetByteCount($block))
$insertBytes = [System.Text.Encoding]::UTF8.GetBytes($block)
[Array]::Copy($bytes, 0, $newBytes, 0, $insertAt)
[Array]::Copy($insertBytes, 0, $newBytes, $insertAt, $insertBytes.Length)
[Array]::Copy($bytes, $insertAt, $newBytes, $insertAt + $insertBytes.Length, $bytes.Length - $insertAt)
[System.IO.File]::WriteAllBytes($readme, $newBytes)
[System.IO.File]::Copy($builtHex, $releaseHex, $false)
$sourceHash = (Get-FileHash -LiteralPath $builtHex -Algorithm SHA256).Hash
$releaseHash = (Get-FileHash -LiteralPath $releaseHex -Algorithm SHA256).Hash
if ($sourceHash -ne $releaseHash) { throw 'Copied HEX hash differs from built HEX.' }
Write-Host "HEX SHA-256: $releaseHash"

if ($Commit) {
    $paths = @('README.md', $ReleaseName) + $CommitPaths
    git -C $repo add -- $paths
    if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }
    $message = "${artifactBase}_v${Version}_${Date}_${Description}"
    $messageFile = Join-Path $env:TEMP ("keil_commit_{0}_{1}.txt" -f $PID, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    try {
        [System.IO.File]::WriteAllText($messageFile, $message, (New-Object System.Text.UTF8Encoding($false)))
        git -C $repo commit -F $messageFile
        if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
    }
    finally { Remove-Item -LiteralPath $messageFile -Force -ErrorAction SilentlyContinue }
}
if ($Push) {
    git -C $repo push $pushRemote "HEAD:$mergeRef"
    if ($LASTEXITCODE -ne 0) { throw "git push failed; the local commit was created but not uploaded to $pushRemote $mergeRef." }
    Write-Host "Pushed to $pushRemote $mergeRef"
}
Write-Host 'Release prepared.'
