#!/bin/sh
# wezterm-remote-hook.sh
# リモートホストの .bashrc / .zshrc で source して使用する
# REMOTE_HOST と REMOTE_CWD を User Var として wezterm に通知する
#
# 使い方:
#   リモートホストの ~/.bashrc に以下を追加:
#     source ~/wezterm-remote-hook.sh
#
# 前提:
#   - wezterm の mux-server (SSHMUX) 経由で接続していること
#   - $WEZTERM_PANE が設定されていること（mux-server が自動設定）

# wezterm 以外のターミナルでは何もしない
[ -z "$WEZTERM_PANE" ] && return 0

__wezterm_osc1337_setvar() {
    printf "\033]1337;SetUserVar=%s=%s\007" "$1" "$(printf '%s' "$2" | base64 | tr -d '\n')"
}

__wezterm_notify_remote() {
    __wezterm_osc1337_setvar REMOTE_HOST "$(hostname -s | tr '[:upper:]' '[:lower:]')"
    __wezterm_osc1337_setvar REMOTE_CWD "$PWD"
}

# bash
if [ -n "$BASH_VERSION" ]; then
    PROMPT_COMMAND="__wezterm_notify_remote${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
fi

# zsh
if [ -n "$ZSH_VERSION" ]; then
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd __wezterm_notify_remote
fi

# 初回実行（source した直後にも通知する）
__wezterm_notify_remote
