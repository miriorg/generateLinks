<#
    Test-generateLinks.ps1

    generateLinks.ps1 の分岐を一時フォルダ内で検証する自己完結テスト。
    実行:  powershell -File .\Test-generateLinks.ps1
           pwsh       -File .\Test-generateLinks.ps1

    シンボリックリンク作成に権限が要る環境では symlink 系シナリオを SKIP する
    (hardlink / check / dry-run / 引数系は常に実行)。
#>
#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# 定数・状態
# ----------------------------------------------------------------------------
$GEN_SCRIPT = Join-Path $PSScriptRoot 'generateLinks.ps1'
$HOST_EXE   = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }

$Script:Pass = 0
$Script:Fail = 0
$Script:Skip = 0

# ----------------------------------------------------------------------------
# テスト補助
# ----------------------------------------------------------------------------
function Write-Head {
    # シナリオ見出しを表示する。返り値: なし
    param([string] $Title)
    Write-Host ''
    Write-Host "== $Title ==" -ForegroundColor Cyan
}

function Pass-Case {
    # 成功を記録・表示する。返り値: なし
    param([string] $Name)
    $Script:Pass++
    Write-Host "  [PASS] $Name" -ForegroundColor Green
}

function Fail-Case {
    # 失敗を記録・表示する。返り値: なし
    param([string] $Name, [string] $Detail)
    $Script:Fail++
    Write-Host "  [FAIL] $Name" -ForegroundColor Red
    if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkYellow }
}

function Skip-Case {
    # スキップを記録・表示する。返り値: なし
    param([string] $Name, [string] $Reason)
    $Script:Skip++
    Write-Host "  [SKIP] $Name ($Reason)" -ForegroundColor Yellow
}

function Assert-Match {
    # $Text が正規表現 $Pattern を含むか検証する。返り値: なし
    param([string] $Text, [string] $Pattern, [string] $Name)
    if ($Text -match $Pattern) { Pass-Case $Name }
    else { Fail-Case $Name "pattern '/$Pattern/' not found in output:`n---`n$Text`n---" }
}

function Assert-NoMatch {
    # $Text が正規表現 $Pattern を含まないことを検証する。返り値: なし
    param([string] $Text, [string] $Pattern, [string] $Name)
    if ($Text -notmatch $Pattern) { Pass-Case $Name }
    else { Fail-Case $Name "unexpected pattern '/$Pattern/' found in output:`n$Text" }
}

function Assert-Eq {
    # $Actual と $Expected の一致を検証する。返り値: なし
    param($Actual, $Expected, [string] $Name)
    if ($Actual -eq $Expected) { Pass-Case $Name }
    else { Fail-Case $Name "expected [$Expected], got [$Actual]" }
}

function Assert-True {
    # $Condition が真であることを検証する。返り値: なし
    param($Condition, [string] $Name)
    if ($Condition) { Pass-Case $Name } else { Fail-Case $Name 'condition was false' }
}

# ----------------------------------------------------------------------------
# 実行補助
# ----------------------------------------------------------------------------
function Invoke-Gen {
    # generateLinks.ps1(または指定スクリプト)を子プロセスで実行し、出力と終了コードを返す。
    # 引数:
    #   $GenArgs - スクリプトへ渡す引数配列
    #   $WorkDir - 実行時のカレントディレクトリ(省略時は現在の場所)
    #   $Script  - 実行するスクリプトのパス(省略時は $GEN_SCRIPT)
    # 返り値: [pscustomobject] @{ Out; Code }
    param([string[]] $GenArgs, [string] $WorkDir, [string] $Script = $GEN_SCRIPT)
    $ErrorActionPreference = 'Continue'   # 子プロセスが stderr に書いても停止しないようにする
    $errFile = [System.IO.Path]::GetTempFileName()
    $pushed = $false
    try {
        if ($WorkDir) { Push-Location -LiteralPath $WorkDir; $pushed = $true }
        $stdout = & $HOST_EXE -NoProfile -NonInteractive -File $Script @GenArgs 2>$errFile | Out-String
        $code   = $LASTEXITCODE
        $stderr = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
        return [pscustomobject]@{ Out = ($stdout + "`n" + [string]$stderr); Code = $code }
    } finally {
        if ($pushed) { Pop-Location }
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }
}

function New-ListFile {
    # 指定パス群を1行ずつ書いたリストファイルを作る。
    # 引数:
    #   $Dir   - 出力先フォルダ
    #   $Name  - リストファイル名
    #   $Paths - 記載するパス配列
    # 返り値: [string] 作成したリストファイルの絶対パス
    param([string] $Dir, [string] $Name, [string[]] $Paths)
    $p = Join-Path $Dir $Name
    Set-Content -LiteralPath $p -Value $Paths -Encoding UTF8
    return $p
}

