param([string]$GameDir, [string]$PatchDir = (Join-Path $PSScriptRoot 'patches/megaton-1.4.9-windows'))
. (Join-Path $PSScriptRoot 'lib/common.ps1')

Invoke-Main uninstall {
    $p = Read-Patch $PatchDir
    $game = Resolve-Game $p $GameDir
    $exe = Join-Path $game $p.Exe
    $backup = Join-Path (Split-Path -Parent $exe) $p.Backup
    "game=$game"

    $current = Get-Sha $exe
    if ($current -eq $p.OriginalSha) { return 'not patched, nothing to restore' }
    if ($current -ne $p.PatchedSha) { throw "unknown executable sha256=$current, leaving it alone" }
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw "backup $backup is missing, use Steam to verify the game files" }
    $data = [IO.File]::ReadAllBytes($backup)
    if ((Get-BytesSha $data) -ne $p.OriginalSha) { throw "backup $backup does not match the original" }

    Write-Beside $exe $data
    if ((Get-Sha $exe) -ne $p.OriginalSha) { throw 'restore did not verify' }
    Remove-Item -LiteralPath $backup -Force
    "restored sha256=$($p.OriginalSha)"
}
