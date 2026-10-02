#!/bin/bash
# wezterm prompt integration for AI helper mode management
# このファイルは ~/.bashrc から読み込まれることを想定しています

# wezterm 以外の環境では何もしない
if [[ -z "$WEZTERM_PANE" ]]; then
    return
fi

# プロンプトコマンドに Normal Mode を設定するエスケープシーケンスを追加
# これにより、bash のプロンプトが表示されるたびに Normal Mode になる
__wezterm_set_normal_mode() {
    # WEZTERM_AI_HELPER を空文字列に設定（Normal Mode）
    printf "\033]1337;SetUserVar=%s=%s\007" "WEZTERM_AI_HELPER" "$(echo -n "" | base64)"
}

# PROMPT_COMMAND に追加
# 既存の PROMPT_COMMAND がある場合は前に追加（プロンプト表示前に実行）
if [[ -z "$PROMPT_COMMAND" ]]; then
    PROMPT_COMMAND="__wezterm_set_normal_mode"
else
    # 既に追加されていない場合のみ追加
    if [[ "$PROMPT_COMMAND" != *"__wezterm_set_normal_mode"* ]]; then
        PROMPT_COMMAND="__wezterm_set_normal_mode${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
    fi
fi
