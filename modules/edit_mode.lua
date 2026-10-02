-- modules/edit_mode.lua
-- Ctrl+; 編集モード（コピー、検索、クイック選択）
local wezterm = require("wezterm")

local M = {}

-- ヘルプ項目（apply_to_config でアクションが設定される）
M.help_entries = {}

--- 自分を起動するためのキー定義を返す
---@return table キー定義
function M.get_activation_entry()
	return {
		key = ";",
		mods = "CTRL",
		action = wezterm.action.ActivateKeyTable({
			name = "edit_mode",
			one_shot = true,
			timeout_milliseconds = 1000,
		}),
	}
end

--- 設定に edit_mode を適用する
---@param config table wezterm config オブジェクト
function M.apply_to_config(config)
	config.keys = config.keys or {}
	config.key_tables = config.key_tables or {}

	-- config.keys に起動キーを追加
	table.insert(config.keys, M.get_activation_entry())

	-- copy mode への移行アクション（SAVED_PATTERN をクリアしてから起動）
	local activate_copy_mode_clean = wezterm.action_callback(function(win, pane)
		-- 一度開いてパターンをクリアし、閉じてから再度開く
		win:perform_action(wezterm.action.ActivateCopyMode, pane)
		win:perform_action(wezterm.action.CopyMode("ClearPattern"), pane)
		win:perform_action(wezterm.action.CopyMode("Close"), pane)
		win:perform_action(wezterm.action.ActivateCopyMode, pane)
	end)

	-- search mode から copy mode への遷移（オーバーレイを閉じずにサブモード切り替え）
	local search_to_copy_clean = wezterm.action.Multiple({
		wezterm.action.CopyMode("ClearPattern"),
		wezterm.action.CopyMode("AcceptPattern"),
	})

	-- quick select から他モードへの移行（ESC で閉じてから起動）
	local quick_select_to_copy = wezterm.action_callback(function(win, pane)
		win:perform_action(wezterm.action.SendKey({ key = "Escape" }), pane)
		-- 一度開いてパターンをクリアし、閉じてから再度開く
		win:perform_action(wezterm.action.ActivateCopyMode, pane)
		win:perform_action(wezterm.action.CopyMode("ClearPattern"), pane)
		win:perform_action(wezterm.action.CopyMode("Close"), pane)
		win:perform_action(wezterm.action.ActivateCopyMode, pane)
	end)
	local quick_select_to_search = wezterm.action.Multiple({
		wezterm.action.SendKey({ key = "Escape" }),
		wezterm.action.Search("CurrentSelectionOrEmptyString"),
	})

	-- Ctrl+Shift+X: copy mode をクリーンに起動（前回の検索パターンをクリア）
	table.insert(config.keys, {
		key = "X",
		mods = "CTRL|SHIFT",
		action = activate_copy_mode_clean,
	})

	-- デフォルトのキーテーブルを取得して拡張
	local default_key_tables = wezterm.gui.default_key_tables()

	-- copy_mode に Ctrl-[ と Ctrl-; を追加（vim の ESC 代替 & モード切り替え）
	local copy_mode = default_key_tables.copy_mode
	table.insert(copy_mode, { key = "[", mods = "CTRL", action = wezterm.action.CopyMode("Close") })
	table.insert(copy_mode, {
		key = ";",
		mods = "CTRL",
		action = wezterm.action.ActivateKeyTable({
			name = "edit_mode_from_copy",
			one_shot = true,
			timeout_milliseconds = 1000,
		}),
	})

	-- copy_mode から C-, でペイン操作（overlay を閉じて pane_mode に入る）
	-- ActivatePaneDirection は overlay 存在中は動作しないため、先に閉じる必要がある
	table.insert(copy_mode, {
		key = ",",
		mods = "CTRL",
		action = wezterm.action.Multiple({
			wezterm.action.CopyMode("Close"),
			wezterm.action.ActivateKeyTable({
				name = "pane_mode",
				one_shot = true,
				timeout_milliseconds = 1000,
			}),
		}),
	})

	-- search_mode を拡張（デフォルトのエントリを書き換え）
	local search_mode = default_key_tables.search_mode
	for _, entry in ipairs(search_mode) do
		-- Enter (mapped:0x0d) の action を AcceptPattern に変更
		if entry.key == "mapped:\x0d" then
			entry.action = wezterm.action.CopyMode("AcceptPattern")
		end
	end
	table.insert(search_mode, { key = "[", mods = "CTRL", action = wezterm.action.CopyMode("Close") })
	table.insert(search_mode, {
		key = ",",
		mods = "CTRL",
		action = wezterm.action.Multiple({
			wezterm.action.CopyMode("Close"),
			wezterm.action.ActivateKeyTable({
				name = "pane_mode",
				one_shot = true,
				timeout_milliseconds = 1000,
			}),
		}),
	})

	-- key_tables を設定
	config.key_tables.copy_mode = copy_mode
	config.key_tables.search_mode = search_mode

	-- quick_select_mode は wezterm 標準にはないが、定義すれば使われる
	config.key_tables.quick_select_mode = {
		{ key = "[", mods = "CTRL", action = wezterm.action.SendKey({ key = "Escape" }) },
		{
			key = ";",
			mods = "CTRL",
			action = wezterm.action.ActivateKeyTable({
				name = "edit_mode_from_quick_select",
				one_shot = true,
				timeout_milliseconds = 1000,
			}),
		},
	}

	-- copy_mode からのモード切り替え
	config.key_tables.edit_mode_from_copy = {
		{ key = ";", mods = "CTRL", action = wezterm.action.CopyMode("ClearPattern") }, -- パターンクリアのみ（既に copy mode）
		{ key = "s", action = wezterm.action.CopyMode("EditPattern") }, -- search mode へ
		{ key = "/", action = wezterm.action.CopyMode("EditPattern") },
		{
			key = "p",
			action = wezterm.action_callback(function(win, pane)
				win:perform_action(wezterm.action.CopyMode("Close"), pane)
				win:perform_action(wezterm.action.QuickSelect, pane)
			end),
		},
		{ key = "Escape", action = wezterm.action.CopyMode("Close") },
		{ key = "[", mods = "CTRL", action = wezterm.action.CopyMode("Close") },
	}

	-- search_mode からのモード切り替え
	config.key_tables.edit_mode_from_search = {
		{ key = ";", mods = "CTRL", action = search_to_copy_clean }, -- パターンクリアして copy mode へ
		{ key = "s", action = wezterm.action.Nop }, -- 既に search mode
		{ key = "/", action = wezterm.action.Nop },
		{
			key = "p",
			action = wezterm.action_callback(function(win, pane)
				win:perform_action(wezterm.action.CopyMode("Close"), pane)
				win:perform_action(wezterm.action.QuickSelect, pane)
			end),
		},
		{ key = "Escape", action = wezterm.action.CopyMode("Close") },
		{ key = "[", mods = "CTRL", action = wezterm.action.CopyMode("Close") },
	}

	-- quick_select からのモード切り替え
	config.key_tables.edit_mode_from_quick_select = {
		{ key = ";", mods = "CTRL", action = quick_select_to_copy },
		{ key = "s", action = quick_select_to_search },
		{ key = "/", action = quick_select_to_search },
		{ key = "p", action = wezterm.action.Nop }, -- 既に quick select
		{ key = "Escape", action = wezterm.action.SendKey({ key = "Escape" }) },
		{ key = "[", mods = "CTRL", action = wezterm.action.SendKey({ key = "Escape" }) },
	}

	-- CWD をクリップボードにコピーするアクション
	local copy_cwd = wezterm.action_callback(function(win, pane)
		local cwd_uri = pane:get_current_working_dir()
		if cwd_uri and cwd_uri.file_path then
			local path = cwd_uri.file_path
			win:copy_to_clipboard(path, "Clipboard")
			win:set_right_status(wezterm.format({
				{ Background = { Color = "#333333" } },
				{ Foreground = { Color = "#88cc88" } },
				{ Text = " Copied: " .. path .. " " },
			}))
			wezterm.time.call_after(2, function()
				win:set_right_status("")
			end)
		else
			win:set_right_status(wezterm.format({
				{ Background = { Color = "#333333" } },
				{ Foreground = { Color = "#cc8888" } },
				{ Text = " CWD unknown " },
			}))
			wezterm.time.call_after(2, function()
				win:set_right_status("")
			end)
		end
	end)

	-- ヘルプ項目にアクションを紐づけ
	M.help_entries = {
		{ id = "copy", label = "C-;  Copy Mode（クリーン起動）", action = activate_copy_mode_clean },
		{ id = "search", label = "s /  Search Mode", action = wezterm.action.Search("CurrentSelectionOrEmptyString") },
		{ id = "quick", label = "p    Quick Select", action = wezterm.action.QuickSelect },
		{ id = "cwd", label = "d    CWD をクリップボードにコピー", action = copy_cwd },
	}

	-- 編集モード（通常時、コピー、検索、クイック選択）
	config.key_tables.edit_mode = {
		{ key = ";", mods = "CTRL", action = activate_copy_mode_clean },
		{ key = "s", action = wezterm.action.Search("CurrentSelectionOrEmptyString") },
		{ key = "/", action = wezterm.action.Search("CurrentSelectionOrEmptyString") },
		{ key = "p", action = wezterm.action.QuickSelect },
		{ key = "d", action = copy_cwd },
		-- ヘルプ
		{ key = "?", mods = "SHIFT", action = wezterm.action_callback(function(win, pane)
			M.show_help(win, pane)
		end) },
		-- ESCでキャンセル
		{ key = "Escape", action = wezterm.action.PopKeyTable },
	}
end

--- ヘルプダイアログを表示（選択で実行）
function M.show_help(window, pane)
	local choices = {}
	for _, entry in ipairs(M.help_entries) do
		table.insert(choices, {
			id = entry.id,
			label = entry.label,
		})
	end
	window:perform_action(wezterm.action.InputSelector({
		title = "Edit Mode (Ctrl-;)",
		choices = choices,
		action = wezterm.action_callback(function(win2, pane2, id, label)
			if not id then return end
			for _, entry in ipairs(M.help_entries) do
				if entry.id == id then
					win2:perform_action(entry.action, pane2)
					return
				end
			end
		end),
	}), pane)
end

return M
