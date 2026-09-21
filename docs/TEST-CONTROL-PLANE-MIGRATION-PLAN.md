# JS を test control plane にし、shell を system boundary として残す

## この計画で決めること

テストケースの組み立て、fixture の lifecycle、assertion、結果表示は `node:test` に寄せる。一方、外部 CLI の fake、実際の shell 環境との contract test、mise から Node.js を起動する launcher は shell のまま残す。

Issue 8 では、次の状態を完成形とする。

- `tests/check-diagnostics.sh` と `tests/bootstrap.sh` のテストケースを `node:test` へ移す
- `tests/test-helper.bash` と `tests/fixtures/setup.bash` は、参照元がなくなった時点で削除する
- `tests/fixtures/fake-brew.bash` と `tests/fixtures/fake-mise.bash` は Unix executable の test double として残す
- `tests/mise-isolation.sh` は実 shell・実 mise との contract test として残す
- `tests/run.sh` は mise 管理の Node.js を起動する短い launcher として残す
- `.github/workflows/e2e_smoke.yml` の shell は、本番に近い CLI smoke test なので変更しない

この計画はテスト構成の整理に限る。production code の仕様変更、テスト対象の挙動変更、すべての shell の撤去は対象外とする。

## 現状と問題

現在の `node:test` は、`cli.test.mjs`、`lifecycle.test.mjs`、`packages.test.mjs`、`symlinks.test.mjs` に機能別のテストを持つ。その一方で、`shell-regression.test.mjs` が `bootstrap.sh` と `check-diagnostics.sh` を各1件のテストとして起動している。

この構成では、Bash 側に詳細な failure message があっても、Node.js 側から見える失敗単位は `passes bootstrap.sh` または `passes check-diagnostics.sh` までになる。特に296行ある `check-diagnostics.sh` は、データ駆動の繰り返し、終了コードの捕捉、fake command の準備、assertion を自身で担っており、テスト対象の shell 境界よりもテストランナーとしての責務が大きい。

また、`tests/fixtures/setup.bash` の一時 HOME、fake command、環境変数の準備は、すでに `tests/helpers/fixture.mjs` の `TestFixture` と重複している。移行後も両方を残すと、fixture の変更箇所が分散する。

## ファイルごとの着地点

| 現在のファイル | 着地点 | 判断理由 |
| --- | --- | --- |
| `tests/check-diagnostics.sh` | 機能別の `.test.mjs` へ分割して削除 | assertion、case 分岐、終了コード管理を `node:test` の subtest に置き換えられる |
| `tests/bootstrap.sh` | `tests/bootstrap.test.mjs` へ移して削除 | 独立した bootstrap ケースをテスト名と失敗箇所に直接対応させられる |
| `tests/shell-regression.test.mjs` | 移行完了後に削除 | 対象の2本がなくなると役割を失う |
| `tests/test-helper.bash` | 参照元消滅後に削除 | assertion と共通処理を Node.js helper に統一できる |
| `tests/fixtures/setup.bash` | 参照元消滅後に削除 | `TestFixture` と責務が重複する |
| `tests/fixtures/fake-brew.bash` | 維持 | `brew` executable の最小な test double である |
| `tests/fixtures/fake-mise.bash` | 維持 | `mise` executable の最小な test double である |
| `tests/mise-isolation.sh` | `tests/integration/mise-isolation.sh` へ移動 | hostile な shell/mise environment との境界を直接検証する |
| `tests/run.sh` | 維持 | repository が固定した Node.js で test runner を起動する境界である |
| `.github/workflows/e2e_smoke.yml` | 維持 | 実 CLI の一連の操作を GitHub Actions 上で検証する smoke test である |
| `.github/workflows/test.yml` | isolation test の実行パスだけ更新 | `tests/integration/mise-isolation.sh` への移動を CI に反映する |
| `Makefile` | Bash 構文検査の対象を更新 | 移動後の `tests/integration/*.sh` を `bash -n` の対象に含める |
| `docs/ARCHITECTURE.md` | テスト構成と shell boundary の説明を更新 | 今後のテスト追加時にも同じ判断基準を使えるようにする |

`mise-isolation.sh` の移動は、shell が残っている理由を配置でも示すために行う。CI の実行パスと `make validate` の構文検査対象も同じ変更で更新する。

## 移行方針

### `check-diagnostics.sh` は production code の所有単位へ戻す

`check-diagnostics.sh` と同じ大きさの `check.test.mjs` を作るのではなく、検証対象に応じて既存ファイルへ移す。

