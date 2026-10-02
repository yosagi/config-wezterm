#!/bin/bash
# WezTerm用の.desktopファイルを生成・インストールするヘルパースクリプト

set -euo pipefail

# カラー出力用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# スクリプトのディレクトリ
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# インストール先ディレクトリ
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

# 非対話モード（--yes で有効化）
FORCE_YES=false

# 設定ファイル（SSH接続先を定義）
CONFIG_FILE="${SCRIPT_DIR}/wezterm-connections.conf"

print_usage() {
    cat <<EOF
使用方法: $0 [COMMAND] [OPTIONS]

COMMANDS:
    generate [OPTIONS]  設定ファイルに基づいてSSH/SSHMUX用.desktopファイルを生成
        --from-ssh-config   .ssh/configからホストを収集して設定ファイルとvfs.tomlを生成
        --ssh-config FILE   使用するSSH設定ファイル（デフォルト: ~/.ssh/config）
        --type TYPE         接続タイプ (sshmux, ssh) デフォルト: sshmux
    install             生成済みの.desktopファイルとwezterm-launcherをインストール
                        - wezterm-launcher.sh を ~/.local/bin/wezterm-launcher にインストール
                        - wezterm-unix.desktop（Unix domain用、リポジトリ固定）をインストール
                        - 生成されたSSH/SSHMUX用.desktopファイルをインストール
    all                 generate + install を実行（デフォルト）
    uninstall           インストール済みの.desktopファイルを削除
    list                インストール済みのWezTerm .desktopファイルを一覧表示

OPTIONS:
    -y, --yes   確認プロンプトをスキップして上書き（非対話モード）
    -h, --help  このヘルプを表示

設定ファイル: ${CONFIG_FILE}
インストール先: ${INSTALL_DIR}

注意:
    - Unix domain用の wezterm-unix.desktop はリポジトリ内の固定ファイルです
    - wezterm-unix.desktop は wezterm-launcher を使用してスマートに起動します

例:
    $0                              # generate + install を実行
    $0 generate                     # SSH/SSHMUX用.desktopファイルのみ生成
    $0 generate --from-ssh-config   # .ssh/configからSSHMUX接続設定を生成
    $0 generate --from-ssh-config --type ssh  # SSH接続として生成
    $0 install                      # 既存の.desktopファイルとランチャーをインストール
    $0 uninstall                    # インストール済みファイルを削除
EOF
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# wezterm.luaからunix_domainsを抽出
parse_unix_domains() {
    local wezterm_lua="${1:-${SCRIPT_DIR}/wezterm.lua}"

    if [[ ! -f "${wezterm_lua}" ]]; then
        return 0
    fi

    # config.unix_domains = { ... } の部分を抽出してnameを取得
    # シンプルなパターンマッチング（複数行対応）
    awk '
        /config\.unix_domains[[:space:]]*=/ {
            in_unix_domains = 1
            brace_count = 0
        }
        in_unix_domains {
            # 中括弧のカウント
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == "{") brace_count++
                if (c == "}") brace_count--
            }

            # name = "..." を抽出
            if (match($0, /name[[:space:]]*=[[:space:]]*"([^"]+)"/, arr)) {
                print arr[1]
            }

            # 終了条件
            if (in_unix_domains && brace_count == 0) {
                in_unix_domains = 0
            }
        }
    ' "${wezterm_lua}"
}

# .ssh/configからホストリストを抽出
parse_ssh_config() {
    local ssh_config="${1:-$HOME/.ssh/config}"

    if [[ ! -f "${ssh_config}" ]]; then
        log_error "SSH設定ファイルが見つかりません: ${ssh_config}"
        return 1
    fi

    # Hostディレクティブを抽出（ワイルドカードを除外）
    grep -i '^[[:space:]]*Host[[:space:]]' "${ssh_config}" | \
        sed 's/^[[:space:]]*[Hh][Oo][Ss][Tt][[:space:]]*//' | \
        tr ' ' '\n' | \
        grep -v '[*?]' | \
        sort -u
}

