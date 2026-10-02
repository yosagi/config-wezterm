-- modules/pane_mode.lua
-- Ctrl+, ペイン操作モード（vim の Ctrl+w 風）
local wezterm = require("wezterm")

local M = {}

--- 自分を起動するためのキー定義を返す
---@return table キー定義
function M.get_activation_entry()
	return {
		key = ",",
		mods = "CTRL",
		action = wezterm.action.ActivateKeyTable({
			name = "pane_mode",
			one_shot = true,
			timeout_milliseconds = 1000,
		}),
	}
end

-- ヘルプに表示するキーバインド定義
M.help_items = {
	{ key = "h", label = "h", description = "左のペインに移動" },
	{ key = "j", label = "j", description = "下のペインに移動" },
	{ key = "k", label = "k", description = "上のペインに移動" },
	{ key = "l", label = "l", description = "右のペインに移動" },
	{ key = "w", label = "w / Space", description = "次のペインに移動（循環）" },
	{ key = "v", label = "v", description = "左右に分割" },
	{ key = "s", label = "s", description = "上下に分割" },
	{ key = "c", label = "c", description = "現在のペインを閉じる" },
	{ key = "n", label = "n", description = "新しいウィンドウを開く" },
}

--- 設定に pane_mode を適用する
---@param config table wezterm config オブジェクト
function M.apply_to_config(config)
	config.keys = config.keys or {}
	config.key_tables = config.key_tables or {}

	-- config.keys に起動キーを追加
	table.insert(config.keys, M.get_activation_entry())

	-- key_tables に pane_mode を定義
	config.key_tables.pane_mode = {
		-- 移動
		{ key = "h", action = wezterm.action.ActivatePaneDirection("Left") },
		{ key = "j", action = wezterm.action.ActivatePaneDirection("Down") },
		{ key = "k", action = wezterm.action.ActivatePaneDirection("Up") },
		{ key = "l", action = wezterm.action.ActivatePaneDirection("Right") },
		{ key = "w", action = wezterm.action.ActivatePaneDirection("Next") }, -- 循環
		{ key = " ", action = wezterm.action.ActivatePaneDirection("Next") }, -- 循環（screen/tmux風）
		-- 分割
		{ key = "v", action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }) }, -- 左右に分割
		{ key = "s", action = wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }) }, -- 上下に分割
		-- 閉じる
		{ key = "c", action = wezterm.action.CloseCurrentPane({ confirm = false }) },
		-- 新しいウィンドウ
		{ key = "n", action = wezterm.action.SpawnCommandInNewWindow({ domain = "CurrentPaneDomain" }) },
		-- ヘルプ
		{ key = "?", mods = "SHIFT", action = wezterm.action_callback(function(win, pane)
			M.show_help(win, pane)
		end) },
		-- ESCでキャンセル
		{ key = "Escape", action = wezterm.action.PopKeyTable },
	}
end

--- ヘルプダイアログを表示
function M.show_help(window, pane)
	local choices = {}
	for _, item in ipairs(M.help_items) do
		table.insert(choices, {
			id = item.key,
			label = item.label .. "  —  " .. item.description,
		})
	end
	window:perform_action(wezterm.action.InputSelector({
		title = "Pane Mode (Ctrl-,)",
		choices = choices,
		action = wezterm.action_callback(function(win2, pane2, id, label)
			if not id then return end
			-- 選択されたキーに対応するアクションを実行
			local key_table = win2:effective_config().key_tables.pane_mode
			for _, entry in ipairs(key_table) do
				if entry.key == id then
					win2:perform_action(entry.action, pane2)
					return
				end
			end
		end),
	}), pane)
end

return M
