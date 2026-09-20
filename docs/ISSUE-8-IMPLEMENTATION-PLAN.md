# Issue #8 実装計画

対象 Issue: [make check で、状態不一致と実行エラーを区別できるようにする](https://github.com/gkzz/dotfiles/issues/8)

この文書は `fix/8-distinguish-check-errors` ブランチの実装方針をまとめたもの。対象は `make check` の診断改善に限り、終了コードの追加や lifecycle 全体の作り直しは行わない。

## 1. エラー分類とメッセージ規約

`make check` の失敗は、表示上で次の2種類に分ける。終了コードはどちらも従来どおり `1` とする。

| 分類 | 意味 | 接頭辞 |
| --- | --- | --- |
| 状態不一致 | コマンドは正常に検査できたが、期待する状態ではない | `check failed:` |
| 実行エラー | 検査に必要なコマンドや補助処理を完了できない | `check error:` |

失敗の集約には、既存の `CHECK_FAILED` を引き続き使う。メッセージの違いが呼び出し側から分かるよう、次の関数を追加する。

```text
check_failure "..."
check_error "..."
```

どちらの関数も `CHECK_FAILED=true` にする。今回は終了コードを分けないため、状態別のフラグは増やさない。

`preflight_error` と `PREFLIGHT_FAILED` は install / uninstall でも使っている。既存コマンドの出力を変えないよう、共通処理の全面的な置き換えは避ける。check から呼ぶ validator には状態不一致用と実行エラー用の報告経路を用意し、install / uninstall の `error:` はそのまま残す。

必須コマンドや検査対象のファイルがない場合は、その前提に依存する検査だけを止める。他の検査は続ける。同じ原因を preflight と後続処理から重ねて表示しない。

| 検査 | 分類 |
| --- | --- |
| 必須コマンドが PATH にない | 実行エラー |
| repository の必須ファイルがない、または読めない | 状態不一致 |
| `bash -n` が設定ファイルを不正と判定 | 状態不一致 |
| `git config` が設定ファイルを不正と判定 | 状態不一致 |
| Homebrew package が不足 | 状態不一致 |
| `brew` が見つからない | 実行エラー |
| `brew bundle check` が非ゼロ | 当面は状態不一致 |
| mise tool が不足 | 状態不一致 |
| mise が見つからない | 実行エラー |
| mise config / lock 検証コマンドが非ゼロ | 実行エラー |
| `mktemp`、`mkdir`、`cp`、cleanup が失敗 | 実行エラー |

`brew bundle check` の非ゼロは通常、package の不足を示す。そのため今回は状態不一致として扱う。出力を解析して brew 内部の障害まで見分ける対応は、この Issue には含めない。`brew` が見つからない場合は、現行の `check failed:` から `check error:` へ変更する。

## 2. managed symlink の診断

変更箇所は `setup/resources.bash` の `check_managed_links`。

各 destination を次の順序で判定する。

1. symlink が存在しない
2. symlink が存在する
3. `readlink` で actual target を取得できる
4. actual target が expected target と一致する

出力形式は次のとおり。

```text
check failed: managed symlink is missing: path=<destination> expected=<source>
check failed: managed symlink target differs: path=<destination> expected=<source> actual=<target>
check error: failed to read managed symlink target: path=<destination>
```

ケースごとの扱いを以下に示す。

| ケース | 判定 |
| --- | --- |
| destination が存在しない | missing |
| regular file または directory がある | managed symlink ではない状態不一致 |
| dangling symlink で expected target と一致 | 正常 |
| dangling symlink で別 target | wrong target |
| 別 target の有効な symlink | wrong target |
| `readlink` が失敗 | 実行エラー |
| source が存在しない | repository の状態不一致 |

regular file や directory には次の形式を使用する。

```text
check failed: managed destination is not a symlink: path=<destination> expected=<source>
```

symlink の正否は、symlink に記録された target 文字列で判断する。参照先の実在はこの判定に含めない。expected target と一致する dangling symlink は、symlink 単体の検査では正常になる。source の不在は、それより前に行う repository 検証で状態不一致として報告する。

## 3. mise 検査の分離

`setup/packages.bash` の次の関数を変更する。

- `run_repository_mise`
- `validate_mise_compatibility`
- `check_mise_tools`

### mise tool の不足

`mise ls --missing --no-header` が成功して stdout に出力があれば、tool が不足している。

```text
check failed: mise tools are missing:
node 24.19.0 missing
```

この出力形式は維持する。

### mise コマンドの失敗

`mise ls` 自体が非ゼロなら実行エラーとして扱い、stderr も表示する。

```text
check error: mise could not inspect tools
<mise の stdout / stderr>
```

config / lock の検証も同じ規則にする。

```text
check error: mise could not load the isolated repository config
<元の出力>

check error: mise could not validate the repository lockfile
<元の出力>
```

mise の終了コードだけでは、設定不正と mise 自体の障害を確実に判別できない。どちらも「検査コマンドを完了できなかった実行エラー」として扱い、原因を調べられるよう元の出力を残す。

### install への影響を抑えながら診断を保持する

`run_repository_mise` は check と install の両方から使われている。低レベルの実行関数として、次の情報を失わず呼び出し元へ返す。

- mise の stdout
- mise の stderr
- 補助処理の失敗理由
- mise の終了コード
- cleanup の成否

表示方法は呼び出し元で決める。`validate_mise_compatibility` と `check_mise_tools` は `check failed:` / `check error:` を使い、`apply_mise_tools` は既存の install 向けエラー処理を保つ。補助処理のエラーで mise 本体の出力を上書きせず、install の正常系にも変更がないことを回帰テストで確かめる。

## 4. 一時ディレクトリ処理

`run_repository_mise` の準備処理を段階別にする。

1. `mktemp -d`
2. `system` directory の作成
3. config のコピー
4. lock file のコピー
5. mise の実行
6. cleanup

各段階で固有のメッセージを出す。

```text
check error: failed to create temporary directory for mise inspection
check error: failed to create temporary mise system directory: path=...
check error: failed to copy mise config into temporary directory: source=...
check error: failed to copy mise lockfile into temporary directory: source=...
check error: failed to remove temporary mise directory: path=...
```

元コマンドの stderr も可能な範囲で続けて表示する。

### cleanup の方針

cleanup の失敗は警告ではなく実行エラーとして扱う。

- Issue の契約に「一時ファイルなども残さない」がある
- 残留を成功扱いすると check の read-only 性を保証できない
- 終了コードはどちらも `1` のため、外部互換性への影響が小さい

mise 本体が成功しても cleanup に失敗した場合は check 全体を失敗させる。mise 本体と cleanup の両方が失敗した場合は、両方の診断を表示する。

Bash 3.2 対応が必要なので、`local -n`、`mapfile`、`trap ... RETURN` には依存せず、明示的な cleanup 関数または各 return 経路からの cleanup 呼び出しで実装する。

## 5. lifecycle 側の集約

`setup/lifecycle.bash` では `check_lifecycle` を変更する。

次の流れを維持する。

1. context / command / platform / repository を検査する
2. managed symlink を検査する
3. Homebrew を検査する
4. mise compatibility を検査する
5. mise tool を検査する
6. 一つでも失敗していれば `1` を返す
7. 全成功時のみ `check complete` を出す

安全に実行できる検査は続け、複数の問題を一度に表示する。ただし、前提コマンドや repository source がなければ、それに依存する検査だけを飛ばす。

例えば mise config source が読めない場合は、source 不在を一度だけ報告し、mise compatibility と tool inspection は実行しない。mise が見つからない場合も、同じエラーを後続処理から重ねて表示しない。

`check` は lifecycle lock を取得せず、修復処理や plan 作成も行わない。

## 6. テスト設計

テストは主に `tests/setup-flow.sh` へ追加する。

重複を避けるため、必要なテスト helper を追加する。

```text
assert_exit_1
assert_file_unchanged
assert_path_absent
assert_managed_state_unchanged
run_dotfiles_capture
```

### symlink テスト

独立した HOME をケースごとに作り、少なくとも次を確認する。

1. destination 不在
   - exit `1`
   - `managed symlink is missing` が出る
   - expected path が表示される
2. regular file
   - exit `1`
   - `managed destination is not a symlink` が出る
   - ファイル内容が変化しない
3. directory
   - exit `1`
   - `managed destination is not a symlink` が出る
   - directory が削除されない
4. 別 target の symlink
   - exit `1`
   - expected / actual が表示される
   - symlink が張り替えられない
5. dangling wrong-target symlink
   - exit `1`
   - actual target が表示される
6. expected target の dangling symlink
   - repository source 不在の状態不一致として検出される
   - symlink 自体は変更されない
7. `readlink` 失敗
   - exit `1`
   - `check error:` になる
   - wrong target や missing と誤表示されない

`readlink` の fake command は、対象 destination またはテスト用の環境変数に一致した呼び出しだけを失敗させる。それ以外は本物の `readlink` へ渡し、テスト対象ではない処理を巻き込まない。

### mise テスト

1. tools installed
   - exit `0`
   - `check complete` が出る
2. tool 不足
   - exit `1`
   - `check failed: mise tools are missing` が出る
   - 不足 tool が表示される
3. `mise ls` 失敗
   - exit `1`
   - `check error: mise could not inspect tools` が出る
   - fake mise の stderr が保持される
   - `tools are missing` とは表示されない
4. `mise config` 失敗
   - exit `1`
   - config 検証の実行エラーが出る
   - 元 stderr が表示される
5. `mise install --locked --dry-run` 失敗
   - exit `1`
   - lockfile 検証の実行エラーが出る
   - 元 stderr が表示される

### 補助コマンド失敗テスト

`PATH` の先頭にケース専用の wrapper を配置し、環境変数で対象操作だけを失敗させる。他の呼び出しは本物のコマンドへ委譲する。

失敗させる対象は次の5つ。

- `mktemp -d`
- 一時 `system` directory に対する `mkdir`
- config コピーの `cp`
- lockfile コピーの `cp`
- 一時 directory に対する `rm`

wrapper は dotfiles の一時パスだけを対象にし、テスト harness 自身の cleanup などを壊さないようにする。

各ケースで次を確認する。

- exit code が `1`
- `check error:` が出る
- 失敗した処理名が分かる
- fake command の stderr が残る
- 状態不一致のメッセージに誤分類されない
- 作成済みの一時ファイルは可能な範囲で cleanup される

cleanup 自体の失敗テストでは残留が意図的に発生するため、テスト終了時に harness 側で明示的に削除する。

## 7. read-only 契約の確認

正常時と失敗時の両方で、dotfiles が管理する状態を check の前後で比べる。

- managed symlink の target
- regular file の内容
- mise config source の checksum
- mise lock source の checksum
- dotfiles が `MISE_DATA_DIR`、cache、state に管理ファイルを作っていないこと
- lifecycle lock の不存在
- temporary directory の不存在

一時ディレクトリ確認用に、テスト専用 `TMPDIR` を HOME ごとに用意する。check 前後で `dotfiles-mise.*` が残っていないことを確認する。

実際の mise は cache や state を更新することがあるため、directory 全体の checksum は比較しない。fake mise の call log もテスト観測用なので対象外とする。

## 8. ドキュメント

`check failed:` / `check error:` は利用者が原因を見分けるための表示なので、実装と同時に次も更新する。

- `docs/TROUBLESHOOTING.md`
  - `check failed:` は状態不一致
  - `check error:` は検査処理の実行エラー
  - expected / actual の見方
- `docs/OPERATIONS.md`
  - check は修復しない
  - 一時的な isolated mise config を使うが、終了時に削除する

操作方法や管理対象は変わらないため、README は更新しない。

## 9. 実装順

1. エラー分類と出力形式を決める
2. managed symlink の判定と診断を変更する
3. mise と一時環境のエラー伝播を変更する
4. fake command とテストケースを追加する
5. read-only 契約を検証する
6. `make validate` と既存テストで回帰確認する
7. 利用者向けドキュメントを更新する

## 10. コミット単位

コミットを分ける場合は、次の3単位を候補にする。

1. `fix: distinguish managed symlink check failures`
2. `fix: report mise check execution errors`
3. `test: cover check diagnostics and read-only behavior`

実装中の変更が小さければ、最終的に1コミットへまとめてもよい。

## 11. 完了条件

- missing、非 symlink、wrong target を区別できる
- wrong target に expected / actual が出る
- `readlink` 失敗が実行エラーとして表示される
- mise tool 不足と mise 実行失敗を区別できる
- `mktemp`、`mkdir`、`cp`、cleanup の失敗箇所が分かる
- 下位コマンドの stderr が失われない
- install の正常系と既存のエラー処理を壊さない
- check が managed state を修復、変更しない
- 正常時に一時ディレクトリが残らない
- cleanup 失敗時は `check error:` を出して終了コード `1` を返す
- 終了コード `0 / 1 / 2` の契約を維持する
- `make validate` が成功する
- 既存の shell 構文検査が成功する
- Linux と Bash 3.2 互換の構文に収まっている

`PREFLIGHT_FAILED` の全面刷新は避け、Issue #8 に必要な check の診断経路だけを分ける。実行エラー専用の終了コードが必要になった場合は、別 Issue で扱う。
