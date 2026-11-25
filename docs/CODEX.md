# Codex Configuration

## Code Review Skill

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

| 指定 | レビュー対象 |
| --- | --- |
| 省略（ローカル変更あり） | ステージ済み・未ステージを区別し、未追跡も含む変更全体 |
| 省略（ローカル変更なし） | 取得済みの `origin/HEAD` が示すブランチとの分岐点からの変更 |
| パスのみ | 指定範囲のコード全体 |

自動 fetch はせず、比較先を特定できない場合は質問します。

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

## Shared Configuration

標準の `~/.codex` を使い、設定を次のように分けます。

| 正本 | 配置先 | 適用方法 |
| --- | --- | --- |
| `.config/codex/shared.toml` | `~/.codex/config.toml` | `merge = true` |
| `.config/codex/defaults.toml` | 同上 | `merge = "missing"` |
| `.config/codex/shared.rules` | `~/.codex/rules/shared.rules` | `mode = "copy"` |
| `.agents/subagents/code-analysis.toml` | `~/.codex/agents/code-analysis.toml` | `mode = "copy"` |

`shared.toml` は次の共通設定を、適用のたびに上書きします。

```toml
sandbox_mode = "workspace-write"
approval_policy = "on-request"
approvals_reviewer = "user"
```

承認は本人が行います。これは適用時の設定統一であり、管理者ポリシーによる強制ではありません。
CLI 引数や、優先順位の高い設定による変更は禁止しません。

`defaults.toml` は `model = "gpt-6.1-sol"` と `model_reasoning_effort = "low"` を補完します。
既存の値は上書きしないため、`/model` や端末の設定ファイルで変更した値は保持されます。
初回限定ではなく、キーを削除すると次回の適用で初期値に戻ります。
ソース側からキーを削除しても、マージ済みのキーは適用先に残ります。
MCP、プロジェクト信頼設定、その他の管理対象外のキーは保持します。認証ファイルは管理しません。

Codex 0.171.0 の[モデル一覧](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/models-manager/models.json)で、
このモデルと `low` の対応を確認しています。認証先やアカウントでの利用可否は別途確認してください。
サブエージェント定義にはモデルや effort を指定せず、親からの継承を基本とします。
`low` で調査に不足があれば、親側の effort を変更して再調査します。品質の評価や追加の機能制限は今回加えていません。