function Get-HardLinkCountForTest {
    # fsutil でハードリンク数を数える(検証用)。返り値: [int]
    param([string] $Path)
    $o = @(& fsutil hardlink list "$Path" 2>$null)
    return @($o | Where-Object { $_.Trim().Length -gt 0 }).Count
}

function Test-SymlinkCapability {
    # このセッションでシンボリックリンクを作成できるか調べる。返り値: [bool]
    param([string] $WorkDir)
    $probe = Join-Path $WorkDir ('probe_'  + [guid]::NewGuid().ToString('N') + '.txt')
    $tgt   = Join-Path $WorkDir ('probet_' + [guid]::NewGuid().ToString('N') + '.txt')
    Set-Content -LiteralPath $tgt -Value 'x' -Encoding UTF8
    try {
        New-Item -ItemType SymbolicLink -Path $probe -Value $tgt -ErrorAction Stop | Out-Null
        Remove-Item -LiteralPath $probe -Force
        return $true
    } catch {
        return $false
    } finally {
        Remove-Item -LiteralPath $tgt -Force -ErrorAction SilentlyContinue
    }
}

# ----------------------------------------------------------------------------
# シナリオ
# ----------------------------------------------------------------------------
function Invoke-ArgScenarios {
    # 引数解析まわり(usage / 未知オプション / 位置引数過多 / target 不在)。
    # 引数: $Tmp - 作業フォルダ / $Master - ダミー実体 / $ValidList - 既存のリストファイル
    # 返り値: なし
    param([string] $Tmp, [string] $Master, [string] $ValidList)

    Write-Head 'args: no argument -> usage, exit 0'
    $r = Invoke-Gen @()
    Assert-Eq    $r.Code 0            'no-arg exit code is 0'
    Assert-Match $r.Out  'USAGE'      'no-arg prints USAGE'

    Write-Head 'args: unknown option -> exit 2'
    $r = Invoke-Gen @('--bogus')
    Assert-Eq    $r.Code 2                 'unknown-option exit code is 2'
    Assert-Match $r.Out  'Unknown option'  'unknown-option message'

    Write-Head 'args: too many positionals -> exit 2'
    $r = Invoke-Gen @('a.md', 'b.md')
    Assert-Eq    $r.Code 2                       'two-positionals exit code is 2'
    Assert-Match $r.Out  'Too many positional'   'two-positionals message'

    Write-Head 'args: missing target file -> exit 2'
    $missing = Join-Path $Tmp ('nope_' + [guid]::NewGuid().ToString('N') + '.md')
    $r = Invoke-Gen @('--target', $missing, '--source', $ValidList)
    Assert-Eq    $r.Code 2                  'missing-target exit code is 2'
    Assert-Match $r.Out  'Target not found' 'missing-target message'

    Write-Head 'args: missing list file -> exit 2'
    $missingList = Join-Path $Tmp ('nolist_' + [guid]::NewGuid().ToString('N') + '.list')
    $r = Invoke-Gen @('--target', $Master, '--source', $missingList)
    Assert-Eq    $r.Code 2                     'missing-list exit code is 2'
    Assert-Match $r.Out  'List file not found' 'missing-list message'
}

function Invoke-CheckScenario {
    # --check: 存在/不在エントリの一覧、Links 列。
    # 引数: $Tmp - 作業フォルダ / $Master - ダミー実体
    # 返り値: なし
    param([string] $Tmp, [string] $Master)

    Write-Head 'check: existing real file + missing entry'
    $real = Join-Path $Tmp 'check_real.md'
    Set-Content -LiteralPath $real -Value 'real' -Encoding UTF8
    $missing = Join-Path $Tmp 'check_missing.md'
    $list = New-ListFile $Tmp 'check.list' @($real, $missing)

    $r = Invoke-Gen @('--check', '--target', $Master, '--source', $list)
    Assert-Eq    $r.Code 0             'check exit code is 0'
    Assert-Match $r.Out  'check_real'  'check lists the real file'
    Assert-Match $r.Out  'check_missing' 'check lists the missing entry'
    Assert-Match $r.Out  'Real'        'check shows Type=Real'
    Assert-Match $r.Out  'Links'       'check output has a Links column'
    Assert-Match $r.Out  'Source:'     'check prints Source line'
}

