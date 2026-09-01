<#
    generateLinks.ps1

    リストファイルに書かれたパスへ、指定した1つの実体ファイル/フォルダの
    シンボリックリンク(既定)またはハードリンク(--hard)を一括作成する。

    仕様の確定内容は generateLinks.ToDo.md を参照。
    使い方は  .\generateLinks.ps1 --help  で表示。
#>
#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# 定数
# ============================================================================

# 動作ログの既定レベル。'Quiet' / 'Normal' / 'Debug'。
# 開発時は 'Debug' にすると関数トレースを表示する。完成後は 'Normal' 運用。
$Script:LogLevel = 'Normal'

$DEFAULT_LIST_NAME = 'target.list'

# 出力メッセージ(英語)
$MSG_CREATED          = 'created.'
$MSG_OVERWRITTEN      = 'overwritten.'
$MSG_REAL_EXISTS      = 'File already exists.'
$MSG_SYMLINK_EXISTS   = 'Symlink already exists'
$MSG_HARDLINK_EXISTS  = 'Hardlink already exists'
$MSG_NO_FOLDER        = 'Folder not exists.'
$MSG_HARD_DIR         = 'Target is a directory (hardlink not allowed).'
$MSG_HARD_VOLUME      = 'Different volume (hardlink not allowed).'
$MSG_POINTS_ELSEWHERE = 'points to another file'
$MSG_DRYRUN           = 'would create (dry-run).'

# 終了コード
$EXIT_OK       = 0
$EXIT_HAS_FAIL = 1
$EXIT_USAGE    = 2

# ============================================================================
# 動作ログ
# ============================================================================

function Write-DebugLog {
    # 診断メッセージを表示する($Script:LogLevel が 'Debug' のときのみ)。返り値: なし
    param([string] $Message)
    if ($Script:LogLevel -eq 'Debug') { Write-Host "[debug] $Message" -ForegroundColor DarkGray }
}

function Write-VerboseLog {
    # 詳細トレースを表示する($Script:LogLevel が 'Debug' のときのみ)。返り値: なし
    param([string] $Message)
    if ($Script:LogLevel -eq 'Debug') { Write-Host "[verbose] $Message" -ForegroundColor DarkGray }
}

function Write-FatalError {
    # 致命的エラーを標準エラーへ出力し、使用方法エラーとしてプロセスを終了する。返り値: なし(exit)
    param([string] $Message)
    [Console]::Error.WriteLine("ERROR: $Message")
    exit $EXIT_USAGE
}

# ============================================================================
# 使用方法
# ============================================================================

function Show-Usage {
    # 使用方法を標準出力へ表示する。返り値: なし
    $text = @'
generateLinks - create symbolic / hard links listed in a list file.

USAGE
  generateLinks.ps1 <target> [options]
  generateLinks.ps1 --target <file> [options]
  generateLinks.ps1                     (no argument -> show this help)

OPTIONS
  -t, --target <path>   Real file or directory to link FROM. Required.
                        A bare positional argument is treated as --target.
  -s, --source <path>   List file (default: <script folder>\target.list).
  -o, --overwrite       Replace an existing LINK. Real files/dirs are kept.
      --hard            Create hard links instead of symbolic links.
      --check           Only report existence / type of each entry. No changes.
      --dry-run         Show what would happen; create nothing.
  -v, --verbose         Print the result table.
  -h, --help            Show this help.

LIST FILE FORMAT
  One path per line. Blank lines and lines starting with '#' are ignored.
  %VAR%, $env:VAR and a leading ~ are expanded.
  Relative paths are resolved against the list file's own folder.

EXIT CODES
  0  all entries succeeded or were skipped
  1  one or more entries failed
  2  usage error, or target / list file not found
'@
    Write-Host $text
}

# ============================================================================
# 引数解析
# ============================================================================

