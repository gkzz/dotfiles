if ! shopt -oq posix; then
    if [ -r /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -r /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

if [ -r /etc/bash_completion.d/git-prompt ]; then
    . /etc/bash_completion.d/git-prompt
fi

if type __git_ps1 >/dev/null 2>&1; then
    PS1='\[\033[01;32m\]\u@\h\[\033[01;33m\] \w$(__git_ps1) \n\[\033[01;34m\]\$\[\033[00m\] '
else
    PS1='\[\033[01;32m\]\u@\h\[\033[01;33m\] \w \n\[\033[01;34m\]\$\[\033[00m\] '
fi

if [ -r "$HOME/lib/azure-cli/az.completion" ]; then
    . "$HOME/lib/azure-cli/az.completion"
fi

if command -v argocd >/dev/null 2>&1; then
    source <(argocd completion bash)
fi
