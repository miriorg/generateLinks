# generateLinks

## 処理

リストファイルを読み込み、パラメータで指定されたファイルのシンボリックリンクを作成する。

## target オプション(必須)

--targetオプションを指定してリンク元のファイルを指定する。

パラメータのみ渡した時はtargetオプションの指定とみなす。

## verbose オプション

verboseオプションを指定すると、動作結果を表示する。

### 出力例

``` cmd
Source: C:\master\agent.md

Result  Exists Type         Path                                       Description
------- ------ ------------ -----------------------------------------  -----------------------------------
success true   SymbolicLink C:\users\account\.claude\CLAUDE.md         created.
skip    true   Real         C:\users\account\.gemini\Gemini.md         File already exists.
skip    true   HardLink     C:\users\account\.openai\agent.md          Hardlink already exists
skip    false  -            C:\users\account\.copilot\instructions.md  Folder not exists.
```

**Result列:** success=成功 / skip=
**Exists列:** true=存在 / false=存在しない
**Type列:** Real=実体 / SymbolicLink=シンボリックリンク / HardLink=ハードリンク
**Path列:** リンク先パス名
**Description列:** 処理結果

## source オプション

デフォルトではリンクを作るスクリプトが存在するフォルダの target.list を読み込む

--sourceオプションを指定すると読込先が変更できる

## overwrite オプション

作成したいシンボリックリンクと同名のファイルがある時は指定されたモードによって処理を変える。

- スキップ（デフォルト）

- 上書き（--overwrite, -o 指定時）

## check オプション

--check オプション指定時はリストファイルが存在するか否かのリストを出力する。

### 出力例

``` cmd
Source: C:\master\agent.md

Exists Type         Path                                       Link to
------ ------------ -----------------------------------------  -----------------------------------
true   SymbolicLink C:\users\account\.claude\CLAUDE.md         C:\users\account\git\repo\CLAUDE.md
true   Real         C:\users\account\.gemini\Gemini.md         -
true   HardLink     C:\users\account\.openai\agent.md          C:\users\account\git\repo\agent.md
false  -            C:\users\account\.copilot\instructions.md  -
```

**Exists列:** true=存在 / false=存在しない
**Type列:** Real=実体 / SymbolicLink=シンボリックリンク / HardLink=ハードリンク
**Path列:** リンク先パス名
**Link to列:** リンク先のパス名

## hardオプション

リンクをSymbolic LinkではなくHard Linkにする
デフォルトはSymbolic Link

## 使用例

### generateLinks

パラメータなしで実行するとusageを表示して終了する

### generateLinks CLAUDE.md

カレントディレクトリのCLAUDE.mdをリンク元とし、target.listに記載されたファイル名をリンク先としてシンボリックリンクを作成する

### generateLinks --hard --target CLAUDE.md --source .\hardlink.list

カレントディレクトリのCLAUDE.mdをリンク元とし、hardlink.listに記載されたファイル名をリンク先としてハードリンクを作成する

### generateLinks --hard --target CLAUDE.md --overwrite

カレントディレクトリのCLAUDE.mdをリンク元とし、target.listに記載されたファイル名をリンク先として、リンク先が存在しても上書きでシンボリックリンクを作成する

不明点が解消するまでコーディングは開始せず、ヒアリングを繰り返してください。