| 現在の検証 | 移行先 | テストの粒度 |
| --- | --- | --- |
| managed symlink の missing、regular file、directory、wrong target、`readlink` failure | `tests/symlinks.test.mjs` | 状態ごとの subtest |
| mise 一時ディレクトリの準備・copy・cleanup failure | `tests/packages.test.mjs` | failure stage ごとのデータ駆動 subtest |
| primary failure と cleanup failure の同時発生 | `tests/packages.test.mjs` | prepare/mise の組み合わせごとの subtest |
| mise config、lock、tool inspection の failure と終了コード | `tests/packages.test.mjs` | operation/status ごとのデータ駆動 subtest |
| repository input の欠落、必須 command の欠落 | `tests/check.test.mjs` | 外部 package/mise に依存しない repository validation を dependency ごとの subtest にする |
| 複数の missing state を集約し、修復しないこと | `tests/lifecycle.test.mjs` | `check` 全体の振る舞いを示すテスト |

既存の `packages.test.mjs` には mise の result state や check 診断の検証がすでにある。移行時は、旧 Bash テストの各 assertion を既存ケースと突き合わせ、同じ契約を重ねて検証しているだけなら新規ケースを増やさない。旧 assertion がどの Node.js テストで担保されたかは、移行用チェックリストで一対一に追跡する。

shell function を直接検証する必要がある場合は、既存テストと同様に `run("bash", ["-c", script])` を使う。JS の担当は setup、process 起動、assertion、cleanup、reporting であり、production の Bash 関数を JavaScript に再実装しない。

### `bootstrap.sh` は独立したケースを `bootstrap.test.mjs` にする

`tests/bootstrap.test.mjs` には、現在の138行を次の単位で移す。

- mise bootstrap が ambient override を無視し、固定 version と HOME 配下の install path を使う
- mise installer が release asset と SHA-256 checksum を検証する
- Homebrew installer の download failure と実行 failure を伝播する
- bootstrap 後に発見した `brew` の `shellenv` を評価する
- lockfile validation 用の mise を一時領域だけに作り、成功後に状態を持ち越さない
- invalid lockfile を拒否する
- composite action が private install path を明示的な境界へ渡す
- non-executable な既存 bootstrap target を競合として拒否し、元ファイルを保つ

fake executable は shell のまま一時 `bin` に作成してよい。ただし、その生成と permission 設定、実行、結果確認は `TestFixture` または小さな JS helper が管理する。複数ケースで同じ処理が必要になった場合だけ helper を追加し、単一ケース専用の abstraction は作らない。

## 実装手順

### 1. 現在の契約を一覧化する

最初に `bootstrap.sh` と `check-diagnostics.sh` の assertion をケース単位で列挙する。この一覧を移行中の coverage checklist とし、少なくとも次の列を持たせる。

| 旧ケース | 旧 assertion | 期待する status/stdout/stderr/state | 移行先テスト | 重複確認 | 完了 |
| --- | --- | --- | --- | --- | --- |

checklist は実装PRの説明、またはレビュー中だけ追跡する一時文書に置く。旧 Bash ケースを削除する前に該当行をレビューし、全行が完了したことをPRから確認できる状態にする。一時文書を使った場合は、全件確認後に削除して完成後のリポジトリへ残さない。

この段階では production code を変更しない。現行の `./tests/run.sh` と `make validate` を基準結果として記録する。

### 2. `check-diagnostics.sh` を機能別に移す

移行順は次のとおりとする。

1. managed symlink の診断を `symlinks.test.mjs` へ移す
2. mise preparation、execution、cleanup の診断を `packages.test.mjs` へ移す
3. repository validation を新しい `check.test.mjs` へ移す
4. aggregate check behavior を `lifecycle.test.mjs` へ移す

各まとまりを移したら、対応する Bash 側ケースを削除して同じ契約を二重実行しない。全ケースの移行後に `check-diagnostics.sh` を `shell-regression.test.mjs` の対象から外す。

failure injection は二つの方法を使い分ける。CLI 境界で起こす失敗は一時 `bin` に置く fake executable で作る。source 済みの shell function 内部だけで起こせる失敗は、短い Bash snippet で関数を override する。どちらも個別の `it` またはデータ駆動 subtest から起動し、失敗名が test report に出るようにする。

### 3. `bootstrap.sh` を `bootstrap.test.mjs` へ移す

`TestFixture` を再利用し、必要であれば次の最小機能を追加する。

- fixture 配下に executable を作成する
- fixture 用の repository tree を用意する
- stdout/stderr を含めて期待する終了コードを検証する

helper の追加は、複数ケースで共有し、既存の `run` と `TestFixture` の組み合わせでは重複を避けられない処理に限る。単一ケース専用の setup はテスト内に置く。

ケースごとに HOME と作業ディレクトリを分ける。ambient environment の影響を検証するケースを除き、親 process の `HOME`、mise 関連変数、PATH に依存させない。全ケースの移行後に `bootstrap.sh` を `shell-regression.test.mjs` の対象から外す。

