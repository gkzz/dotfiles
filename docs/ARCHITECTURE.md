# Architecture

この文書では、リポジトリの構成と内部処理の関係を説明します。利用者向けのコマンドは [Operations](OPERATIONS.md)、エラー時の対応は [Troubleshooting](TROUBLESHOOTING.md) を参照してください。

## 全体の流れ

```mermaid
flowchart TD
    user[利用者] --> command{bin/dotfiles}

    command -->|install| install_mode{dry-run / apply}
    command -->|check| check
    command -->|uninstall| uninstall_mode{dry-run / apply}

    install_mode --> install_lock{apply?}
    install_lock -->|yes| lock_i[HOME 単位の lock を取得]
    install_lock -->|no| preflight_i
    lock_i --> preflight_i[preflight: 実行環境と競合を確認]
    preflight_i --> plan_i[install の処理を組み立てて表示]
    plan_i --> apply_i{apply?}
    apply_i -->|no| done_i[dry-run 完了]
    apply_i -->|yes| skip_brew{--skip-brew?}
    skip_brew -->|no| packages[Homebrew / mise を適用]
    skip_brew -->|yes| mise_only[mise を適用]
    packages --> links[managed symlink を作成・置換]
    mise_only --> links
    links --> unlock_i[lock を解放]

    check --> check_env[Bash / Git / mise と Homebrew 任意を確認]
    check_env --> check_links[managed symlink を確認]
    check_links --> done_c[結果を表示]

    uninstall_mode --> uninstall_lock{apply?}
    uninstall_lock -->|yes| lock_u[HOME 単位の lock を取得]
    uninstall_lock -->|no| preflight_u
    lock_u --> preflight_u[preflight: 削除対象を確認]
    preflight_u --> plan_u[uninstall の処理を組み立てて表示]
    plan_u --> apply_u{apply?}
    apply_u -->|no| done_u[dry-run 完了]
    apply_u -->|yes| unlink[managed symlink を削除]
    unlink --> unlock_u[lock を解放]
```

`preflight` は install / uninstall の内部処理です。変更前に実行環境、必要なコマンド、対象パス、symlink の競合を確認します。dry-run と apply のどちらでも実行します。

`check` は独立したコマンドです。現在の環境が期待どおりか確認しますが、処理計画の作成や修復は行いません。

## ファイルの責務

| ファイル | 担当 |
| --- | --- |
| `bin/dotfiles` | コマンドと option のインタフェース |
| `setup/lifecycle.bash` | install / check / uninstall、lock、preflight の進行管理 |
| `setup/plan.bash` | dry-run と apply で共通する処理計画の保持と実行 |
| `setup/packages.bash` | Homebrew / mise の確認、bootstrap、適用 |
| `setup/symlinks.bash` | managed symlink の定義検証、確認、backup、作成、削除 |
| `setup/context.bash` | HOME / XDG と管理対象パスの決定 |
| `setup/lib.bash` | 共通の検証とログ出力 |
| `tests/helpers/` | `node:test` から使う process 実行、共通 assertion、`TestFixture` |
| `tests/test-helper.bash` | 移行中の Bash 回帰テスト用 assertion |
| `tests/fixtures/` | 一時HOME、fake command、共通 fixture |
| `tests/run.sh` | mise 管理の Node.js で `node:test` を実行する入口 |

設定の解析や package/tool の状態確認には、それぞれの公式コマンドを使います。dotfiles 側では lifecycle と symlink の処理だけを管理します。

`setup/context.bash` は managed symlink を種類・source・destination の3要素で宣言します。install、check、uninstall は同じ宣言を参照します。install は最初の preflight に加え、処理計画を作る直前と実行時にも destination を確認します。確認後に別のプロセスが destination を変更しても、未検証の置換へ切り替えません。

mise が PATH にない場合は、`setup/mise-install.sh` が repository に固定した mise version と platform ごとの SHA-256 checksumを照合して、公式 release asset をインストールします。

repository の mise config と lock file を検査するときは、一時ディレクトリに両ファイルをコピーし、呼び出し元の mise 設定から隔離します。check と preflight は stdout と stderr を保持して診断へ使います。`install --apply` は進捗を端末へ直接流します。準備、mise の実行、cleanup の結果は別々に保持し、mise と cleanup が同時に失敗した場合は mise の終了コードを優先しつつ、両方の診断を表示します。

テストはCLI、bootstrap、lifecycle、resource、package、check診断の単位に分けています。CLI テストは依存パッケージを持たない `node:test` で実行し、残る Bash 回帰テストも移行中は同じ runner から実行します。Node.js は mise config と lock file で固定し、`tests/run.sh` が管理版を選択します。

## 管理対象

- `.bashrc`、`.bash_profile`、`.gitconfig`、mise config の symlink
- `Brewfile` に記載した package
- mise lock に記載した tool

symlink は repository 内の source と HOME/XDG 配下の destination を絶対パスで結びます。`.bashrc` は symlink の参照先を辿って repository root を求め、mise config は自身の実体パスから同じ root を求めます。そのため clone 先を設定ファイルへ固定で記録しません。

uninstall は現在の repository を指す symlink だけを削除します。package/tool、backup、既存の state file は削除しません。

## 排他制御と失敗時の扱い

`install --apply` と `uninstall --apply` は `$HOME/.dotfiles-lifecycle.lock` を使い、同じ HOME に対する変更を直列化します。dry-run と check は lock を作成しません。

package manager の処理が途中で失敗しても、dotfiles 側では元に戻しません。原因を解消して install を再実行します。symlink の作成に失敗した場合だけ、直前に作成した backup を戻します。