端末固有設定は[設定例](../.config/codex/local.config.toml.example)を参考に、`~/.codex/config.toml` を編集します。
example 自体は読み込まれません。`file_opener` は端末側で設定し、VS Code なら `"vscode"` を指定します。
有効な設定値は[公式設定リファレンス](https://learn.chatgpt.com/docs/config-file/config-reference)を参照してください。

## Command Approval Rules

`shared.rules` はリポジトリを正本とします。コピー先の直接編集は、次の適用で上書きされます。
端末固有の `local.rules` と、Codex が承認時に更新する `default.rules` は mise で管理しません。
[端末用のルール例](../.config/codex/local.rules.example)には GitHub の閲覧・検索用 allow を残しています。
これらはサンドボックス外での実行を許可するため、読み取り専用のサブコマンドに限定しています。
`gh api` 全体の許可は、更新操作も含むため追加していません。
既存 PC の local.rules に共通ルールが残っていても、自動削除は行いません。

サンドボックスはファイルやネットワークへのアクセスを制限し、ルールはコマンドの承認を判定します。
Codex 0.171.0 の[実装](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/core/src/exec_policy.rs)では、
一致する `prompt` ルールはサンドボックス内の操作にも承認を要求します。
`approvals_reviewer = "user"` は承認先を指定する設定であり、すべての操作を承認対象にはしません。
複数ルールの一致では `forbidden > prompt > allow` の順に制限の強い判定が優先されます。
既存の allow より prompt が優先されます。

ルールは引数の接頭辞に一致します。今回の対象は通常の `git push/rebase/reset/clean/restore`、
`git checkout --`、先頭の削除オプションを指定する `git branch`、`git stash drop/clear`、`rm` です。
`rm` は後続のオプションや順序に依存しません。次の表記や間接実行には限界があります。

- `git -C repo reset --hard` など、サブコマンド前のグローバルオプション
- `git branch --force --delete topic` や `git checkout HEAD -- file` など、異なる引数位置
- alias、スクリプト、別の削除コマンド、API やファイル編集ツールによる同等の操作
- 絶対パスの実行ファイル名。解決設定や `host_executable()` 定義によって一致が変わる

実行時には単純な shell wrapper のコマンド列を分解して評価しますが、変数展開や制御構文などは分解されない場合があります。
ルールはサンドボックスを補完するもので、完全なセキュリティ境界ではありません。
詳しくは[公式ルール仕様](https://learn.chatgpt.com/docs/agent-configuration/rules)を参照してください。

判定だけを確認するには次を使います。破壊的コマンド自体は実行しません。

```bash
codex execpolicy check --pretty --rules .config/codex/shared.rules -- git reset --hard HEAD
codex execpolicy check --pretty --rules .config/codex/shared.rules -- rm -rf directory
```

このコマンドは構文と判定の検証であり、実行時の承認 UI の検証ではありません。
直接渡した shell wrapper は実行時と同じように分解されるとは限りません。

## Backup and Apply

既存 PC はリポジトリを更新し、Codex を終了してから適用します。
Codex が設定を書き込んでいる最中の適用は避けてください。
初回導入は [導入手順](USAGE.md#getting-started)で必要なツールを準備します。
標準と異なる `CODEX_HOME` を指定しても、mise の配置先は `~/.codex` のままです。
このリポジトリでは標準の配置先を基本とします。

既存設定は必要に応じて手動でバックアップします。新規 PC では不要です。

```bash
if [ -f "$HOME/.codex/config.toml" ]; then
  backup="$HOME/.local/state/dotfiles/backups/codex/$(date +%Y%m%dT%H%M%S)"
  install -d -m 700 "$backup"
  cp -p "$HOME/.codex/config.toml" "$backup/config.toml"
  chmod 600 "$backup/config.toml"
fi
```

リポジトリのルートで確認・適用します。

```bash
git pull --ff-only
make install
make install-apply
make verify
```

`make install` は dry-run、`make install-apply` はパッケージやツールも含む実適用です。
Codex の設定・ルール・エージェントだけを確認する場合は、mise の標準の対象指定を使います。
次の `--dry-run` を `--yes` に替えると適用します。
関連スキルもまとめて更新する場合は、上記の `make install-apply` を使います。

```bash
mise dot apply \
  '~/.codex/config.toml/shared' \
  '~/.codex/config.toml/defaults' \
  '~/.codex/rules/shared.rules' \
  '~/.codex/agents/code-analysis.toml' \
  --dry-run
make verify-dotfiles
```

`git pull` だけでは copy と merge の配置先は更新されません。
スキルは symlink なのでリポジトリ更新が反映されますが、サブエージェントは再適用が必要です。
適用後は Codex を再起動し、`/status` でモデルと権限設定を確認します。

copy 対象と新規 config の権限は `0600` です。merge は既存ファイルの権限を変更しません。
既存の config を保護する場合は、通常ファイルであることを確認してから `chmod 600 ~/.codex/config.toml` を実行します。
バックアップ、差分、ログには秘密情報や端末固有のパスが含まれ得るため、公開・コミットしないでください。

`make uninstall-apply` は copy と symlink の管理対象を削除しますが、マージ済みの config は残します。
端末固有の local.rules と default.rules も残ります。
マージと権限指定の詳細は [mise の公式仕様](https://mise.jdx.dev/dotfiles/edits.html)を参照してください。

## Restore from Backup

Codex を終了し、`backup` に退避ディレクトリのパスを設定します。
`~/.codex/config.toml` が通常ファイルであることを確認してから戻します。

```bash
cp "$backup/config.toml" "$HOME/.codex/config.toml"
chmod 600 "$HOME/.codex/config.toml"
```

次回適用では共通設定の上書きと初期値の補完が再び行われます。
共通設定を今後適用したくない場合は mise の対象エントリを外します。
復元後は Codex を再起動してください。
