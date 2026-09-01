# generateLinks

Create symbolic links (or hard links) for one master file at every path
listed in a list file. Useful for distributing a single instruction file
(e.g. `CLAUDE.md`) to the many conventional locations different tools expect
(`.gemini/GEMINI.md`, `.github/copilot-instructions.md`, ...).

Windows / PowerShell 5.1+ (also runs on PowerShell 7+). NTFS only.

## Usage

```powershell
# Show help (no argument)
.\generateLinks.ps1

# Symlink .\CLAUDE.md to every path in target.list (script folder, then current dir)
.\generateLinks.ps1 CLAUDE.md

# Same, but read the list from another file
.\generateLinks.ps1 --hard --target CLAUDE.md --source .\hardlink.list

# Replace existing LINKS (real files/folders are always kept)
.\generateLinks.ps1 --hard --target CLAUDE.md --overwrite

# Only report what exists (no changes)
.\generateLinks.ps1 --check --target CLAUDE.md

# Preview actions without creating anything
.\generateLinks.ps1 --dry-run --verbose --target CLAUDE.md
```

## Options

| Option | Meaning |
| --- | --- |
| `-t`, `--target <path>` | Real file or directory to link **from**. Required. A bare positional argument is treated as `--target`. Resolved against the current directory. |
| `-s`, `--source <path>` | List file. When omitted, `target.list` is looked up first in the script's own folder, then in the current directory. When given, the path is resolved against the current directory. |
| `-o`, `--overwrite` | Replace an existing **link**. Real files and directories are never deleted. |
| `--hard` | Create hard links instead of symbolic links. |
| `--check` | Only report existence / type of each entry. Makes no changes. |
| `--dry-run` | Show what would happen; create nothing. |
| `-v`, `--verbose` | Print the result table. Without it, a normal run is silent except for failures / fatal errors. |
| `-h`, `--help` | Show help. |

Long (`--target`) and short (`-t`) forms are both accepted, case-insensitively.

## List file format

- One path per line = one link to be created.
- Blank lines and lines starting with `#` are ignored.
- `%VAR%`, `$env:VAR` and a leading `~` are expanded.
- Relative paths are resolved against the **list file's own folder**.

See [`target.list`](target.list) for an annotated sample.

## Behavior

| Situation | `--overwrite` off (default) | `--overwrite` on |
| --- | --- | --- |
| Parent folder missing | skip — `Folder not exists.` | skip |
| Nothing there | create — `created.` | create |
| A real file / directory | skip — `File already exists.` | skip (real data is protected) |
| A link of the requested kind | skip — `Symlink/Hardlink already exists` | replace — `overwritten.` |
| A link of another kind | skip | replace — `overwritten.` |
| `--hard` + target is a directory | fail — `Target is a directory (hardlink not allowed).` | fail |
| `--hard` + different volume | fail — `Different volume (hardlink not allowed).` | fail |

- `--check` adds a `Links` column (hard-link count; `1` for a real file) and, for
  a symbolic link that points somewhere other than `--target`, appends
  `(points to another file)` to its **Link to** value.
- Output is emitted as objects, so it can be piped
  (`... --check --target x | Where-Object { -not $_.Exists }`).
  Console rendering uses the table views in
  [`generateLinks.format.ps1xml`](generateLinks.format.ps1xml).

## Permissions

Creating **symbolic** links on Windows requires either **Developer Mode**
(Settings → Privacy & security → For developers) or running the shell as
**Administrator**. Without it the script prints a clear message and exits with
code `2` — it never tries to elevate. **Hard** links need no special privilege.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | All entries succeeded or were skipped |
| `1` | One or more entries failed |
| `2` | Usage error, or `--target` / list file not found |

## Tests

```powershell
powershell -File .\Test-generateLinks.ps1
pwsh       -File .\Test-generateLinks.ps1
```

The suite runs entirely in a throwaway folder. Symbolic-link scenarios are
skipped automatically when the session cannot create symlinks; hard-link,
`--check`, `--dry-run` and argument-handling scenarios always run.

---

# generateLinks（日本語）

1 つのマスターファイルについて、リストファイルに書かれた各パスへ
シンボリックリンク（または `--hard` でハードリンク）を作成します。
`CLAUDE.md` のような指示ファイルを、ツールごとに異なる慣用パス
（`.gemini/GEMINI.md`、`.github/copilot-instructions.md` など）へ
一括配布する用途を想定しています。

Windows / PowerShell 5.1 以上（PowerShell 7+ でも動作）。NTFS 専用。

