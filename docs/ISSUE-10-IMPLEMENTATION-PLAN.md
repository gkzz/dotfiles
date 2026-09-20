# Issue #10 実装計画

対象 Issue: [Bash lifecycle の責務とテスト構成を整理する](https://github.com/gkzz/dotfiles/issues/10)

この文書は `refactor/10-bash-lifecycle-structure` ブランチの実装方針をまとめたもの。利用者向けの CLI、終了コード、出力、managed resource、Homebrew・mise・symlink の管理方針は変えない。既存テストを機能別に分けて回帰検知の基盤を整えた後、resource 定義と mise 実行処理を段階的に整理する。

[レビュー結果](ISSUE-10-IMPLEMENTATION-PLAN-REVIEW.md)の指摘は反映済み。実装時はこの計画書を正とし、レビュー結果は判断の経緯を確認するときに使う。

## 1. 調査結果と方針

現状は主に次の箇所で責務が重なっている。

| 対象 | 現状 | この Issue での整理 |
| --- | --- | --- |
| `tests/setup-flow.sh` | 872行に CLI、bootstrap、lifecycle、symlink、package、異常系が同居 | 共通 fixture と機能別テストへ分割する |
| managed resource | source と destination が別々の配列で、対応関係が添字に依存 | 種類・source・destination を1つの宣言にまとめる |
| `run_repository_mise` | isolated 環境の準備、実行、出力保持、cleanup、直接表示を担当 | 準備・実行・cleanup・結果報告を関数単位で分ける |
| mise の結果 | `RUN_REPOSITORY_MISE_*` 変数群と暗黙の capture mode で受け渡し | 結果の所有者を限定し、用途が分かる capture / stream の入口へ分ける |
| check / install の表示 | `CHECK_MODE` を下位関数が参照して接頭辞を決定 | 共通処理は結果だけを返し、lifecycle 側の呼び出し元が表示を決める |
| resource の計画 | `MANAGED_LINK_STATUSES` を preflight と plan が共有 | preflight と plan の入力を宣言一覧に統一し、状態配列の共有をなくす |

Bash 3.2 には nameref や associative array がない。複数の結果をすべて関数の終了コードだけで返すと、mise 本体と cleanup の両方が失敗した場合の情報を保持できない。このため、グローバル変数は一律に廃止せず、次の基準で残す。

- lifecycle 全体の集約状態や実行計画など、複数関数が共同で扱う状態に限る
- 書き込む関数と読み取る関数をコメントと命名で明示する
- 呼び出し元の種類を表す mode 変数は下位処理へ持ち込まない
- 一時的な値は `local`、単一値は終了コードまたは標準出力で返す

## 2. テストを先に機能別へ分割する

最初に `tests/setup-flow.sh` を分割し、その後の refactor が既存動作を変えていないことを小さい単位で確認できるようにする。テスト内容や assertion は原則として書き換えず、移動と共通化を先に行う。

構成は次を基本とする。

| ファイル | 対象 |
| --- | --- |
| `tests/test-helper.bash` | 一時 root、fake command、`run_dotfiles`、assertion |
| `tests/cli.sh` | CLI parser、option、終了コード `2` |
| `tests/bootstrap.sh` | Homebrew / mise bootstrap、GitHub Actions 用 setup |
| `tests/lifecycle.sh` | install / uninstall、dry-run / apply、lock、idempotency |
| `tests/resources.sh` | managed symlink、競合、backup、rollback |
| `tests/packages.sh` | Homebrew / mise の正常系、isolated config、tool 状態 |
| `tests/check-diagnostics.sh` | check の集約、状態不一致、実行エラー、helper failure |
| `tests/run.sh` | 上記テストを固定順で一括実行する runner |

`tests/mise-isolation.sh` は実際の mise を使う CI 専用の役割が明確なので、独立ファイルのまま残す。

### 共通 fixture の契約

各テストファイルは `test-helper.bash` を source し、自分専用の一時 root と fake command directory を作る。終了時の cleanup は helper の trap で行う。あるテストが作成した HOME、環境変数、fake command、call log を別のテストへ引き継がない。

helper には少なくとも次を置く。

```text
fail
assert_contains
assert_not_contains
assert_exit_1
assert_exit_2
assert_before
path_glob_exists
permission_bits
new_home
run_dotfiles
```

テスト固有の wrapper や assertion は、1ファイルだけで使うなら共通 helper へ移さない。共通 helper が新しい巨大ファイルになることを避ける。

### テストケースの移動表

移動表はこの計画書の「付録A テストケース移動表」で管理し、テスト分割と同じ commit で更新する。別の一時ファイルには置かない。分割前に、`tests/setup-flow.sh` のコメント単位のケースを付録へ起こし、各行に次を記録する。

- ケース名と移動先
- 必要な fake command
- 開始時の HOME の状態
- 事前に `install --apply` が必要か
- 期待する終了コードと主要 assertion

旧 `tests/setup-flow.sh` は、新しい機能別テストと `tests/run.sh` が全ケースを実行できるまで削除しない。移行確認では、新旧の入口を両方実行する。移動表の各ケースが新しいテストから1回ずつ参照され、production code に差分がない状態で契約上の観測結果が一致した後、旧ファイルを削除する。

ここで比較する「結果」は raw output の完全一致ではない。一時 path、timestamp、call log の保存先など、実行ごとに変わる値は比較対象から外す。次を比較する。

- 新旧 runner の終了コード
- 移動表の全ケースが1回ずつ実行されたこと
- 各ケースの主要 assertion
- package manager と managed resource action の呼び出し順
- install / check / uninstall の公開出力契約

### 一括実行と単独実行

`tests/run.sh` は機能別テストを明示的な順番で実行し、途中の失敗をそのまま返す。glob の順序には依存しない。各ファイルも repository root 以外の current directory から直接実行できるよう、自身のパスから `DOTFILES` を求める。

`Makefile` の `validate` は次を満たすように変更する。

1. 分割後の全 shell file を `bash -n` で検査する
2. `tests/run.sh` から全テストを実行する
3. 現在の `make validate` の利用方法と成功時の意味を変えない

GitHub Actions の portability job も `tests/run.sh` を呼ぶ。Ubuntu と macOS がローカルの一括実行と同じ入口を使う状態にする。ShellCheck は従来の `tests/*.sh` に加え、source 専用の `tests/*.bash` も対象にする。

## 3. managed resource を1つの宣言へまとめる

`setup/context.bash` の `MANAGED_SOURCES` と `MANAGED_DESTINATIONS` は同じ添字が1件の resource を表す。配列長のずれを型や構文では検出できないため、種類・source・destination を連続した3要素として持つ単一配列へ置き換える。

```text
MANAGED_RESOURCES=(
  symlink "$DOTFILES/.bashrc" "$HOME/.bashrc"
  symlink "$DOTFILES/.bash_profile" "$HOME/.bash_profile"
  symlink "$DOTFILES/.gitconfig" "$HOME/.gitconfig"
  symlink "$MISE_CONFIG_SOURCE" "$MISE_CONFIG_TARGET"
)
```

delimiter を含む1文字列にはせず、3要素ずつ走査する。これならパスの空白を保持でき、`eval` も不要になる。resource type は現時点では `symlink` だけだが、各処理は未知の type を黙って無視せず内部エラーにする。

`setup/resources.bash` に resource 走査の規則を集約し、次の処理が同じ `MANAGED_RESOURCES` を参照するようにする。

- install preflight
- install plan
- check
- uninstall preflight / plan

`MANAGED_LINK_STATUSES` は削除する。ただし、plan 作成時に `link_status` だけを再評価して action を追加してはならない。preflight 後に destination が変わると、未検証の競合を plan に取り込むおそれがあるためである。

install では次の二段階で検証する。

1. 初期 preflight で source、destination、親 directory、`--force`、同一ファイル性を確認する。既知の filesystem conflict があれば、package manager の検査へ進まない
2. package 検証後、同じ項目を再検証し、その走査内で resource action を plan に追加する。1件でも失敗したら plan を表示・実行しない

apply 時は `ensure_symlink` が状態をもう一度確認し、planned type と一致しない変更を拒否する。これにより、状態 snapshot 用の配列を残さず、preflight、plan 作成、apply の各境界で destination の変更を検出する。

plan の並びは現在と同じく、Homebrew、mise、managed symlink の順を保つ。resource の preflight 中に plan を追加して順序を変えない。

### resource 定義の検証

初期化後に次を検査する。

- 要素数が3の倍数である
- type が既知である
- source と destination が空でない
- 同じ destination が重複していない

既存の context 検証により tab と newline を含む主要パスは拒否されるが、resource の表現自体は delimiter に依存させない。

## 4. mise 実行処理を4つの責務へ分ける

`setup/packages.bash` の `run_repository_mise` を、次の層に分ける。

### isolated 環境の準備

`prepare_repository_mise_environment` は `mktemp`、`system` directory の作成、config と lock file のコピーを担当する。終了コードで成否を返し、isolated root と失敗段階は `run_repository_mise` が所有する結果状態へ記録する。command substitution の subshell で結果状態を失わないよう、この helper の標準出力には依存しない。

どの段階で失敗したかは、呼び出し元が既存メッセージへ変換できる識別子として保持する。作成済みの isolated root がある場合は、準備途中の失敗でも cleanup 対象にする。

### mise コマンドの実行

`execute_repository_mise` は isolated root と mise command、引数を受け取り、`run_isolated_mise` を実行する。I/O は operation の用途に応じて次の2種類に分ける。

| 用途 | I/O 方針 |
| --- | --- |
| check の config / lock / tool inspection | stdout と stderr を一時ファイルへ分離して capture する |
| install preflight の config / lock 検証 | 診断用に stdout と stderr を分離して capture する |
| install apply | stdout と stderr を端末へ直接流し、現在の進捗表示と出力順を保つ |

低レベル helper に呼び出し側の状態を表す boolean mode は持たせない。`run_repository_mise_check` と `run_repository_mise_apply` のように用途が分かる薄い入口を設け、isolated 環境の準備、mise 起動、cleanup の実装は内部で共有する。

`run_isolated_mise` は環境変数を隔離して mise を起動する責務だけを維持する。診断の接頭辞や lifecycle の種類は知らない。

### cleanup

`cleanup_repository_mise_environment` は isolated root の削除だけを担当し、cleanup 自身の終了コードと stderr を結果状態へ記録する。mise 本体が失敗していても必ず呼び出す。

orchestrator は mise 本体の結果を cleanup の結果で上書きしない。両方が失敗した場合は両方の情報を残し、全体として非ゼロを返す。

### 結果の保持と報告

Bash 3.2 で複数の結果を同時に返す必要があるため、次の結果状態を `run_repository_mise` が所有する名前空間に限定して残す。

```text
REPOSITORY_MISE_RESULT_STAGE
REPOSITORY_MISE_RESULT_STATUS
REPOSITORY_MISE_RESULT_STDOUT
REPOSITORY_MISE_RESULT_STDERR
REPOSITORY_MISE_RESULT_CLEANUP_STATUS
REPOSITORY_MISE_RESULT_CLEANUP_STDERR
REPOSITORY_MISE_RESULT_TEMP_PATH
```

`STAGE` は `prepare`、`mise`、`cleanup`、空文字のいずれかとする。未実行の status は空文字、成功は `0` とし、formatter が未実行と成功を区別できるようにする。各 operation の開始時に全項目を初期化する。

終了コードの優先順位は次のとおり。

| ケース | `STAGE` | command status | cleanup status | 全体の終了コード |
| --- | --- | --- | --- | --- |
| 準備成功、mise 成功、cleanup 成功 | 空文字 | `0` | `0` | `0` |
| 準備失敗、cleanup 成功 | `prepare` | 未実行 | `0` | `1` |
| 準備失敗、cleanup 失敗 | `prepare` | 未実行 | cleanup の値 | `1` |
| mise 失敗、cleanup 成功 | `mise` | mise の値 | `0` | mise の値 |
| mise 成功、cleanup 失敗 | `cleanup` | `0` | cleanup の値 | `1` |
| mise 失敗、cleanup 失敗 | `mise` | mise の値 | cleanup の値 | mise の値 |

準備途中で isolated root を作成済みなら、準備失敗時も cleanup を試みる。mise と cleanup が両方失敗した場合は mise の終了コードを優先し、cleanup の診断も失わず表示する。

orchestrator は結果状態の唯一の writer とし、formatter と呼び出し元だけが読み取る。各変数の writer / reader と「次の呼び出しで上書きされる」契約を関数の直前へ記載する。現在の `RUN_REPOSITORY_MISE_CAPTURE` は削除し、呼び出し側が設定する暗黙の mode をなくす。

## 5. 共通処理と表示処理を分ける

低レベルの mise 処理は `check failed:`、`check error:`、`error:` を直接表示しない。次の層で役割を分ける。

| 層 | 役割 |
| --- | --- |
| 実行 helper | isolated 環境の準備、mise 実行、cleanup、結果保持 |
| 共通 validator | config / lock の検証結果を終了コードで返す |
| check 側 | `check_error`、`check_failure` と元の stdout / stderr を表示 |
| install 側 | `preflight_error` または apply の stderr と終了コードを維持 |

`validate_mise_compatibility` は check / install を暗黙に判別しない共通 validator にする。config と lock は別関数に分け、呼び出し側がどの operation に失敗したかを把握できるようにする。

```text
validate_repository_mise_config
validate_repository_mise_lock
```

install preflight は失敗時に従来の `error: mise cannot ...` を表示する。check は同じ結果を `check error: mise could not ...` として表示する。`apply_mise_tools` は install apply の既存 stdout / stderr と非ゼロ終了を保つ。

まず mise validator から表示責務を分け、`CHECK_MODE` を package 処理から削除する。config / lock の共通処理と check / install の formatter が分離できた後、`report_check_or_preflight` と `report_check_error_or_preflight` の残りの利用箇所を個別に整理する。

context / platform / repository の validator を最初から一括して callback 化しない。callback が必要な場合は `preflight_error`、`check_failure`、`check_error` など repository 内で定義した固定 reporter 名だけを lifecycle から渡す。汎用 callback 機構は作らず、外部入力や `eval` も使わない。

### 残す lifecycle 状態

次の状態は複数処理の集約に必要なので残す。ただし writer と利用期間を限定する。

- `PREFLIGHT_FAILED`: 1回の preflight 中に validator が設定する
- `CHECK_FAILED`: 1回の check 中に reporter が設定する
- `PLAN_TYPES` / `PLAN_TARGETS` / `PLAN_DETAILS`: `plan_reset` から `plan_execute` まで `setup/plan.bash` が所有する
- `LIFECYCLE_LOCK_HELD`: lock acquire から release まで `setup/lifecycle.bash` が所有する
- `BREW_CMD` / `MISE_CMD`: command discovery と同一 lifecycle 内の呼び出しで共有する

`CHECK_HAVE_*` は個別の command 不在時に依存する検査だけを止めるために使われている。これらは一括削除せず、command 検証結果を呼び出し側が明示的に参照する構造へまとめる。Issue #8 で追加した「検査可能な項目は続け、同じ原因を重ねて表示しない」という挙動を優先する。

## 6. 既存動作を固定する回帰テスト

refactor 前後で、既存テストの assertion と利用者向け出力を維持する。特に次を明示的に確認する。

### lifecycle と managed resource

- dry-run と apply の plan が一致する
- package manager の後に symlink を適用する
- install の再実行が idempotent である
- regular file の backup と symlink 作成失敗時の rollback が変わらない
- uninstall は現在の repository を指す symlink だけを削除する
- lifecycle lock の取得、stale lock の回収、release が変わらない
- 4件の managed resource が install / check / uninstall で同じ一覧から処理される
- resource 定義の不正と重複 destination をテストで検出できる
- preflight 後に regular file、directory、別 target の symlink が出現しても、完全な再検証を経ていない置換 action を実行しない
- plan 作成時の再検証に失敗した場合は、部分的な plan を表示・実行しない

### mise の結果と cleanup

- config、lock、tool inspection の成功と失敗を区別する
- mise の stdout と stderr を失わない
- `mktemp`、`mkdir`、config copy、lock copy の失敗理由を維持する
- 準備途中でも作成済みの isolated root を cleanup する
- mise 成功 / cleanup 失敗で全体が失敗する
- mise 失敗 / cleanup 成功で mise の終了コードと診断が残る
- mise 失敗 / cleanup 失敗で両方の診断が表示される
- 準備失敗、準備と cleanup の同時失敗、mise 失敗、cleanup 失敗、mise と cleanup の同時失敗で、定義した result state と終了コードになる
- check の低レベル処理から install 向け出力が出ず、install から `check error:` が出ない
- install apply の mise 出力が従来どおり端末へ流れ、完了まで保留されない
- 正常終了後に `dotfiles-mise.*` が残らない

streaming は fake mise を使って自動検証する。fake mise は開始 marker を stdout へ出した後、テスト用の release file が作成されるまで待つ。`install --apply` を background で起動し、親テストが process の終了前に marker を観測できることを期限付きの polling で確認する。marker を確認したら release file を作り、process の終了コードと後続出力を検証する。期限内に marker が現れない場合は、capture によって完了まで保留されたものとして失敗させ、background process を cleanup する。

### テスト分割そのもの

- `tests/run.sh` で全機能別テストが実行される
- 各機能別テストを単独実行できる
- 1テストの環境変数や fake command が別テストへ漏れない
- 移動表の全ケースが新しいテストから1回ずつ参照されている
- production code を変えない状態で、新旧 runner の終了コード、主要 assertion、処理順、公開出力契約が一致する
- `make validate` が分割前と同じ検証範囲を持つ

## 7. ドキュメント更新

利用者向けの操作やエラー分類は変わらないため、README、`docs/OPERATIONS.md`、`docs/TROUBLESHOOTING.md` は原則として変更しない。

内部構造は変わるため、`docs/ARCHITECTURE.md` の次を更新する。

- managed resource の宣言元と各 lifecycle からの参照関係
- package 共通処理と check / install の表示責務
- 分割後のテスト構成と一括実行の入口

実装中に利用者向け出力の変更が必要になった場合は、Issue #10 の「変更しないこと」に反するため、その場で広げず別 Issue の要否を判断する。

## 8. 実装順

1. `tests/setup-flow.sh` のケース移動表を作る
2. production code を変えず、fixture と機能別テストへ移動する
3. `tests/run.sh`、`make validate`、CI の実行入口を揃える
4. 新旧のテスト入口で同じ結果になることを確認し、旧 `tests/setup-flow.sh` を削除する
5. managed resource を単一の宣言配列へ集約する
6. plan 作成時の完全な再検証を追加してから `MANAGED_LINK_STATUSES` を削除する
7. mise result state と終了コードの契約をテストで固定する
8. mise の準備・実行・cleanup helper と capture / stream の入口を分離する
9. config / lock の共通 validator と check / install の formatter を分ける
10. package 処理から `CHECK_MODE` と暗黙の capture mode を削除する
11. 残った共通 validator の表示責務とグローバル変数を個別に整理する
12. `docs/ARCHITECTURE.md` を更新する
13. `make validate`、ShellCheck、actionlint、Linux / macOS CI で回帰確認する

各段階でテストを通し、テスト分割、resource 集約、mise 分割を一度の大きな書き換えにしない。

## 9. コミット単位

コミットを分ける場合は、次の4単位を候補にする。

1. `test: split lifecycle tests by feature`
2. `refactor: centralize managed resource definitions`
3. `refactor: separate repository mise responsibilities`
4. `docs: document lifecycle responsibility boundaries`

実装途中の fixup は最終的に対応する単位へまとめる。テスト移動と production code の変更を同じコミットに混ぜず、動作差分を追える履歴にする。

## 10. 完了条件

- `tests/setup-flow.sh` のテストが機能別ファイルへ分割されている
- 移動表により、旧テストの各ケースと新しい移動先、初期状態、主要 assertion を追える
- 共通 fixture と assertion が一か所にまとまり、テスト固有処理は各ファイルに残っている
- 個別テストと `tests/run.sh` による全テストの両方を実行できる
- `make validate` が分割後の全テストを実行する
- managed resource の種類・source・destination を一か所で確認できる
- install / check / uninstall が同じ resource 定義を参照する
- `MANAGED_LINK_STATUSES` の暗黙な受け渡しがなくなっている
- plan 作成時に resource の競合条件を完全に再検証し、失敗時は plan を表示・実行しない
- mise の準備、実行、出力保持、cleanup、診断が関数単位で分かれている
- mise 本体と cleanup の両方が失敗した場合に、両方の情報を確認できる
- mise result state の未実行、成功、失敗と終了コードの優先順位が固定されている
- check / preflight は診断を capture し、install apply は従来どおり出力を端末へ流す
- fake mise の開始 marker を process 終了前に観測する自動テストで、install apply の streaming を確認できる
- 共通 mise 処理が check / install 固有の接頭辞を決めない
- package 処理が `CHECK_MODE` や呼び出し側設定の capture mode を参照しない
- 残るグローバル変数の owner、writer、利用期間が分かる
- CLI、終了コード、利用者向け出力、managed resource の対象が変わっていない
- install / check / uninstall の既存テストに回帰がない
- Bash 3.2 互換を維持している
- `make validate`、ShellCheck、actionlint が成功する
- Linux と macOS の CI が成功する

## 11. 調査方法と制約

この計画は Issue #10、`origin/main` の lifecycle 実装、872行の `tests/setup-flow.sh`、`Makefile`、GitHub Actions workflow、Issue #8 の実装計画を照合して作成した。

現時点では実装前のため、分割後のファイルごとの行数や helper の最終名は確定していない。実装中に境界を調整しても、テストの独立実行、共通処理と表示処理の分離、利用者向け挙動の維持という判断基準は変えない。

## 付録A テストケース移動表

この表は `tests/setup-flow.sh` のテストケースを分割後も漏れなく維持するための台帳である。移動時に実際の test 名または該当行への参照を追記し、すべての行が新しいテストから1回ずつ参照されていることを確認する。

| 旧ケース | 移動先 | 必要な fake / 初期状態 | 主要 assertion |
| --- | --- | --- | --- |
| Parser and removed legacy options fail explicitly | `tests/cli.sh` | clean HOME | 不正引数は終了 `2`、廃止 option を拒否 |
| Bootstrap wrapper ignores ambient version overrides | `tests/bootstrap.sh` | fake version 環境変数 | repository 固定 version、既定 install path、checksum 検証 |
| Homebrew bootstrap success and failure | `tests/bootstrap.sh` | fake `curl` / installer | 公式 installer URL、download / installer 失敗を伝播 |
| Homebrew bootstrap handoff | `tests/bootstrap.sh` | fake installer / `brew` | 新しい brew を再発見し `shellenv` を評価 |
| Missing mise temporary bootstrap | `tests/bootstrap.sh` | fake mise installer | 一時 bootstrap で lock 検証し、`MISE_CMD` を復元 |
| Composite action install-path mapping | `tests/bootstrap.sh` | action YAML | private install path を wrapper 境界へ渡す |
| Install dry-run plan | `tests/lifecycle.sh` | fake brew / mise、clean HOME | 完全な plan、HOME を変更しない |
| Install apply plan and order | `tests/lifecycle.sh` | fake brew / mise、clean HOME | dry-run と同じ plan、package 後に symlink 作成 |
| Check succeeds after convergence | `tests/packages.sh` | install 済み HOME、fake brew / mise | upstream checker を呼び、終了 `0` |
| Managed-link check diagnostics | `tests/check-diagnostics.sh` | install 済み HOME、missing / file / directory / wrong link | 各状態の診断、対象を修復しない |
| `readlink` execution failure | `tests/check-diagnostics.sh` | 対象を限定した fake `readlink` | `check error:`、wrong-target と誤表示しない |
| Mise cleanup failure during check | `tests/check-diagnostics.sh` | 対象を限定した fake `rm` | cleanup 診断、終了 `1`、残留物を harness が削除 |
| Mise preparation helper failures | `tests/check-diagnostics.sh` | fake `mktemp` / `mkdir` / `cp` | 失敗段階ごとの `check error:` と stderr |
| Install helper failure output | `tests/packages.sh` | failing fake `mktemp` | 非ゼロ、install に `check error:` を出さない |
| Missing repository input | `tests/check-diagnostics.sh` | mise config を欠く repository copy | 原因を1回だけ表示し、依存検査を skip |
| Missing required command | `tests/check-diagnostics.sh` | fake `have_cmd` / `git` | 依存 validator を実行せず、他の検査は継続 |
| Mise config / lock / ls failures | `tests/check-diagnostics.sh` | failing fake mise | operation 別診断、元 stderr、終了 `1` |
| Mise exit-status preservation | `tests/check-diagnostics.sh` | status `90`〜`95` の fake mise | mise 失敗を helper failure と誤分類しない |
| Missing mise tools | `tests/packages.sh` | tool 未導入の HOME | `mise tools are missing` と不足 tool を表示 |
| Successful mise stderr | `tests/packages.sh` | warning を出す fake mise | warning を保持し、missing tools と誤判定しない |
| Repeated apply is idempotent | `tests/lifecycle.sh` | install 済み HOME | backup を増やさず成功 |
| Conflict stops package actions | `tests/resources.sh` | regular-file conflict | package action 前に失敗 |
| `--force` backup and convergence | `tests/resources.sh` | regular-file conflict | backup を作り symlink へ収束 |
| Failed symlink creation rollback | `tests/resources.sh` | failing fake `ln` | backup から元ファイルを復元 |
| Rollback does not clobber concurrent destination | `tests/resources.sh` | destination を再作成する fake `ln` | 再出現した destination を上書きしない |
| Missing destination changes after planning | `tests/resources.sh` | plan 後に destination を作る fake command | ensure を replace に昇格しない |
| Directory conflict with `--force` | `tests/resources.sh` | directory conflict | directory を置換せず失敗 |
| Existing lifecycle lock | `tests/lifecycle.sh` | active lock | mutation 前に停止 |
| Failed lock PID write | `tests/lifecycle.sh` | failing pid write | unusable lock を残さない |
| Dead or malformed lock recovery | `tests/lifecycle.sh` | stale / malformed pid | stale lock のみ回収 |
| Stale lock with unexpected entries | `tests/lifecycle.sh` | extra lock entry | metadata を保持して停止 |
| No-op uninstall lock cleanup | `tests/lifecycle.sh` | clean HOME | lock-only state を残さない |
| Symlinked lock parent rejection | `tests/lifecycle.sh` | symlinked parent | link target に触れず停止 |
| Symlinked HOME boundary | `tests/lifecycle.sh` | symlinked HOME / ancestor | HOME 内の symlink だけを拒否 |
| Symlinked lock directory | `tests/lifecycle.sh` | lock directory symlink | stale recovery を redirect しない |
| Existing parent permissions | `tests/lifecycle.sh` | permission 固定 parent | lock 処理が permission を変更しない |
| Relative HOME rejection | `tests/lifecycle.sh` | relative HOME | lock path 作成前に失敗 |
| `--skip-brew` behavior | `tests/packages.sh` | fake brew / mise | Homebrew の検査と action を呼ばない |
| Check aggregates missing state | `tests/check-diagnostics.sh` | missing link / tool | 複数問題を集約し、修復しない |
| Uninstall dry-run / apply | `tests/lifecycle.sh` | install 済み HOME、drift、legacy state | plan 一致、managed link のみ削除 |
| Minimal-command uninstall | `tests/lifecycle.sh` | Git / package manager なしの PATH | uninstall apply が成功 |
| `.bashrc` repository discovery | `tests/resources.sh` | repository を指す `.bashrc` symlink | clone path を固定せず `DOTFILES` を解決 |
| Non-executable bootstrap target | `tests/bootstrap.sh` | unmanaged non-executable mise file | hard conflict として保持し失敗 |

Issue #10 で新規追加する次のケースも、分割後の対応先で管理する。

| 新規ケース | 移動先 | 必要な fake / 初期状態 | 主要 assertion |
| --- | --- | --- | --- |
| Resource changes between preflight and plan | `tests/resources.sh` | plan 前に file / directory / wrong link を作る fake | 完全再検証なしに action を追加しない |
| Mise prepare and cleanup both fail | `tests/check-diagnostics.sh` | failing preparation helper / `rm` | primary と cleanup の両診断、終了コード契約 |
| Mise command and cleanup both fail | `tests/check-diagnostics.sh` | failing fake mise / `rm` | mise status を優先し cleanup 診断も保持 |
| Install apply streams mise output | `tests/packages.sh` | marker 後に release を待つ fake mise | process 終了前に marker を観測 |
