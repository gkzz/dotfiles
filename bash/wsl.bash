ensure_ssh_agent() {
    command -v ssh-agent >/dev/null 2>&1 || return 0
    command -v ssh-add >/dev/null 2>&1 || return 0

    local agent_env="$HOME/.ssh/agent-env"

    if [ ! -d "$HOME/.ssh" ] || [ ! -w "$HOME/.ssh" ]; then
        return 0
    fi

    if [ -r "$agent_env" ]; then
        . "$agent_env" >/dev/null 2>&1
    fi

    ssh-add -l >/dev/null 2>&1
    case $? in
        0|1) return 0 ;;
    esac

    eval "$(ssh-agent -s)" || return 0
    {
        printf 'export SSH_AUTH_SOCK=%q\n' "$SSH_AUTH_SOCK"
        printf 'export SSH_AGENT_PID=%q\n' "$SSH_AGENT_PID"
    } > "$agent_env" || return 0
    chmod 600 "$agent_env" || return 0
}

ensure_ssh_agent

if command -v ssh-add >/dev/null 2>&1 && [ -r "$HOME/.ssh/id_ed25519_wsl2" ]; then
    ssh-add -l >/dev/null 2>&1 || ssh-add "$HOME/.ssh/id_ed25519_wsl2" >/dev/null 2>&1
fi
