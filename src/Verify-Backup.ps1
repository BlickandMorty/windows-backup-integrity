[CmdletBinding()]
param([Parameter(Mandatory)][string]$BackupPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path -LiteralPath $BackupPath).Path
$temporary = $null
try {
    if (Test-Path -LiteralPath $resolved -PathType Leaf) {
        if ([IO.Path]::GetExtension($resolved) -ine '.zip') { throw 'Backup file must be a ZIP archive.' }
        $temporary = Join-Path $env:TEMP ('BackupVerify-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $temporary | Out-Null
        Expand-Archive -LiteralPath $resolved -DestinationPath $temporary
        $root = $temporary
    } else { $root = $resolved }
    $manifestPath = Join-Path $root 'manifest.json'
    $sidecarPath = Join-Path $root 'manifest.sha256'
    if (-not (Test-Path -LiteralPath $manifestPath) -or -not (Test-Path -LiteralPath $sidecarPath)) { throw 'Manifest or manifest sidecar is missing.' }
    $expectedManifestHash = ((Get-Content -LiteralPath $sidecarPath -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
    $actualManifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expectedManifestHash -ne $actualManifestHash) { throw 'Manifest SHA-256 mismatch.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $failures = [Collections.Generic.List[object]]::new()
    foreach ($file in @($manifest.files)) {
        $path = Join-Path $root ([string]$file.relativePath)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $failures.Add([pscustomobject]@{ path = $file.relativePath; error = 'Missing' }); continue }
        $item = Get-Item -LiteralPath $path
        if ($item.Length -ne [int64]$file.bytes) { $failures.Add([pscustomobject]@{ path = $file.relativePath; error = 'Size mismatch' }); continue }
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne [string]$file.sha256) { $failures.Add([pscustomobject]@{ path = $file.relativePath; error = 'Hash mismatch' }) }
    }
    $result = [ordered]@{ verifiedAt = (Get-Date).ToString('o'); backupPath = $resolved; files = @($manifest.files).Count; failures = @($failures) }
    $result | ConvertTo-Json -Depth 6
    if ($failures.Count) { exit 2 }
}
finally {
    if ($temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}

