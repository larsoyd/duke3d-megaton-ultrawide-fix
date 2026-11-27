BeforeAll {
    $Root = Split-Path -Parent $PSScriptRoot
    $Shell = (Get-Process -Id $PID).Path
    . (Join-Path $Root 'lib/common.ps1')

    function Get-Sha([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }

    function New-Fixture([string]$Name, [string]$Eol = "`n") {
        $d = Join-Path $TestDrive $Name
        $bin = Join-Path $d 'game/bin'
        $patch = Join-Path $d 'patch'
        New-Item -ItemType Directory -Force -Path $bin, $patch | Out-Null
        $data = New-Object byte[] 65536
        (New-Object Random 7).NextBytes($data)
        $orig = Join-Path $d 'original'
        [IO.File]::WriteAllBytes($orig, $data)
        $rows = foreach ($off in 100, 2048, 40000) {
            $old = [BitConverter]::ToUInt32($data, $off)
            $new = [uint32]($old -bxor 0x00200000)
            [Array]::Copy([BitConverter]::GetBytes($new), 0, $data, $off, 4)
            '0x{0:x8}{3}0x{1:x8}{3}0x{2:x8}{3}word_{0:x}' -f $off, $old, $new, "`t"
        }
        $patched = Join-Path $d 'patched'
        [IO.File]::WriteAllBytes($patched, $data)
        Copy-Item -LiteralPath $orig -Destination (Join-Path $bin 'duke3d.exe')
        $manifest = @(
            "ORIGINAL_SHA256=$(Get-Sha $orig)", "PATCHED_SHA256=$(Get-Sha $patched)",
            'EXE=bin/duke3d.exe', 'BACKUP=duke3d.exe.megaton-original', 'CHANGES=changes.tsv')
        [IO.File]::WriteAllText((Join-Path $patch 'manifest'), ($manifest -join $Eol) + $Eol)
        [IO.File]::WriteAllText((Join-Path $patch 'changes.tsv'), ($rows -join $Eol) + $Eol)
        [pscustomobject]@{
            Dir = $d; Game = Join-Path $d 'game'; Patch = $patch; Original = $orig; Patched = $patched
            Exe = Join-Path $bin 'duke3d.exe'; Backup = Join-Path $bin 'duke3d.exe.megaton-original'; Bin = $bin
        }
    }

    function Invoke-Script([string]$Script, $F, [string[]]$Extra = @()) {
        $log = Join-Path $F.Dir "$Script.log"
        $argv = @('-NoProfile', '-NonInteractive', '-File', (Join-Path $Root "$Script.ps1"), '-PatchDir', $F.Patch) + $Extra
        $p = Start-Process -FilePath $Shell -ArgumentList ($argv | ForEach-Object { '"' + $_ + '"' }) -NoNewWindow -PassThru `
            -RedirectStandardOutput $log -RedirectStandardError "$log.err"
        $null = $p.Handle # windows powershell drops the exit code unless the handle is held
        if (-not $p.WaitForExit(120000)) { $p.Kill(); throw "$Script timed out" }
        [pscustomobject]@{ Code = $p.ExitCode; Out = (Get-Content -Raw $log) + (Get-Content -Raw "$log.err") }
    }

    function Install-Fix($F) { Invoke-Script install $F @('-GameDir', $F.Game) }
    function Uninstall-Fix($F) { Invoke-Script uninstall $F @('-GameDir', $F.Game) }
    function Get-LeftoverCount($F) { @(Get-ChildItem -LiteralPath $F.Bin -Force -Filter '.duke3d.*').Count }
}

Describe 'install.ps1' {
    It 'patches and keeps a verified backup' {
        $f = New-Fixture install
        $r = Install-Fix $f
        $r.Code | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match '\[install\] patched sha256='
        Get-Sha $f.Exe | Should -Be (Get-Sha $f.Patched)
        Get-Sha $f.Backup | Should -Be (Get-Sha $f.Original)
        Get-LeftoverCount $f | Should -Be 0
    }

    It 'reads a manifest and table with crlf line ends' {
        $f = New-Fixture crlf "`r`n"
        (Install-Fix $f).Code | Should -Be 0
        Get-Sha $f.Exe | Should -Be (Get-Sha $f.Patched)
    }

    It 'takes relative folders after a cd in the same session' {
        $f = New-Fixture relative
        Push-Location $f.Dir
        try {
            $p = Read-Patch 'patch'
            Resolve-Game $p 'game' | Should -Be (Get-Item -LiteralPath $f.Game).FullName
        } finally { Pop-Location }
        $p.Changes.Count | Should -Be 3
    }

    It 'does nothing on a second run' {
        $f = New-Fixture twice
        Install-Fix $f | Out-Null
        $r = Install-Fix $f
        $r.Code | Should -Be 0
        $r.Out | Should -Match 'already patched'
        Get-Sha $f.Exe | Should -Be (Get-Sha $f.Patched)
    }

    It 'refuses an unknown executable and writes nothing' {
        $f = New-Fixture unknown
        [IO.File]::AppendAllText($f.Exe, 'x')
        $before = Get-Sha $f.Exe
        $r = Install-Fix $f
        $r.Code | Should -Be 1
        $r.Out | Should -Match 'refused: unknown executable'
        Get-Sha $f.Exe | Should -Be $before
        Test-Path -LiteralPath $f.Backup | Should -BeFalse
    }

    It 'refuses when an old value does not match' {
        $f = New-Fixture oldvalue
        $t = Join-Path $f.Patch 'changes.tsv'
        [IO.File]::WriteAllText($t, ([IO.File]::ReadAllText($t) -replace '0x00000064\t0x[0-9a-f]{8}', "0x00000064`t0x12345678"))
        $r = Install-Fix $f
        $r.Code | Should -Be 1
        $r.Out | Should -Match 'refused: offset 0x00000064 word_64 holds 0x[0-9a-f]{8}, expected 0x12345678'
        Get-Sha $f.Exe | Should -Be (Get-Sha $f.Original)
        Test-Path -LiteralPath $f.Backup | Should -BeFalse
    }

    It 'refuses a change past the end of the file' {
        $f = New-Fixture pastend
        [IO.File]::AppendAllText((Join-Path $f.Patch 'changes.tsv'), "0x0000fffe`t0x00000000`t0x00000001`ttail`n")
        $r = Install-Fix $f
        $r.Code | Should -Be 1
        $r.Out | Should -Match 'refused: offset 0x0000fffe tail is past the end of the file'
        Get-Sha $f.Exe | Should -Be (Get-Sha $f.Original)
    }

    It 'refuses a result with the wrong checksum' {
        $f = New-Fixture mismatch
        $m = Join-Path $f.Patch 'manifest'
        [IO.File]::WriteAllText($m, ([IO.File]::ReadAllText($m) -replace 'PATCHED_SHA256=\w+', ('PATCHED_SHA256=' + '0' * 64)))
        $r = Install-Fix $f
        $r.Code | Should -Be 1
        $r.Out | Should -Match 'refused: patched checksum'
        Get-Sha $f.Exe | Should -Be (Get-Sha $f.Original)
        Get-LeftoverCount $f | Should -Be 0
    }

    It 'refuses a manifest without checksums' {
        $f = New-Fixture nosum
        $m = Join-Path $f.Patch 'manifest'
        [IO.File]::WriteAllText($m, ([IO.File]::ReadAllText($m) -replace 'ORIGINAL_SHA256=\w+\n', ''))
        $r = Install-Fix $f
        $r.Code | Should -Be 1
        $r.Out | Should -Match 'refused: manifest has no ORIGINAL_SHA256'
    }

    It 'leaves a foreign backup alone' {
        $f = New-Fixture badbackup
        [IO.File]::WriteAllText($f.Backup, 'junk')
        $r = Install-Fix $f
        $r.Code | Should -Be 1
        $r.Out | Should -Match 'refused: backup .* is not the original'
        [IO.File]::ReadAllText($f.Backup) | Should -Be 'junk'
        Get-Sha $f.Exe | Should -Be (Get-Sha $f.Original)
    }

    It 'refuses a folder without the game' {
        $f = New-Fixture nogame
        Remove-Item -LiteralPath $f.Exe
        $r = Install-Fix $f
        $r.Code | Should -Be 1
        $r.Out | Should -Match 'refused: game not found: no bin/duke3d.exe in'
    }

    It 'refuses while the game file is locked' -Skip:([Environment]::OSVersion.Platform -ne 'Win32NT') {
        $f = New-Fixture locked
        $h = [IO.File]::Open($f.Exe, 'Open', 'Read', 'Read')
        try { $r = Install-Fix $f } finally { $h.Close() }
        $r.Code | Should -Be 1
        $r.Out | Should -Match 'refused: .*denied|refused: .*being used'
        Get-Sha $f.Exe | Should -Be (Get-Sha $f.Original)
        Get-LeftoverCount $f | Should -Be 0
    }
}

Describe 'uninstall.ps1' {
    It 'restores the original and removes the backup' {
        $f = New-Fixture restore
        Install-Fix $f | Out-Null
        $r = Uninstall-Fix $f
        $r.Code | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match '\[uninstall\] restored sha256='
        Get-Sha $f.Exe | Should -Be (Get-Sha $f.Original)
        Test-Path -LiteralPath $f.Backup | Should -BeFalse
    }

    It 'does nothing when not patched' {
        $f = New-Fixture unpatched
        $r = Uninstall-Fix $f
        $r.Code | Should -Be 0
        $r.Out | Should -Match 'not patched, nothing to restore'
    }

    It 'refuses a tampered backup' {
        $f = New-Fixture tampered
        Install-Fix $f | Out-Null
        [IO.File]::AppendAllText($f.Backup, 'x')
        $r = Uninstall-Fix $f
        $r.Code | Should -Be 1
        $r.Out | Should -Match 'refused: backup .* does not match the original'
        Get-Sha $f.Exe | Should -Be (Get-Sha $f.Patched)
    }

    It 'refuses a missing backup' {
        $f = New-Fixture nobackup
        Install-Fix $f | Out-Null
        Remove-Item -LiteralPath $f.Backup
        $r = Uninstall-Fix $f
        $r.Code | Should -Be 1
        $r.Out | Should -Match 'refused: backup .* is missing'
        Get-Sha $f.Exe | Should -Be (Get-Sha $f.Patched)
    }

    It 'leaves an unknown executable alone' {
        $f = New-Fixture foreign
        Install-Fix $f | Out-Null
        [IO.File]::WriteAllText($f.Exe, 'other')
        $r = Uninstall-Fix $f
        $r.Code | Should -Be 1
        $r.Out | Should -Match 'refused: unknown executable'
        [IO.File]::ReadAllText($f.Exe) | Should -Be 'other'
    }
}

Describe 'Find-Game' {
    BeforeEach {
        $base = Join-Path $TestDrive ([guid]::NewGuid())
        $steam = Join-Path $base 'Steam'
        $lib = Join-Path $base 'lib2'
        New-Item -ItemType Directory -Force -Path (Join-Path $steam 'steamapps'), (Join-Path $lib 'steamapps/common') | Out-Null
        $vdf = "`"libraryfolders`"`n{`n`t`"0`"`n`t{`n`t`t`"path`"`t`t`"$($steam -replace '\\', '\\')`"`n`t}`n`t`"1`"`n`t{`n`t`t`"path`"`t`t`"$($lib -replace '\\', '\\')`"`n`t}`n}`n"
        [IO.File]::WriteAllText((Join-Path $steam 'steamapps/libraryfolders.vdf'), $vdf)
    }

    It 'finds the game in an extra library folder' {
        $game = Join-Path $lib 'steamapps/common/Duke Nukem 3D'
        New-Item -ItemType Directory -Force -Path (Join-Path $game 'bin') | Out-Null
        [IO.File]::WriteAllText((Join-Path $game 'bin/duke3d.exe'), 'x')
        Find-Game -Exe 'bin/duke3d.exe' -Roots @($steam) | Should -Be (Get-Item -LiteralPath $game).FullName
    }

    It 'refuses when no library has the game' {
        { Find-Game -Exe 'bin/duke3d.exe' -Roots @($steam) } | Should -Throw 'game not found in any Steam library, pass -GameDir'
    }

    It 'refuses several installs' {
        foreach ($l in $steam, $lib) {
            $g = Join-Path $l 'steamapps/common/Duke Nukem 3D/bin'
            New-Item -ItemType Directory -Force -Path $g | Out-Null
            [IO.File]::WriteAllText((Join-Path $g 'duke3d.exe'), 'x')
        }
        { Find-Game -Exe 'bin/duke3d.exe' -Roots @($steam) } | Should -Throw 'several installs found*'
    }
}

