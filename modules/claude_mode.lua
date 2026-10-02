-- modules/claude_mode.lua
-- AI Helper 検出・モード切替（Claude Code, Codex 対応）
local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

-- デバッグモード（true: オン, false: オフ）
M.DEBUG = false

-- AI ペイン情報キャッシュ: tab_id → { spinner = "⠋", project = "wezterm" } or nil
local ai_pane_cache = {}

local function utf8_first_char(s)
	if not s or s == "" then return "" end
	local b = s:byte(1)
	if b < 0x80 then return s:sub(1, 1)
	elseif b < 0xE0 then return s:sub(1, 2)
	elseif b < 0xF0 then return s:sub(1, 3)
	else return s:sub(1, 4)
	end
end

function M.get_ai_pane_info(tab_id)
	return ai_pane_cache[tab_id]
end

-- 外部から注入されるキー定義
M.inherited_keys = {}

-- 通知管理オブジェクト
local notification = {
	timer = nil,

	-- 通知を表示
	show = function(self, window, message, duration)
		-- 既存のタイマーがあればキャンセル
		if self.timer then
			wezterm.time.cancel_timer(self.timer)
		end

		-- ステータスバーに表示
		window:set_right_status(wezterm.format({
			{ Background = { Color = "#333333" } },
			{ Foreground = { Color = "#cccccc" } },
			{ Text = " " .. message .. " " },
		}))

		-- 指定時間後に通知を消す
		self.timer = wezterm.time.call_after(duration or 1.5, function()
			window:set_right_status("")
			self.timer = nil
		end)
	end,

	-- 通知をクリア
	clear = function(self, window)
		if self.timer then
			wezterm.time.cancel_timer(self.timer)
			self.timer = nil
		end
		window:set_right_status("")
	end,
}

--- claude/codexプロセスの検出
-- user_varsを使用してシェルから通知されたプロセス情報を取得
local function is_ai_helper_running(pane)
	-- paneの有効性をチェック
	if not pane then
		if M.DEBUG then
			wezterm.log_info("is_ai_helper_running: pane is nil")
		end
		return false
	end

	-- get_user_vars()の呼び出しをpcallでラップ
	-- (muxにpaneが登録されていない場合などにエラーが発生する可能性がある)
	local success, user_vars = pcall(function()
		return pane:get_user_vars()
	end)

	if not success or not user_vars then
		if M.DEBUG then
			wezterm.log_info("is_ai_helper_running: get_user_vars() failed or returned nil")
		end
		return false
	end

	local ai_helper = user_vars.WEZTERM_AI_HELPER

	if M.DEBUG then
		wezterm.log_info("is_ai_helper_running: WEZTERM_AI_HELPER=" .. tostring(ai_helper))
	end

	-- ai_helperが設定されていて、空文字列でない場合
	if ai_helper and ai_helper ~= "" then
		if M.DEBUG then
			wezterm.log_info("is_ai_helper_running: AI helper detected: " .. ai_helper)
		end
		return true
	end

	return false
end

--- 他のモードへのキーを追加（外部から注入）
---@param keys table[] キー定義の配列
function M.add_inherited_keys(keys)
	for _, key in ipairs(keys) do
		table.insert(M.inherited_keys, key)
	end
end

--- 設定に claude_mode を適用する
---@param config table wezterm config オブジェクト
function M.apply_to_config(config)
	config.key_tables = config.key_tables or {}

	-- claude_mode キーテーブルを構築
	local claude_mode_keys = {
		{
			key = "Enter",
			mods = "NONE",
			action = wezterm.action.SendString("\n"), -- LF (0x0a)
		},
		{
			key = "Enter",
			mods = "SHIFT",
			action = wezterm.action.SendString("\r"), -- CR (0x0d)
		},
		{
			key = "Enter",
			mods = "CTRL",
			action = wezterm.action.SendString("\r"), -- CR (0x0d)
		},
		-- Ctrl-B → LeftArrow（Claude Code バグ #21008 暫定対処）
		{
			key = "b",
			mods = "CTRL",
			action = wezterm.action.SendKey({ key = "LeftArrow" }),
		},
		-- 設定リロード（claude_mode 中でも使えるように）
		{
			key = "R",
			mods = "CTRL|SHIFT",
			action = wezterm.action.ReloadConfiguration,
		},
	}

	-- 継承されたキーを追加
	for _, key in ipairs(M.inherited_keys) do
		table.insert(claude_mode_keys, key)
	end

	config.key_tables.claude_mode = claude_mode_keys
end

--- update-status イベントで claude_mode を切り替えるハンドラを登録
function M.setup_update_status()
	wezterm.on("update-status", function(window, pane)
		-- paneの有効性をチェック
		if not pane then
			return
		end

		-- AI ペイン情報キャッシュを更新（全タブ・全ペインを走査）
		local scan_ok, mux_win = pcall(function() return window:mux_window() end)
		if scan_ok and mux_win then
			for _, tab in ipairs(mux_win:tabs()) do
				local tab_id = tab:tab_id()
				local found = nil
				for _, p in ipairs(tab:panes()) do
					local uv_ok, uvars = pcall(function() return p:get_user_vars() end)
					if uv_ok and uvars and uvars.WEZTERM_AI_HELPER and uvars.WEZTERM_AI_HELPER ~= "" then
						local p_title = p:get_title() or ""
						local spinner = utf8_first_char(p_title)

						local cwd_ok, cwd_url = pcall(function() return p:get_current_working_dir() end)
						local project = ""
						if cwd_ok and cwd_url then
							local path = cwd_url.file_path or ""
							project = path:match("([^/]+)/?$") or path
						end

						found = { spinner = spinner, project = project }
						break
					end
				end
				ai_pane_cache[tab_id] = found
			end
		end

		local active_table = window:active_key_table()
		local is_ai_helper = is_ai_helper_running(pane)

		-- 特定のモード中は干渉しない
		-- - overlay系（copy_mode, search_mode, quick_select）
		-- - pane_mode, edit_mode*（一時的なキーテーブル）
		local should_skip = active_table
			and (
				active_table:find("copy_mode") -- copy modeの正確な名前
				or active_table:find("search_mode") -- search modeの正確な名前
				or active_table:find("quick_select") -- quick selectモード
				or active_table == "pane_mode" -- ペイン操作モード
				or active_table:find("edit_mode") -- 編集モード（edit_mode, edit_mode_from_*）
			)

		if should_skip then
			-- これらのモード中は何もしない（通知も出さない）
			return
		end

		if is_ai_helper then
			-- claude_modeがアクティブでない場合のみ有効化
			if active_table ~= "claude_mode" then
				wezterm.log_info("Activating claude_mode")
				window:perform_action(
					act.ActivateKeyTable({
						name = "claude_mode",
						replace_current = true,
						one_shot = false,
						until_unknown = false,
					}),
					pane
				)
				-- claude modeに切り替わった時の通知
				notification:show(window, "AI Mode", 1.5)
			end
		else
			-- claude_modeがアクティブな場合のみクリア
			if active_table == "claude_mode" then
				wezterm.log_info("Clearing key table stack")
				window:perform_action(act.ClearKeyTableStack, pane)
				-- 通常モードに戻った時の通知
				notification:show(window, "Normal Mode", 1.5)
			end
		end
	end)
end

return M
