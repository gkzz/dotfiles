# Usage

## Getting Started

macOS で Git と make を利用できない場合は、先に Command Line Tools を導入してください。

```bash
xcode-select --install
```

macOS の Homebrew は `/opt/homebrew` を利用します。macOS で Homebrew を初めて導入する場合は、ターミナルで `sudo -v` を実行してから次の手順へ進んでください。

リポジトリを任意の場所に clone し、ルートで準備、適用内容の確認、適用、状態確認の順に進めます。

```bash
git clone https://github.com/gkzz/dotfiles.git
cd dotfiles
make setup
make install       # 適用内容を確認（dry-run）
make install-apply # 適用
make verify        # 状態を確認
```

macOS の標準シェルが zsh でも make の各コマンドは実行できます。適用したシェル設定を利用するときは、ターミナルで `/bin/bash -l` を起動してください。

Homebrew のインストール時に OS や権限の確認を求められる場合があります。

## Migration

既存の設定やリンクを確認してから適用します。

| 対象 | 対応 |
| --- | --- |
| 独自の `XDG_CONFIG_HOME` | 下記の手順で既定の設定先へ移行 |
| `~/.dotfiles` | 同じ checkout へのリンクなら継続利用。別の checkout なら内容と参照先を確認して手動で解除 |
| `~/.agents/skills/` の管理対象スキル | 実ディレクトリや別のリンクがあれば、内容と参照先を確認して退避 |

独自の `XDG_CONFIG_HOME` を使っている場合は、次の順に移行してください。