# .ssh/configからホスト詳細情報を抽出（Host, HostName, User, Port）
# 出力形式: host_alias|hostname|user|port（1行1ホスト）
parse_ssh_config_detailed() {
    local ssh_config="${1:-$HOME/.ssh/config}"

    if [[ ! -f "${ssh_config}" ]]; then
        return 1
    fi

    local current_host="" current_hostname="" current_user="" current_port=""
    local key value

    while IFS= read -r line; do
        # 前後の空白を除去
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # コメント・空行をスキップ
        case "$line" in '#'*|'') continue ;; esac

        # 最初の空白でキーと値に分割
        read -r key value <<< "$line"
        key="${key,,}" # 小文字に変換

        case "$key" in
            host)
                # 前のホストを出力
                if [[ -n "$current_host" && ! "$current_host" =~ [*?] ]]; then
                    echo "${current_host}|${current_hostname:-$current_host}|${current_user:-$USER}|${current_port:-22}"
                fi
                current_host="$value"
                current_hostname=""
                current_user=""
                current_port=""
                ;;
            hostname)
                current_hostname="$value"
                ;;
            user)
                current_user="$value"
                ;;
            port)
                current_port="$value"
                ;;
        esac
    done < "$ssh_config"

    # 最後のホストを出力
    if [[ -n "$current_host" && ! "$current_host" =~ [*?] ]]; then
        echo "${current_host}|${current_hostname:-$current_host}|${current_user:-$USER}|${current_port:-22}"
    fi
}

# yazi 用の vfs.toml を生成（sftp VFS 設定）
generate_yazi_vfs_toml() {
    local ssh_config="${1:-$HOME/.ssh/config}"
    local vfs_toml="${HOME}/.config/yazi/vfs.toml"
    local vfs_dir
    vfs_dir="$(dirname "$vfs_toml")"

    if [[ ! -f "$ssh_config" ]]; then
        log_error "SSH設定ファイルが見つかりません: $ssh_config"
        return 1
    fi

    mkdir -p "$vfs_dir"

    if [[ -f "$vfs_toml" ]]; then
        if [[ "$FORCE_YES" == true ]]; then
            log_info "vfs.toml を上書きします（--yes）: $vfs_toml"
        else
            log_warn "vfs.toml は既に存在します: $vfs_toml"
            read -p "上書きしますか? [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "vfs.toml の生成をスキップしました"
                return 0
            fi
        fi
    fi

    # ヘッダー
    cat > "$vfs_toml" <<'EOF'
# yazi sftp VFS 設定
# install-wezterm-desktop.sh で ~/.ssh/config から自動生成

EOF

    local count=0
    while IFS='|' read -r host hostname user port; do
        [[ -z "$host" ]] && continue
        cat >> "$vfs_toml" <<EOF
[services.${host}]
type = "sftp"
host = "${hostname}"
user = "${user}"
port = ${port}

EOF
        count=$((count + 1))
    done < <(parse_ssh_config_detailed "$ssh_config")

    log_info "vfs.toml を生成しました: $vfs_toml（${count} ホスト）"
}

