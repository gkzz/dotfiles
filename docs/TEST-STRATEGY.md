# テスト戦略

自作ラッパーとGitフックの安全性はNode.jsテストで確認します。mise Dotfilesの正常系は模倣せず、隔離したHOMEで実際にinstall、uninstall、再installするE2Eで確認します。

## 自動テスト

テストピラミッドの上から、対象範囲が広い順に並べています。

| レイヤー | テスト | 確認すること |
| --- | --- | --- |
| E2E | [Dotfiles lifecycle E2E](../.github/workflows/e2e_smoke.yml) | Ubuntu/macOSでdry-runとverifyがHOME・mise data・stateを変更しないこと、installの冪等性、uninstall直後のツール保持、再install、管理対象リンク |
| 結合テスト | [dotfiles-lifecycle.sh](../tests/integration/dotfiles-lifecycle.sh) | 既存ファイルとの競合で中断し、内容を上書きしないこと。危険なXDGパス経由でHOME外を変更しないこと。miseへ破壊的な`--force`を渡さないこと |
| 結合テスト | [mise-isolation.sh](../tests/integration/mise-isolation.sh) | 呼び出し元、HOME、リポジトリ内の追加設定がmiseの検査へ混入しないこと |
| コンポーネント・単体テスト | [Node.jsテスト](../tests/run.sh) | 排他制御、利用者データの保護、失敗時の終了状態と診断、Gitフックのstaged内容・ignore・Dockerへの受け渡し、通常installのstate隔離とdata/cacheへの書き込み、スナップショットの権限変更検出と失敗伝播 |

`make test` はNode.jsテストと実miseによる境界確認を実行します。Ubuntu/macOSのCIでも同じテストを実行します。installから再installまでの正常な一連の動作と、リンク欠落時のverifyの失敗・非修復は、pull requestのE2Eで確認します。

E2Eではmiseの初回migrationを準備段階で実行し、その後のHOME・data・stateを比較します。mise初回起動時のmigration記録とcacheの更新は、非変更性の保証に含めません。

スナップショットはNode.jsの1プロセスで比較対象のルートディレクトリ自身の権限と、配下のファイル種別・権限・SHA-256・symlink参照先を記録します。E2Eの検証用Node.jsは、比較対象のmise dataとは別に導入します。列挙、権限取得、読み取りのどれかが失敗したら、既存のスナップショットを置き換えずに失敗します。

## 自動テストで確認しないこと

mise DotfilesやGit、Dockerの仕様は再実装して確認しません。テスト用コマンドは、自作コードへの応答と障害注入に使います。実際の利用者HOMEへの適用、Homebrewの実インストール、Secretlintの検出精度は自動テストの対象外です。実HOMEに適用する場合は、dry-runの計画と競合を確認してください。