Describe 'real change table' {
    It 'matches an independent python apply' {
        $table = Join-Path $Root 'patches/megaton-1.4.9-windows/changes.tsv'
        $d = Join-Path $TestDrive 'real'
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        $rows = Get-Content -LiteralPath $table | ForEach-Object { , ($_ -split "`t") }
        $size = [Convert]::ToInt32($rows[-1][0], 16) + 64
        $data = New-Object byte[] $size
        (New-Object Random 11).NextBytes($data)
        foreach ($r in $rows) {
            [Array]::Copy([BitConverter]::GetBytes([Convert]::ToUInt32($r[1], 16)), 0, $data, [Convert]::ToInt32($r[0], 16), 4)
        }
        $base = Join-Path $d 'base'
        [IO.File]::WriteAllBytes($base, $data)
        $patch = Read-Patch (Join-Path $Root 'patches/megaton-1.4.9-windows')
        $patch.PatchedSha = $null
        $ours = Join-Path $d 'ours'
        [IO.File]::WriteAllBytes($ours, (Invoke-ChangeTable $patch.Changes ([IO.File]::ReadAllBytes($base))))

        $py = (Get-Command python, python3 -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
        $py | Should -Not -BeNullOrEmpty -Because 'the cross check needs python'
        $ref = Join-Path $d 'ref'
        $prog = "import struct,sys`nd=bytearray(open(sys.argv[1],'rb').read())`n" +
            "for l in open(sys.argv[2]):`n o,a,b,_=l.rstrip('\n').split('\t'); o=int(o,16)`n" +
            " assert struct.unpack_from('<I',d,o)[0]==int(a,16); struct.pack_into('<I',d,o,int(b,16))`n" +
            "open(sys.argv[3],'wb').write(d)`n"
        & $py -I -c $prog $base $table $ref
        $LASTEXITCODE | Should -Be 0
        $rows.Count | Should -Be 399
        Get-Sha $ours | Should -Be (Get-Sha $ref)
        Get-Sha $ours | Should -Not -Be (Get-Sha $base)
    }
}