# .ssh/configから設定ファイルを生成
generate_config_from_ssh() {
    local ssh_config="${1:-$HOME/.ssh/config}"
    local connection_type="${2:-ssh}"

    if [[ -f "${CONFIG_FILE}" ]]; then
        if [[ "$FORCE_YES" == true ]]; then
            log_info "設定ファイルを上書きします（--yes）: ${CONFIG_FILE}"
        else
            log_warn "設定ファイルは既に存在します: ${CONFIG_FILE}"
            read -p "上書きしますか? [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "キャンセルしました"
                return 1
            fi
        fi
    fi

    log_info ".ssh/configからホストを抽出中: ${ssh_config}"

    local hosts
    hosts=$(parse_ssh_config "${ssh_config}")

    if [[ -z "${hosts}" ]]; then
        log_warn "有効なホストが見つかりませんでした"
        return 1
    fi

    # ヘッダーを書き込み
    cat > "${CONFIG_FILE}" <<'EOF'
# WezTerm接続設定ファイル
# .ssh/configから自動生成
# 書式: TYPE|NAME|COMMENT|EXEC_ARGS

EOF

    local host_count=0

    # 各ホストに対してエントリを生成
    echo "${hosts}" | while IFS= read -r host; do
        [[ -z "${host}" ]] && continue

        # ホスト名を表示用に整形（ハイフンを空白に変換して単語ごとに先頭を大文字に）
        local display_name=$(echo "${host}" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')

        if [[ "${connection_type}" == "sshmux" ]]; then
            # SSHMUX接続の場合
            echo "sshmux|WezTerm (${display_name})|${host}へSSHMUX接続|connect SSHMUX:${host}"
        else
            # SSH接続の場合
            echo "ssh|WezTerm (${display_name})|${host}へSSH接続|connect SSH:${host}"
        fi
    done >> "${CONFIG_FILE}"

    # ホスト数をカウント（生成されたエントリから計算）
    host_count=$(echo "${hosts}" | grep -c .)

    log_info "設定ファイルを生成しました: ${CONFIG_FILE}"
    log_info "検出されたホスト数: ${host_count}"
    log_info "接続タイプ: ${connection_type}"

    if [[ "${connection_type}" == "sshmux" ]]; then
        log_warn "SSHMUXを使用する場合は、wezterm.luaでssh_domainsを設定してください"
    fi
}

# 設定ファイルのサンプルを生成
generate_sample_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        log_warn "設定ファイルは既に存在します: ${CONFIG_FILE}"
        return
    fi

    cat > "${CONFIG_FILE}" <<'EOF'
# WezTerm接続設定ファイル
# 書式: TYPE|NAME|COMMENT|EXEC_ARGS
#
# TYPE: 接続タイプ (sshmux, ssh)
# NAME: 表示名（例: WezTerm (MyServer)）
# COMMENT: コメント
# EXEC_ARGS: wezterm コマンドの引数
#
# 注: Unix domain接続は既存の wezterm-unix.desktop を使用してください
#
# 例:
# sshmux|WezTerm (MyServer)|MyServerへSSHMUX接続|connect SSHMUX:myserver
# ssh|WezTerm (DevBox)|DevBoxへSSH接続|connect SSH:devbox

# SSHMUX接続の例（コメントアウトを外して使用）
# sshmux|WezTerm (Server1)|Server1へSSHMUX接続|connect SSHMUX:server1
# sshmux|WezTerm (Server2)|Server2へSSHMUX接続|connect SSHMUX:server2

# SSH接続の例
# ssh|WezTerm (DevServer)|DevServerへSSH接続|connect SSH:devserver
EOF

    log_info "サンプル設定ファイルを生成しました: ${CONFIG_FILE}"
    log_info "このファイルを編集してSSH接続先を追加してください"
}

# .desktopファイルを生成
generate_desktop_file() {
    local type="$1"
    local name="$2"
    local comment="$3"
    local exec_args="$4"

    # exec_argsからホスト名/ドメイン名を抽出してファイル名に使用
    local hostname=""
    if [[ "${type}" == "unix" ]]; then
        # Unix domain: "connect domain-name" からドメイン名を抽出
        hostname=$(echo "${exec_args}" | awk '{print $NF}')
    elif [[ "${type}" == "sshmux" ]]; then
        # SSHMUX: "connect SSHMUX:hostname" からホスト名を抽出
        hostname=$(echo "${exec_args}" | sed -n 's/.*SSHMUX:\([^ ]*\).*/\1/p')
    elif [[ "${type}" == "ssh" ]]; then
        # SSH: "connect SSH:hostname" からホスト名を抽出
        hostname=$(echo "${exec_args}" | sed -n 's/.*SSH:\([^ ]*\).*/\1/p')
    fi

    # ホスト名が抽出できない場合は名前から生成
    if [[ -z "${hostname}" ]]; then
        hostname=$(echo "${name}" | sed 's/[^a-zA-Z0-9-]/_/g' | tr '[:upper:]' '[:lower:]')
    fi

    local desktop_file="${SCRIPT_DIR}/wezterm-${hostname}.desktop"

    # .desktopファイルの内容を生成
    cat > "${desktop_file}" <<EOF
[Desktop Entry]
Name=${name}
Comment=${comment}
Keywords=shell;prompt;command;commandline;cmd;terminal;
Icon=org.wezfurlong.wezterm
StartupWMClass=org.wezfurlong.wezterm
TryExec=wezterm
Exec=wezterm ${exec_args}
Type=Application
Categories=System;TerminalEmulator;Utility;
Terminal=false
EOF

    log_info ".desktopファイルを生成: ${desktop_file}"
    echo "${desktop_file}"
}

