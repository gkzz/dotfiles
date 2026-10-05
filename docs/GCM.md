# Git Credential Manager の設定

Windows（WSL2）では Git for Windows に付属する GCM、macOS では手動導入した GCM を使います。このリポジトリは GCM を自動インストールしません。既に導入済みの GCM は、自動導入対象から外しても削除されません。

この手順は dotfiles 適用後の Bash で実行します。`.gitconfig` は共有設定へのリンクなので、端末固有の設定は `~/.gitconfig.local` に保存します。Git 認証の設定変更だけならブランチや commit は不要です。

## 変更前の設定を保存する

まず現在の helper と保存先を確認します。設定がなければ、対応するコマンドの出力はありません。

```bash
git config --show-origin --get-all credential.helper
git config --show-origin --get-all credential.credentialStore
```

`~/.gitconfig.local` がある場合は、変更前にバックアップを作ります。バックアップのパスは、元に戻すときまで控えておいてください。

```bash
if [ -f "$HOME/.gitconfig.local" ]; then
    gcm_backup=$(mktemp "$HOME/.gitconfig.local.before-gcm.XXXXXX")
    cp -p "$HOME/.gitconfig.local" "$gcm_backup"
    printf 'Backup: %s\n' "$gcm_backup"
fi
```

以下の設定は、local ファイル内の既存の helper を置き換えます。最初の空の helper は、それ以前に読み込まれた helper をリセットします。その後に OS ごとの helper を追加することで、共有設定の `manager` より優先させます。

## Windows（WSL2）

Windows 側に [Git for Windows](https://gitforwindows.org/) をインストールし、インストーラーで GCM を選択します。WSL2 側には GCM を追加インストールしません。これは [GCM の公式 WSL 手順](https://github.com/git-ecosystem/git-credential-manager/blob/main/docs/wsl.md#configuring-wsl-with-git-for-windows-recommended)に沿った構成です。

WSL2 の Bash で、Windows 側の実行ファイルを確認します。

```bash
ls /mnt/c/Program\ Files/Git/{ucrt64,mingw64,clangarm64}/bin/git-credential-manager*.exe
```

存在しない候補のエラーは無視し、見つかったパスを使います。インストール先、Git for Windows のバージョン、CPU によってディレクトリが異なります。古い環境ではファイル名が `git-credential-manager-core.exe` の場合もあります。

以下は `mingw64/bin/git-credential-manager.exe` の例です。`gcm_exe` を実際のパスに置き換え、バージョン確認が成功してから設定します。

```bash
gcm_exe='/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe'
"$gcm_exe" --version
```

```bash
gcm_helper=$(printf '%q' "$gcm_exe")
git config --file "$HOME/.gitconfig.local" --replace-all credential.helper ''
git config --file "$HOME/.gitconfig.local" --add credential.helper "$gcm_helper"
```

`printf '%q'` はパス内の空白をエスケープし、Git が helper を起動できる形式にします。

認証情報は Windows 資格情報マネージャーに保存されます。GCM は通常 Windows 側の Git 設定を読むため、プロキシなど GCM に必要な設定は Windows 側にも設定してください。この構成では、WSL2 側に `credential.credentialStore` や `WSLENV` の追加設定は不要です。

Azure DevOps を利用する場合は、WSL2 側に次も設定します。

```bash
git config --file "$HOME/.gitconfig.local" credential.https://dev.azure.com.useHttpPath true
```

## macOS

macOS での動作は未確認です。以下は公式ドキュメントに基づく手順で、実機でのインストールと認証は検証していません。

Homebrew 導入後に、[公式のインストール手順](https://github.com/git-ecosystem/git-credential-manager/blob/main/docs/install.md#macos)に従って GCM を手動導入します。

```bash
brew install --cask git-credential-manager
git-credential-manager --version
```

helper と認証情報の保存先を設定します。共有設定には `credentialStore = cache` があるため、local ファイルで `keychain` に上書きします。[macOS Keychain は GCM が対応する保存先](https://github.com/git-ecosystem/git-credential-manager/blob/main/docs/credstores.md#macos-keychain)です。

```bash
git config --file "$HOME/.gitconfig.local" --replace-all credential.helper ''
git config --file "$HOME/.gitconfig.local" --add credential.helper manager
git config --file "$HOME/.gitconfig.local" --replace-all credential.credentialStore keychain
```

GCM の更新も手動で行います。

```bash
brew upgrade --cask git-credential-manager
```

## 設定と認証を確認する

```bash
git config --show-origin --get-all credential.helper
git config --show-origin --get-all credential.credentialStore
git remote -v
```

helper の出力では、`~/.gitconfig.local` の空の値と、その後に OS ごとの helper があることを確認します。macOS の保存先は最後の値が `keychain` になっていれば設定済みです。WSL2 の Windows GCM は通常 Windows 側の設定を読むため、WSL2 側に表示される `cache` は使いません。

HTTPS の remote があるリポジトリで、次を実行します。SSH の remote は GCM を使わないため、HTTPS の remote を指定してください。

```bash
git ls-remote origin HEAD
```

認証を求められたら、表示された案内に従ってサインインします。公開リポジトリは認証なしでも読めるため、認証まで確認する場合は、アクセス権のある非公開リポジトリで実行してください。認証情報を表示する `git credential fill` は確認に使いません。

## 元の設定に戻す

バックアップを作成した場合は、控えたパスから復元します。設定後に加えた別の変更がある場合は、復元前に差分を確認してください。

```bash
cp -p "$gcm_backup" "$HOME/.gitconfig.local"
```

別のシェルで復元する場合は、`$gcm_backup` をバックアップの実際のパスに置き換えます。新しく local ファイルを作成した場合は、同ファイルから今回追加した `credential.helper`、macOS の `credential.credentialStore`、追加していれば Azure DevOps の `useHttpPath` を取り除きます。ほかの端末固有の設定は残してください。

この復元は Git 設定だけを戻します。GCM 本体や Windows 資格情報マネージャー、macOS Keychain に保存された認証情報は削除しません。
