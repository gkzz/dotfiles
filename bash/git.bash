# ===== Staging =====

# 指定したファイルをステージングする
alias ga='git add'

# すべての変更（追加・変更・削除）をステージングする
alias gaa='git add -A'


# ===== Commit =====

# ステージング済みの変更をコミットする
alias gc='git commit'

# 直前のコミットを修正する
alias gca='git commit --amend'

# コミットメッセージを指定してコミットする
alias gcm='git commit -m'


# ===== Push =====

# 現在のブランチをoriginへpushし、upstreamを設定する（主に初回push）
alias gpu='git push -u origin HEAD'

# 現在のブランチを安全にforce pushする（push済みブランチのrebase後など）
alias gpuf='git push --force-with-lease origin HEAD'


# ===== Fetch / Pull / Rebase =====

# originの最新情報を取得する（現在の作業ブランチには変更を加えない）
alias gf='git fetch origin'

# 現在のブランチをfast-forwardのみで更新する（主にmainの更新用）
alias gpl='git pull --ff-only'

# gpuの反対として使うpull alias（fast-forwardのみ）
alias gup='git pull --ff-only'

# 現在の作業ブランチを最新のorigin/main上にrebaseする
alias grm='git rebase origin/main'

# 現在の作業ブランチを最新のorigin/main上にrebaseし、コミットも整理する
alias grmi='git rebase -i origin/main'


# ===== Status / Branch =====

# ワークツリーとステージングの状態を確認する
alias gst='git status'

# ブランチ一覧を表示する
alias gb='git branch'

# ブランチを切り替える
alias gsw='git switch'

# 新しいブランチを作成して切り替える
alias gswc='git switch -c'


# ===== Diff =====

# ステージング前の変更を確認する
alias gd='git diff'

# ステージング済み（次のコミットに入る）の変更を確認する
alias gds='git diff --staged'


# ===== Log =====

# 直近72時間のコミット履歴をグラフ形式で表示する
alias gl='git log --since="72 hours ago" --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'