1. 旧設定内の必要な内容を保存し、旧設定先の管理リンクを手動で解除します。
2. シェル起動ファイルや `~/.bashrc.local` を確認し、`XDG_CONFIG_HOME` の独自指定を外します。
3. 新しいシェルで適用します。mise の設定先は[管理対象](ARCHITECTURE.md#managed-files-and-tools)を参照してください。

## Local Settings

端末固有の Git 設定は `~/.gitconfig.local`、シェル設定は `~/.bashrc.local` に置きます。
Codex は[設定ガイド](CODEX.md)、HTTPS での Git 認証は [GCM の設定](GIT-CREDENTIAL-MANAGER.md)を参照してください。

## Apply and Verify

リポジトリルートから Makefile の target を実行します。`setup` 以外は `mise-operations.toml` に定義したタスクを呼ぶラッパーです。たとえば `make install` は `MISE_CONFIG_FILE="$PWD/mise-operations.toml" mise run dotfiles:install` を実行します。

```bash
make install         # 適用内容を確認（dry-run）
make install-apply   # 適用
make verify          # bootstrap 全体の状態を確認
make verify-dotfiles # dotfile の状態を確認
```

適用前に dry-run の出力を確認してください。bootstrap は宣言されたパッケージ、dotfile、ツールを順に適用します。失敗時の対応は[トラブルシューティング](TROUBLESHOOTING.md#apply-failures)を参照してください。同じ HOME への適用・解除は同時に実行しないでください。

## Uninstall

```bash
make uninstall       # 解除内容を確認
make uninstall-apply # 解除
```

| 解除するもの | 残るもの |
| --- | --- |
| 管理対象の dotfile のリンク、コピーしたサブエージェント定義 | Homebrew、mise 本体、リポジトリ、パッケージ、開発ツール、Codex にマージした設定 |

変更されたファイルなど mise が識別できない対象は、診断に従って個別に対応してください。
インストール前の状態へ戻す処理はありません。`setup` で準備した環境の削除は、利用状況に応じて判断してください。
Codex の設定を戻す場合は[バックアップからの復元](CODEX.md#restore-from-backup)を参照してください。

## mise Installation and Version Checks

`make setup` は mise が見つからない場合、固定バージョンを導入します。手動で導入する場合は次を実行してください。

```bash
./setup/mise-install.sh --dry-run
./setup/mise-install.sh --apply
```

導入するバージョンは `mise.toml` の `min_version` から取得します。OS と CPU に応じた SHA-256 checksum を検証します。リポジトリが指定する導入バージョンと、現在使用している mise は次のコマンドで確認できます。

```bash
./setup/mise-version.sh
type -a mise
mise version
```

mise 本体は Renovate が `min_version` と `mise.env` の3環境分の SHA-256 checksum を同じ PR で更新します。共有設定の公開後14日間の待機期間と Dependency Dashboard での事前承認が適用されます。手動で更新する場合も、`min_version`、各 checksum、その直前のバージョンコメントを合わせて更新してください。

### Updating mise

`min_version` は mise の最低要求バージョンです。このリポジトリでは、初回導入と本体更新のバージョン指定にも使います。

更新 PR をチェックアウトしたら、リポジトリルートで次を実行してください。このリポジトリのセットアップで導入した mise が対象です。

```bash
mise self-update --no-plugins "$(./setup/mise-version.sh)"
mise version
mise install --locked
make ci
```

`mise version` の出力が `./setup/mise-version.sh` の指定と一致することを確認します。`mise install --locked` は `mise.lock` に固定された開発ツールを導入し、`make ci` は lint とテストを実行します。

[`mise self-update`](https://mise.jdx.dev/cli/self-update.html) は mise 本体を更新します。`--no-plugins` を付けると、プラグインは更新しません。Homebrew などのパッケージマネージャーで導入した mise は、そのパッケージマネージャーで更新してください。

`make setup` は既にインストール済みの mise を更新しません。`./setup/mise-install.sh --apply` も初回導入用で、インストール先にファイルが存在するとエラーになります。また、`mise upgrade` は管理対象ツールの更新用であり、mise 本体の更新には使いません。

## Dependency Vulnerability Checks

[Lint ワークフロー](../.github/workflows/lint.yml)は、main への push、pull request、手動実行時に、独立したジョブで `pnpm audit` を実行します。
textlint 用の開発依存も含め、重大度による絞り込みや例外を指定せず、既定の失敗条件に該当する脆弱性があればジョブを失敗させます。
この検査は `make lint` と `make ci` には含まれません。

ローカルでは、リポジトリルートで次のコマンドを実行します。

```bash
mise install --locked node pnpm
mise exec -- pnpm install --frozen-lockfile
mise exec -- pnpm audit
```

検査には脆弱性データベースへのネットワーク接続が必要です。検出内容を確認してから、依存パッケージの更新や例外の必要性を判断してください。
Bash には依存パッケージの定義がなく、Go・Python のモジュールや依存ファイルもないため、これらの依存検査は追加していません。

## GitHub Actions Dependency Updates

[共有プリセット](../renovate.json5)を使い、Action の依存関係を `.github/workflows/actions.lock` に記録します。
導入・手動更新・検証の共通手順は、[共有ガイド](https://github.com/gkzz/renovate-config/blob/main/docs/actions-lock.md)を参照してください。

- 最初の Renovate による Action 更新 PR では、ロックファイルも更新され、検証に成功していることをマージ前に確認します。
- ワークフローとロックファイルに記録されたコミットの差分を合わせて確認します。
- [検証ワークフロー](../.github/workflows/verify-lockfile.yml)は、main への push、pull request、手動実行時にロックファイルの整合性と依存先を検証します。
- 共通 Action の参照には `$/` を使い、内部の `actions/cache` もロック対象にしています。

## Development Commands

初回と依存関係の更新後は、固定したツールとパッケージを導入します。

```bash
mise install --locked node pnpm
mise exec -- pnpm install --frozen-lockfile
```

文章の検査・自動修正は[日本語の執筆ガイド](writing.ja.md#linting-with-textlint)、lint とテストの実行方法・確認範囲は[テスト](TESTING.md)を参照してください。

タスクは checkout のルートで実行されます。`MISE_BOOTSTRAP_ARGS` は導入タスクへ渡せます（例：`make install MISE_BOOTSTRAP_ARGS="--only dotfiles"`）。

操作用設定を指定すれば、Makefile を使わずにタスクを直接実行できます。

```bash
MISE_CONFIG_FILE="$PWD/mise-operations.toml" mise run dotfiles:install
```

`mise-operations.toml` では `task.run_auto_install = false` にしているため、直接呼んでもタスク実行前にツールを自動導入しません。管理対象の `mise.toml` は引き続きグローバル設定へリンクしますが、操作用設定はリンクせず、ほかのプロジェクトのタスクには影響させません。従来のグローバルタスク呼び出しは、上記の操作用設定の指定に切り替えてください。
