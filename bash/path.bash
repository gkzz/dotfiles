path_prepend() {
    [ -d "$1" ] || return 0
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH="$1:$PATH" ;;
    esac
}

path_append() {
    [ -d "$1" ] || return 0
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH="$PATH:$1" ;;
    esac
}

path_prepend "$HOME/.local/bin"
path_prepend "$HOME/.local/node/bin"
path_append "$HOME/bin"
path_append "$HOME/.devcontainers/bin"

if [ -d "$HOME/projects/go" ]; then
    export GOPATH="$HOME/projects/go"
    export GOBIN="$GOPATH/bin"
    path_append "$GOBIN"
fi

if [ -d /usr/local/go-1.19.1 ]; then
    export GOROOT=/usr/local/go-1.19.1
    path_append "$GOROOT/bin"
elif [ -d /usr/local/go ]; then
    path_append /usr/local/go/bin
fi

if [ -d /usr/lib/jvm/java-17-openjdk-amd64 ]; then
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
    path_prepend "$JAVA_HOME/bin"
fi

path_append "$HOME/.maestro/bin"

if [ -d "$HOME/Android/Sdk" ]; then
    export ANDROID_HOME="$HOME/Android/Sdk"
    export ANDROID_SDK_ROOT="$ANDROID_HOME"
    path_prepend "$ANDROID_HOME/platform-tools"
    path_prepend "$ANDROID_HOME/cmdline-tools/latest/bin"
fi

path_prepend "$HOME/flutter/bin"

export PATH
