# Issue #10 実装計画のレビュー結果

対象計画: [ISSUE-10-IMPLEMENTATION-PLAN.md](ISSUE-10-IMPLEMENTATION-PLAN.md)

結論は **要修正**。責務分割の方向、Bash 3.2 を前提に一部のグローバル状態を残す判断、テストを先に分割する順序は妥当である。一方、managed resource の再評価方法には既存の安全性を弱める問題があり、mise の出力契約とテスト移行手順にも実装者の判断が残っている。以下の「実装前に直す指摘」を計画へ反映してから着手したい。

## 実装前に直す指摘

### resource の再評価時には競合検証もやり直す

計画では `MANAGED_LINK_STATUSES` を削除し、install preflight で競合を検証した後、plan 作成時に `link_status` を再評価するとしている。この二段階の間に destination が変わると、plan が未検証の状態を取り込む。

たとえば、preflight 時には destination が存在せず、plan 作成前に regular file が作られた場合を考える。plan 側が `link_status` だけを再評価すると、`replaceable_conflict` として置換 action を追加できる。この regular file については、source と同一ファイルでないか、親 directory が安全か、`--force` が指定されているかを検証していない。apply 時の `ensure_symlink` は planned type と現在の状態が一致すれば処理を続けるため、この抜けを補えない。

`MANAGED_LINK_STATUSES` をなくす方針は維持してよい。ただし、次のどちらかへ計画を変更する必要がある。

1. package 検証後、resource の状態確認・競合検証・plan 追加を同じ走査で行う
2. preflight が作った resource action の snapshot を保持し、plan は再判定せずその snapshot を使う

グローバル状態を減らす目的には1が合う。現在と同じく既知の filesystem conflict で package manager の検査を止めたい場合は、前段の早期検証を残し、plan 作成時にも同じ競合検証を再実行する。2回目の検証で失敗したら plan を実行しない。

回帰テストには「preflight では missing、plan 作成前に regular file が出現」のケースを追加する。`--force` の有無にかかわらず、検証を経ていない置換 action を実行しないことを確認する。

### mise の利用者向け出力契約を先に固定する

計画は `RUN_REPOSITORY_MISE_CAPTURE` を削除し、stdout と stderr を常に捕捉するとしている。現行の install apply は mise の出力をそのまま端末へ流すため、常時 capture に変えると次が変わり得る。

- 長時間の `mise install` で進捗が完了まで表示されない
- stdout と stderr を後から再生すると、元の出力順を再現できない
- signal や異常終了時に、capture 済みの途中出力を表示できない

Issue #10 は利用者向けの挙動を変更しないため、単に「stdout / stderr の内容を失わない」だけでは契約が足りない。実装前に operation ごとの扱いを決める。

- config / lock / tool inspection は診断用に stdout と stderr を分離して捕捉する
- install apply は従来どおり端末へ直接流すか、同等のリアルタイム表示を保つ
- cleanup の結果は、mise の出力経路に関係なく別に保持する
- mise と cleanup が両方失敗した場合の最終終了コードを明記する

capture mode という呼び出し側依存のフラグを廃止することと、すべての operation を同じ I/O 方式にすることは分けて考える。`run_repository_mise_capture` と `run_repository_mise_stream` のように入口を明示するか、実行 helper に固定値の I/O 方針を引数で渡せば、暗黙の mode を持たずに現行動作を保てる。

### テスト分割ではケースの移動表を作る

`tests/setup-flow.sh` は単に長いだけではなく、前半で作った fake package manager、収束済み HOME、call log を後半のテストが再利用している。ファイルを切り分けると、この暗黙の前提が失われる。計画にある「各テストは専用の一時 root を持つ」方針は正しいが、helper 一覧だけでは各テストが必要とする初期状態を再構築できない。

分割前に、現在のコメント単位のテストケースを移動先へ対応付ける表を作る。少なくとも次を記録する。

- ケース名と移動先
- 必要な fake command
- 開始時の HOME の状態
- 事前に install apply が必要か
- 期待する終了コードと主要 assertion

移行は、機能別テストと runner を追加し、全ケースが新しい入口から動くことを確認してから `setup-flow.sh` を削除する順にする。行数や成功メッセージだけを比較せず、元の各コメントブロックが移動表で1回ずつ参照されていることを完了条件に加える。

### result state の項目と終了コードを表で定義する

`REPOSITORY_MISE_RESULT_*` という namespace を設ける方針は妥当だが、計画では必要項目と状態の組み合わせがまだ曖昧である。特に準備失敗時には mise を実行しておらず、「mise の終了コード」は存在しない。空文字、`0`、独自値のどれを使うかで formatter の条件分岐が変わる。

