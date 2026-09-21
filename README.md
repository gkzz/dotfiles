# dotfiles

WSL2 を主環境とする Bash 環境用の dotfiles です。mise の開発ツール、Homebrew パッケージ、シェル起動時の設定、Git の共有設定を管理します。

処理の流れと内部構成は [Architecture](docs/ARCHITECTURE.md) を参照してください。

対応環境は Linux/WSL2（x86_64、arm64）です。zsh の起動ファイルは管理しません。

macOS も対応できるように目指しているところです。

## 操作

通常の操作は `install`、`check`、`uninstall` の3つです。dry-run が既定で、変更には `--apply` が必要です。

```bash
make install
make install-apply
make check
make uninstall
make uninstall-apply
```

直接実行する場合は次を使います。

```bash
bin/dotfiles install [--dry-run|--apply] [--force] [--skip-brew]
bin/dotfiles check [--skip-brew]
bin/dotfiles uninstall [--dry-run|--apply]
```

### OS パッケージの更新

WSL の Bash を含む OS パッケージは、このリポジトリでは管理しません。Ubuntu の通常のメンテナンスとして更新してください。

```bash
sudo apt update
sudo apt upgrade
```

`install` と `install-apply` は `apt` や `sudo` を実行しません。

### 操作と確認の関係

| 操作 | 役割 | dry-run | `--apply` |
| --- | --- | --- | --- |
| `install` | package、tool、managed symlink を揃える | デフォルト。確認結果と実行内容を表示する | 確認の後に変更する |
| `uninstall` | dotfiles が作成した managed symlink を削除する | デフォルト。削除対象を表示する | 確認の後に削除する |
| `check` | package、tool、設定、symlink が期待どおりか確認する | — | — |

`install` と `uninstall` は、変更する前に対象と競合を確認します。dry-run では確認結果と実行内容を表示し、`--apply` では同じ確認の後に変更を実行します。`check` は install や uninstall とは別に、現在の状態だけを確認します。

`install --apply` と `uninstall --apply` は対象 HOME ごとの lifecycle lock を取得して直列化します。競合する既存ファイルは通常停止し、`--force` 指定時だけ regular file または symlink を日時付き backup へ移して置き換えます。directory と特殊ファイルは置き換えません。

install は Homebrew Bundle、mise、managed symlink をまとめて適用します。各ツールの設定確認やバージョン確認は、それぞれのコマンドを使います。

## 管理対象

- `~/.bashrc`
- `~/.bash_profile`
- `~/.gitconfig`
- `${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml`
- Brewfile の直接指定項目
- mise lock file に記載された開発ツール

machine-local な Git 設定は `~/.gitconfig.local`、shell 設定は `~/.bashrc.local` に置きます。

### mise本体のバージョン

`.config/mise/config.toml` の `min_version` は、設定を読み込める最低バージョンと、dotfilesがbootstrapする固定バージョンを兼ねます。ローカルとCIが参照するmise本体のバージョンを1か所で管理するため、この2つは意図的に同じ値とします。

mise本体を更新するときは、`min_version` と `.config/mise/mise.env` のプラットフォーム別SHA-256を、同じリリースの値へまとめて更新してください。互換性の下限とbootstrapするバージョンを別々に管理する運用は、このリポジトリでは行いません。

## 補助操作とテスト

Git Credential Manager は lifecycle 外の補助操作です。

```bash
make gcm
make gcm-apply
make validate
```

`make validate` は、シェルスクリプトの構文チェック、BiomeによるJavaScriptの検査、`node:test` によるlifecycleテストを実行します。実行には `mise` と、repository の mise 設定で固定された Node.js / Biome が必要です。必要なツールは次で導入・確認できます。

```bash
./setup/mise-install.sh --apply
mise --cd .config/mise install
```

テストの一括実行入口は `tests/run.sh` です。テストファイルは機能別に分かれており、必要なファイルだけを `mise exec -- node --test ...` で単独実行できます。

詳細は [docs/](./docs/) を参照してください。