function Convert-ArgList {
    # コマンドライン引数を解析し、設定オブジェクトを返す。
    # 引数:
    #   $ArgList - $args (スクリプトへ渡された生の引数配列)
    # 返り値: [pscustomobject] @{ Target; Source; Verbose; Overwrite; Hard; Check; DryRun; Help; ShowUsage; Error }
    param([string[]] $ArgList)

    $opt = [pscustomobject]@{
        Target = $null; Source = $null; Verbose = $false; Overwrite = $false
        Hard = $false; Check = $false; DryRun = $false; Help = $false
        ShowUsage = $false; Error = $null
    }
    if (-not $ArgList -or $ArgList.Count -eq 0) { $opt.ShowUsage = $true; return $opt }

    $positional = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $ArgList.Count; $i++) {
        $tok = [string]$ArgList[$i]
        $low = $tok.ToLowerInvariant()

        if ($low -in @('--target', '-t', '--source', '-s')) {
            if ($i + 1 -ge $ArgList.Count) { $opt.Error = "Option '$tok' requires a value."; return $opt }
            $val = [string]$ArgList[$i + 1]; $i++
            if ($low -eq '--target' -or $low -eq '-t') { $opt.Target = $val } else { $opt.Source = $val }
            continue
        }

        switch ($low) {
            '--verbose'   { $opt.Verbose = $true }
            '-v'          { $opt.Verbose = $true }
            '--overwrite' { $opt.Overwrite = $true }
            '-o'          { $opt.Overwrite = $true }
            '--hard'      { $opt.Hard = $true }
            '--check'     { $opt.Check = $true }
            '--dry-run'   { $opt.DryRun = $true }
            '--help'      { $opt.Help = $true }
            '-h'          { $opt.Help = $true }
            '-?'          { $opt.Help = $true }
            default {
                if ($low.StartsWith('-')) { $opt.Error = "Unknown option: $tok"; return $opt }
                $positional.Add($tok)
            }
        }
    }

    if ($positional.Count -gt 1) { $opt.Error = 'Too many positional arguments (only one target allowed).'; return $opt }
    if ($positional.Count -eq 1) {
        if ($opt.Target) { $opt.Error = 'Target given twice (positional and --target).'; return $opt }
        $opt.Target = $positional[0]
    }
    return $opt
}

# ============================================================================
# パス解決
# ============================================================================

function Expand-EntryPath {
    # リスト1行分のパス文字列を展開し、絶対パスへ正規化する。
    # 引数:
    #   $Raw     - リストファイルの1行(コメント/空行除外済み)
    #   $BaseDir - 相対パスの基準ディレクトリ(リストファイルのある場所)
    # 返り値: [string] 絶対パス
    param([string] $Raw, [string] $BaseDir)

    $s = $Raw.Trim().Trim('"')
    if ($s -eq '~') { $s = $HOME }
    elseif ($s.StartsWith('~/') -or $s.StartsWith('~\')) { $s = Join-Path $HOME $s.Substring(2) }

    $s = [Environment]::ExpandEnvironmentVariables($s)                       # %VAR%
    $s = [regex]::Replace($s, '\$env:([A-Za-z_][A-Za-z0-9_]*)', {           # $env:VAR
        param($m)
        $v = [Environment]::GetEnvironmentVariable($m.Groups[1].Value)
        if ($null -eq $v) { $m.Value } else { $v }
    })

    if (-not [System.IO.Path]::IsPathRooted($s)) { $s = Join-Path $BaseDir $s }
    return [System.IO.Path]::GetFullPath($s)
}

function Resolve-TargetInfo {
    # --target のパスをカレント基準で解決する。存在しなければ致命的エラーで終了。
    # 引数:
    #   $Target - --target で指定された文字列
    # 返り値: [pscustomobject] @{ Path; IsDirectory }
    param([string] $Target)

    if ([string]::IsNullOrWhiteSpace($Target)) { Write-FatalError 'No target specified. Use --target <file>.' }
    try {
        $full = (Resolve-Path -LiteralPath $Target -ErrorAction Stop).ProviderPath
    } catch {
        Write-FatalError "Target not found: $Target"
    }
    $item = Get-Item -LiteralPath $full -Force
    return [pscustomobject]@{ Path = $full; IsDirectory = [bool]$item.PSIsContainer }
}

function Resolve-SourcePath {
    # リストファイルのパスを解決する。--source 未指定ならスクリプトフォルダの target.list。
    # 引数:
    #   $Source    - --source 指定値(カレント基準) / 空なら既定
    #   $ScriptDir - このスクリプトの存在フォルダ
    # 返り値: [string] リストファイルの絶対パス(存在しなければ致命的エラーで終了)
    param([string] $Source, [string] $ScriptDir)

    if ([string]::IsNullOrWhiteSpace($Source)) { $candidate = Join-Path $ScriptDir $DEFAULT_LIST_NAME }
    else { $candidate = $Source }

    try {
        return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).ProviderPath
    } catch {
        Write-FatalError "List file not found: $candidate"
    }
}

function Read-LinkList {
    # リストファイルを読み込み、コメント/空行を除いた絶対パス配列を返す。
    # 引数:
    #   $ListPath - リストファイルの絶対パス
    # 返り値: [string[]] 絶対パスの配列(0件あり得る)
    param([string] $ListPath)

    $baseDir = [System.IO.Path]::GetDirectoryName($ListPath)
    $lines = @(Get-Content -LiteralPath $ListPath -Encoding UTF8)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $t = $line.Trim()
        if ($t.Length -eq 0) { continue }
        if ($t.StartsWith('#')) { continue }
        $result.Add((Expand-EntryPath -Raw $t -BaseDir $baseDir))
    }
    return $result.ToArray()
}

