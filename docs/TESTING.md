# Testing

CI では Linux と macOS で自動テストを実行します。

## Running Tests

リポジトリルートで実行します。

```bash
make ci                              # lint とテスト
make test                            # bootstrap dry-run と各種自動テスト
make test-bootstrap-packages-dry-run # パッケージの dry-run
```

`make test` の dry-run は packages と dotfiles を除いて実行します。パッケージの宣言と解決は別の dry-run で、一時 HOME への dotfile の適用・状態確認・解除は GitHub Actions で確認します。

## Automated Tests

textlint のテストには依存パッケージが必要です。初回は `mise exec -- pnpm install --frozen-lockfile` を実行してください。

| レイヤー | テスト | 確認内容 |
| --- | --- | --- |
| Lint | `make lint` | hook、setup、補助スクリプトの Bash 構文と日本語の文章 |
| Makefile | `mise run dotfiles:test:make`（操作用設定を指定） | 追加した PATH からの mise 検出、空白を含むパス、mise 未導入時の案内 |
| シェル起動 | `mise run dotfiles:test:shell`（操作用設定を指定） | [起動テスト7件](#shell-startup-tests)で OS ごとの初期化と PATH を確認 |
| Git hook | `make test-git-hooks` | 既存16ケースでステージ済み内容、ignore、設定、失敗時の処理、Git からのフック実行を確認 |
| textlint | `mise run dotfiles:test:textlint`（操作用設定を指定） | 再帰探索、隠しディレクトリ、ignore、全件除外、対象なしの挙動 |
| Codex | `mise run dotfiles:test:codex`（操作用設定を指定） | 一時 HOME で mise のマージ、既存設定の保持、再適用、解除、不正な設定での停止を確認 |
| Help | [test.yml](../.github/workflows/test.yml) | Makefile と補助スクリプトの help 出力 |
| Dry-run | [test.yml](../.github/workflows/test.yml) | packages と dotfiles を除いた bootstrap の dry-run が完了すること |
| Package dry-run | [test.yml](../.github/workflows/test.yml) | Homebrew package bootstrap の dry-run が完了すること |
| Dotfiles lifecycle | [test.yml](../.github/workflows/test.yml) | 一時 HOME で install の dry-run/apply 後に `status --missing` が成功し、unapply 後はリンクが missing と判定され、Codex のマージ済み設定が残ること |
| macOS Bash 起動 | [test.yml](../.github/workflows/test.yml) | 一時 HOME への適用後、`/bin/bash -ilc` で `DOTFILES`、`ll` alias、mise のシェル関数が読み込まれること |

Git hook のテストは Docker を模擬し、実際の secretlint による secret 検出は確認しません。

## Shell Startup Tests

[tests/shell.test.js](../tests/shell.test.js) は、一時 HOME と制御した PATH で対話 Bash を起動します。
親シェルの環境変数は引き継がず、OS 判定と外部コマンドを代替してホスト環境への依存を抑えます。
共通設定のうち PATH 設定は読み込み、無関係な補完やプロンプト設定は読み込みません。

| 条件 | 件数 | 確認内容 |
| --- | --- | --- |
| 通常の Linux。mise を HOME 配下または PATH に配置 | 2 | Homebrew → mise → direnv の順序、管理対象ツールの実行、SSH 処理が動かないこと |
| WSL | 1 | Linux 共通処理が一度だけ動き、その後に SSH 処理が動くこと |
| macOS | 1 | macOS の初期化が動き、Linux・WSL 固有処理が動かないこと |
| ツール未導入の Linux、WSL、macOS | 3 | シェルが起動できること |

全ケースで `~/.bashrc.local` が最後に読み込まれることも確認します。
このテストは分岐とコマンドの呼び出しを検証し、実際のツールや SSH agent の動作は検証しません。
macOS で適用したファイルからの起動は、表中の「macOS Bash 起動」で別途確認します。

## Out of Scope

次の処理は自動テストの対象外です。

- `make setup` による Homebrew・mise の実導入
- 全パッケージのインストール成功
- mise 自身による競合解決や unapply の実装

実環境に bootstrap を適用する前に dry-run を確認してください。
