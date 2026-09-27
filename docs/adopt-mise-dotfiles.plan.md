# シンボリックリンクの管理をmiseへ移管する

独自の`setup/symlinks.bash`を廃止し、5本のsymlinkをmise Dotfilesへ移管する。`bin/dotfiles`は利用者向けの入口として残すが、symlinkの状態判定、作成、解除は行わない。wrapperの責務は、固定版miseのbootstrap、Homebrewとtool install、mise Dotfilesの実行順、lifecycle lock、安全なtarget pathの事前検証、mise設定の隔離に限定する。

既存利用者との挙動の互換性は非ゴールとする。現在の利用者はリポジトリ所有者だけなので、独自実装を段階的に残さず、miseの状態モデルと診断へ寄せる。

## miseの設定一式をリポジトリルートへ移す

現在の`.config/mise`配下にある3ファイルをリポジトリルートへ移す。

```text
.config/mise/config.toml -> mise.toml
.config/mise/mise.lock  -> mise.lock
.config/mise/mise.env   -> mise.env
```

root `mise.toml`は、project config、global configのsource、tool設定、task、通常のdotfiles宣言を兼ねる。`min_version`は引き続き、設定を読み込める最低バージョンとbootstrapするmise本体の固定バージョンを兼ねる。`mise.env`のSHA-256と同時に更新する運用も維持する。

root配置により、`DOTFILES`の算出は`mise.toml`の実体をcanonicalizeした後、その親ディレクトリをrepository rootとして扱う式へ変更する。従来の`.config/mise/config.toml`を前提にした3階層上への移動は残さない。直接root configを読んだ場合と、global configのsymlink経由で読んだ場合の両方で、`DOTFILES`が実際のcheckoutを指すことを受け入れ条件にする。

配置変更に伴い、次をrootの`mise.toml`と`mise.lock`へ追従させる。

- `setup/mise-install.sh`と`setup/mise-version.sh`
- tool install用の一時configとlock file
- Makefileのlintとtest
- `.github/actions/setup-mise`とE2E workflow
- Node.jsテストとmise isolationテスト
- `renovate.json5`のmise manager対象
- README、Architecture、Operations、Test Strategy、Troubleshooting

## 5本のsymlinkをmise Dotfilesで管理する

管理対象は次の5本とする。

```text
~/.dotfiles
~/.bashrc
~/.bash_profile
~/.gitconfig
${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml
```

`~/.dotfiles`は、実際のcheckoutを指す安定したanchorである。global configはXDG Base Directoryに従い、anchor経由でroot `mise.toml`を指す。

```text
~/.dotfiles
  -> <実際のcheckout>

${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml
  -> ~/.dotfiles/mise.toml
```

root `mise.toml`には、環境に依存しない3本を宣言する。

```toml
[dotfiles]
"~/.bashrc" = { source = "~/.dotfiles/.bashrc" }
"~/.bash_profile" = { source = "~/.dotfiles/.bash_profile" }
"~/.gitconfig" = { source = "~/.dotfiles/.gitconfig" }
```

固定版mise 2026.8.15のschemaに合わせ、各targetの値は`source`を持つinline tableとする。`mode`は既定のsymlinkを使うため省略する。一時configの宣言も同じschemaで生成する。

sourceにcheckoutからの相対パスは使わない。root `mise.toml`はglobal configのsymlink経由でも読み込まれるため、相対sourceは`${XDG_CONFIG_HOME}/mise`基準に変わる可能性がある。`~/.dotfiles`から始まるsourceへ統一し、読み込み経路に依存しないようにする。

## 環境依存の2本は一時configで宣言する

mise 2026.8.15では、`[dotfiles]`のtargetやsourceへ`XDG_CONFIG_HOME`、config実体パスなどのテンプレートを展開できない。任意のcheckout先と非標準の`XDG_CONFIG_HOME`へ対応するため、wrapperは実行ごとに一時mise configを生成する。

一時configには、解決済みの絶対sourceと絶対targetで次の2本だけを宣言する。

```text
~/.dotfiles -> <実際のcheckout>
<解決済みXDG_CONFIG_HOME>/mise/config.toml -> ~/.dotfiles/mise.toml
```

一時configは`mktemp -d`で作成したディレクトリに置き、処理後に削除する。HOMEやXDG config directoryには、補助的な`conf.d`ファイルを残さない。一時config自身や一時ディレクトリをsymlinkのsourceにしてはならない。

