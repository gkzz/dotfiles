# 変更履歴

このファイルでは、利用者に影響する変更を記録します。

## [Unreleased]

### 追加

- `install`、`verify`、`uninstall` による dotfiles のライフサイクル管理
- dry-run を既定にした安全な適用・削除操作と、`--force` によるバックアップ付きの競合解決
- Homebrew、mise、管理対象シンボリックリンクをまとめて扱うセットアップ処理
- Linux/WSL2（x86_64、arm64）向けの環境構成
- mise のバージョンとツールを lock file で固定する仕組み
- `make ci`、`make lint`、`make test` による検査と、Node.js・シェルを使ったテスト基盤
- GitHub Actions から利用できる、リポジトリ固定版 mise をセットアップする composite action
- `setup-mise` action の検証、タグ作成、GitHub Release 公開を行う手動リリース workflow

### 改善

- install、verify、uninstall の処理を分離し、確認と変更の責務を明確化
- lifecycle lock により、同じ HOME を対象にした install と uninstall を直列化
- GitHub Actions で mise のインストール先・キャッシュ先を分離し、再利用しやすく整理
- private repository の mise ツールを利用できるよう、caller workflow の GitHub token を action から mise に渡す構成に変更
- アーキテクチャ、テスト戦略、運用方法、トラブルシューティングのドキュメントを整備

### 修正

- WSL の OS パッケージ更新を dotfiles の管理対象から分離
- Homebrew を使わない環境でも lifecycle smoke test を実行できるように修正
- mise の診断結果と検証エラーを区別して表示
- Linux/WSL2 と macOS の差異を考慮した検証・セットアップ処理を修正