### 4. 移行専用の shell scaffold を削除する

`bootstrap.sh` と `check-diagnostics.sh` の削除後、`rg` で参照がないことを確認してから、次を削除する。

- `tests/shell-regression.test.mjs`
- `tests/test-helper.bash`
- `tests/fixtures/setup.bash`

`tests/run.sh` には `bootstrap.test.mjs` と `check.test.mjs` を追加し、削除した `shell-regression.test.mjs` を外す。`make validate` の Bash 構文検査は残す shell のみを対象にする。

### 5. shell boundary を配置と文書に反映する

`tests/mise-isolation.sh` を `tests/integration/mise-isolation.sh` へ移し、次を同じ変更で更新する。

- `.github/workflows/test.yml` の `mise-isolation` job
- `Makefile` の `bash -n` 対象。`tests/integration/*.sh` を明示的に含める
- `docs/ARCHITECTURE.md` のテスト構成と単独実行パス

更新後は `bash -n tests/integration/*.sh` と `./tests/integration/mise-isolation.sh` を単独で実行する。`rg 'tests/mise-isolation\.sh'` で旧パスが残っていないことも確認する。

`docs/ARCHITECTURE.md` には、次のルールが分かる記述を加える。

> テストケース、fixture lifecycle、assertion は原則 `node:test` で記述する。外部 CLI の fake、実 shell 環境との contract test、test runner の bootstrap には shell を使う。

今後 shell テストへ `if`、`for`、独自 assertion が増え、system boundary の確認より orchestration が主になった場合は `.test.mjs` への移行を検討する。

## 検証方法

各段階で、repository が固定した toolchain を通して次を実行する。

```bash
./tests/run.sh
make validate
```

個別テストの開発時も ambient Node.js を直接使わず、repository の mise 設定を通す。

```bash
mise --cd .config/mise exec -- node --test --test-isolation=none --test-concurrency=1 tests/bootstrap.test.mjs
mise --cd .config/mise exec -- node --test --test-isolation=none --test-concurrency=1 tests/check.test.mjs
```

repository は `.config/mise/config.toml` と lock file で Node.js `24.19.0` を固定しており、現行の `tests/run.sh` は `--test-isolation=none` を含む構成で成功している。この移行では Node.js の対応範囲や runner option を変更しない。個別実行で option error が出た場合は、ambient Node.js ではなく mise 管理版が選択されているかを確認する。

shell contract test を移動した段階では、次も実行する。

```bash
bash -n tests/integration/*.sh
./tests/integration/mise-isolation.sh
```

CI では次を確認する。

- Ubuntu と macOS の portability job で全 Node.js テストが通る
- `mise-isolation` job が移動後の shell contract test を実行する
- E2E smoke test の挙動が変わらない
- test report が旧 Bash ファイル単位ではなく、失敗した機能とケース名を示す

## 完了条件

- `bootstrap.sh` と `check-diagnostics.sh` の全 assertion に移行先があり、`./tests/run.sh` から個別ケースとして実行される
- coverage checklist の全行がレビュー済みで、旧 Bash ケースの削除前に完了している
- `tests/check-diagnostics.sh`、`tests/bootstrap.sh`、`tests/shell-regression.test.mjs` が削除されている
- `tests/test-helper.bash` と `tests/fixtures/setup.bash` に参照元がなく、削除されている
- fake command、`tests/integration/mise-isolation.sh`、`tests/run.sh` は shell boundary として残っている
- `bash -n tests/integration/*.sh` と `./tests/integration/mise-isolation.sh` が成功する
- `rg 'tests/mise-isolation\.sh'` で旧パス参照が見つからない
- `docs/ARCHITECTURE.md` が移行後のテスト構成、shell boundary、単独実行パスを説明している
- `make validate` が成功する
- GitHub Actions の test、mise isolation、portability が成功する
- production code の挙動と公開 CLI に意図しない変更がない

## リスクと抑え方

最も大きなリスクは、移行中に assertion を落とすことと、既存の Node.js テストと重複させて suite を遅くすることにある。最初に coverage checklist を作り、Bash ケースを消すたびに移行先を対応づける。既存テストで契約が十分に表現されている場合は、ケースを複製せず checklist 上でそのテストを移行先とする。

次に、親 process の環境が fixture へ漏れる可能性がある。`TestFixture.dotfilesEnv()` を共通の入口とし、環境分離そのものがテスト対象のケースだけ明示的に上書きする。

最後に、`mise-isolation.sh` の移動で CI だけが古いパスを参照する可能性がある。移動と workflow、`make validate`、文書の更新は同じ変更にまとめ、旧パスが残っていないことを `rg` で確認する。
