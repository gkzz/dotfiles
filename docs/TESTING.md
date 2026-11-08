# テスト

このリポジトリは mise bootstrap を利用します。CI では mise のパッケージや dotfile の処理を再実装せず、help の出力、bootstrap の dry-run、dotfile の適用と解除に加え、Git フックの既存テストを実行します。

## 実行方法

リポジトリルートで実行します。

```bash
make ci                              # lint とテスト
make test                            # bootstrap dry-run、Makefile、Git hook のテスト
make test-bootstrap-packages-dry-run # パッケージの dry-run
```

`make test` の dry-run は packages と dotfiles を除いて実行します。パッケージの宣言と解決は別の dry-run で、一時 HOME への dotfile の適用・状態確認・解除は GitHub Actions で確認します。

## 自動テスト

| レイヤー | テスト | 確認内容 |
| --- | --- | --- |
| Lint | `make lint` | hook、setup、補助スクリプトの Bash 構文 |
| Makefile | `mise run dotfiles:test:make`（操作用設定を指定） | 追加した PATH からの mise 検出、空白を含むパス、mise 未導入時の案内 |
| Git hook | `make test-git-hooks` | 既存16ケースでステージ済み内容、ignore、設定、失敗時の処理、Git からのフック実行を確認 |
| Help | [test.yml](../.github/workflows/test.yml) | Makefile と補助スクリプトの help 出力 |
| Dry-run | [test.yml](../.github/workflows/test.yml) | packages と dotfiles を除いた bootstrap の dry-run が完了すること |
| Package dry-run | [test.yml](../.github/workflows/test.yml) | Homebrew package bootstrap の dry-run が完了すること |
| Dotfiles lifecycle | [test.yml](../.github/workflows/test.yml) | 一時 HOME で install の dry-run/apply 後に `status --missing` が成功し、unapply 後は全 dotfile が missing と判定されること |
| macOS Bash 起動 | [test.yml](../.github/workflows/test.yml) | 一時 HOME への適用後、`/bin/bash -ilc` で `DOTFILES`、`ll` alias、mise のシェル関数が読み込まれること |

Git hook のテストは Docker を模擬するため、実際の secretlint による secret 検出は確認しません。Bash 構文は `make lint` で確認します。

GitHub Actions では help、dry-run、Makefile、Git hook、dotfile の適用と解除を Linux と macOS の両方で確認します。

## テスト対象外

`make setup` がネットワーク経由で Homebrew や mise を実際に導入する処理、全パッケージのインストール成功、mise 自身による競合解決や unapply の実装は、自動テストの対象外です。実環境に bootstrap を適用する前に dry-run を確認してください。
