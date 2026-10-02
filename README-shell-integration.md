# Wezterm AI Helper Mode - Shell Integration

## 概要

このshell integrationは、weztermのClaude Modeを自動的に有効/無効にするための設定です。
Claude Code や codex CLI を実行すると自動的に検出され、適切なキーバインドに切り替わります。

## 仕組み

### 通常の bash プロンプト
- `wezterm-prompt-integration.bash` がプロンプト表示時に実行される
- OSC 1337 シーケンスで `WEZTERM_AI_HELPER=""` を設定（Normal Mode）
- bash に戻ると自動的に Normal Mode になる

### Claude Code のプロンプト
- `~/.claude/settings.json` の `statusLine.command` にOSCシーケンスを追加
- OSC 1337 シーケンスで `WEZTERM_AI_HELPER="claude"` を設定（Claude Mode）
- claude 実行中は自動的に Claude Mode になる

### Codex CLI
- `setup-codex-wezterm-integration.sh` が `~/.bashrc` に codex ラッパー関数を追加
- wezterm 上で `codex` を呼び出すと、実行前に `WEZTERM_AI_HELPER="codex"` を送信
- プロセス終了時に自動的に Normal Mode（空文字列）へ戻す
- wezterm 以外のターミナルでは副作用なし

### Wezterm 側の動作
- `wezterm.lua` が `update-status` イベントで `WEZTERM_AI_HELPER` を監視
- 値に応じてキーテーブルを自動切り替え
- ペインごとに独立して動作

## セットアップ

### 自動セットアップ（推奨）

```bash
cd ~/.config/wezterm
./setup-wezterm-ai-mode.sh
```

このスクリプトは以下を実行します：
1. `~/.bashrc` に prompt integration の読み込みを追加
2. `~/.claude/settings.json` に Claude Mode 設定を追加
3. 設定の反映方法を案内

### Codex ランチャーの追加

```bash
cd ~/.config/wezterm
./setup-codex-wezterm-integration.sh
```

`codex` コマンドを wezterm AI helper と連携させるための関数を `~/.bashrc` に追記します。wezterm 上で `codex` を実行すると自動的に ai helper へ切り替わり、終了時に Normal Mode へ戻ります。

### 手動セットアップ

#### 1. Bash プロンプト設定

`~/.bashrc` に以下を追加：

```bash
# Wezterm AI helper prompt integration
if [[ -f "$HOME/.config/wezterm/wezterm-prompt-integration.bash" ]]; then
    source "$HOME/.config/wezterm/wezterm-prompt-integration.bash"
fi
```

#### 2. Claude Code 設定

```bash
cd ~/.config/wezterm
./setup-claude-wezterm-integration.sh
```

または、手動で `~/.claude/settings.json` を編集：

```json
{
  "statusLine": {
    "type": "command",
    "command": "既存のコマンド; printf '\\033]1337;SetUserVar=%s=%s\\007' 'WEZTERM_AI_HELPER' \"$(echo -n 'claude' | base64)\""
  }
}
```

#### 3. 設定を反映

```bash
source ~/.bashrc
```

#### 4. Codex コマンド連携（任意）

`~/.bashrc` に以下の関数ブロックを追加し、`codex` 実行時に `WEZTERM_AI_HELPER` を自動制御します。wezterm 以外では何もしません。

```bash
__wezterm_set_ai_helper() {
	local value="${1:-}"

	if [[ -z "$WEZTERM_PANE" ]]; then
		return 0
	}

	local encoded
	encoded="$(printf '%s' "$value" | base64 | tr -d '\r\n')"

	printf '\033]1337;SetUserVar=%s=%s\007' \
		"WEZTERM_AI_HELPER" \
		"$encoded"
}

__wezterm_reset_ai_helper() {
	__wezterm_set_ai_helper ""
}

codex() {
	if ! command -v codex >/dev/null 2>&1; then
		echo "codex: コマンドが見つかりません" >&2
		return 127
	}

	local cleanup_needed=0

	if [[ -n "$WEZTERM_PANE" ]]; then
		cleanup_needed=1
		trap '__wezterm_reset_ai_helper' EXIT
		__wezterm_set_ai_helper "codex"
	}

	command codex "$@"
	local status=$?

	if (( cleanup_needed )); then
		trap - EXIT
		__wezterm_reset_ai_helper
	}

	return "$status"
}
```

