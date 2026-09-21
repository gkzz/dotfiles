# TEST-CONTROL-PLANE-MIGRATION-PLAN のレビュー

## トリアージ結果

| 指摘 | 判断 | 理由 |
| --- | --- | --- |
| Node.js と `--test-isolation=none` の互換性 | 不採用 | repository と現在の実行環境はともに Node.js `24.19.0` であり、現行の `tests/run.sh` は option を含むまま成功する。Node.js 22 という前提が現状と一致しない |
| assertion 対応表の明確化 | 採用 | 移行漏れと重複をレビューできる成果物、列、完了条件を計画書に追加する |
| `mise-isolation.sh` 移動範囲の具体化 | 採用 | workflow、構文検査、単独実行、旧パス検索を同じ変更で確認する |
| `check.test.mjs` の所有範囲 | 採用 | 外部 package/mise に依存しない repository validation の置き場として明記する |
| helper 追加の制約 | 採用 | 既存の `run` と `TestFixture` で表現できない共有処理に限る |
| documentation 更新の一覧化 | 採用 | `docs/ARCHITECTURE.md` をファイルごとの着地点と完了条件へ加える |

## 結論

移行方針は妥当である。`node:test` をテストケースの control plane とし、fake command、実 mise との isolation、launcher を shell の境界として残す判断は、現在のファイル構成と一致している。特に `check-diagnostics.sh` をそのまま `check.test.mjs` に翻訳せず、symlink・package/mise・lifecycle の所有単位へ戻す方針は、既存テストとの重複を抑えやすい。

ただし、現状のままでは実装者が判断をやり直す箇所が残っている。採用した2点と軽微な改善提案を計画書へ反映してから着手したい。

| 重要度 | 指摘 | 対応 |
| --- | --- | --- |
| 取り下げ | Node.js の対応範囲と `--test-isolation=none` の扱い | Node.js 22 という前提が誤っていた。固定版の Node.js `24.19.0` で現行 runner は成功する |
| 高 | assertion の移行先を記録する checklist の成果物と完了基準が曖昧 | リポジトリに残さない一時台帳でもよいので、ケース・assertion 単位の対応表を必須化する |
| 中 | `mise-isolation.sh` の移動に伴う CI・構文検査・単独実行の更新範囲が不十分 | 参照箇所を列挙し、移動後の実行確認を完了条件に追加する |

## 取り下げ: Node.js と test runner option の互換性

計画書は個別テストの実行例に次を掲載している。

```bash
mise --cd .config/mise exec -- node --test --test-isolation=none --test-concurrency=1 tests/bootstrap.test.mjs
```

確認の結果、`.config/mise/config.toml` と lock file は Node.js `24.19.0` を固定していた。現在の実行環境も同じバージョンであり、`./tests/run.sh` は `--test-isolation=none` を含むまま25件すべて成功した。Node.js 22 を前提にした指摘は取り下げる。

計画書には、Node.js の対応範囲と runner option をこの移行で変更しないこと、option error が出た場合は mise 管理版が選択されているか確認することを追記した。

## 高: assertion 対応表を実装成果物として定義する

計画書は「coverage checklist を作る」「旧 assertion がどの Node.js テストで担保されたかを一対一で追跡する」としている。しかし、その checklist をどこに作り、いつ削除し、何をもって全件対応と判定するかが書かれていない。

このままでは、既存の `packages.test.mjs` に似た検証がある場合に、次のどちらかが起きやすい。

- Bash の assertion を削除したが、stderr の文言、終了コード、cleanup 状態のいずれかを移し忘れる
- 既存テストと新規テストを重複して追加し、どのケースが必要なのか分からなくなる

少なくとも次の列を持つ対応表を作り、各移行コミットで更新するべきである。

| 旧ケース | 旧 assertion | 期待する status/stdout/stderr/state | 移行先テスト | 重複確認 | 完了 |
| --- | --- | --- | --- | --- | --- |

台帳はレビュー用の一時ファイルとして作業ブランチ内に置き、移行完了時に削除してもよい。ただし、PR の差分またはレビューコメントから、全 assertion を確認したことが分かる状態にする必要がある。計画書の完了条件も「全 assertion に移行先がある」だけでなく、「対応表の全行が完了し、旧テストの削除前にレビューした」にすると明確になる。

## 中: `mise-isolation.sh` の移動範囲を具体化する

`tests/mise-isolation.sh` を `tests/integration/mise-isolation.sh` へ移す判断は理解できる。ただし、現在の構成では少なくとも次の参照・運用面を同時に更新する必要がある。

- `.github/workflows/test.yml` の `run` パス
- `make validate` の `bash -n` glob（`tests/*.sh` では移動後の `tests/integration/mise-isolation.sh` を拾わない）
- 開発者が単独実行するパス
- `rg` による旧パス参照の確認
- `tests/integration` 自体を shell test の置き場として説明する文書

計画書には workflow と構文検査の更新が書かれているが、単独実行と「移動後のファイルが構文検査対象に入ったこと」の確認が完了条件にない。`bash -n tests/integration/*.sh` など、移動後のパスを明示した検証を追加すべきである。なお、`tests/run.sh` は Node.js テスト専用なので、integration shell test をそこへ混ぜない現在の分離は維持してよい。

## 方針として良い点

### shell を「残存」ではなく境界として定義している

fake-brew、fake-mise、実 mise との isolation、launcher を「移行漏れ」ではなく system boundary と説明している。新しい `.sh` テストを追加するときの判断基準としても使える。

### 既存テストとの重複を抑える方向が明確である

`packages.test.mjs` にはすでに mise の result state、cleanup、check の検証がある。移行時に旧 Bash テストを丸ごと移植せず、既存ケースを移行先として認める方針は適切である。

### failure locality を完了条件にしている

単に Bash の行数を減らすのではなく、失敗した stage、status、機能が test report に出ることを目標にしている。Issue の目的に対して測定可能な方向である。

## 軽微な改善提案

- `bootstrap.test.mjs` と `check.test.mjs` を新設する判断は妥当だが、`check` の repository validation を既存の `cli`、`lifecycle`、`packages` のどこに置くかは、実装時に迷わないよう「外部 package/mise に依存しない check validation は `check.test.mjs`」と一文で固定するとよい。
- `TestFixture` に追加する helper の候補が抽象的である。fixture の一時 repository、executable 作成、環境変数の上書きのうち、既存 `run` helper で足りるものは増やさないという制約を加えると helper の肥大化を防げる。
- `docs/ARCHITECTURE.md` の更新を実装手順に含めている点はよい。計画書のファイルごとの着地点にも documentation の更新を含めると、実装漏れを見つけやすい。

## レビュー後の推奨順序

1. assertion 対応表を作る
2. `check-diagnostics.sh` を symlink、packages、check、lifecycle の順で移行する
3. `bootstrap.sh` を移行する
4. shell scaffold を削除し、`mise-isolation.sh` の配置を整理する
5. `make validate`、`./tests/run.sh`、CI の各 job と旧パス参照を確認する

この順序なら、先に runner の前提と契約の抜け漏れを潰してから、実装量の大きい移行へ進められる。
