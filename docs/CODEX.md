# Codex の設定

## コードレビュー用スキル

`code-review` は `mise.toml` で管理し、既存の `make install` → `make install-apply` で
`~/.agents/skills/code-review` へリンクします。適用後に Codex を起動し直し、任意のリポジトリで呼び出します。

```text
$code-review
$code-review ステージ済みの変更
$code-review 未ステージの変更
$code-review origin/main をベースとする変更
$code-review abc123 と def456 のコミット間
$code-review src/auth/
```

対象省略時は、ステージ済み・未ステージを区別して未追跡を含むローカル変更全体を確認します。
ローカル変更がなければ、取得済みの `origin/HEAD` が示すブランチとの分岐点からレビューします。
自動 fetch はせず、比較先を特定できない場合は質問します。
パスだけを指定した場合は、その範囲のコード全体を対象にします。

指摘は日本語とし、根拠、発生条件・影響、修正案を添えて P0〜P3 の順に報告します。
レビュー対象コードは原則変更せず、最後に要約とテストの実行結果・未確認事項を示します。
詳しい手順と出典は [SKILL.md](../.agents/skills/code-review/SKILL.md) を参照してください。

`code-review` は、[code-analysis](../.agents/subagents/code-analysis.toml) サブエージェント1つへ
差分・既存実装・呼び出し経路・影響範囲・関連テストの調査を委譲します。
定義の正本は `.agents/subagents/` に置き、同じ適用手順で `~/.codex/agents/code-analysis.toml` にコピーします。
Codex は起動時に定義ファイルのシンボリックリンクを拒否するため、通常ファイルとして配置します。
定義を更新したときは、再度適用してください。
以前の設定でリンクを配置済みの場合も、再度適用すると通常ファイルに置き換わります。
`code-analysis` はスキルとして直接呼び出すものではありません。
まとまった追加調査は同じエージェントへ再依頼し、局所的な確認は親が行います。

調査側はファイルを変更せず、テストも実行しません。不具合の確定や重要度の分類は親に任せます。
親が調査結果を独立して検証し、テスト実行と最終レビューを担当します。
判定に影響する仕様・意図が調査で解消できない場合は、親が `grill-me` で一問ずつ確認します。
回答を得るまで、その論点に依存する仮説や指摘へ進めません。
委譲が利用できない場合や完了しない場合は、親が調査を引き継ぎます。

読み取り専用はエージェントへの指示であり、権限による隔離ではありません。
サブエージェントは親のサンドボックス設定を引き継ぎます。
カスタムエージェントの仕様は [Codex の公式ドキュメント](https://learn.chatgpt.com/docs/agent-configuration/subagents)を参照してください。

## 共通の権限設定

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
