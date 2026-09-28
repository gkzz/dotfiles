# Troubleshooting

## 最初に確認する

```bash
make install
make verify
make ci
```

install の dry-run でエラーを解消してから [make install-apply](../Makefile) を実行してください。

## ライフサイクルロックを取得できない

同じ HOME に対する install / uninstall が実行中です。PID は次のコマンドで確認できます。

```bash
cat "$HOME/.dotfiles-lifecycle.lock/pid"
```

実行中の処理が終わってから再実行してください。記録された PID が終了済みなら、次回の apply がロックを回収します。不正な PID のロックは自動で削除しません。dotfiles が動いていないことを確認してから、ロック用ディレクトリを別名へ退避してください。

## シンボリックリンクが競合する

```bash
bin/dotfiles install --dry-run
```

競合する配置先の内容と参照先を確認し、必要なデータを手動で退避してから競合を解消してください。`--force`はサポートしていません。

## mise が見つからない、または古い

```bash
bin/dotfiles install --dry-run
mise version
```

mise がなければ、install は [リポジトリで指定したバージョンのmise実行ファイル](../setup/mise-install.sh) をダウンロードし、SHA-256チェックサムを照合してインストールします。既存 mise は自動更新しません。`curl`、SHA-256チェックサムの照合、ネットワーク、バージョン、設定、ロックに関する mise のエラーを確認し、必要なら対応版をインストールしてください。

## Homebrew が利用できない

Homebrew がなければ、install は [公式インストールスクリプトを呼び出す処理](../setup/homebrew-install.sh) の実行を予定します。OS、Command Line Tools、コンパイラー、権限に関するエラーは [インストールスクリプト](../setup/homebrew-install.sh) の出力を確認してください。

Homebrew を使わない場合は [--skip-brew](../bin/dotfiles) を指定します。

## verify が失敗する

出力の先頭で、状態の不一致と検査処理のエラーを区別できます。

- `verify failed:`: 検査は完了したものの、設定やインストール状態が期待と異なります。
- `verify error:`: 必須コマンドの不足やコマンドの異常終了により、検査を完了できませんでした。続けて表示される元のエラーも確認してください。

dotfilesの状態はmiseの`bootstrap dotfiles status --missing`で確認します。verifyは不一致を報告するだけで、シンボリックリンクを張り替えません。

各項目を個別に確認します。

```bash
bash -n .bashrc .bash_profile
git config --no-includes --file .gitconfig --list
brew bundle check --no-upgrade --file Brewfile
bin/dotfiles verify --skip-brew
```

## リポジトリを移動した

`~/.dotfiles`は新しいリポジトリを自動参照しません。参照先を確認して手動で削除した後、新しいリポジトリからinstallを再実行してください。以前のバージョンが作成したバックアップや状態管理ファイルは自動で探索・削除しません。

## 調査情報を保存する

```bash
bin/dotfiles install --dry-run
bin/dotfiles verify --skip-brew
uname -a
bash --version | head -n 1
```

認証情報、メールアドレス、署名鍵、トークン、`~/.gitconfig.local` の内容は共有しないでください。
