# Troubleshooting

## Apply Failures

```bash
make install
make verify
```

mise の出力で失敗した対象を確認します。途中で失敗した場合、それまでの変更は残ります。
原因を解消したら `make install` の dry-run を確認し、`make install-apply` を再実行してください。

| 診断された対象 | 対応 |
| --- | --- |
| 既存ファイルや古いリンクとの競合 | 内容と参照先を確認し、必要な内容を保存して個別に解消。一括置換に `--force` は使わない |
| ツールやパッケージの不足 | mise の診断に従って不足を解消 |

## Setup Failures

`make setup` は Homebrew、Git、ネットワークを使います。まず Homebrew や Git のエラーを解消してください。このコマンドは実行元が Git checkout であることを確認します。別のリポジトリから実行した場合は、dotfiles の checkout に移動して `make setup` を実行してください。

mise が見つからない場合、`make setup` は `setup/mise-install.sh` を使って固定バージョンを checksum 検証付きで導入します。手動導入やバージョン確認は[使い方](USAGE.md#mise-installation-and-version-checks)を参照してください。既存の mise が古い場合は `mise version` を確認し、リポジトリの `min_version` 以上へ更新してください。

## Pre-commit Hook Failures

Git の `pre-commit` hook は、ステージ済みの内容を Docker 版 secretlint で検査します。イメージのバージョンと digest は hook 内で固定しています。検査には `$HOME/.secretlintignore` とステージ済みの `.secretlintignore` を適用します。Docker を利用できない場合や secret が検出された場合、commit は中止されます。

Docker が利用できる状態か確認してください。検査を意図的に省略する場合は `git commit --no-verify` を使います。

## Moving the Repository

dotfile は bootstrap に使った checkout を参照します。checkout を別の場所へ移した場合は、新しい場所から `make install-apply` を再実行してください。
