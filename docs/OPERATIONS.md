# Operations

## コマンド

| 操作 | dry-run | `--apply` |
| --- | --- | --- |
| `install` | デフォルト。導入内容を表示する | package、tool、managed symlink を適用する |
| `uninstall` | デフォルト。削除対象を表示する | managed symlink を削除する |
| `check` | 対象外 | 対象外。現在の状態を確認するだけ |

```bash
make install
make install-apply
make check
make uninstall
make uninstall-apply
```

直接実行する場合は次を使います。

```bash
bin/dotfiles install [--dry-run|--apply] [--force] [--skip-brew]
bin/dotfiles check [--skip-brew]
bin/dotfiles uninstall [--dry-run|--apply]
```

## install

最初に `make install` で内容を確認し、問題がなければ `make install-apply` を実行します。mise config、mise lock、Brewfile を変更した場合も同じ手順で反映します。

mise が未導入の場合、apply 時には `curl` と SHA-256 検証コマンド、ネットワーク接続が必要です。repository に固定した version と checksum を使って mise を導入します。

既存の regular file または symlink と競合した場合は停止します。置き換える場合は `--force --dry-run` で対象を確認してから `--force --apply` を実行します。directory と特殊ファイルは置き換えません。

Homebrew を対象外にする場合は次を使います。

```bash
bin/dotfiles install --skip-brew
bin/dotfiles install --skip-brew --apply
```

managed symlink の source file の内容だけを変更した場合、install の再実行は不要です。

## check

`make check` は Bash、Git、Homebrew、mise、managed symlink を確認します。修復は行いません。

Homebrew を対象外にする場合は `bin/dotfiles check --skip-brew` を使います。

## uninstall

最初に `make uninstall` で削除対象を確認し、問題がなければ `make uninstall-apply` を実行します。削除するのは現在の repository を指す managed symlink だけです。package/tool、Homebrew/mise 本体、backup、既存の state file は残します。

## ローカル設定と補助操作

個人の Git email、署名鍵、credential override は `~/.gitconfig.local`、端末固有の shell 設定は `~/.bashrc.local` に置きます。

Git Credential Manager は lifecycle とは別に管理します。

```bash
make gcm
make gcm-apply
```
