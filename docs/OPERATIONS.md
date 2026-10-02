# Operations

## コマンド

| 操作 | dry-run | [--apply](../bin/dotfiles) |
| --- | --- | --- |
| [install](../bin/dotfiles) | デフォルト。インストール内容を表示する | パッケージ、ツール、管理対象のシンボリックリンクを適用する |
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
bin/dotfiles install [--dry-run|--apply] [--skip-brew]
bin/dotfiles verify [--skip-brew]
bin/dotfiles uninstall [--dry-run|--apply]
```

## install

最初に [make install](../Makefile) で内容を確認し、問題がなければ [make install-apply](../Makefile) を実行します。miseの設定、miseのロックファイル、Brewfile を変更した場合も同じ手順で反映します。

mise がインストールされていない場合、apply 時には `curl`、SHA-256チェックサムを照合できるコマンド、ネットワーク接続が必要です。リポジトリに固定したバージョンとチェックサムを使って mise をインストールします。

既存のファイル、別の参照先を指すシンボリックリンク、ディレクトリと競合した場合は停止します。自動的な置換やバックアップは行いません。内容を確認し、競合を手動で解消してからinstallを再実行してください。

Homebrewパッケージをこのライフサイクルの管理対象にしない場合や、Homebrew を利用できない環境で mise と管理対象のシンボリックリンクだけを適用したい場合は [--skip-brew](../bin/dotfiles) を使います。Homebrew の検出、初期導入、Brewfile の適用を省略しますが、mise と管理対象のシンボリックリンクは通常どおり処理します。

```bash
bin/dotfiles install --skip-brew
bin/dotfiles install --skip-brew --apply
```

CIのライフサイクル確認では、Homebrew に依存しないよう環境変数で省略し、Makeターゲットを順に実行します。

管理対象のシンボリックリンクの参照元ファイルだけを変更した場合、install の再実行は不要です。

## verify

[make verify](../Makefile) は Bash、Git、Homebrew、mise、管理対象のシンボリックリンクを確認します。修復やライフサイクルロックの作成は行いません。[make ci](../Makefile) はリポジトリのlintとテストを実行する開発用コマンドです。

miseの設定、ロックファイル、ツールを確認するときは、一時ディレクトリにリポジトリの設定をコピーして検査します。このディレクトリは検査の終了時に削除されます。削除できなかった場合は `verify error:` を表示し、verify は失敗します。

`verify failed:` は設定やインストール状態の不一致、`verify error:` は検査に必要な処理を完了できなかったことを表します。どちらの場合も終了コードは `1` です。

Homebrewパッケージを管理対象にしない場合や Homebrew を利用できない環境では [bin/dotfiles verify --skip-brew](../bin/dotfiles) を使います。この場合、Brewfile に記載した Homebrewパッケージやcaskなどが現在の環境にすべて入っているかの確認を省略します。

## uninstall

最初に [make uninstall](../Makefile) で削除対象を確認し、問題がなければ [make uninstall-apply](../Makefile) を実行します。削除するのはmise Dotfilesが管理する5本です。パッケージとツール、Homebrewとmise本体、miseの状態、以前のバージョンが作成した状態管理ファイルは残します。uninstallにはmiseが必要です。

## ローカル設定と補助操作

個人のGitメールアドレス、署名鍵、認証情報の上書き設定は `~/.gitconfig.local`、端末固有のシェル設定は `~/.bashrc.local` に置きます。

Git Credential Manager はライフサイクルとは別に管理します。

```bash
make gcm
make gcm-apply
```
