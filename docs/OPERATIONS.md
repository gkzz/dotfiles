# Operations

## コマンド

| 操作 | dry-run | [--apply](../bin/dotfiles) |
| --- | --- | --- |
| [install](../bin/dotfiles) | デフォルト。インストール内容を表示する | package、tool、管理対象のシンボリックリンクを適用する |
| [uninstall](../bin/dotfiles) | デフォルト。削除対象を表示する | 管理対象のシンボリックリンクを削除する |
| [verify](../bin/dotfiles) | 対象外 | 対象外。現在の状態を確認するだけ |

```bash
make install
make install-apply
make verify
make uninstall
make uninstall-apply
```

直接実行する場合は次を使います。

```bash
bin/dotfiles install [--dry-run|--apply] [--force] [--skip-brew]
bin/dotfiles verify [--skip-brew]
bin/dotfiles uninstall [--dry-run|--apply]
```

## install

最初に [make install](../Makefile) で内容を確認し、問題がなければ [make install-apply](../Makefile) を実行します。mise config、mise lock、Brewfile を変更した場合も同じ手順で反映します。

mise がインストールされていない場合、apply 時には `curl`、SHA-256 checksumを照合できるコマンド、ネットワーク接続が必要です。repository に固定した version と checksum を使って mise をインストールします。

既存の通常ファイルまたはシンボリックリンクと競合した場合は停止します。通常ファイルとは、ディレクトリやシンボリックリンクではないファイルです。置き換える場合は [--force --dry-run](../bin/dotfiles) で対象を確認してから [--force --apply](../bin/dotfiles) を実行します。ディレクトリと特殊ファイルは置き換えません。

Homebrew package をこの lifecycle の管理対象にしない場合や、Homebrew を利用できない環境で mise と管理対象のシンボリックリンクだけを適用したい場合は [--skip-brew](../bin/dotfiles) を使います。Homebrew の検出、bootstrap、Brewfile の適用を省略しますが、mise と管理対象のシンボリックリンクは通常どおり処理します。

```bash
bin/dotfiles install --skip-brew
bin/dotfiles install --skip-brew --apply
```

たとえば E2E smoke では、Homebrew に依存せず lifecycle を確認するために [bin/dotfiles install --skip-brew --apply](../bin/dotfiles) を明示的に実行します。

管理対象のシンボリックリンクの参照元ファイルだけを変更した場合、install の再実行は不要です。

## verify

[make verify](../Makefile) は Bash、Git、Homebrew、mise、管理対象のシンボリックリンクを確認します。修復や lifecycle lock の作成は行いません。[make ci](../Makefile) はリポジトリのlintとテストを実行する開発用コマンドです。

mise の config、lock file、tool を確認するときは、一時ディレクトリに repository の設定をコピーして検査します。このディレクトリは検査の終了時に削除されます。削除できなかった場合は `verify error:` を表示し、verify は失敗します。

`verify failed:` は設定やインストール状態の不一致、`verify error:` は検査に必要な処理を完了できなかったことを表します。どちらの場合も終了コードは `1` です。

Homebrew package を管理対象にしない場合や Homebrew を利用できない環境では [bin/dotfiles verify --skip-brew](../bin/dotfiles) を使います。この場合、Brewfile に記載した Homebrew package / cask などが現在の環境にすべて入っているかの確認を省略します。

## uninstall

最初に [make uninstall](../Makefile) で削除対象を確認し、問題がなければ [make uninstall-apply](../Makefile) を実行します。削除するのは、現在のリポジトリを指す管理対象のシンボリックリンクだけです。package/tool、Homebrew/mise 本体、backup、以前のバージョンが作成した状態管理ファイルは残します。

## ローカル設定と補助操作

個人の Git email、署名鍵、credential override は `~/.gitconfig.local`、端末固有の shell 設定は `~/.bashrc.local` に置きます。

Git Credential Manager は lifecycle とは別に管理します。

```bash
make gcm
make gcm-apply
```