次のケースごとに result state と `run_repository_mise` の終了コードを表で固定する。

| ケース | primary failure | command status | cleanup status | 全体の終了コード |
| --- | --- | --- | --- | --- |
| 準備成功、mise 成功、cleanup 成功 | なし | `0` | `0` | `0` |
| 準備失敗、cleanup 成功 | 準備段階 | 未実行 | `0` | 非ゼロ |
| mise 失敗、cleanup 成功 | `mise` | mise の値 | `0` | mise の値 |
| mise 成功、cleanup 失敗 | `cleanup` | `0` | cleanup の値 | 非ゼロ |
| mise 失敗、cleanup 失敗 | `mise` と `cleanup` | mise の値 | cleanup の値 | mise の値を優先 |

最後の優先順位は推奨案であり、既存の CLI 契約に収まるなら別の非ゼロ値でもよい。重要なのは、formatter が空文字や直前の呼び出し結果を誤読しないよう、未実行状態と失敗状態を区別することにある。結果は毎回初期化し、すべての項目を必ず設定する。

## 計画のまま進めてよい点

### Bash 3.2 ではグローバル変数をゼロにしない

nameref と associative array を使えない環境で、複数の結果を無理に標準出力へ符号化すると、quoting と subshell の問題が増える。所有者、writer、reader、利用期間を限定した result state を残す判断は現実的である。

特に command substitution 内で更新した変数は親 shell に戻らないため、isolated root と失敗段階を `run_repository_mise` の結果状態へ直接記録する説明は妥当である。

### managed resource を3要素の単一配列にする

`type source destination` を連続した配列要素として持つ案は、Bash 3.2 で空白を含む path を安全に扱える。delimiter の解析や `eval` も不要で、現在の2本の平行配列より対応関係を追いやすい。

要素数、既知の type、空値、destination の重複を初期化時に検証する方針もよい。内部定義の破損は通常の利用者エラーではないため、未知の type を黙って無視しない判断を維持する。

### 低レベル処理から表示形式を外す

config / lock の検証結果と `check error:`、install 向け `error:` の表示を分ける方針は Issue の目的に合っている。`CHECK_MODE` を下位の package 処理が読む構造をやめ、呼び出し側が formatter を選ぶ形にすると、共通処理の契約が追いやすくなる。

### テスト分割を production code より先に行う

resource と mise の refactor は異常系が多い。先にテストの入口を整理し、テスト移動だけの段階で Linux と macOS の結果を確認する順序は安全である。テスト移動と production code の変更を別 commit にする案も維持する。

## 条件を明確にして取り込む指摘

### callback は固定名の reporter だけに限定する

validator に reporter 関数を渡す案は、`CHECK_MODE` 削除には使える。ただし Bash では関数名も文字列なので、任意の callback を許すと呼び出し関係が追いにくくなる。

callback を使う場合は `preflight_error`、`check_failure`、`check_error` など repository 内で定義した固定名だけを lifecycle から渡す。callback の妥当性検証や汎用 callback framework は作らない。引数の展開に `eval` を使わないという計画の制約も維持する。

### CI の入口変更は workflow lint と同じ commit で確認する

`tests/run.sh` を追加すると、`Makefile`、portability job、ShellCheck の対象が同時に変わる。source 専用の `tests/*.bash` を ShellCheck へ追加し忘れると、共通 helper だけ検査対象から外れる。

テスト分割 commit では、`make validate`、`bash -n`、ShellCheck、actionlint の対象一覧をまとめて更新する。macOS の標準 Bash 3.2 で individual test と runner の両方を起動することも確認する。

## 今回は扱わない内容

- Bash から別言語への移行
- lifecycle 全体を result object 風の仕組みへ統一すること
- `PREFLIGHT_FAILED`、`CHECK_FAILED`、plan 配列、lock 状態の全面廃止
- managed resource type を増やすこと
- test framework の導入
- CLI、終了コード体系、診断メッセージの変更
- package manager の rollback

これらは Issue #10 の完了に必要ない。今回の refactor に混ぜると、既存動作を維持できたか判断しにくくなる。

## 結論

計画の分割方針と実装順は妥当だが、現状のまま実装へ進むべきではない。最優先で直すのは、`MANAGED_LINK_STATUSES` 削除後の再検証方法である。次に mise の stream / capture 契約、テストケースの移動表、result state の状態遷移を計画へ加える。

この4点が明文化されれば、実装者が安全性や互換性をその場で推測する必要がなくなり、[ISSUE-10-IMPLEMENTATION-PLAN.md](ISSUE-10-IMPLEMENTATION-PLAN.md) に沿って段階的に実装できる。

## 私ならこう進める

