# トラブルシューティング

## 適用に失敗する

```bash
make install
make verify
```

mise の出力を確認し、競合や不足を解消してください。bootstrap は全対象を一括で事前検査しないため、先に処理した項目が適用されてから後続の処理が失敗することがあります。原因を解消したら dry-run で確認し、再実行してください。

## 初回導入に失敗する

`make setup` は Homebrew、Git、ネットワークを使います。まず Homebrew や Git のエラーを解消してください。このコマンドは実行元が Git checkout であることを確認します。別のリポジトリから実行した場合は、dotfiles の checkout に移動して `make setup` を実行してください。

mise が見つからない場合、`make setup` は `setup/mise-install.sh` を使って固定バージョンを checksum 検証付きで導入します。手動導入やバージョン確認は[運用手順](OPERATIONS.md#mise-の導入とバージョン確認)を参照してください。既存の mise が古い場合は `mise version` を確認し、リポジトリの `min_version` 以上へ更新してください。

## pre-commit hook が失敗する

hook は Docker で固定バージョンの secretlint を実行します。Docker が利用できる状態か確認してください。検査を意図的に省略する場合は `git commit --no-verify` を使います。

## dotfile のリンクが競合する

```bash
make install
make verify
```

既存ファイルや古いリンクの参照先を確認し、必要な内容を保存したうえで個別に解消します。部分適用の後に失敗した場合も、現在の状態を確認してから再実行してください。一括置換に `--force` は使いません。

## 状態を確認する

```bash
make verify
```

mise のグローバル設定リンクは `~/.config/mise/config.toml` に作成されます。リンク先の決定に `XDG_CONFIG_HOME` は使いません。

## リポジトリを移動した

dotfile は bootstrap に使った checkout を参照します。checkout を別の場所へ移した場合は、新しい場所から `make install-apply` を再実行してください。

## dotfile を解除する

```bash
make uninstall       # dry-run
make uninstall-apply # 解除
```

解除対象は mise が管理する dotfile のリンクです。Homebrew、mise 本体、clone したリポジトリ、パッケージ、開発ツールは残ります。変更されたリンク先など mise が安全に解除できない対象は、表示された内容を確認して個別に対応してください。
