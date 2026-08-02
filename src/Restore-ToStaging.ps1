[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$BackupPath,
    [Parameter(Mandatory)][string]$Destination,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$backup = (Resolve-Path -LiteralPath $BackupPath).Path
$destinationFull = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
$broad = @([IO.Path]::GetPathRoot($destinationFull).TrimEnd('\'), $env:USERPROFILE.TrimEnd('\'), $env:SystemRoot.TrimEnd('\'), $env:ProgramData.TrimEnd('\'))
if ($destinationFull -in $broad) { throw "Broad restore destination refused: $destinationFull" }
if (Test-Path -LiteralPath $destinationFull) {
    if (@(Get-ChildItem -LiteralPath $destinationFull -Force).Count) { throw 'Restore destination must be new or empty.' }
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-Backup.ps1') -BackupPath $backup
if ($LASTEXITCODE -ne 0) { throw "Backup verification failed with exit code $LASTEXITCODE" }
Write-Host "Verified backup would be restored to new staging directory: $destinationFull"
if (-not $Apply) { Write-Host 'Audit only. Add -Apply to create the staging copy.'; return }
if (-not $PSCmdlet.ShouldProcess($destinationFull, 'Restore verified payload to staging')) { return }

$temporary = $null
try {
    if (Test-Path -LiteralPath $backup -PathType Leaf) {
        $temporary = Join-Path $env:TEMP ('BackupRestore-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $temporary | Out-Null
        Expand-Archive -LiteralPath $backup -DestinationPath $temporary
        $root = $temporary
    } else { $root = $backup }
    $payload = Join-Path $root 'payload'
    if (-not (Test-Path -LiteralPath $payload -PathType Container)) { throw 'Verified backup has no payload directory.' }
    New-Item -ItemType Directory -Path $destinationFull -Force | Out-Null
    Get-ChildItem -LiteralPath $payload -Force | Copy-Item -Destination $destinationFull -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $root 'manifest.json') -Destination (Join-Path $destinationFull 'SOURCE-manifest.json')
    Write-Host "Staging restore complete: $destinationFull"
    Write-Warning 'Do not replace live application state until the application is closed and this staging copy has been reviewed.'
}
finally {
    if ($temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}

