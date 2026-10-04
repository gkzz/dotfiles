# テスト戦略

このリポジトリは mise bootstrap を利用します。CI では mise のパッケージや dotfile の処理を再実装せず、help の出力、bootstrap の dry-run、dotfile の適用と解除に加え、Git フックの既存テストを実行します。

## 自動テスト

| レイヤー | テスト | 確認内容 |
| --- | --- | --- |
| Lint | `make lint` | hook、setup、補助スクリプトの Bash 構文 |
| Git hook | `make test-git-hooks` | 既存16ケースでステージ済み内容、ignore、設定、失敗時の処理、Git からのフック実行を確認 |
| Help | [test.yml](../.github/workflows/test.yml) | Makefile と補助スクリプトの help 出力 |
| Dry-run | [test.yml](../.github/workflows/test.yml) | packages と dotfiles を除いた bootstrap の dry-run が完了すること |
| Package dry-run | [test.yml](../.github/workflows/test.yml) | Homebrew package bootstrap の dry-run が完了すること |
| Dotfiles lifecycle | [test.yml](../.github/workflows/test.yml) | 一時 HOME で install の dry-run/apply 後に `status --missing` が成功し、unapply 後は全 dotfile が missing と判定されること |

Git hook の Bash 構文は `make ci` の lint で確認します。既存テストは Docker を模擬するため、実際の secretlint による secret 検出は確認しません。テストの整理は今後改めて検討します。`make ci` は lint、bootstrap dry-run、Git フックの既存テストを実行し、GitHub Actions では一時 HOME で dotfile の lifecycle も確認します。

`make test` は `make test-bootstrap-dry-run` と `make test-git-hooks` を実行します。この dry-run は dotfile や packages を適用・検証しません。package は別の dry-run target で宣言と解決を確認します。dotfile lifecycle の確認は GitHub Actions で行います。

## テスト対象外

`make setup` がネットワーク経由で Homebrew や mise を実際に導入する処理、全パッケージのインストール成功、mise 自身による競合解決や unapply の実装は、自動テストの対象外です。実環境に bootstrap を適用する前に dry-run を確認してください。
