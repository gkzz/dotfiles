dotfiles_bashrc="${BASH_SOURCE[0]}"
while [ -L "$dotfiles_bashrc" ]; do
    dotfiles_bashrc_dir="$(cd -P "$(dirname "$dotfiles_bashrc")" && pwd)"
    dotfiles_bashrc_target="$(readlink "$dotfiles_bashrc")"
    case "$dotfiles_bashrc_target" in
        /*) dotfiles_bashrc="$dotfiles_bashrc_target" ;;
        *) dotfiles_bashrc="$dotfiles_bashrc_dir/$dotfiles_bashrc_target" ;;
    esac
done
export DOTFILES="${DOTFILES:-$(cd -P "$(dirname "$dotfiles_bashrc")" && pwd)}"
unset dotfiles_bashrc dotfiles_bashrc_dir dotfiles_bashrc_target

# ~/.bashrc: executed by bash(1) for non-login shells.

case $- in
    *i*) ;;
      *) return;;
esac

for file in \
    "$DOTFILES/bash/env.bash" \
    "$DOTFILES/bash/path.bash" \
    "$DOTFILES/bash/aliases.bash" \
    "$DOTFILES/bash/git.bash" \
    "$DOTFILES/bash/completion.bash"
do
    [ -r "$file" ] && . "$file"
done

case "$(uname -s)" in
    Linux*)
        if [ -r /proc/sys/kernel/osrelease ] && grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease; then
            [ -r "$DOTFILES/bash/wsl.bash" ] && . "$DOTFILES/bash/wsl.bash"
        fi
        ;;
    Darwin*) [ -r "$DOTFILES/bash/mac.bash" ] && . "$DOTFILES/bash/mac.bash" ;;
esac

[ -r "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"