function Invoke-HardLinkScenarios {
    # hard link: 新規作成 / 既存で skip / --overwrite で置換 / 親フォルダ無し /
    #            実体保護 / ディレクトリ target で fail(exit 1)。
    # 引数: $Tmp - 作業フォルダ / $Master - ダミー実体 / $Master2 - 別実体
    # 返り値: なし
    param([string] $Tmp, [string] $Master, [string] $Master2)

    Write-Head 'hard: fresh create'
    $h1 = Join-Path $Tmp 'hard_link1.md'
    $list = New-ListFile $Tmp 'hard1.list' @($h1)
    $r = Invoke-Gen @('--hard', '--target', $Master, '--source', $list, '--verbose')
    Assert-Eq    $r.Code 0           'hard fresh exit 0'
    Assert-Match $r.Out  'created\.' 'hard fresh says created.'
    Assert-True  (Test-Path -LiteralPath $h1)                       'hard link file exists'
    Assert-True  ((Get-HardLinkCountForTest $Master) -ge 2)         'master now has >=2 hard links'

    Write-Head 'hard: run again -> skip (already exists)'
    $r = Invoke-Gen @('--hard', '--target', $Master, '--source', $list, '--verbose')
    Assert-Eq    $r.Code 0                       'hard re-run exit 0'
    Assert-Match $r.Out  'Hardlink already exists' 'hard re-run says already exists'

    Write-Head 'hard: --overwrite replaces the link'
    $r = Invoke-Gen @('--hard', '--overwrite', '--target', $Master2, '--source', $list, '--verbose')
    Assert-Eq    $r.Code 0             'hard overwrite exit 0'
    Assert-Match $r.Out  'overwritten\.' 'hard overwrite says overwritten.'
    Assert-True  ((Get-HardLinkCountForTest $Master2) -ge 2) 'master2 now has >=2 hard links'

    Write-Head 'hard: parent folder missing -> skip'
    $noParent = Join-Path $Tmp 'no_such_dir\deep.md'
    $list2 = New-ListFile $Tmp 'hard_noparent.list' @($noParent)
    $r = Invoke-Gen @('--hard', '--target', $Master, '--source', $list2, '--verbose')
    Assert-Eq    $r.Code 0                   'missing-parent exit 0 (skip)'
    Assert-Match $r.Out  'Folder not exists\.' 'missing-parent says Folder not exists.'

    Write-Head 'hard: real file is protected even with --overwrite'
    $realp = Join-Path $Tmp 'hard_realprotect.md'
    Set-Content -LiteralPath $realp -Value 'ORIG' -Encoding UTF8
    $list3 = New-ListFile $Tmp 'hard_protect.list' @($realp)
    $r = Invoke-Gen @('--hard', '--overwrite', '--target', $Master, '--source', $list3, '--verbose')
    Assert-Eq    $r.Code 0                    'real-protect exit 0'
    Assert-Match $r.Out  'File already exists\.' 'real-protect says File already exists.'
    Assert-Eq    (Get-Content -LiteralPath $realp -Raw).Trim() 'ORIG' 'real file content unchanged'

    Write-Head 'hard: directory target -> fail (exit 1)'
    $dirTargetLink = Join-Path $Tmp 'hard_from_dir.md'
    $list4 = New-ListFile $Tmp 'hard_dir.list' @($dirTargetLink)
    $r = Invoke-Gen @('--hard', '--target', $Tmp, '--source', $list4, '--verbose')
    Assert-Eq    $r.Code 1                'dir-target exit 1'
    Assert-Match $r.Out  'is a directory' 'dir-target message'
}

function Invoke-SourceLookupScenario {
    # --source 未指定時: スクリプトフォルダに無ければカレントディレクトリの target.list を探す。
    # 引数: $Tmp - 作業フォルダ / $Master - ダミー実体
    # 返り値: なし
    param([string] $Tmp, [string] $Master)

    # スクリプト一式を target.list の無い隔離フォルダへコピー
    $isoDir = Join-Path $Tmp 'iso_script'
    New-Item -ItemType Directory -Path $isoDir -Force | Out-Null
    Copy-Item -LiteralPath $GEN_SCRIPT -Destination $isoDir
    $fmt = Join-Path $PSScriptRoot 'generateLinks.format.ps1xml'
    if (Test-Path -LiteralPath $fmt) { Copy-Item -LiteralPath $fmt -Destination $isoDir }
    $isoScript = Join-Path $isoDir 'generateLinks.ps1'

    Write-Head 'source: falls back to current directory target.list'
    $cwdDir = Join-Path $Tmp 'cwd_here'
    New-Item -ItemType Directory -Path $cwdDir -Force | Out-Null
    $entry = Join-Path $cwdDir 'from_cwd_list.md'
    Set-Content -LiteralPath (Join-Path $cwdDir 'target.list') -Value @($entry) -Encoding UTF8

    $r = Invoke-Gen -GenArgs @('--check', '--target', $Master) -WorkDir $cwdDir -Script $isoScript
    Assert-Eq    $r.Code 0          'cwd-fallback exit 0'
    Assert-Match $r.Out  'cwd_here' 'cwd-fallback used ./target.list'

    Write-Head 'source: clear error when target.list is nowhere'
    $r = Invoke-Gen -GenArgs @('--check', '--target', $Master) -WorkDir $isoDir -Script $isoScript
    Assert-Eq    $r.Code 2         'no-list-anywhere exit 2'
    Assert-Match $r.Out  'not found' 'no-list-anywhere clear message'
}

