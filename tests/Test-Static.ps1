$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scripts = Get-ChildItem -LiteralPath (Join-Path $root 'src') -Filter '*.ps1' -File
foreach ($script in $scripts) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "$($script.Name): $($errors -join '; ')" }
}
$config = Get-Content -LiteralPath (Join-Path $root 'config\backup.example.json') -Raw | ConvertFrom-Json
if (-not @($config.sources).Count) { throw 'Example configuration needs at least one source.' }
if ([string]$config.destinationRoot -match '(?i)github') { throw 'Example destination must not encourage publishing backups.' }
Write-Host "Static checks passed for $($scripts.Count) scripts."

