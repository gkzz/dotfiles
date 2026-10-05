# 運用手順

## 初回導入

dotfiles を clone したら、checkout のルートで最初に `make setup` を実行し、Homebrew と mise 本体を準備してください。このコマンドは mise bootstrap 自体は実行しません。準備後、dry-run の内容を確認してから適用します。

```bash
make setup
make install       # 適用内容を確認
make install-apply # 適用
```

Homebrew のインストール時に OS や権限の確認が求められることがあります。`make setup` は実行元 checkout を使います。Git のグローバル `pre-commit` hook はこのリポジトリで管理しており、実行には Docker が必要です。

## 既存環境からの移行

mise のグローバル設定先は `~/.config/mise/config.toml` に固定します。独自の `XDG_CONFIG_HOME` を設定している端末では、設定内の必要な内容を保存し、旧設定先の管理リンクを手動で解除してから、独自指定を外してください。シェル起動ファイルや `~/.bashrc.local` の指定も確認し、新しいシェルで移行を進めます。

既存の `~/.dotfiles` は、同じ checkout を指すリンクならそのまま使います。別の checkout を指す場合は、内容と参照先を確認して手動で解除してから適用してください。

## mise の導入とバージョン確認

`make setup` は mise が見つからない場合、固定バージョンを導入します。手動で導入する場合は次を実行してください。

```bash
./setup/mise-install.sh --dry-run
./setup/mise-install.sh --apply
```

導入するバージョンは `mise.toml` の `min_version` から取得します。OS と CPU に応じた SHA-256 checksum を検証します。現在のバージョンは次のコマンドで確認できます。

```bash
./setup/mise-version.sh
```

## 適用と状態確認

リポジトリルートから Makefile の target を実行します。

```bash
make install
make install-apply
make verify
```

適用前に dry-run の出力を確認してください。bootstrap は宣言されたパッケージ、dotfile、ツールを順に適用します。競合が起きたら mise の診断を確認し、対象を個別に解消して再実行してください。処理の途中で失敗した場合、それ以前の変更は残ることがあります。同じ HOME への適用・解除は同時に実行しないでください。

## 解除

```bash
make uninstall       # 解除内容を確認
make uninstall-apply # 解除
```

mise が管理する dotfile のリンクを解除します。Homebrew、mise 本体、リポジトリ、パッケージ、開発ツールは残ります。変更されたファイルなど mise が安全に識別できない対象は、表示された診断に従って個別に対応してください。

> [!NOTE]
> ### スコープ外
>
> `uninstall-apply` は、Homebrew や mise 本体、インストール済みのパッケージや開発ツールを削除しません。`setup` で準備した環境をどこまで削除するかは利用状況によって異なるため、インストール前の状態へ戻す処理は用意していません。

## Git Credential Manager の設定

Git Credential Manager (GCM) は端末ごとに導入します。Homebrew の自動導入対象には含めません。Windows（WSL2）では Windows 側の GCM、macOS では手動導入した GCM と Keychain を使います。導入、設定、確認、元に戻す手順は [GCM の設定](GCM.md)を参照してください。

## 開発用コマンド

```bash
make lint
make test
make ci
```

`make test` は `make test-bootstrap-dry-run` と `make test-git-hooks` を実行します。Git フックの既存テストは Docker を模擬して実行します。この dry-run は packages と dotfiles を除いて mise bootstrap を確認します。`make test-bootstrap-packages-dry-run` は Homebrew package bootstrap を dry-run します。どちらも実際のインストールは行いません。dotfiles の lifecycle は GitHub Actions で別途確認します。