function Invoke-DryRunScenario {
    # --dry-run: 何も作らずに予定だけ表示。
    # 引数: $Tmp - 作業フォルダ / $Master - ダミー実体
    # 返り値: なし
    param([string] $Tmp, [string] $Master)

    Write-Head 'dry-run: nothing is created'
    $d = Join-Path $Tmp 'dry_link.md'
    $list = New-ListFile $Tmp 'dry.list' @($d)
    $r = Invoke-Gen @('--dry-run', '--verbose', '--hard', '--target', $Master, '--source', $list)
    Assert-Eq    $r.Code 0                  'dry-run exit 0'
    Assert-Match $r.Out  'would create'     'dry-run says would create'
    Assert-True  (-not (Test-Path -LiteralPath $d)) 'dry-run created no file'
}

function Invoke-SymlinkScenarios {
    # symbolic link: 新規作成 / 既存で skip / --check の Link to と points-to-another-file。
    # 引数: $Tmp - 作業フォルダ / $Master - ダミー実体 / $Master2 - 別実体
    # 返り値: なし
    param([string] $Tmp, [string] $Master, [string] $Master2)

    Write-Head 'symlink: fresh create + re-run skip'
    $s1 = Join-Path $Tmp 'sym_link1.md'
    $list = New-ListFile $Tmp 'sym1.list' @($s1)
    $r = Invoke-Gen @('--target', $Master, '--source', $list, '--verbose')
    Assert-Eq    $r.Code 0           'symlink fresh exit 0'
    Assert-Match $r.Out  'created\.' 'symlink fresh says created.'
    Assert-True  (Test-Path -LiteralPath $s1) 'symlink file exists'
    $item = Get-Item -LiteralPath $s1 -Force
    Assert-True  (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) 'symlink is a reparse point'

    $r = Invoke-Gen @('--target', $Master, '--source', $list, '--verbose')
    Assert-Match $r.Out 'Symlink already exists' 'symlink re-run says already exists'

    Write-Head 'symlink: --check shows Link to, and flags points-to-another-file'
    $r = Invoke-Gen @('--check', '--target', $Master, '--source', $list)
    Assert-Match $r.Out 'SymbolicLink' 'check shows Type=SymbolicLink'

    $r = Invoke-Gen @('--check', '--target', $Master2, '--source', $list)
    Assert-Match $r.Out 'points to another file' 'check flags mismatched symlink target'
}

# ----------------------------------------------------------------------------
# メイン
# ----------------------------------------------------------------------------
function Invoke-AllTests {
    # 一時フォルダを用意して全シナリオを実行し、終了コードを決める。
    # 返り値: なし(内部で exit)
    # 作業フォルダは意図的に短いパスにする(表出力の列切り詰めで assert が壊れないように)。
    $tmp = Join-Path $env:USERPROFILE ('glt_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    Write-Host "Work dir: $tmp" -ForegroundColor DarkGray
    Write-Host "Target script: $GEN_SCRIPT" -ForegroundColor DarkGray
    Write-Host "Host: $HOST_EXE ($($PSVersionTable.PSVersion))" -ForegroundColor DarkGray

    try {
        $master  = Join-Path $tmp 'master.md'
        $master2 = Join-Path $tmp 'master2.md'
        Set-Content -LiteralPath $master  -Value '# master instructions'  -Encoding UTF8
        Set-Content -LiteralPath $master2 -Value '# master instructions 2' -Encoding UTF8
        $validList = New-ListFile $tmp 'valid.list' @((Join-Path $tmp 'placeholder.md'))

        $canSymlink = Test-SymlinkCapability -WorkDir $tmp
        Write-Host "Symbolic link capability: $canSymlink" -ForegroundColor DarkGray

        Invoke-ArgScenarios   -Tmp $tmp -Master $master -ValidList $validList
        Invoke-SourceLookupScenario -Tmp $tmp -Master $master
        Invoke-CheckScenario  -Tmp $tmp -Master $master
        Invoke-HardLinkScenarios -Tmp $tmp -Master $master -Master2 $master2
        Invoke-DryRunScenario -Tmp $tmp -Master $master

        if ($canSymlink) {
            Invoke-SymlinkScenarios -Tmp $tmp -Master $master -Master2 $master2
        } else {
            Write-Head 'symlink scenarios'
            Skip-Case 'symlink create / check' 'no privilege (enable Developer Mode or run as admin)'
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ''
    Write-Host ('Result: PASS={0}  FAIL={1}  SKIP={2}' -f $Script:Pass, $Script:Fail, $Script:Skip) -ForegroundColor White
    if ($Script:Fail -gt 0) { exit 1 }
    exit 0
}

Invoke-AllTests
