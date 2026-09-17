alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias npm='echo "npm is blocked. Use pnpm instead." >&2 && false'
alias npx='echo "npx is blocked. Use pnpm dlx instead." >&2 && false'

if command -v notify-send >/dev/null 2>&1; then
    alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history | tail -n1 | sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
fi

peco-cd() {
    command -v ghq >/dev/null 2>&1 || return 1
    command -v peco >/dev/null 2>&1 || return 1

    local dir
    dir="$(ghq list --full-path | peco)" || return 1
    [ -n "$dir" ] && cd "$dir" || return 1
}

alias ghql='peco-cd'
