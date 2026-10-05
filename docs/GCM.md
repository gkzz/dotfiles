# Git Credential Manager の設定

Git Credential Manager (GCM) の導入・更新・認証設定は、[公式リポジトリ](https://github.com/git-ecosystem/git-credential-manager)の手順を参照してください。このリポジトリでは GCM を自動インストールしません。

- Windows（WSL2）では Windows 版 GCM を使います。[WSL の設定手順](https://github.com/git-ecosystem/git-credential-manager/blob/main/docs/wsl.md)を参照してください。
- macOS では GCM と Keychain を使います。[導入手順](https://github.com/git-ecosystem/git-credential-manager/blob/main/docs/install.md#macos)と[保存先の設定](https://github.com/git-ecosystem/git-credential-manager/blob/main/docs/credstores.md#macos-keychain)を参照してください。macOS での実機確認は未実施です。

## この dotfiles での設定先

`~/.gitconfig` は共有設定へのシンボリックリンクです。GCM のパスや保存先など、端末固有の Git 設定は `~/.gitconfig.local` に保存します。公式手順の `git config --global` は、WSL・macOS 側では `git config --file "$HOME/.gitconfig.local"` に読み替えてください。

共有設定には `credential.helper = manager` と `credential.credentialStore = cache` があります。別の helper を指定する場合は、local ファイルで空の `credential.helper` を先に指定して既存の helper をリセットし、その後に使用する helper を追加します。macOS では保存先も `keychain` に上書きします。

WSL から呼ぶ Windows 版 GCM の実行ファイルのパスは端末ごとに確認してください。GCM 自身が読む Windows 側の Git 設定については、公式の [Shared configuration](https://github.com/git-ecosystem/git-credential-manager/blob/main/docs/wsl.md#shared-configuration)を参照してください。