## 使い方

```powershell
# ヘルプ表示（引数なし）
.\generateLinks.ps1

# .\CLAUDE.md を target.list（スクリプトと同じ場所→無ければカレント）の各パスへシンボリックリンク
.\generateLinks.ps1 CLAUDE.md

# リストを別ファイルから読む／ハードリンクにする
.\generateLinks.ps1 --hard --target CLAUDE.md --source .\hardlink.list

# 既存の「リンク」を上書き（実体ファイル・フォルダは常に保護）
.\generateLinks.ps1 --hard --target CLAUDE.md --overwrite

# 存在確認のみ（変更なし）
.\generateLinks.ps1 --check --target CLAUDE.md

# 実際には作らず、予定だけ表示
.\generateLinks.ps1 --dry-run --verbose --target CLAUDE.md
```

## オプション

| オプション | 意味 |
| --- | --- |
| `-t`, `--target <path>` | リンク元の実体ファイル／フォルダ。必須。位置引数のみでも `--target` とみなす。カレントディレクトリ基準。 |
| `-s`, `--source <path>` | リストファイル。省略時は `target.list` をまずスクリプトと同じ場所で、無ければカレントディレクトリで探す。指定時はカレントディレクトリ基準で解決。 |
| `-o`, `--overwrite` | 既存の**リンク**を置き換える。実体ファイル・フォルダは削除しない。 |
| `--hard` | シンボリックリンクではなくハードリンクを作成。 |
| `--check` | 各エントリの存在・種類を報告するだけ。変更しない。 |
| `--dry-run` | 実行内容を表示するだけで何も作成しない。 |
| `-v`, `--verbose` | 結果表を表示。指定しない場合、通常実行は失敗・致命的エラー以外は無出力。 |
| `-h`, `--help` | ヘルプ表示。 |

ロング形式（`--target`）・ショート形式（`-t`）の両方を大文字小文字を問わず受け付けます。

## リストファイルの書式

- 1 行 1 パス（作成するリンクのパス）。
- 空行と `#` で始まる行は無視。
- `%VAR%`、`$env:VAR`、先頭の `~` を展開。
- 相対パスは**リストファイル自身のあるフォルダ**を基準に解決。

注釈付きサンプルは [`target.list`](target.list) を参照。

## 動作

| 状況 | `--overwrite` なし（既定） | `--overwrite` あり |
| --- | --- | --- |
| 親フォルダが無い | skip — `Folder not exists.` | skip |
| 何も無い | 作成 — `created.` | 作成 |
| 実体ファイル／フォルダ | skip — `File already exists.`（実体は保護） | skip |
| 要求と同じ種類のリンク | skip — `Symlink/Hardlink already exists` | 置換 — `overwritten.` |
| 別の種類のリンク | skip | 置換 — `overwritten.` |
| `--hard` かつ target がフォルダ | fail — `Target is a directory (hardlink not allowed).` | fail |
| `--hard` かつ別ボリューム | fail — `Different volume (hardlink not allowed).` | fail |

- `--check` は `Links` 列（ハードリンク数。実体ファイルは `1`）を追加します。
  シンボリックリンクが `--target` 以外を指している場合、その **Link to** 値に
  `(points to another file)` を付けます。
- 出力はオブジェクトなので、そのままパイプできます
  （`... --check --target x | Where-Object { -not $_.Exists }`）。
  コンソール表示は [`generateLinks.format.ps1xml`](generateLinks.format.ps1xml) の
  表ビュー定義に従います。

## 権限

Windows で**シンボリックリンク**を作成するには、**開発者モード**
（設定 → プライバシーとセキュリティ → 開発者向け）を有効にするか、
シェルを**管理者として実行**する必要があります。未充足の場合、スクリプトは
分かりやすいメッセージを表示して終了コード `2` で終了します（昇格は試みません）。
**ハードリンク**には特別な権限は不要です。

## 終了コード

| コード | 意味 |
| --- | --- |
| `0` | 全エントリが成功またはスキップ |
| `1` | 1 件以上が失敗 |
| `2` | 引数エラー、または `--target` / リストファイルが見つからない |

## テスト

```powershell
powershell -File .\Test-generateLinks.ps1
pwsh       -File .\Test-generateLinks.ps1
```

テストは使い捨てフォルダ内で完結します。シンボリックリンクを作成できない
セッションでは symlink 系シナリオを自動でスキップします（hardlink /
`--check` / `--dry-run` / 引数系は常に実行）。