# ============================================================================
# リンク種別の判定
# ============================================================================

function Get-HardLinkCount {
    # 同一実体を指すハードリンク数を返す(fsutil 使用、管理者権限不要)。
    # 引数:
    #   $Path - 対象ファイルの絶対パス
    # 返り値: [int] リンク数(取得失敗時は 1)
    param([string] $Path)
    try {
        $out = @(& fsutil hardlink list "$Path" 2>$null)
        if ($LASTEXITCODE -ne 0 -or $out.Count -eq 0) { return 1 }
        $count = @($out | Where-Object { $_.Trim().Length -gt 0 }).Count
        if ($count -lt 1) { return 1 }
        return $count
    } catch {
        return 1
    }
}

function Get-OtherHardLink {
    # 対象と同一実体を指す「別の」ハードリンクパスを1つ返す。
    # 引数:
    #   $Path - 対象ファイルの絶対パス
    # 返り値: [string] 別パス(見つからなければ $null)
    param([string] $Path)
    try {
        $root = [System.IO.Path]::GetPathRoot($Path).TrimEnd('\')
        $out = @(& fsutil hardlink list "$Path" 2>$null)
        if ($LASTEXITCODE -ne 0) { return $null }
        foreach ($line in $out) {
            $rel = $line.Trim()
            if ($rel.Length -eq 0) { continue }
            $abs = $root + $rel
            if ($abs -ine $Path) { return $abs }
        }
        return $null
    } catch {
        return $null
    }
}

function Get-SymlinkTarget {
    # シンボリックリンク/ジャンクションのリンク先を返す。
    # 引数:
    #   $Path - リンクの絶対パス
    # 返り値: [string] リンク先パス(取得不可なら $null)
    param([string] $Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $tgt = $item.Target
        if ($tgt) { return [string]($tgt | Select-Object -First 1) }
        return $null
    } catch {
        return $null
    }
}

function Get-LinkKind {
    # 指定パスの種類を判定する。
    # 引数:
    #   $Path - 判定対象の絶対パス(存在する前提)
    # 返り値: [string] 'Real' | 'SymbolicLink' | 'HardLink' | 'Junction'
    param([string] $Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return 'Real' }

    $lt = $null
    try { $lt = $item.LinkType } catch { $lt = $null }
    switch ($lt) {
        'SymbolicLink' { return 'SymbolicLink' }
        'Junction'     { return 'Junction' }
        'HardLink'     { return 'HardLink' }
    }
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return 'SymbolicLink' }
    if (-not $item.PSIsContainer -and (Get-HardLinkCount -Path $Path) -gt 1) { return 'HardLink' }
    return 'Real'
}

function Get-TypeOrDash {
    # パスが存在すれば種類を、無ければ '-' を返す。
    # 引数:
    #   $Path - 対象パス
    # 返り値: [string]
    param([string] $Path)
    if (Test-Path -LiteralPath $Path) { return (Get-LinkKind -Path $Path) }
    return '-'
}

