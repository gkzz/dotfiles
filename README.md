# dotfiles

[![Lint](https://github.com/gkzz/dotfiles/actions/workflows/lint.yml/badge.svg)](https://github.com/gkzz/dotfiles/actions/workflows/lint.yml)
[![Test](https://github.com/gkzz/dotfiles/actions/workflows/test.yml/badge.svg)](https://github.com/gkzz/dotfiles/actions/workflows/test.yml)

WSL2 を主な利用環境とする Bash 用の dotfiles です。[mise bootstrap](https://mise.jdx.dev/bootstrap.html) を使い、シェル設定、Git 設定、Homebrew パッケージ、開発ツールを管理します。

対応環境は Linux/WSL2（x86_64、arm64）です。macOS（Apple Silicon / arm64）は対応中です。Intel Mac はサポート対象外です。Bash の設定を管理し、zsh の起動ファイルは管理しません。

## Getting Started

[初回導入](docs/USAGE.md#getting-started)に従って、OS ごとの準備と適用を進めてください。

## Usage

日常の操作は[適用と状態確認](docs/USAGE.md#apply-and-verify)、取り外す場合は[解除](docs/USAGE.md#uninstall)を参照してください。
既存環境には[移行手順](docs/USAGE.md#migration)があります。

## Managed Files and Local Settings

[管理対象](docs/ARCHITECTURE.md#managed-files-and-tools)と[端末固有の設定](docs/USAGE.md#local-settings)を参照してください。

## Docs

目的別のガイドは[ドキュメント一覧](docs/README.md)から参照できます。
スキルの追加・更新時は [Agent Skills の管理方針](docs/SKILLS.md)に従ってください。
