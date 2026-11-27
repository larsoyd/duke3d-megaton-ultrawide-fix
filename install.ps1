param([string]$GameDir, [string]$PatchDir = (Join-Path $PSScriptRoot 'patches/megaton-1.4.9-windows'))
. (Join-Path $PSScriptRoot 'lib/common.ps1')

Invoke-Main install {
    $p = Read-Patch $PatchDir
    $game = Resolve-Game $p $GameDir
    $exe = Join-Path $game $p.Exe
    $backup = Join-Path (Split-Path -Parent $exe) $p.Backup
    "game=$game"

    $data = [IO.File]::ReadAllBytes($exe)
    $current = Get-BytesSha $data
    if ($current -eq $p.PatchedSha) { return "already patched sha256=$current" }
    if ($current -ne $p.OriginalSha) { throw "unknown executable sha256=$current, expected $($p.OriginalSha)" }

    $patched = Invoke-ChangeTable $p.Changes $data
    $got = Get-BytesSha $patched
    if ($got -ne $p.PatchedSha) { throw "patched checksum $got does not match $($p.PatchedSha)" }

    if (Test-Path -LiteralPath $backup) {
        if ((Get-Sha $backup) -ne $p.OriginalSha) { throw "backup $backup exists and is not the original" }
    } else {
        Write-Beside $backup $data
        if ((Get-Sha $backup) -ne $p.OriginalSha) { throw 'backup did not verify' }
        "backup=$backup"
    }

    Write-Beside $exe $patched
    if ((Get-Sha $exe) -ne $p.PatchedSha) { throw 'patched file did not verify' }
    "patched sha256=$got"
}
