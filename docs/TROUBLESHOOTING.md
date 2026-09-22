# Troubleshooting

## 最初に確認する

```bash
make install
make verify
make check
```

install の dry-run でエラーを解消してから [make install-apply](../Makefile) を実行してください。

## lifecycle lock を取得できない

同じ HOME に対する install / uninstall が実行中です。PID は次のコマンドで確認できます。

```bash
cat "$HOME/.dotfiles-lifecycle.lock/pid"
```

実行中の処理が終わってから再実行してください。記録された PID が終了済みなら、次回の apply が lock を回収します。不正な PID の lock は自動で削除しません。dotfiles が動いていないことを確認してから、lock directory を別名へ退避してください。

## symlink が競合する

```bash
bin/dotfiles install --dry-run
bin/dotfiles install --force --dry-run
bin/dotfiles install --force --apply
```

[--force](../bin/dotfiles) は通常ファイルとシンボリックリンクを日時付きbackupへ移してから置き換えます。ディレクトリと特殊ファイルは置き換えません。backupは自動復元・削除しません。

## mise が見つからない、または古い

```bash
bin/dotfiles install --dry-run
mise version
```

mise がなければ、install は [リポジトリで指定したバージョンのmise実行ファイル](../setup/mise-install.sh) をダウンロードし、SHA-256 checksumを照合してインストールします。既存 mise は自動更新しません。`curl`、SHA-256 checksumの照合、ネットワーク、version、config、lock に関する mise のエラーを確認し、必要なら対応版をインストールしてください。

## Homebrew が利用できない

Homebrew がなければ、install は [公式インストールスクリプトを呼び出す処理](../setup/homebrew-install.sh) の実行を予定します。OS、Command Line Tools、compiler、権限に関するエラーは [インストールスクリプト](../setup/homebrew-install.sh) の出力を確認してください。

Homebrew を使わない場合は [--skip-brew](../bin/dotfiles) を指定します。

## verify が失敗する

出力の先頭で、状態の不一致と検査処理のエラーを区別できます。

- `verify failed:`: 検査は完了したものの、設定やインストール状態が期待と異なります。
- `verify error:`: 必須コマンドの不足やコマンドの異常終了により、検査を完了できませんでした。続けて表示される元のエラーも確認してください。

管理対象のシンボリックリンクのエラーに表示される `expected` は期待する参照先、`actual` は現在の参照先です。`actual` が異なる場合も、verify はシンボリックリンクを張り替えません。

各項目を個別に確認します。

```bash
bash -n .bashrc .bash_profile
git config --no-includes --file .gitconfig --list
brew bundle check --no-upgrade --file Brewfile
bin/dotfiles verify --skip-brew
```

## repository を移動した

既存 symlink は新しい repository を自動参照しません。新しい repository で install の dry-run を実行し、競合する symlink を確認してください。以前のbackupや、以前のバージョンが作成した状態管理ファイルは自動で探索・削除しません。

## 調査情報を保存する

```bash
bin/dotfiles install --dry-run
bin/dotfiles verify --skip-brew
uname -a
bash --version | head -n 1
```

credential、email、署名鍵、token、`~/.gitconfig.local` の内容は共有しないでください。