一時configへパスを埋め込むときは、TOML basic stringとしてencodeする。`"`、`\`、制御文字をTOMLのescape sequenceへ変換し、生成後のconfigを固定版miseでparseできることをテストする。shellで値を引用するだけの文字列連結は使わない。

パスには既存の検証を適用する。

- `HOME`、checkout、`XDG_CONFIG_HOME`は絶対パスであること。
- tabと改行を含まないこと。
- checkoutとroot `mise.toml`が存在すること。
- 各targetのparentを絶対パスとして字句的に正規化し、`/`直下からparentまでの既存componentを順に`lstat`相当で検査すること。`HOME`と`XDG_CONFIG_HOME`自身も検査対象に含める。symlink componentがある場合はapply/unapplyを実行せず拒否し、存在しないcomponentへ到達した時点で検査を終える。miseがsymlink parentを安全に扱うことを前提にしない。apply/unapplyを呼ぶ直前にも同じ検査を行い、検査後に作られたsymlinkを見つける時間幅を狭める。

この検査はdry-runにも適用する。拒否した場合は外部側を変更せず、どのparent componentがpreconditionに違反したかを表示する。symlink parentを通るtargetを用意したE2Eでは、操作が非ゼロで終了し、外部側と他のtargetが不変であることを確認する。ただし、検査とmiseによるfilesystem操作はatomicではない。外部processがその間にcomponentをsymlinkへ置き換えるTOCTOU raceまで安全性を保証しない。この制約は運用上の注意として文書化し、完全な対策が必要になった場合はdescriptor基準のfilesystem操作を含む別設計で扱う。

## `bin/dotfiles`はmise Dotfilesを順序制御する

利用者向けの正式な入口は、引き続き次の3操作とする。miseのdotfilesコマンドを直接使う操作は利用者向け契約に含めない。

```text
bin/dotfiles install [--dry-run|--apply] [--skip-brew]
bin/dotfiles verify [--skip-brew]
bin/dotfiles uninstall [--dry-run|--apply]
```

固定版mise 2026.8.15には`mise dot` aliasがないため、内部コマンドは実測済みの`mise bootstrap dotfiles`へ統一する。

### install

applyでは、依存順を守って次を実行する。

1. 既存のpreflightを実行する。
2. 必要なら固定版miseをbootstrapする。
3. 5本すべてを絶対パスで宣言したpreflight用の一時configに対して`mise bootstrap dotfiles apply --dry-run`を実行し、競合がないことを確認する。このconfigでは、anchorがまだ存在しない初回installでもsourceを解決できるよう、残り4本のsourceを`~/.dotfiles`経由ではなくcheckout実体の絶対パスで指定する。
4. Homebrewとtool installを処理する。
5. 一時configで`~/.dotfiles`を`mise bootstrap dotfiles apply --yes`する。
6. 一時configでXDG配下のglobal configを`mise bootstrap dotfiles apply --yes`する。
7. root `mise.toml`で`.bashrc`、`.bash_profile`、`.gitconfig`を`mise bootstrap dotfiles apply --yes`する。

anchorを先に作るのは、残り4本のsourceが`~/.dotfiles`配下にあるためである。global configを作成した後も、root `mise.toml`を明示して処理を続け、実行途中で設定探索の基準を変えない。

dry-runではfilesystemを変更せず、同じ5本に対するmiseの計画を表示する。anchorが未作成でも残りのsourceを検査できるよう、dry-run用の一時configでは5本すべてに解決済みのsourceとtargetを指定し、global configのsourceにもcheckout実体の`mise.toml`を使う。applyでも変更前に同じpreflightを通すため、既知の競合がある状態でanchorや他targetを部分適用しない。anchorがないクリーンなHOMEでdry-runとinstallが成功すること、およびdry-runとapplyで対象となる5本が一致することをテストする。

### verify

verifyは、現行の公開契約を維持し、Homebrew、mise tool、dotfilesの状態を検証する。`--skip-brew`指定時はHomebrewの検証だけを省略する。dotfiles部分は、一時configとroot `mise.toml`のそれぞれに対して`mise bootstrap dotfiles status --missing`を実行する。miseの標準出力、標準エラー、終了コードを加工せず利用する。独自のmissing、wrong source、source missing診断は廃止する。

Homebrew、tool、dotfilesのいずれかが非ゼロならverifyを失敗とする。verifyはtarget、state、configを変更しない。dotfiles操作だけのためにverify全体をdotfiles-onlyへ縮退させない。

### uninstall

applyではinstallと逆の順序で解除する。

1. root `mise.toml`で`.bashrc`、`.bash_profile`、`.gitconfig`を`mise bootstrap dotfiles unapply --yes`する。
2. 一時configでXDG配下のglobal configを`mise bootstrap dotfiles unapply --yes`する。
3. 一時configで`~/.dotfiles`を`mise bootstrap dotfiles unapply --yes`する。

anchorを最後に解除し、他のsourceが途中で参照不能にならないようにする。dry-runも同じ順序で`mise bootstrap dotfiles unapply --dry-run`を実行する。

uninstallのためにmiseをbootstrapしない。miseがPATHにも固定のbootstrap先にも見つからない場合は、何も変更せずエラー終了し、miseを導入してから再実行するよう案内する。

## mise標準のstateを使い、親ディレクトリ削除は保証しない

dotfiles操作では、通常のmiseと同じstate directoryを使う。

```text
${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}
```

実行ごとの一時state directoryは使わず、mise標準の状態管理を維持する。install、verify、uninstallは、同じ規則で解決したstate directoryを使う。

固定するmise 2026.8.15では、symlinkの`unapply`が空の親ディレクトリを削除することを保証しない。したがって、uninstall後に親ディレクトリまで削除することは要件にしない。既存ディレクトリ、管理外ファイルを含むディレクトリ、miseが作成した空の親ディレクトリのいずれも、symlink解除後の扱いはmise標準に委ねる。wrapperは親ディレクトリを独自に削除しない。

将来miseを更新する場合も、親ディレクトリcleanupの挙動をこの計画の契約にはしない。cleanupを要件にする場合は、miseの対応範囲（特にHOME外のXDG_CONFIG_HOME）を確認したうえで、wrapperが作成したdirectoryを明示的に記録・検証して安全にcleanupする別設計とする。

## `--force`と独自の復旧機能を廃止する

publicな`install --force`を廃止し、CLIへ渡された場合はusage errorとして終了コード2を返す。miseへ`bootstrap dotfiles apply --force`を渡さない。

既存targetが通常ファイル、別sourceを指すsymlink、ディレクトリの場合は、mise標準の競合エラーで停止する。wrapperは既存targetを移動、削除、置換しない。利用者が内容を確認し、競合を手動で解消してからinstallを再実行する。

次の独自保証と実装を廃止する。

- 日時付きbackup
- 失敗時のrollback
- directoryと特殊ファイルの独自分類
- preflightとapply間の競合レースに対する独自処理
- 旧実装の状態ファイルとの互換性

checkoutを移動し、既存の`~/.dotfiles`が旧checkoutを指している場合も自動更新しない。利用者がlink先を確認して`~/.dotfiles`を手動で削除した後、新しいcheckoutからinstallを再実行する。

安全な`--force`を再導入する場合は別issueで扱う。そのissueでは、置換対象、directory保護、backup、rollback、TOCTOU対策をまとめて決める。本計画ではGitHub issueの作成自体は行わない。

## lifecycle lockは維持する

`install --apply`と`uninstall --apply`は、既存の`$HOME/.dotfiles-lifecycle.lock`を使って直列化する。dry-runとverifyはlockを取得しない。

lockは同じHOMEに対する`bin/dotfiles`同士の同時実行を防ぐ。CLI外からのfilesystem変更や、直接実行されたmiseコマンドまでは防がない。miseのdotfilesコマンドを直接使う操作を正式サポートしない理由の一つとして文書化する。

## dotfiles操作にもmiseの設定隔離を適用する

miseの呼び出しは`run_dotfiles_mise <config> ...`相当の一箇所へ集約する。install、status、apply、unapplyのすべてがこのrunnerを通り、呼び出し元のsystem/global config、config ceiling、config filename、env、hooksがdotfiles操作へ混入しないようにする。root `mise.toml`を明示することは、他の設定をcomposeさせないことの代替にはならない。

runnerへ入る前に、`MISE_DATA_DIR`、`MISE_CACHE_DIR`、`MISE_STATE_DIR`を呼び出し元の値とXDG/HOMEの既定値から解決する。その後、設定探索や実行内容へ影響する`MISE_*`を除去し、解決済みのdata、cache、state directoryと、隔離に必要な変数だけをallowlistとして明示的に設定する。これにより、呼び出し元の保存先は維持しつつ、設定の合成は許可しない。install、status、unapplyが同じstate directoryを使用することもテストする。

tool install時に既存の設定隔離テストを維持するだけでなく、dotfiles操作についてもhostileなHOMEとcaller/global/system configを用意したE2Eを追加する。意図したroot configと一時config以外の設定が読まれないこと、install、status、unapplyの結果が隔離環境の外部設定に左右されないことを確認する。

## E2Eは配線と受け入れ条件へ絞る

`.github/workflows/e2e_smoke.yml`では固定版の実miseを使い、`HOME`、`XDG_CONFIG_HOME`、`XDG_STATE_HOME`を隔離する。`XDG_CONFIG_HOME`には標準値と異なるパスを設定する。

正常系では次を確認する。

1. dry-runが5本を表示し、HOME、XDG config、mise stateを変更しない。
2. install後に5本すべてが`test -L`を満たす。
3. `readlink`が期待するanchorまたはsourceを指す。
4. root `mise.toml`がglobal configとしてmiseに認識される。
5. verifyが成功する。
6. installを再実行しても同じ状態へ収束する。
7. uninstallのdry-runでは5本が残る。
8. uninstall apply後に5本が消える。
9. uninstall後もpackage、tool、mise stateの管理外データは残る。親ディレクトリの削除有無は受け入れ条件にしない。
10. targetのparent componentにsymlinkがある場合、install/uninstallのdry-runとapplyが拒否され、外部側と他のtargetが不変である。
11. hostileなmise設定を置いても、dotfilesのinstall、status、unapplyが意図したconfigだけで実行され、同じ規則で解決したstate directoryを使う。
12. root `mise.toml`を直接読んだ場合とglobal configのsymlink経由で読んだ場合の両方で、`DOTFILES`が実際のcheckoutを指す。

代表的な競合として、既存の通常ファイルを`~/.bashrc`へ置いたケースを検査する。

- install applyが非ゼロで終了する。
- 既存ファイルの内容が変わらない。
- `.bash_profile`、`.gitconfig`を含む他targetも部分適用されない。
- `--force`がmiseへ渡されない。

mise内部の全競合種別、競合レース、rollbackは再検証しない。今回のE2Eは、wrapperの配線、実行順、公開契約に対象を絞る。

## 削除する独自実装

受け入れ条件を満たした後、次を削除する。

- `setup/symlinks.bash`
- `MANAGED_RESOURCES`
- planの`ensure_symlink`、`replace_symlink`、`remove_symlink`
- symlink用の独自backupとrollback
- `tests/symlinks.test.js`のmise内部処理と重複するケース
- `tests/fixtures/inputs/symlinks.json`の不要部分
- lifecycleテスト内の独自競合分類と競合レースのケース

Node.jsテストには、CLI option、mise呼び出し、実行順、mise不在時のuninstall、`--force`拒否を残す。実miseとの接続はE2Eで確認する。tool install時の設定隔離を検査する`tests/integration/mise-isolation.sh`は、root配置へ追従させたうえで維持する。

## 実装順

1. `config.toml`、`mise.lock`、`mise.env`をrootへ移し、参照元、`renovate.json5`、テストを追従させる。
2. root `mise.toml`へ3本の`[dotfiles]`宣言を追加する。
3. 環境依存の2本を宣言する一時config、TOML string encoder、設定を隔離する`run_dotfiles_mise` runnerを追加する。
4. target parentの既存componentをpreflight時とmise呼び出し直前に検査し、symlinkがあればmiseを呼ばずに拒否するpreconditionを追加する。TOCTOU raceは保証範囲外であることも文書化する。
5. install、verify、uninstallをmise Dotfiles呼び出しへ置き換える。
6. `--force`、backup、rollback、独自診断を削除する。
7. E2Eへ5本の正常系、通常ファイル競合、symlink parent拒否、XDG対応、設定隔離、state directoryの一致、root config経路別の`DOTFILES`検証を追加する。
8. 旧symlink実装と重複テストを削除する。
9. Makefile、README、Architecture、Operations、Test Strategy、Troubleshootingを更新する。

実装完了後、symlinkの状態遷移は5本ともmise Dotfilesが担当する。このリポジトリには、環境依存パスの宣言生成、安全なtarget pathの事前検証、mise設定の隔離、処理順、lifecycle lock、miseの実環境を使った受け入れ確認だけを残す。
