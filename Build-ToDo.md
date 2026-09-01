# Build-ToDo.md — generateLinks 実装チェックリスト

- 依頼内容: `prompt.md` の仕様に沿ったリンク一括作成 CLI（PowerShell）一式の作成
- 依頼日時: 2026-09-01
- 確定仕様: [generateLinks.ToDo.md](generateLinks.ToDo.md) の「決定事項 / 制限事項 / 2026-09-01 追加確認の確定」
- 実装計画: `C:\Users\messe\.claude\plans\noble-toasting-origami.md`（承認済み）
- 現在の状況: **完了（全テスト PASS）**

---

## 手順

### 1. 本チェックリストの承認
- [x] ユーザーが本ファイルの内容を了承（2026-09-01）

### 2. generateLinks.ps1（本体）
- [x] 2-1 ヘッダーコメント（目的・usage）＋ `Set-StrictMode` / `$ErrorActionPreference`
- [x] 2-2 定数群: `$Script:LogLevel`（Quiet/Normal/Debug、既定 Normal）、`$DEFAULT_LIST_NAME`、
      メッセージ定数（英語）、終了コード定数（0/1/2）
- [x] 2-3 ログ薄ラッパー: `Write-DebugLog` / `Write-VerboseLog` / `Write-FatalError`
- [x] 2-4 `Show-Usage`（全オプション説明）
- [x] 2-5 `Convert-ArgList`（`--long`/`-short` 両対応の自前パーサ。未知オプション・位置引数2個で exit 2）
- [x] 2-6 `Expand-EntryPath`（`%VAR%` / `$env:VAR` / 先頭 `~` 展開、相対はリスト位置基準で絶対化）
- [x] 2-7 `Resolve-TargetInfo`（カレント基準、不在で exit 2、IsDirectory 判定）
- [x] 2-8 `Resolve-SourcePath`（`--source` はカレント基準／未指定は `<scriptdir>\target.list`、不在で exit 2）
- [x] 2-9 `Read-LinkList`（UTF-8/BOM 可、`#`・空行除外）
- [x] 2-10 `Get-LinkKind` / `Get-HardLinkCount`（`fsutil hardlink list`）/ `Get-OtherHardLink` / `Get-SymlinkTarget` / `Test-SameVolume`
- [x] 2-11 `New-RequestedLink` + `Remove-LinkOnly`（Symbolic/Hard、フォルダ symlink 可、DryRun 対応、権限不足で exit 2）
- [x] 2-12 `Get-CheckRow`（列: Exists / Type / Path / Link to / Links、symlink 不一致注記）
- [x] 2-13 `Get-CreateRow` + `Get-FreshLinkRow` / `Get-ExistingLinkRow` / `Test-HardLinkBlocked`（判定表どおり）
- [x] 2-14 `Emit-Rows`（`Source:` 行＋行オブジェクトを出力）／ `generateLinks.format.ps1xml` に表ビュー定義
- [x] 2-15 `Invoke-GenerateLinks`（引数ゼロ→usage/exit0、`--help`→usage、`--check` 優先、終了コード集計）

### 3. target.list（サンプル）
- [x] 3-1 使い方コメント＋慣用パスをコメントアウトで例示（パス名のみ）

### 4. Test-generateLinks.ps1
- [x] 4-1 一時フォルダ生成／後始末（短いパスを使用）、ダミーのマスターファイルと `*.list` 生成
- [x] 4-2 シナリオ: 引数ゼロ usage / 未知オプション exit2 / 位置引数過多 exit2 / target 不在 exit2 /
      list 不在 exit2 / `--check` の列と Links / hard 新規 / hard 既存 skip / hard `--overwrite` /
      親無し skip / 実体保護 / hard フォルダ target で fail(exit1) / `--dry-run` 未作成 /
      （権限があれば）symlink 新規・既存 skip・`--check` の Link to と points-to-another-file
- [x] 4-3 symlink 系は権限検知して不可なら SKIP 表示、末尾に PASS/FAIL サマリ

### 5. README.md
- [x] 5-1 英語セクション → 日本語セクションの順（usage / オプション / list 書式 / 動作 / 権限 / 終了コード / テスト）

### 6. 検証と仕上げ
- [x] 6-1 `powershell -File .\Test-generateLinks.ps1` 実行 → PASS=35 / FAIL=0 / SKIP=1（symlink 系）
- [x] 6-2 `pwsh -File .\Test-generateLinks.ps1`（7.6.5）実行 → PASS=35 / FAIL=0 / SKIP=1
- [x] 6-3 手動確認: usage（exit 0）/ `--check` の表と Links 列 / 権限不足時の friendly error（exit 2）
- [x] 6-4 `generateLinks.ToDo.md`（状況）と本ファイルを最終更新

---

## 成果物

| ファイル | 説明 |
| --- | --- |
| `generateLinks.ps1` | 本体スクリプト |
| `generateLinks.format.ps1xml` | 出力オブジェクトの表ビュー定義（起動時 `Update-FormatData`） |
| `target.list` | 注釈付きサンプルリスト（全行コメントアウト） |
| `Test-generateLinks.ps1` | 自己完結テスト（一時フォルダ内で実行） |
| `README.md` | 使い方（英語→日本語） |

## 補足（実装上の判断）

- 引数は `param()` を使わず `$args` を自前解析（`prompt.md` の GNU 形式 `--target` を満たし、
  PowerShell 予約名 `-Verbose` との衝突も回避するため）。`--long` と `-short` の両方を受理。
- G4(b) に従い結果はオブジェクト出力。コンソール表示は 5 列でも表になるよう
  `generateLinks.format.ps1xml` の TableControl ビューで制御。
- リダイレクト時の表は端末幅（既定 120 桁）で列が切り詰められる（Format-Table 由来の仕様）。
  厳密な値が必要な場合はパイプでオブジェクトを受ける（`... | Where-Object` 等）。

## 更新ログ
- 2026-09-01 作成 → 同日 承認 → 実装 → 全テスト PASS で完了
- 2026-09-01 仕様追加: `--source` 未指定時、スクリプトフォルダに `target.list` が無ければ
  カレントディレクトリの `target.list` も探す（`Resolve-SourcePath` 改修、テスト
  `Invoke-SourceLookupScenario` 追加、PASS=39）。詳細は generateLinks.ToDo.md「2026-09-01 仕様追加」。