function Test-SameVolume {
    # 2つのパスが同一ボリューム上にあるか判定する(ハードリンク可否用)。
    # 引数:
    #   $PathA - 比較パス1(絶対)
    #   $PathB - 比較パス2(絶対)
    # 返り値: [bool] 同一ボリュームなら $true
    param([string] $PathA, [string] $PathB)
    $a = [System.IO.Path]::GetPathRoot($PathA)
    $b = [System.IO.Path]::GetPathRoot($PathB)
    return [bool]($a -and $b -and ($a.TrimEnd('\') -ieq $b.TrimEnd('\')))
}

# ============================================================================
# リンク作成
# ============================================================================

function Test-IsPrivilegeError {
    # 例外レコードがシンボリックリンク作成の権限不足を示すか判定する。
    # 引数:
    #   $ErrRecord - catch した $_
    # 返り値: [bool]
    param($ErrRecord)
    $msg = "$($ErrRecord.Exception.Message)"
    return [bool]($msg -match '1314' -or $msg -match 'privilege' -or $msg -match 'SeCreateSymbolicLink')
}

function Remove-LinkOnly {
    # リンク自体のみを削除する(シンボリックリンク先の実体には触れない)。
    # 引数:
    #   $Path - 削除するリンクのパス
    # 返り値: なし(失敗時は例外)
    param([string] $Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer) { [System.IO.Directory]::Delete($Path, $false) }
    else { [System.IO.File]::Delete($Path) }
}

function New-RequestedLink {
    # 要求された種類のリンクを1つ作成する(DryRun 対応)。
    # 引数:
    #   $LinkPath   - 作成するリンクのフルパス
    #   $TargetPath - リンク元(実体)のフルパス
    #   $AsHard     - $true でハードリンク / $false でシンボリックリンク
    #   $DryRun     - $true なら実際には作成しない
    # 返り値: [pscustomobject] @{ Ok; Message }
    param([string] $LinkPath, [string] $TargetPath, [bool] $AsHard, [bool] $DryRun)

    if ($DryRun) { return [pscustomobject]@{ Ok = $true; Message = $MSG_DRYRUN } }

    $kind = if ($AsHard) { 'HardLink' } else { 'SymbolicLink' }
    try {
        New-Item -ItemType $kind -Path $LinkPath -Value $TargetPath -ErrorAction Stop | Out-Null
        return [pscustomobject]@{ Ok = $true; Message = $MSG_CREATED }
    } catch {
        if (-not $AsHard -and (Test-IsPrivilegeError $_)) {
            Write-FatalError (
                "Cannot create a symbolic link (a required privilege is not held). " +
                "Enable Windows 'Developer Mode' or run PowerShell as Administrator, " +
                "or use --hard for hard links.`n  $($_.Exception.Message)")
        }
        return [pscustomobject]@{ Ok = $false; Message = "failed: $($_.Exception.Message)" }
    }
}

# ============================================================================
# 結果行の生成
# ============================================================================

function New-ResultRow {
    # 結果表示用の1行オブジェクトを生成する。
    # 引数:
    #   $Result      - 'success' | 'skip' | 'fail'
    #   $Exists      - [bool] リンク先パスが存在するか
    #   $Type        - 'Real'|'SymbolicLink'|'HardLink'|'Junction'|'-'
    #   $Path        - リンク先パス
    #   $Description - 処理結果の説明
    # 返り値: [pscustomobject]
    param([string] $Result, [bool] $Exists, [string] $Type, [string] $Path, [string] $Description)
    $row = [pscustomobject][ordered]@{
        Result = $Result; Exists = $Exists; Type = $Type; Path = $Path; Description = $Description
    }
    $row.PSObject.TypeNames.Insert(0, 'GenerateLinks.ResultRow')
    return $row
}

function Get-CheckRow {
    # --check モード用に、1エントリの状態行を作る。
    # 引数:
    #   $LinkPath   - リストのエントリ(絶対パス)
    #   $TargetPath - --target の実体パス(絶対、比較用)
    # 返り値: [pscustomobject] @{ Exists; Type; Path; 'Link to'; Links }
    param([string] $LinkPath, [string] $TargetPath)

    $exists = [bool](Test-Path -LiteralPath $LinkPath)
    $kind   = '-'
    $linkTo = '-'
    $links  = 0

    if ($exists) {
        $kind  = Get-LinkKind -Path $LinkPath
        $links = 1
        switch ($kind) {
            'SymbolicLink' {
                $t = Get-SymlinkTarget -Path $LinkPath
                if ($t) {
                    $linkTo = $t
                    $resolved = $t
                    try { $resolved = [System.IO.Path]::GetFullPath($t) } catch { }
                    if ($resolved -ine $TargetPath) { $linkTo = "$t  ($MSG_POINTS_ELSEWHERE)" }
                }
            }
            'Junction' {
                $t = Get-SymlinkTarget -Path $LinkPath
                if ($t) { $linkTo = $t }
            }
            'HardLink' {
                $links = Get-HardLinkCount -Path $LinkPath
                $other = Get-OtherHardLink -Path $LinkPath
                if ($other) { $linkTo = $other }
            }
        }
    }

    $row = [pscustomobject][ordered]@{ Exists = $exists; Type = $kind; Path = $LinkPath; 'Link to' = $linkTo; Links = $links }
    $row.PSObject.TypeNames.Insert(0, 'GenerateLinks.CheckRow')
    return $row
}

function Test-HardLinkBlocked {
    # ハードリンク不可条件に該当すれば結果行を、なければ $null を返す。
    # 引数:
    #   $LinkPath   - リンクのパス
    #   $TargetInfo - ターゲット情報(Path, IsDirectory)
    # 返り値: [pscustomobject] or $null
    param([string] $LinkPath, $TargetInfo)
    if ($TargetInfo.IsDirectory) {
        return (New-ResultRow 'fail' (Test-Path -LiteralPath $LinkPath) (Get-TypeOrDash $LinkPath) $LinkPath $MSG_HARD_DIR)
    }
    if (-not (Test-SameVolume $LinkPath $TargetInfo.Path)) {
        return (New-ResultRow 'fail' (Test-Path -LiteralPath $LinkPath) (Get-TypeOrDash $LinkPath) $LinkPath $MSG_HARD_VOLUME)
    }
    return $null
}

function Get-FreshLinkRow {
    # リンク先が存在しない場合に新規作成し、結果行を返す。
    # 引数:
    #   $LinkPath   - 作成するリンクのパス
    #   $TargetInfo - ターゲット情報(Path, IsDirectory)
    #   $Options    - Convert-ArgList の戻り値
    # 返り値: [pscustomobject] 結果行
    param([string] $LinkPath, $TargetInfo, $Options)

    $r = New-RequestedLink -LinkPath $LinkPath -TargetPath $TargetInfo.Path -AsHard $Options.Hard -DryRun $Options.DryRun
    if ($Options.DryRun) { return (New-ResultRow 'success' $false '-' $LinkPath $MSG_DRYRUN) }
    if ($r.Ok) { return (New-ResultRow 'success' $true (Get-LinkKind -Path $LinkPath) $LinkPath $r.Message) }
    return (New-ResultRow 'fail' (Test-Path -LiteralPath $LinkPath) (Get-TypeOrDash $LinkPath) $LinkPath $r.Message)
}

function Get-ExistingLinkRow {
    # リンク先が既に存在する場合の処理(実体は保護 / skip / --overwrite で置換)。
    # 引数:
    #   $LinkPath   - リンクのパス
    #   $TargetInfo - ターゲット情報(Path, IsDirectory)
    #   $Options    - Convert-ArgList の戻り値
    # 返り値: [pscustomobject] 結果行
    param([string] $LinkPath, $TargetInfo, $Options)

    $kind = Get-LinkKind -Path $LinkPath
    if ($kind -eq 'Real' -or $kind -eq 'Junction') {
        return (New-ResultRow 'skip' $true $kind $LinkPath $MSG_REAL_EXISTS)
    }

    $existsMsg = if ($kind -eq 'HardLink') { $MSG_HARDLINK_EXISTS } else { $MSG_SYMLINK_EXISTS }
    if (-not $Options.Overwrite) { return (New-ResultRow 'skip' $true $kind $LinkPath $existsMsg) }
    if ($Options.DryRun)        { return (New-ResultRow 'success' $true $kind $LinkPath $MSG_DRYRUN) }

    try {
        Remove-LinkOnly -Path $LinkPath
    } catch {
        return (New-ResultRow 'fail' $true $kind $LinkPath "failed to remove existing link: $($_.Exception.Message)")
    }

    $r = New-RequestedLink -LinkPath $LinkPath -TargetPath $TargetInfo.Path -AsHard $Options.Hard -DryRun $false
    if ($r.Ok) { return (New-ResultRow 'success' $true (Get-LinkKind -Path $LinkPath) $LinkPath $MSG_OVERWRITTEN) }
    return (New-ResultRow 'fail' (Test-Path -LiteralPath $LinkPath) (Get-TypeOrDash $LinkPath) $LinkPath $r.Message)
}

function Get-CreateRow {
    # create / dry-run モードで1エントリを処理し、結果行を返す。
    # 引数:
    #   $LinkPath   - 作成するリンクのパス(絶対)
    #   $TargetInfo - Resolve-TargetInfo の戻り値(Path, IsDirectory)
    #   $Options    - Convert-ArgList の戻り値
    # 返り値: [pscustomobject] @{ Result; Exists; Type; Path; Description }
    param([string] $LinkPath, $TargetInfo, $Options)

    $parent = [System.IO.Path]::GetDirectoryName($LinkPath)
    if ([string]::IsNullOrEmpty($parent) -or -not (Test-Path -LiteralPath $parent)) {
        return (New-ResultRow 'skip' $false '-' $LinkPath $MSG_NO_FOLDER)
    }

    if ($Options.Hard) {
        $blocked = Test-HardLinkBlocked -LinkPath $LinkPath -TargetInfo $TargetInfo
        if ($blocked) { return $blocked }
    }

    if (Test-Path -LiteralPath $LinkPath) {
        return (Get-ExistingLinkRow -LinkPath $LinkPath -TargetInfo $TargetInfo -Options $Options)
    }
    return (Get-FreshLinkRow -LinkPath $LinkPath -TargetInfo $TargetInfo -Options $Options)
}

# ============================================================================
# 出力
# ============================================================================

function Emit-Rows {
    # 結果行を出力する。'Source:' 行はコンソールへ(Write-Host)、行はオブジェクトとして
    # パイプラインへ流す。コンソール表示は generateLinks.format.ps1xml の表ビューに従う。
    # 引数:
    #   $SourcePath - 'Source:' 行に表示する --target の絶対パス
    #   $Rows       - 出力する行オブジェクトの配列
    # 返り値: なし (パイプラインに $Rows を放流)
    param([string] $SourcePath, [object[]] $Rows)

    Write-Host "Source: $SourcePath"
    Write-Host ''
    if ($Rows -and $Rows.Count -gt 0) { $Rows }
}

# ============================================================================
# エントリポイント
# ============================================================================

function Invoke-GenerateLinks {
    # 引数解析からリンク処理・出力・終了コードまでを実行する。
    # 引数:
    #   $RawArgs   - $args(生のコマンドライン引数)
    #   $ScriptDir - このスクリプトの存在フォルダ($PSScriptRoot)
    # 返り値: なし(内部で exit する)
    param([string[]] $RawArgs, [string] $ScriptDir)

    $opt = Convert-ArgList -ArgList $RawArgs
    if ($opt.ShowUsage -or $opt.Help) { Show-Usage; exit $EXIT_OK }
    if ($opt.Error) { [Console]::Error.WriteLine($opt.Error); Write-Host ''; Show-Usage; exit $EXIT_USAGE }

    Write-DebugLog "options: $($opt | Out-String)"

    $targetInfo = Resolve-TargetInfo -Target $opt.Target
    $listPath   = Resolve-SourcePath -Source $opt.Source -ScriptDir $ScriptDir
    Write-VerboseLog "target = $($targetInfo.Path) (dir=$($targetInfo.IsDirectory))"
    Write-VerboseLog "source = $listPath"

    $entries = @(Read-LinkList -ListPath $listPath)
    Write-DebugLog "entries = $($entries.Count)"

    if ($opt.Check) {
        $rows = @(foreach ($e in $entries) { Get-CheckRow -LinkPath $e -TargetPath $targetInfo.Path })
        Emit-Rows -SourcePath $targetInfo.Path -Rows $rows
        exit $EXIT_OK
    }

    $rows   = @(foreach ($e in $entries) { Get-CreateRow -LinkPath $e -TargetInfo $targetInfo -Options $opt })
    $failed = @($rows | Where-Object { $_.Result -eq 'fail' })

    if ($opt.Verbose) {
        Emit-Rows -SourcePath $targetInfo.Path -Rows $rows
    } elseif ($failed.Count -gt 0) {
        Emit-Rows -SourcePath $targetInfo.Path -Rows $failed
    }

    if ($failed.Count -gt 0) { exit $EXIT_HAS_FAIL }
    exit $EXIT_OK
}

function Import-LinkFormatData {
    # 表ビュー定義(generateLinks.format.ps1xml)を読み込む。存在しなければ何もしない。
    # 引数: $ScriptDir - このスクリプトの存在フォルダ
    # 返り値: なし
    param([string] $ScriptDir)
    $formatFile = Join-Path $ScriptDir 'generateLinks.format.ps1xml'
    if (Test-Path -LiteralPath $formatFile) {
        try { Update-FormatData -PrependPath $formatFile -ErrorAction Stop }
        catch { Write-DebugLog "Update-FormatData failed: $($_.Exception.Message)" }
    }
}

Import-LinkFormatData -ScriptDir $PSScriptRoot
Invoke-GenerateLinks -RawArgs $args -ScriptDir $PSScriptRoot
