#!/bin/bash
# Wezterm Unix Domain ランチャー
# wezterm-gui の有無を判定して適切なコマンドで起動します

set -e

# デバッグモード（環境変数で制御）
DEBUG=${WEZTERM_LAUNCHER_DEBUG:-0}

# ログ出力関数
log() {
    if [[ "$DEBUG" == "1" ]]; then
        echo "[wezterm-launcher] $*" >&2
    fi
}

# エラー出力関数
error() {
    echo "[wezterm-launcher] ERROR: $*" >&2
}

# ローカル unix domain に接続した wezterm-gui が存在するかチェック
# （sshmux 接続の wezterm-gui は無視）
is_local_gui_running() {
    pgrep -f "wezterm-gui connect unix" > /dev/null 2>&1
}

# メイン処理
main() {
    log "Starting wezterm launcher..."

    # wezterm コマンドの存在確認
    if ! command -v wezterm &> /dev/null; then
        error "wezterm command not found"
        exit 1
    fi

    # ローカル unix domain に接続した GUI が存在するかチェック
    if is_local_gui_running; then
        log "Local GUI is running, spawning new window..."

        if wezterm cli spawn --new-window; then
            log "Successfully spawned new window"
            exit 0
        else
            error "Failed to spawn new window, falling back to connect"
        fi
    fi

    log "Connecting to unix domain..."

    # unix ドメインに接続
    # - mux-server がない → 自動起動してウィンドウ作成
    # - mux-server あり、ウィンドウなし → ウィンドウ作成
    # - mux-server あり、ウィンドウあり → デタッチセッションに接続
    exec wezterm connect unix
}

main "$@"
