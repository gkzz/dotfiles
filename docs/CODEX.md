# Codex の設定

共通の権限設定は `.config/codex/shared.toml` で管理します。
mise の `merge = true` で、`~/.codex/config.toml` の次の2項目を適用時に上書きします。
モデル、MCP、プロジェクトの信頼設定など、他の項目は保持します。

```toml
sandbox_mode = "workspace-write"
approval_policy = "on-request"
```

適用先は Git 管理外の通常ファイルです。CLI と IDE は同じユーザー設定を使います。
モデルや通知など、利用してから共有範囲を判断したい設定は、各端末のファイルで管理します。

端末ごとの設定は[設定例](../.config/codex/local.config.toml.example)、コマンドの承認ルールは[ルール例](../.config/codex/local.rules.example)を参照してください。

## バックアップと適用

Codex を終了し、リポジトリのルートで実行します。
既存の `~/.codex/config.toml` が通常ファイルなら、最初に退避します。
ファイルがない新規環境では、バックアップは不要です。
`date +%Y%m%dT%H%M%S` で年月日・時分秒を付けた退避ディレクトリを作成します。

```bash
if [ -f "$HOME/.codex/config.toml" ]; then
  backup="$HOME/.local/state/dotfiles/backups/codex/$(date +%Y%m%dT%H%M%S)"
  install -d -m 700 "$backup"
  cp -p "$HOME/.codex/config.toml" "$backup/config.toml"
  chmod 600 "$backup/config.toml"
fi
```

差分を確認してから適用します。端末の設定を含む差分は公開しないでください。

```bash
mise dot diff ~/.codex/config.toml/shared
mise dot apply ~/.codex/config.toml/shared --dry-run --verbose
mise dot apply ~/.codex/config.toml/shared --yes
mise dot status
```

`make install-apply` でも反映されます。新規作成時の権限は `0600` です。
既存ファイルの権限は変わりません。
別の `CODEX_HOME` を使う場合は、`mise.toml` の適用先も変更してください。

これは適用時のマージであり、常時強制するポリシーではありません。
Codex が共有キーを変更した場合は、次の適用で共通設定に戻ります。
ソースからキーを削除しても、適用先には残ります。
`make uninstall-apply` でもマージした設定は削除されません。
末尾の `/shared` は編集ルールの ID で、実際のファイルは `~/.codex/config.toml` です。
仕組みの詳細は [mise の公式ドキュメント](https://mise.jdx.dev/dotfiles/edits.html)を参照してください。

## 退避した設定に戻す

Codex を終了し、バックアップ時に設定した `backup` 変数で退避ディレクトリを参照します。
別のシェルで復元する場合は、`backup` に既存の退避ディレクトリのパスを設定してください。
`config.toml` が通常ファイルであることを確認してから戻してください。

```bash
cp "$backup/config.toml" "$HOME/.codex/config.toml"
chmod 600 "$HOME/.codex/config.toml"
```

共通の権限設定を今後も適用したくない場合は、mise のマージルールも外します。
変更後は Codex を起動し直し、`/status` で権限設定を確認してください。
認証情報、端末固有のパスや信頼設定、履歴は公開リポジトリにコミットしないでください。
