# dotfiles

WSL2 を主環境とする Bash 環境用の dotfiles です。mise の開発ツール、Homebrew パッケージ、シェル起動時の設定、Git の共有設定を管理します。

処理の流れと内部構成は [Architecture](docs/ARCHITECTURE.md) を参照してください。

対応環境は Linux/WSL2（x86_64、arm64）です。zsh の起動ファイルは管理しません。

macOS も対応できるように目指しているところです。

## 操作

通常の操作は `install`、`verify`、`uninstall` の3つです。Makefileでも、現在の環境を確認する `verify` 操作を `make verify` で実行します。`make ci` はリポジトリのlintとテストに使います。dry-run が既定で、変更には `--apply` が必要です。

```bash
make install
make install-apply
make verify
make uninstall
make uninstall-apply
```

直接実行する場合は次を使います。

```bash
bin/dotfiles install [--dry-run|--apply] [--skip-brew]
bin/dotfiles verify [--skip-brew]
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
| `install` | パッケージ、ツール、管理対象のシンボリックリンクを揃える | デフォルト。確認結果と実行内容を表示する | 確認の後に変更する |
| `uninstall` | dotfiles が作成した管理対象のシンボリックリンクを削除する | デフォルト。削除対象を表示する | 確認の後に削除する |
| `verify` | パッケージ、ツール、設定、シンボリックリンクが期待どおりか確認する | — | — |

`install` と `uninstall` は、変更する前に対象と競合を確認します。dry-run では確認結果と実行内容を表示し、`--apply` では同じ確認の後に変更を実行します。`verify` は install や uninstall とは別に、現在の状態だけを確認します。

`install --apply` と `uninstall --apply` は対象 HOME ごとのライフサイクルロックを取得して直列化します。既存ファイルと競合した場合は、置き換えずに停止します。内容を確認し、競合を手動で解消してから再実行してください。

install は Homebrew Bundle、mise、管理対象のシンボリックリンクをまとめて適用します。各ツールの設定確認やバージョン確認は、それぞれのコマンドを使います。

## 管理対象

- `~/.bashrc`
- `~/.bash_profile`
- `~/.gitconfig`
- `~/.dotfiles/git/hooks/pre-commit`を参照するグローバルGitフック
- `~/.dotfiles`
- `${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml`
- Brewfile の直接指定項目
- miseのロックファイルに記載された開発ツール

端末固有の Git 設定は `~/.gitconfig.local`、シェル設定は `~/.bashrc.local` に置きます。

Gitの`pre-commit`フックは、ステージ済みファイルをDocker版secretlintで検査します。使用するイメージはフック内でバージョンとdigestを固定しています。`$HOME/.secretlintignore`と、ステージ済みの`.secretlintignore`をこの順に適用します。作業ツリーにしかない`.secretlintignore`の内容は適用しません。リポジトリ固有の実行可能な`.git/hooks/pre-commit`がある場合は、secretlintより先に実行します。Dockerを利用できない場合や検査でsecretを検出した場合、commitは中止されます。意図的にフックを省略する場合は`git commit --no-verify`を使います。端末固有の`~/.gitconfig.local`で`core.hooksPath`を設定するとこのフックを上書きするため、同項目は置かないでください。

### mise本体のバージョン

`mise.toml` の `min_version` は、設定を読み込める最低バージョンと、dotfilesが初期導入する固定バージョンを兼ねます。ローカルとCIが参照するmise本体のバージョンを1か所で管理するため、この2つは意図的に同じ値とします。

mise本体を更新するときは、`min_version` と `mise.env` のプラットフォーム別SHA-256を、同じリリースの値へまとめて更新してください。互換性の下限と初期導入するバージョンを別々に管理する運用は、このリポジトリでは行いません。

## 補助操作とテスト

Git Credential Manager はライフサイクル外の補助操作です。

```bash
make gcm
make gcm-apply
make ci
make lint
make test
```

`make verify` は、パッケージ、ツール、設定、シンボリックリンクが現在の環境で期待どおりか確認します。`make ci` は開発中の変更を検査するコマンドで、`make lint`、`make test` の順に実行します。

`make lint` はシェルスクリプトの構文チェックとBiomeによるJavaScriptの検査、`make test` はNode.jsのテスト一式とmiseを使うシェルの境界テストを実行します。境界テストは実際のmiseを使うため、環境やキャッシュの状態によって時間がかかることがあります。実行には `mise` と、リポジトリのmise設定で固定されたNode.js / Biomeが必要です。必要なツールは次で導入・確認できます。

```bash
./setup/mise-install.sh --apply
mise install
```

Node.jsのテスト一式だけを実行する場合は`tests/run.sh`を使います。miseの境界テストは`tests/integration/mise-isolation.sh`と`tests/integration/dotfiles-lifecycle.sh`から個別に実行できます。Node.jsのテストファイルは機能別に分かれており、必要なファイルだけを`mise exec -- node --test tests/check.test.js`のように単独実行できます。JavaScriptは、リポジトリ直下の`package.json`にある`"type": "module"`によりES Modulesとして扱います。

テストのレイヤーと品質保証の範囲は [テスト戦略](docs/TEST-STRATEGY.md)、その他の詳細は [docs/](./docs/) を参照してください。
