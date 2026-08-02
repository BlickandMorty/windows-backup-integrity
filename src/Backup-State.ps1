[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Audit', 'Backup')][string]$Mode = 'Audit',
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\backup.example.json'),
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath (Resolve-Path -LiteralPath $ConfigPath) -Raw | ConvertFrom-Json
if ($config.schemaVersion -ne 1) { throw 'Unsupported configuration schema.' }
$destinationRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$config.destinationRoot))
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runName = '{0}-{1}' -f ([string]$config.archiveName), $stamp
$runRoot = Join-Path $destinationRoot $runName

$auditSources = foreach ($source in @($config.sources)) {
    $path = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$source.path))
    [pscustomobject]@{ name = [string]$source.name; path = $path; exists = Test-Path -LiteralPath $path -PathType Container; excludes = $source }
}
$audit = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    mode = $Mode
    apply = [bool]$Apply
    destination = $runRoot
    sources = @($auditSources)
}
$audit | ConvertTo-Json -Depth 8
if ($Mode -eq 'Audit' -or -not $Apply) { Write-Host 'Audit only. No backup was created.'; return }
if (@($auditSources | Where-Object { -not $_.exists }).Count) { throw 'One or more configured source folders do not exist.' }
if (-not $PSCmdlet.ShouldProcess($runRoot, 'Create versioned backup and manifest')) { return }

New-Item -ItemType Directory -Path (Join-Path $runRoot 'payload') -Force | Out-Null
foreach ($entry in $auditSources) {
    $destination = Join-Path $runRoot (Join-Path 'payload' $entry.name)
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $arguments = @($entry.path, $destination, '/E', '/COPY:DAT', '/DCOPY:DAT', '/R:2', '/W:2', '/XJ', '/NP', '/NFL', '/NDL')
    if (@($entry.excludes.excludeDirectories).Count) {
        $arguments += '/XD'
        $arguments += @($entry.excludes.excludeDirectories | ForEach-Object { Join-Path $entry.path ([string]$_) })
    }
    if (@($entry.excludes.excludeFiles).Count) { $arguments += '/XF'; $arguments += @($entry.excludes.excludeFiles) }
    & robocopy.exe @arguments | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "Robocopy failed for $($entry.name) with exit code $LASTEXITCODE" }
}

$files = Get-ChildItem -LiteralPath (Join-Path $runRoot 'payload') -Recurse -File -Force | ForEach-Object {
    [pscustomobject]@{
        relativePath = $_.FullName.Substring($runRoot.Length + 1)
        bytes = $_.Length
        lastWriteUtc = $_.LastWriteTimeUtc.ToString('o')
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
$manifest = [ordered]@{
    schemaVersion = 1
    createdAt = (Get-Date).ToString('o')
    archiveName = $runName
    sourceComputer = $env:COMPUTERNAME
    files = @($files)
}
[IO.File]::WriteAllText((Join-Path $runRoot 'manifest.json'), ($manifest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
$manifestHash = (Get-FileHash -LiteralPath (Join-Path $runRoot 'manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $runRoot 'manifest.sha256'), $manifestHash + "  manifest.json`n", [Text.UTF8Encoding]::new($false))

if ([bool]$config.createZip) {
    $zipPath = "$runRoot.zip"
    Compress-Archive -Path (Join-Path $runRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal
    $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText("$zipPath.sha256", "$zipHash  $([IO.Path]::GetFileName($zipPath))`n", [Text.UTF8Encoding]::new($false))
    Write-Host "ZIP: $zipPath"
}
Write-Host "Backup directory: $runRoot"
Write-Host "Files: $($files.Count)"
