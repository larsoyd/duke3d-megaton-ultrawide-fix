Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'
$GameName = 'Duke Nukem 3D'

function Get-Sha([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }

function Get-BytesSha([byte[]]$Data) {
    $h = [Security.Cryptography.SHA256]::Create()
    try { -join ($h.ComputeHash($Data) | ForEach-Object { $_.ToString('x2') }) } finally { $h.Dispose() }
}

function Read-Patch([string]$Dir) {
    $file = Join-Path $Dir 'manifest'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "no manifest in $Dir" }
    $Dir = (Get-Item -LiteralPath $Dir).FullName
    $file = Join-Path $Dir 'manifest'
    $m = @{}
    foreach ($line in [IO.File]::ReadAllLines($file)) {
        $k, $v = $line -split '=', 2
        if ($null -ne $v) { $m[$k] = $v }
    }
    foreach ($k in 'ORIGINAL_SHA256', 'PATCHED_SHA256', 'EXE', 'BACKUP', 'CHANGES') {
        if (-not $m[$k]) { throw "manifest has no $k" }
    }
    $n = 0
    $changes = foreach ($line in [IO.File]::ReadAllLines((Join-Path $Dir $m.CHANGES))) {
        $n++
        $f = $line -split "`t"
        if ($f.Count -ne 4) { throw "change table line $n has $($f.Count) fields" }
        [pscustomobject]@{
            Offset = [Convert]::ToUInt32($f[0], 16); Old = [Convert]::ToUInt32($f[1], 16)
            New = [Convert]::ToUInt32($f[2], 16); Label = $f[3]
        }
    }
    [pscustomobject]@{
        OriginalSha = $m.ORIGINAL_SHA256; PatchedSha = $m.PATCHED_SHA256
        Exe = $m.EXE; Backup = $m.BACKUP; Changes = @($changes)
    }
}

function Invoke-ChangeTable($Changes, [byte[]]$Data) {
    $out = [byte[]]$Data.Clone()
    foreach ($c in $Changes) {
        if ($c.Offset + 4 -gt $out.Length) { throw ('offset 0x{0:x8} {1} is past the end of the file' -f $c.Offset, $c.Label) }
        $have = [BitConverter]::ToUInt32($out, $c.Offset)
        if ($have -ne $c.Old) { throw ('offset 0x{0:x8} {1} holds 0x{2:x8}, expected 0x{3:x8}' -f $c.Offset, $c.Label, $have, $c.Old) }
        [Array]::Copy([BitConverter]::GetBytes([uint32]$c.New), 0, $out, $c.Offset, 4)
    }
    , $out
}

function Get-SteamRoot {
    $reg = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue
    if ($reg) { $reg.SteamPath }
    if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Steam' }
}

function Find-Game([string]$Exe, [string[]]$Roots) {
    $libs = foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath (Join-Path $root 'steamapps') -PathType Container)) { continue }
        $root
        $vdf = Join-Path $root 'steamapps/libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($line in [IO.File]::ReadAllLines($vdf)) {
                if ($line -match '^\s*"path"\s*"(.*)"\s*$') { $Matches[1] -replace '\\\\', '\' }
            }
        }
    }
    $found = @(foreach ($lib in $libs) {
        $dir = Join-Path $lib "steamapps/common/$GameName"
        if (Test-Path -LiteralPath (Join-Path $dir $Exe) -PathType Leaf) { (Get-Item -LiteralPath $dir).FullName.TrimEnd('\', '/') }
    }) | Sort-Object -Unique
    if (@($found).Count -eq 0) { throw 'game not found in any Steam library, pass -GameDir' }
    if (@($found).Count -gt 1) { throw "several installs found ($($found -join ', ')), pass -GameDir" }
    $found
}

function Resolve-Game($Patch, [string]$GameDir) {
    if (-not $GameDir) { return Find-Game -Exe $Patch.Exe -Roots @(Get-SteamRoot) }
    if (-not (Test-Path -LiteralPath (Join-Path $GameDir $Patch.Exe) -PathType Leaf)) {
        throw "game not found: no $($Patch.Exe) in $GameDir"
    }
    (Get-Item -LiteralPath $GameDir).FullName
}

# temp file beside the target so the final step is a rename on the same volume
function Write-Beside([string]$Dest, [byte[]]$Data) {
    $tmp = Join-Path (Split-Path -Parent $Dest) ('.duke3d.' + [IO.Path]::GetRandomFileName())
    try {
        [IO.File]::WriteAllBytes($tmp, $Data)
        if (Test-Path -LiteralPath $Dest) { [IO.File]::Replace($tmp, $Dest, [NullString]::Value) } else { [IO.File]::Move($tmp, $Dest) }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    }
}

function Invoke-Main([string]$Tag, [scriptblock]$Body) {
    try {
        & $Body | ForEach-Object { Write-Output "[$Tag] $_" }
        exit 0
    } catch {
        $e = $_.Exception
        if ($e.InnerException) { $e = $e.InnerException }
        [Console]::Error.WriteLine("[$Tag] refused: $($e.Message)")
        exit 1
    }
}
