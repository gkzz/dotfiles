# Troubleshooting

## 最初に確認する

```bash
make install
make check
make validate
```

install の dry-run でエラーを解消してから `make install-apply` を実行してください。

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

`--force` は regular file と symlink を日時付き backup へ移してから置き換えます。directory と特殊ファイルは置き換えません。backup は自動復元・削除しません。

## mise が見つからない、または古い

```bash
bin/dotfiles install --dry-run
mise version
```

mise がなければ、install は repository に固定した mise release asset の SHA-256 checksumを照合してインストールします。既存 mise は自動更新しません。`curl`、SHA-256 checksumの照合、ネットワーク、version、config、lock に関する mise のエラーを確認し、必要なら対応版をインストールしてください。

## Homebrew が利用できない

Homebrew がなければ、install は公式 installer の実行を予定します。OS、Command Line Tools、compiler、権限に関するエラーは installer の出力を確認してください。

Homebrew を使わない場合は `--skip-brew` を指定します。

## check が失敗する

各項目を個別に確認します。

```bash
bash -n .bashrc .bash_profile
git config --no-includes --file .gitconfig --list
brew bundle check --no-upgrade --file Brewfile
bin/dotfiles check --skip-brew
```

## repository を移動した

既存 symlink は新しい repository を自動参照しません。新しい repository で install の dry-run を実行し、競合する symlink を確認してください。旧 backup や state file は自動で探索・削除しません。

## 調査情報を保存する

```bash
bin/dotfiles install --dry-run
bin/dotfiles check --skip-brew
uname -a
bash --version | head -n 1
```

credential、email、署名鍵、token、`~/.gitconfig.local` の内容は共有しないでください。