## 動作確認

1. wezterm で新しいタブを開く
2. 通常のターミナルで Enter を押す → 通常動作
3. `claude` を実行
4. プロンプトが表示されると、右上に "Claude Mode" と表示される（1.5秒間）
5. Enter キーの動作が変わる：
   - Enter のみ: LF (0x0a) を送信
   - Shift+Enter または Ctrl+Enter: CR (0x0d) を送信
6. `/exit` で claude を終了
7. bash のプロンプトが表示されると、右上に "Normal Mode" と表示される
8. Enter キーの動作が通常に戻る
9. `codex` CLI でも同様に AI helper が自動切り替えされる（wezterm 外で実行しても `.bashrc` の関数は何もしない）

## Unix ドメインでの動作

この実装は unix ドメイン (`wezterm connect unix`) でも正しく動作します。
user_vars は LocalPane と ClientPane の両方でサポートされています。

## トラブルシューティング

### Claude Mode に切り替わらない

1. **bashrc の設定を確認**:
   ```bash
   type __wezterm_set_normal_mode
   ```
   関数が定義されていることを確認

2. **claude の settings.json を確認**:
   ```bash
   cat ~/.claude/settings.json | grep -i wezterm
   ```
   OSCシーケンスが含まれていることを確認

3. **デバッグモードを有効化**:
   `wezterm.lua` の 66行目を以下のように変更：
   ```lua
   local DEBUG_AI_HELPER = true
   ```

   その後、別ターミナルでログを監視：
   ```bash
   wezterm start --always-new-process 2>&1 | grep -i "ai_helper\|WEZTERM_AI_HELPER"
   ```

4. **手動で user_var を設定してテスト**:
   ```bash
   # Claude Mode を設定
   printf "\033]1337;SetUserVar=%s=%s\007" "WEZTERM_AI_HELPER" "$(echo -n "claude" | base64)"

   # Normal Mode に戻す
   printf "\033]1337;SetUserVar=%s=%s\007" "WEZTERM_AI_HELPER" "$(echo -n "" | base64)"
   ```

### settings.json が壊れた場合

セットアップスクリプトは自動的にバックアップを作成します：

```bash
# 最新のバックアップを確認
ls -lt ~/.claude/settings.json.backup.* | head -1

# バックアップから復元
cp ~/.claude/settings.json.backup.YYYYMMDD_HHMMSS ~/.claude/settings.json
```

## ファイル構成

- `wezterm.lua`: メイン設定ファイル（user_vars ベースのプロセス検出）
- `wezterm-prompt-integration.bash`: Bash プロンプト用の設定
- `setup-claude-wezterm-integration.sh`: Claude settings.json 編集スクリプト
- `setup-codex-wezterm-integration.sh`: Codex CLI 用の `.bashrc` 追記スクリプト
- `setup-wezterm-ai-mode.sh`: 統合セットアップスクリプト
- `README-shell-integration.md`: このファイル

## 他の AI アシスタントツールへの対応

Codex など他のツールにも対応させたい場合：

1. そのツールの設定ファイルに同様の OSC シーケンスを追加
2. `WEZTERM_AI_HELPER` に適切な値を設定（例: "codex"）

現在の実装では、`WEZTERM_AI_HELPER` が空でなければ Claude Mode が有効になります。
codex の例を参考に、必要な CLI ごとにラッパー関数を用意することで同じ仕組みを共有できます。
