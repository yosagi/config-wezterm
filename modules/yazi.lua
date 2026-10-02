-- modules/yazi.lua
-- yazi + sftp によるリモートファイル転送
-- キーバインドで yazi を起動し、リモート(sftp)とローカルの2タブ構成でファイル転送を可能にする
-- 依存モジュール: なし（他モジュールへの依存なしで共有可能）
local wezterm = require("wezterm")

local M = {}

-- デフォルト設定
local defaults = {
	remote_host_var = "REMOTE_HOST",
	remote_cwd_var = "REMOTE_CWD",
}

-- 現在の設定（apply_to_config で上書きされる）
local opts = {}

-- ホスト → yazi ペインID のマッピング（CWD 同期時のフォーカス移動用）
local yazi_pane_ids = {}

--------------------------------------------------------------------------------
-- ヘルパー関数
--------------------------------------------------------------------------------

--- 数値を整数文字列に変換（Lua の double は tostring で ".0" が付くため）
local function int_to_str(n)
	return string.format("%d", n)
end

--- ホスト名から client-id 用のハッシュ値を生成
--- Lua の number は double なので 53bit の精度がある
local function hostname_to_client_id(hostname)
	local hash = 5381
	for i = 1, #hostname do
		hash = ((hash * 33) + string.byte(hostname, i)) % (2 ^ 53)
	end
	if hash == 0 then
		hash = 1
	end
	return hash
end

--- ペインからリモート情報を取得
---@return string|nil host リモートホスト名
---@return string|nil cwd リモートのカレントディレクトリ
local function get_remote_info(pane)
	local ok, user_vars = pcall(function()
		return pane:get_user_vars()
	end)
	if not ok or not user_vars then
		return nil, nil
	end

	local host = user_vars[opts.remote_host_var]
	local cwd = user_vars[opts.remote_cwd_var]

	if not host or host == "" then
		return nil, nil
	end

	return host, cwd or "/"
end

--- sftp URL を構築
--- yazi の sftp URL は絶対パスの場合 sftp://host//path の形式（スラッシュ2つ）
local function build_sftp_url(host, path)
	return "sftp://" .. host .. "/" .. (path or "/")
end

--- 通知を表示（右ステータスバーに一時表示）
local function notify(window, message)
	window:set_right_status(wezterm.format({
		{ Background = { Color = "#333333" } },
		{ Foreground = { Color = "#cccccc" } },
		{ Text = " " .. message .. " " },
	}))
	wezterm.time.call_after(2, function()
		window:set_right_status("")
	end)
end

--- 指定ペインIDを含む GUI ウィンドウにフォーカスを移す（OS レベル）
--- activate-pane は mux レベルのフォーカスのみなので、ウィンドウの前面化はこちらで行う
---@param target_pane_id number
---@return boolean 成功したかどうか
local function focus_window_by_pane_id(target_pane_id)
	local ok, gui_windows = pcall(wezterm.gui.gui_windows)
	if not ok or not gui_windows then
		return false
	end
	for _, gui_win in ipairs(gui_windows) do
		for _, tab in ipairs(gui_win:mux_window():tabs()) do
			for _, pane_info in ipairs(tab:panes_with_info()) do
				if pane_info.pane:pane_id() == target_pane_id then
					gui_win:focus()
					return true
				end
			end
		end
	end
	return false
end

--- ya emit-to で CWD 変更を送信
--- 成功すれば yazi が起動済みということ
---@return boolean 成功したかどうか
local function ya_emit_cd(client_id, sftp_url, tab_index)
	local ok, stdout, stderr = wezterm.run_child_process({
		"ya",
		"emit-to",
		int_to_str(client_id),
		"cd",
		"--str",
		sftp_url,
		"--tab",
		int_to_str(tab_index),
	})
	if not ok then
		wezterm.log_info("ya emit-to failed (instance not running?): " .. tostring(stderr))
	end
	return ok
end

--------------------------------------------------------------------------------
-- Window 方式
-- 別ウィンドウで yazi を起動（ローカル domain）
-- 同じホストの複数ペインが1つの yazi を共有
-- client-id = ホスト名のハッシュ
--------------------------------------------------------------------------------

local function yazi_window_action(window, pane)
	local host, cwd = get_remote_info(pane)
	if not host then
		notify(window, "yazi: リモートホスト未検出")
		return
	end

	local client_id = hostname_to_client_id(host)
	local sftp_url = build_sftp_url(host, cwd)

	-- まず CWD 同期を試みる（yazi が起動済みなら成功する）
	if ya_emit_cd(client_id, sftp_url, 0) then
		-- 保存済みのペインIDで yazi ウィンドウにフォーカスを移す
		local yazi_pane_id = yazi_pane_ids[host]
		if yazi_pane_id then
			-- mux レベル: ペイン/タブのアクティベーション
			wezterm.run_child_process({
				"wezterm", "cli", "activate-pane",
				"--pane-id", int_to_str(yazi_pane_id),
			})
			-- OS レベル: ウィンドウの前面化
			focus_window_by_pane_id(yazi_pane_id)
		end
		notify(window, "yazi: CWD → " .. host .. ":" .. cwd)
		return
	end

	-- yazi が起動していない → 古いマッピングをクリア
	yazi_pane_ids[host] = nil

	-- 新規ウィンドウで起動（ローカルで）、ペインIDを取得して保存
	local home = os.getenv("HOME") or "~"
	local ok, stdout, stderr = wezterm.run_child_process({
		"wezterm", "cli", "spawn", "--new-window",
		"--domain-name", "local",
		"--",
		"yazi", "--client-id", int_to_str(client_id),
		sftp_url, home,
	})
	if ok then
		local pane_id = tonumber(stdout:match("(%d+)"))
		if pane_id then
			yazi_pane_ids[host] = pane_id
		end
	else
		wezterm.log_info("yazi spawn failed: " .. tostring(stderr))
	end
	notify(window, "yazi: " .. host .. " (ウィンドウ)")
end

--------------------------------------------------------------------------------
-- 公開 API
--------------------------------------------------------------------------------

--- edit_mode に追加するキー定義を返す
---@return table[] キー定義の配列
function M.get_edit_mode_keys()
	return {
		{
			key = "y",
			action = wezterm.action_callback(yazi_window_action),
		},
	}
end

--- 設定に yazi モジュールを適用する
--- edit_mode.apply_to_config() の後に呼ぶこと
---@param config table wezterm config オブジェクト
---@param user_opts table|nil オプション
function M.apply_to_config(config, user_opts)
	-- オプションのマージ
	opts = {}
	for k, v in pairs(defaults) do
		opts[k] = v
	end
	if user_opts then
		for k, v in pairs(user_opts) do
			opts[k] = v
		end
	end

	-- edit_mode キーテーブルにキーを追加
	if config.key_tables and config.key_tables.edit_mode then
		for _, key in ipairs(M.get_edit_mode_keys()) do
			table.insert(config.key_tables.edit_mode, key)
		end
	end

	-- edit_mode のヘルプにも追加
	local edit_mode = require("modules.edit_mode")
	table.insert(edit_mode.help_entries, {
		id = "yazi",
		label = "y    yazi（リモートファイル転送）",
		action = wezterm.action_callback(yazi_window_action),
	})
end

return M
