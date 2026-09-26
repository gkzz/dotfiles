---
name: git-command
description: Git の作業ブランチ作成、add、commit、push、rebase、履歴整理を、このリポジトリの alias と安全な運用方針に沿って案内する。
---

# Git Command

## Provenance

- Origin: Original skill authored for this global skills collection

Git の作業ブランチ作成、add、commit、push、rebase、履歴整理を案内するときにこの skill を使う。

## 前提

- `main` への反映は GitHub Pull Request 経由を前提にする。
- local `main` に直接 commit しない。
- 作業ブランチは基本的に 1 人で扱う。
- 作業ブランチはすでに `origin` に push 済みの場合がある。
- Git に不慣れなメンバーでも理解できるように、コマンドの目的と影響範囲を簡潔に説明する。
- `git pull --rebase` をデフォルトの更新手順として案内しない。

## コマンドの違い

### `git fetch origin`

リモートの情報を取得する。

`origin/main` などの remote-tracking branch は更新するが、現在の作業ブランチ自体、作業ツリー、commit は変更しない。

```bash
git fetch origin
# gf
```

### `git pull --ff-only`

現在のブランチを fast-forward できる場合だけ更新する。

主に local `main` を最新化するときに使う。local `main` に独自 commit がある、または履歴が分岐している場合は停止し、merge commit を作ったり履歴を書き換えたりしない。

```bash
git switch main
git pull --ff-only
# gpl
# gup
```

### `git rebase origin/main`

現在の作業ブランチの commit を、最新取得済みの `origin/main` の上に載せ替える。

作業ブランチにいる状態で実行する。最新の GitHub `main` を使いたいだけなら、local `main` に切り替える必要はない。

```bash
git fetch origin
# gf
git rebase origin/main
# grm
```

### `git rebase -i origin/main`

`git rebase origin/main` と同じく作業ブランチを `origin/main` の上に載せ替えつつ、commit 履歴を整理する。

commit message の修正、squash、fixup、並べ替え、削除をしたいときに使う。

```bash
git fetch origin
# gf
git rebase -i origin/main
# grmi
```

### `git push --force-with-lease`

rebase などで履歴を書き換えた push 済みブランチを更新するときに使う。

rebase では commit ID が変わる。remote branch は古い commit ID を指したままなので、通常の push は fast-forward ではない更新として拒否される。`--force-with-lease` は、最後に取得した後で remote に想定外の更新が入っていない場合だけ push する。

`git push --force` より安全なので、履歴を書き換えた push 済みブランチではこちらを使う。

```bash
git push --force-with-lease origin HEAD
# gpuf
```

## Alias

例を出すときは、実際の Git コマンドを先に示し、その直下に alias をコメントとして示す。
alias は bash/git.bash に記載。

## 作業ブランチの命名

作業ブランチを作るときは、次の形式を基本にする。

```text
<type>/<issue-id>-<short-description>
```

- `type` は変更の種類を表す。原則として `chore`、`docs`、`feat`、`fix`、`perf`、`refactor`、`revert`、`style`、`test` から選ぶ。
- `issue-id` は issue や task の ID がある場合に付ける。ない場合は省略し、`<type>/<short-description>` とする。
- `short-description` は変更内容が分かる短い英語の kebab-case にする。
- `type` で明らかな語を `short-description` で重ねない。たとえば `fix/5678-fix-login-bug` より `fix/5678-login-bug` を選ぶ。
- リポジトリ固有の命名規約がある場合は、その規約を優先する。

例:

```text
feat/1234-add-user-authentication
fix/5678-login-bug
docs/update-contributing-guide
```

## ユースケース 1: 作業ブランチ作成、commit、push

最新の `origin/main` から作業ブランチを作り、変更確認、stage、commit、初回 push まで行う。

```bash
git fetch origin
# gf

git switch -c feat/add-example origin/main
# gswc feat/add-example origin/main

git status
# gst

git diff
# gd

git add path/to/file
# ga path/to/file

git commit
# gc

git push -u origin HEAD
# gpu
```

全変更を stage する意図が明確な場合だけ、`git add -A` / `gaa` も案内してよい。

## ユースケース 2: 別ブランチが main に merge された

状況: 作業ブランチ A を作成した後、別ブランチ B が `main` に merge された。作業ブランチ A にいる状態で、A を最新の `origin/main` の上に載せ替える。

```bash
git fetch origin
# gf

git rebase origin/main
# grm
```

作業ブランチ A がすでに push 済みの場合は、rebase 後に remote branch を更新する。

```bash
git push --force-with-lease origin HEAD
# gpuf
```

説明するときは、rebase により commit ID が変わるため、push 済みブランチでは通常の push が拒否されることを簡潔に伝える。

## ユースケース 3: 作業ブランチの commit を整理する

review 前に作業ブランチの commit を整理する。

```bash
git fetch origin
# gf

git rebase -i origin/main
# grmi
```

interactive rebase の代表的な操作:

- `pick`: commit をそのまま残す。
- `reword`: commit の中身は残し、commit message だけ変更する。
- `squash`: その commit を直前の commit にまとめ、まとめた後の message を編集する。
- `fixup`: その commit を直前の commit にまとめ、この commit の message は捨てる。
- `drop`: commit を削除する。

push 済みの場合は、rebase 後に remote branch を更新する。

```bash
git push --force-with-lease origin HEAD
# gpuf
```

## Rebase 中の復旧操作

conflict が起きたら、対象ファイルを修正し、解決済みファイルを stage してから続行する。

```bash
git add path/to/file
# ga path/to/file

git rebase --continue
```

rebase をやめて開始前の状態に戻す。

```bash
git rebase --abort
```

## 回答方針

- Git に不慣れなメンバー向けに、目的、現在のブランチへの影響、push 済みかどうかの違いを簡潔に説明する。
- 実際の Git コマンドを先に示し、関連する alias を直下にコメントで示す。
- `fetch`、`pull --ff-only`、`rebase` のどれを使うか、その理由を明確にする。
- rebase は push 済み履歴を書き換える可能性があるため、必要なときは明示的に注意する。
- `git push --force` ではなく `git push --force-with-lease origin HEAD` を案内する。
- 作業ブランチ更新のためだけに local `main` へ切り替える手順を不要に案内しない。
- local `main` が最新だと仮定しない。
- 最新の GitHub `main` を基準にする場合は、`git fetch origin` 後の `origin/main` を使う。
- `gup` は `git pull --ff-only` の alias として扱い、`git pull --rebase` として案内しない。
