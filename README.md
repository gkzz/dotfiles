# dotfiles

[![Lint](https://github.com/gkzz/dotfiles/actions/workflows/lint.yml/badge.svg)](https://github.com/gkzz/dotfiles/actions/workflows/lint.yml)
[![Test](https://github.com/gkzz/dotfiles/actions/workflows/test.yml/badge.svg)](https://github.com/gkzz/dotfiles/actions/workflows/test.yml)

WSL2 を主な利用環境とする Bash 用の dotfiles です。[mise bootstrap](https://mise.jdx.dev/bootstrap.html) を使い、シェル設定、Git 設定、Homebrew パッケージ、開発ツールを管理します。

対応環境は Linux/WSL2（x86_64、arm64）です。macOS（Apple Silicon / arm64）は対応中です。Intel Mac はサポート対象外です。Bash の設定を管理し、zsh の起動ファイルは管理しません。

## 初回導入

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

## 通常操作

管理対象は `mise.toml`、操作のタスクは `mise-operations.toml` に定義し、Makefile から呼び出します。mise 導入前の `setup` だけは Makefile から直接実行します。

```bash
make install         # 適用内容を確認（dry-run）
make install-apply   # 適用
make verify          # bootstrap 全体の状態を確認
make verify-dotfiles # dotfile の状態を確認
```

bootstrap は宣言された処理を順に進めます。競合などで途中に失敗した場合は mise の診断を確認し、対象を個別に解消してから dry-run と適用をやり直してください。失敗前に完了した処理は残ります。同じ HOME への適用・解除は同時に実行しないでください。

## 解除

```bash
make uninstall       # 解除内容を確認（dry-run）
make uninstall-apply # dotfile のリンクを解除
```

解除対象は mise が管理する dotfile のリンクです。Homebrew、mise 本体、リポジトリ、パッケージ、開発ツールは残ります。

## 管理対象と端末固有の設定

- `.bashrc`、`.bash_profile`、`.gitconfig`
- `~/.dotfiles`（実際の checkout へのリンク。Git フックはこのリンク経由で参照）
- `~/.config/mise/config.toml`（リポジトリルートの `mise.toml` へのリンク）
- `~/.agents/skills/` のリポジトリ管理スキル（Codex もこの場所から読み込みます）
- mise の `[bootstrap.packages]` に宣言した Homebrew パッケージ
- `mise.lock` に記録した開発ツール

`renodash-dashboard` スキルは、[renodash のサンプル（7b956e9）](https://github.com/gkzz/renodash/blob/7b956e97cf2ca9d8818936a18ffdfa257f1738e8/examples/skills/renodash-dashboard/SKILL.md)を正本とします。dotfiles には配布用のコピーを置き、更新時に正本と照合します。mise はそのコピーを `~/.agents/skills/renodash-dashboard` にリンクします。renodash リポジトリを clone する必要はありません。

mise のグローバル設定先は `~/.config/mise/config.toml` です。独自の `XDG_CONFIG_HOME` はサポートしません。既存環境からの移行は[使い方](docs/USAGE.md#既存環境からの移行)を参照してください。端末固有の Git 設定は `~/.gitconfig.local`、シェル設定は `~/.bashrc.local` に置きます。

Git の `pre-commit` hook は、ステージ済みの内容を Docker 版 secretlint で検査します。イメージのバージョンと digest は hook 内で固定しています。検査には `$HOME/.secretlintignore` とステージ済みの `.secretlintignore` を適用します。Docker を利用できない場合や secret が検出された場合、commit は中止されます。

HTTPS での Git 認証には、端末ごとに Git Credential Manager を導入します。Windows（WSL2）と macOS の手順は [GCM の設定](docs/GIT-CREDENTIAL-MANAGER.md)を参照してください。

## ドキュメント

導入・適用の詳細は[使い方](docs/USAGE.md)、目的別の案内は[ドキュメント一覧](docs/README.md)を参照してください。