# 設定ファイルを読み込んで.desktopファイルを生成
# 注: Unix domain用の wezterm-unix.desktop は生成せず、リポジトリ内の固定ファイルを使用
generate_all_desktop_files() {
    local generated_files=()

    # 設定ファイルからSSH/SSHMUX接続を読み込んで.desktopファイルを生成
    if [[ -f "${CONFIG_FILE}" ]]; then
        while IFS='|' read -r type name comment exec_args; do
            # コメント行と空行をスキップ
            [[ "${type}" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${type}" ]] && continue

            # 前後の空白を削除
            type=$(echo "${type}" | xargs)
            name=$(echo "${name}" | xargs)
            comment=$(echo "${comment}" | xargs)
            exec_args=$(echo "${exec_args}" | xargs)

            local desktop_file=$(generate_desktop_file "${type}" "${name}" "${comment}" "${exec_args}")
            generated_files+=("${desktop_file}")
        done < "${CONFIG_FILE}"
    fi

    if [[ ${#generated_files[@]} -eq 0 ]]; then
        log_warn "SSH/SSHMUX用の.desktopファイルが生成されませんでした"
        if [[ ! -f "${CONFIG_FILE}" ]]; then
            log_info "設定ファイルが見つかりません。'generate' コマンドで設定ファイルを作成してください"
        else
            log_info "設定ファイルを確認してください: ${CONFIG_FILE}"
        fi
        log_info "Unix domain用の wezterm-unix.desktop はリポジトリに含まれています"
        return 1
    fi

    log_info "合計 ${#generated_files[@]} 個のSSH/SSHMUX用.desktopファイルを生成しました"
    log_info "Unix domain用の wezterm-unix.desktop はリポジトリに含まれています"
    return 0
}

# wezterm-launcher をインストール
install_launcher() {
    local launcher_src="${SCRIPT_DIR}/wezterm-launcher.sh"
    local launcher_dest="${HOME}/.local/bin/wezterm-launcher"
    local bin_dir="${HOME}/.local/bin"

    # ~/.local/bin ディレクトリを作成
    mkdir -p "${bin_dir}"

    # wezterm-launcher.sh の存在確認
    if [[ ! -f "${launcher_src}" ]]; then
        log_error "wezterm-launcher.sh が見つかりません: ${launcher_src}"
        return 1
    fi

    # ランチャースクリプトをインストール
    cp "${launcher_src}" "${launcher_dest}"
    chmod 755 "${launcher_dest}"
    log_info "ランチャースクリプトをインストール: ${launcher_dest}"

    # PATH に ~/.local/bin が含まれているかチェック
    if [[ ":$PATH:" != *":${bin_dir}:"* ]]; then
        log_warn "~/.local/bin が PATH に含まれていません"
        log_info "~/.bashrc や ~/.profile に以下を追加してください:"
        log_info "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

# .desktopファイルをインストール
install_desktop_files() {
    # まず wezterm-launcher をインストール
    install_launcher

    # インストール先ディレクトリを作成
    mkdir -p "${INSTALL_DIR}"

    # このディレクトリ内のwezterm-*.desktopファイルを探す
    local -a desktop_files=("${SCRIPT_DIR}"/wezterm-*.desktop)

    if [[ ! -e "${desktop_files[0]}" ]]; then
        log_error ".desktopファイルが見つかりません"
        log_info "まず 'generate' コマンドを実行してください"
        return 1
    fi

    local installed_count=0
    for desktop_file in "${desktop_files[@]}"; do
        [[ ! -f "${desktop_file}" ]] && continue

        local basename=$(basename "${desktop_file}")
        local dest="${INSTALL_DIR}/${basename}"

        cp "${desktop_file}" "${dest}"
        chmod 644 "${dest}"
        log_info "インストール: ${basename} -> ${dest}"
        installed_count=$((installed_count + 1))
    done

    # デスクトップデータベースを更新
    if command -v update-desktop-database &> /dev/null; then
        update-desktop-database "${INSTALL_DIR}" 2>/dev/null || true
        log_info "デスクトップデータベースを更新しました"
    fi

    log_info "合計 ${installed_count} 個の.desktopファイルをインストールしました"
    log_info "アプリケーションランチャーから使用できます"
}

# .desktopファイルをアンインストール
uninstall_desktop_files() {
    local uninstalled_count=0
    local pattern="${INSTALL_DIR}/wezterm-*.desktop"

    for desktop_file in ${pattern}; do
        [[ ! -f "${desktop_file}" ]] && continue

        local basename=$(basename "${desktop_file}")
        rm -f "${desktop_file}"
        log_info "削除: ${basename}"
        uninstalled_count=$((uninstalled_count + 1))
    done

    if [[ ${uninstalled_count} -eq 0 ]]; then
        log_warn "アンインストールするファイルが見つかりませんでした"
    else
        # デスクトップデータベースを更新
        if command -v update-desktop-database &> /dev/null; then
            update-desktop-database "${INSTALL_DIR}" 2>/dev/null || true
            log_info "デスクトップデータベースを更新しました"
        fi
        log_info "合計 ${uninstalled_count} 個のファイルをアンインストールしました"
    fi
}

# インストール済みファイルを一覧表示
list_installed_files() {
    local pattern="${INSTALL_DIR}/wezterm-*.desktop"
    local found=0

    echo "インストール済みのWezTerm .desktopファイル:"
    echo "インストール先: ${INSTALL_DIR}"
    echo ""

    for desktop_file in ${pattern}; do
        [[ ! -f "${desktop_file}" ]] && continue

        local basename=$(basename "${desktop_file}")
        local name=$(grep '^Name=' "${desktop_file}" | cut -d'=' -f2)
        local exec=$(grep '^Exec=' "${desktop_file}" | cut -d'=' -f2)

        echo "  ${basename}"
        echo "    Name: ${name}"
        echo "    Exec: ${exec}"
        echo ""
        found=$((found + 1))
    done

    if [[ ${found} -eq 0 ]]; then
        echo "  (なし)"
    else
        echo "合計: ${found} 個"
    fi
}

# メイン処理
main() {
    local command="${1:-all}"
    shift || true

    # オプション解析用の変数
    local from_ssh_config=false
    local ssh_config_file="$HOME/.ssh/config"
    local connection_type="sshmux"

    case "${command}" in
        -h|--help|help)
            print_usage
            exit 0
            ;;
        generate)
            # generateコマンドのオプションを解析
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --from-ssh-config)
                        from_ssh_config=true
                        shift
                        ;;
                    --ssh-config)
                        ssh_config_file="$2"
                        shift 2
                        ;;
                    --type)
                        connection_type="$2"
                        if [[ ! "${connection_type}" =~ ^(ssh|sshmux)$ ]]; then
                            log_error "無効な接続タイプ: ${connection_type}"
                            log_info "有効な値: ssh, sshmux"
                            exit 1
                        fi
                        shift 2
                        ;;
                    -y|--yes)
                        FORCE_YES=true
                        shift
                        ;;
                    *)
                        log_error "不明なオプション: $1"
                        print_usage
                        exit 1
                        ;;
                esac
            done

            # .ssh/configから生成するか、通常の生成か
            if [[ "${from_ssh_config}" == true ]]; then
                generate_config_from_ssh "${ssh_config_file}" "${connection_type}"
                # vfs.toml も同時に生成
                generate_yazi_vfs_toml "${ssh_config_file}"
            else
                generate_sample_config
            fi

            # 設定ファイルが存在する場合は.desktopファイルを生成
            if [[ -f "${CONFIG_FILE}" ]]; then
                generate_all_desktop_files
            fi
            ;;
        install)
            install_desktop_files
            ;;
        all)
            # allコマンドは既存の設定ファイルを使用
            if [[ ! -f "${CONFIG_FILE}" ]]; then
                generate_sample_config
            fi
            generate_all_desktop_files && install_desktop_files
            ;;
        uninstall)
            uninstall_desktop_files
            ;;
        list)
            list_installed_files
            ;;
        *)
            log_error "不明なコマンド: ${command}"
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