私は、計画を次の方針に修正してから実装する。判断基準は「既存の安全性と利用者向け出力を保ち、変更理由を各 commit で説明できること」である。

### 1. まずテストを移動し、production code は変更しない

最初の commit では `tests/setup-flow.sh` の内容を機能別ファイルへ移すだけにする。共通 helper は fixture の初期化、fake command の配置、assertion に限定し、各テストが必要とする `install --apply` 済み HOME などの状態は各ファイルで明示的に作る。

移動前にコメント単位のケース一覧を作り、移動先、初期状態、主要 assertion を記録する。旧ファイルをすぐ削除せず、新しい runner と旧テストを同じ commit で実行してから削除する。これで「テストが通るがケースが落ちた」という分割事故を検出できる。

この段階の完了条件は、production code の差分がなく、`tests/run.sh`、各テスト単独実行、`make validate` がすべて移動前と同じ結果になることとする。

### 2. resource は単一配列にするが、plan 作成時にも完全検証する

`MANAGED_RESOURCES` の3要素配列は採用する。ただし `MANAGED_LINK_STATUSES` を削除する際、plan 作成側は `link_status` だけを再計算しない。

具体的には次の流れにする。

1. 初期 preflight で明らかな競合を検出し、package manager の検査を不要に実行しない
2. package 検証が終わった直後、resource ごとに source、destination、親 directory、`--force`、同一ファイル性を再検証する
3. その同じ走査で plan action を追加する
4. 1件でも再検証に失敗したら plan を表示・実行しない

この構造なら状態 snapshot 用の配列を減らしながら、preflight 後の destination 変更を安全に扱える。追加テストでは、preflight 後に regular file、directory、別 target の symlink が出現するケースを確認する。

### 3. mise は check と install で I/O 方針を分ける

共通化するのは isolated 環境の準備、mise 起動、cleanup、結果の構造化であり、出力経路まで一つにしない。

- check の config / lock / tool inspection は stdout と stderr を一時ファイルへ分離して capture する
- install apply は mise の stdout / stderr を従来どおり端末へ流し、進捗表示の遅延を発生させない
- install preflight の dry-run 検証は診断が必要なので capture する
- cleanup の失敗は、どの I/O 方針でも result state に記録して呼び出し側が報告する

低レベル helper に boolean の capture mode を持たせる代わりに、`run_repository_mise_check` と `run_repository_mise_apply` のように用途が分かる薄い入口を置き、内部の orchestrator と準備・cleanup helper を共有する。これなら「暗黙の `CHECK_MODE`」は消え、install の出力契約も守れる。

### 4. result state は固定項目と終了コードを先に実装する

結果 namespace は次の項目に限定する。

```text
REPOSITORY_MISE_RESULT_STAGE
REPOSITORY_MISE_RESULT_STATUS
REPOSITORY_MISE_RESULT_STDOUT
REPOSITORY_MISE_RESULT_STDERR
REPOSITORY_MISE_RESULT_CLEANUP_STATUS
REPOSITORY_MISE_RESULT_CLEANUP_STDERR
REPOSITORY_MISE_RESULT_TEMP_PATH
```

`STAGE` は `prepare`、`mise`、`cleanup`、空文字のいずれか、未実行の status は空文字、成功は `0` とする。mise が失敗した場合は mise の終了コードを返し、cleanup だけが失敗した場合は `1` を返す。両方が失敗した場合は mise の終了コードを返し、cleanup の診断も必ず表示する。準備失敗時も cleanup を試み、結果を初期化してから各 operation を開始する。

この契約を先にテストへ落とし、準備失敗、mise 失敗、cleanup 失敗、同時失敗の4ケースを fake command で固定する。formatter はこの result state だけを読み、`run_repository_mise` の内部変数を直接参照しない。

### 5. 表示責務の分離は mise validator から始める

最初から context、platform、repository の全 validator を callback 化しない。まず `validate_repository_mise_config` と `validate_repository_mise_lock` を、結果を返す共通処理と check / install の formatter に分ける。

その後、`CHECK_MODE` が package 処理から消えたことを確認し、残った `report_check_or_preflight` の利用箇所を個別に整理する。callback を使う場合も、repository 内で定義した固定 reporter 名に限定し、汎用 callback 機構は導入しない。

### 6. commit と検証を小さく刻む

私なら commit は次の順にする。

1. `test: split lifecycle tests by feature`
2. `refactor: centralize managed resource definitions`
3. `refactor: separate repository mise responsibilities`
4. `docs: document lifecycle responsibility boundaries`

各段階で `make validate` を通し、production code の変更後は ShellCheck と actionlint も実行する。最終的に Linux と macOS の CI が成功し、CLI の終了コード、plan の順序、install apply の mise 出力が変更前と一致することを確認して完了とする。
