-- modules/tab_group.lua
-- タブグルーピング: 手動でタブをグループ化し、グループ内サイクルと視覚的な区別を実現
-- グループ ID は tab_title フィールドに格納（mux-server 同期、プロセスのタイトル変更に非干渉）
local wezterm = require("wezterm")

local claude_mode = require("modules.claude_mode")

local M = {}

local last_tab_count = {} -- window_id → タブ数（クリーンアップ用）

--------------------------------------------------------------------------------
-- ヘルパー関数
--------------------------------------------------------------------------------

local function hsl_to_hex(h, s, l)
	local function hue_to_rgb(p, q, t)
		if t < 0 then t = t + 1 end
		if t > 1 then t = t - 1 end
		if t < 1 / 6 then return p + (q - p) * 6 * t end
		if t < 1 / 2 then return q end
		if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
		return p
	end

	local q = l < 0.5 and l * (1 + s) or l + s - l * s
	local p = 2 * l - q
	local r = math.floor(hue_to_rgb(p, q, h + 1 / 3) * 255)
	local g = math.floor(hue_to_rgb(p, q, h) * 255)
	local b = math.floor(hue_to_rgb(p, q, h - 1 / 3) * 255)
	return string.format("#%02x%02x%02x", r, g, b)
end

--- MuxTab からグループ ID を読む
local function get_group_id(tab)
	local ok, title = pcall(function() return tab:get_title() end)
	if ok and title and title ~= "" then
		return title
	end
	return nil
end

--- TabInformation（format-tab-title のパラメータ）からグループ ID を読む
local function get_group_id_from_info(tab_info)
	local title = tab_info.tab_title
	if title and title ~= "" then
		return title
	end
	return nil
end

--- MuxTab にグループ ID を設定
local function set_group_id(tab, group_id)
	tab:set_title(group_id)
end

--- MuxTab にグループ ID を遅延設定
-- spawn_tab 直後の set_title は mux 同期のバグで CPU 100% になるため遅延させる
local function set_group_id_deferred(tab, group_id)
	wezterm.time.call_after(1, function()
		tab:set_title(group_id)
	end)
end

--- MuxTab のグループ ID をクリア
local function clear_group_id(tab)
	tab:set_title("")
end

--- グループ ID からカラーセットを生成
-- group_id は pane_id の文字列（連番）なので、黄金角で色相を分散させる
local function group_color_from_id(group_id)
	local id_num = tonumber(group_id) or 0
	local h = ((id_num * 137.508) % 360) / 360

	return {
		indicator = hsl_to_hex(h, 0.8, 0.60),
		bg_active = hsl_to_hex(h, 0.4, 0.28),
		bg_inactive = hsl_to_hex(h, 0.25, 0.12),
		fg_active = hsl_to_hex(h, 0.3, 0.90),
		fg_inactive = hsl_to_hex(h, 0.15, 0.55),
	}
end

--- MuxTab の tab_id から 0-based index を取得
local function find_tab_index(tabs, target_tab_id)
	for i, t in ipairs(tabs) do
		if t:tab_id() == target_tab_id then
			return i - 1
		end
	end
	return nil
end

--- ウィンドウ内で未使用の最小整数をグループ ID として返す
-- 黄金角の色分散は連続した小さい整数で最も良く効く
local function next_group_id(tabs)
	local used = {}
	for _, t in ipairs(tabs) do
		local gid = get_group_id(t)
		if gid then
			used[gid] = true
		end
	end
	local n = 1
	while used[tostring(n)] do
		n = n + 1
	end
	return tostring(n)
end

--------------------------------------------------------------------------------
-- アクション
--------------------------------------------------------------------------------

--- グループタブを生成（Ctrl-, t）
local function spawn_group_tab(win, pane)
	local tab = win:active_tab()
	local mux_win = win:mux_window()
	local tabs = mux_win:tabs()

	local group_id = get_group_id(tab)
	if not group_id then
		group_id = next_group_id(tabs)
	end

	-- 既存タブの set_title は spawn 前に呼ぶ（spawn 後だと mux 同期バグで CPU 100%）
	set_group_id(tab, group_id)

	local current_index = find_tab_index(tabs, tab:tab_id())
	if not current_index then return end

	local ok, domain_name = pcall(function() return pane:get_domain_name() end)
	if not ok then domain_name = "local" end

	local spawn_args = {}
	if domain_name ~= "local" and domain_name ~= "unix" then
		spawn_args.domain = { DomainName = domain_name }
	end

	local new_tab, new_pane, _ = mux_win:spawn_tab(spawn_args)
	if not new_tab then
		wezterm.log_info("tab_group: spawn_tab failed")
		return
	end

	-- 新タブの set_title は遅延実行（spawn 直後の set_title は mux 同期バグで CPU 100%）
	set_group_id_deferred(new_tab, group_id)

	local total_tabs = #mux_win:tabs()
	local target_index = current_index + 1

	if target_index < total_tabs - 1 then
		win:perform_action(wezterm.action.ActivateTab(total_tabs - 1), pane)
		win:perform_action(wezterm.action.MoveTab(target_index), pane)
	else
		win:perform_action(wezterm.action.ActivateTab(target_index), pane)
	end
end

--- グループ間サイクル（Ctrl-, Ctrl-Tab）
local function cycle_inter_group(win, pane)
	local tab = win:active_tab()
	local mux_win = win:mux_window()
	local tabs = mux_win:tabs()
	local current_group = get_group_id(tab)
	local current_tab_id = tab:tab_id()

	local current_pos = nil
	for i, t in ipairs(tabs) do
		if t:tab_id() == current_tab_id then
			current_pos = i
			break
		end
	end
	if not current_pos then return end

	local n = #tabs
	for offset = 1, n - 1 do
		local idx = ((current_pos - 1 + offset) % n) + 1
		local t_group = get_group_id(tabs[idx])
		if t_group ~= current_group then
			win:perform_action(wezterm.action.ActivateTab(idx - 1), pane)
			return
		end
	end
end

--- グループ内サイクル（Ctrl-, Ctrl-,）
local function cycle_group(win, pane)
	local tab = win:active_tab()
	local mux_win = win:mux_window()
	local tabs = mux_win:tabs()
	local group_id = get_group_id(tab)

	local group_tabs = {}
	for i, t in ipairs(tabs) do
		local t_group = get_group_id(t)
		if group_id == nil then
			if t_group == nil then
				table.insert(group_tabs, { tab = t, index = i - 1 })
			end
		else
			if t_group == group_id then
				table.insert(group_tabs, { tab = t, index = i - 1 })
			end
		end
	end

	if #group_tabs <= 1 then return end

	local current_tab_id = tab:tab_id()
	local current_pos = nil
	for i, gt in ipairs(group_tabs) do
		if gt.tab:tab_id() == current_tab_id then
			current_pos = i
			break
		end
	end

	if not current_pos then return end

	local next_pos = (current_pos % #group_tabs) + 1
	win:perform_action(wezterm.action.ActivateTab(group_tabs[next_pos].index), pane)
end

--------------------------------------------------------------------------------
-- タブ並べ替え（グループを前方に集約、野良タブは後方）
--------------------------------------------------------------------------------

--- 現在の並びで各グループの最左位置順にグループ ID を列挙
local function group_order_by_position(mux_win)
	local order = {}
	local seen = {}
	for _, t in ipairs(mux_win:tabs()) do
		local gid = get_group_id(t)
		if gid and not seen[gid] then
			seen[gid] = true
			table.insert(order, gid)
		end
	end
	return order
end

--- グループ ID の数値順にグループ ID を列挙
-- タブ並び順は GUI ごとにローカルなので、再接続時はこちらを使うと
-- どの GUI でも同じグループ順に揃う
local function group_order_by_id(mux_win)
	local order = group_order_by_position(mux_win)
	table.sort(order, function(a, b)
		local na, nb = tonumber(a), tonumber(b)
		if na and nb then return na < nb end
		if na then return true end
		if nb then return false end
		return a < b
	end)
	return order
end

--- group_order 順にグループタブを前方へ詰める（野良タブは自然に後方へ押し出される）
-- グループ内・野良タブ内の相対順序は維持。戻り値: タブ移動を行ったか
local function apply_group_order(gui_win, mux_win, group_order)
	local moved = false
	local max_iters = #mux_win:tabs() * 2
	for _ = 1, max_iters do
		local tabs = mux_win:tabs()

		-- 望ましい前方配置: group_order 順に各グループのメンバー（現在の相対順）
		local members_by_gid = {}
		for _, t in ipairs(tabs) do
			local gid = get_group_id(t)
			if gid then
				members_by_gid[gid] = members_by_gid[gid] or {}
				table.insert(members_by_gid[gid], t)
			end
		end
		local desired = {}
		for _, gid in ipairs(group_order) do
			for _, t in ipairs(members_by_gid[gid] or {}) do
				table.insert(desired, t)
			end
		end

		-- 先頭から最初の不一致を探し、そのタブを目的位置へ移動
		local mismatch = nil
		for pos, t in ipairs(desired) do
			if tabs[pos]:tab_id() ~= t:tab_id() then
				mismatch = { pos = pos, tab = t }
				break
			end
		end
		if not mismatch then return moved end

		local cur_index = find_tab_index(tabs, mismatch.tab:tab_id())
		if not cur_index then return moved end

		local pane = mismatch.tab:active_pane()
		gui_win:perform_action(wezterm.action.ActivateTab(cur_index), pane)
		gui_win:perform_action(wezterm.action.MoveTab(mismatch.pos - 1), pane)
		moved = true
	end
	return moved
end

--- 元のアクティブタブへフォーカスを戻す
local function restore_active_tab(gui_win, mux_win, active_tab_id)
	for i, tab in ipairs(mux_win:tabs()) do
		if tab:tab_id() == active_tab_id then
			gui_win:perform_action(wezterm.action.ActivateTab(i - 1), tab:active_pane())
			return
		end
	end
end

--- タブ並べ替え + グループ色再割り当て（Ctrl-, r）
local function reorder_tabs_action(win, pane)
	local mux_win = win:mux_window()
	if #mux_win:tabs() <= 1 then return end

	local active_tab_id = mux_win:active_tab():tab_id()
	local order = group_order_by_position(mux_win)

	local moved = apply_group_order(win, mux_win, order)

	-- グループ ID を左から 1, 2, ... に振り直す（黄金角の色分散を回復）
	-- 振り直しで ID が入れ替わる場合があるため、メンバーは先にスナップショットする
	local members_by_gid = {}
	for _, t in ipairs(mux_win:tabs()) do
		local gid = get_group_id(t)
		if gid then
			members_by_gid[gid] = members_by_gid[gid] or {}
			table.insert(members_by_gid[gid], t)
		end
	end
	for i, gid in ipairs(order) do
		local new_id = tostring(i)
		if gid ~= new_id then
			for _, t in ipairs(members_by_gid[gid] or {}) do
				set_group_id(t, new_id)
			end
		end
	end

	if moved then
		restore_active_tab(win, mux_win, active_tab_id)
	end
end

--- 再接続時のタブ順序復元（グループ ID 順、色の振り直しはしない）
local function reorder_on_attach(mux_win)
	if #mux_win:tabs() <= 1 then return end

	local ok, gui_win = pcall(function() return mux_win:gui_window() end)
	if not ok or not gui_win then return end

	local active_tab_id = mux_win:active_tab():tab_id()
	local moved = apply_group_order(gui_win, mux_win, group_order_by_id(mux_win))

	if moved then
		restore_active_tab(gui_win, mux_win, active_tab_id)
	end
end

--------------------------------------------------------------------------------
-- 公開 API
--------------------------------------------------------------------------------

M.help_items = {
	{ key = "t", label = "t", description = "タブグループ: 新しいタブ" },
	{ key = ",", label = "C-,", description = "タブグループ: グループ内サイクル" },
	{ key = "Tab", label = "C-Tab", description = "タブグループ: グループ間サイクル" },
	{ key = "r", label = "r", description = "タブグループ: 並べ替え+色再割り当て" },
}

--- pane_mode キーテーブルにキーを追加する
function M.apply_to_config(config)
	if config.key_tables and config.key_tables.pane_mode then
		table.insert(config.key_tables.pane_mode, {
			key = "t",
			action = wezterm.action_callback(spawn_group_tab),
		})
		table.insert(config.key_tables.pane_mode, {
			key = ",",
			mods = "CTRL",
			action = wezterm.action_callback(cycle_group),
		})
		table.insert(config.key_tables.pane_mode, {
			key = "Tab",
			mods = "CTRL",
			action = wezterm.action_callback(cycle_inter_group),
		})
		table.insert(config.key_tables.pane_mode, {
			key = "r",
			action = wezterm.action_callback(reorder_tabs_action),
		})
	end

	local pane_mode = require("modules.pane_mode")
	for _, item in ipairs(M.help_items) do
		table.insert(pane_mode.help_items, item)
	end
end

--- イベントハンドラを登録
function M.setup()
	-- タブタイトルの装飾
	wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
		local group_id = get_group_id_from_info(tab)
		local title = tab.active_pane.title or ""
		local tab_index = tab.tab_index + 1

		-- AI Mode ペインがあればスピナー + プロジェクト名を優先表示
		local ai_info = claude_mode.get_ai_pane_info(tab.tab_id)
		if ai_info then
			if ai_info.project ~= "" then
				title = ai_info.spinner .. " " .. ai_info.project
			elseif ai_info.spinner ~= "" then
				title = ai_info.spinner
			end
		end

		local display = string.format(" %d: %s ", tab_index, title)
		if #display > max_width then
			display = display:sub(1, max_width - 1) .. "…"
		end

		if group_id then
			local colors = group_color_from_id(group_id)
			if tab.is_active then
				return {
					{ Background = { Color = colors.bg_active } },
					{ Foreground = { Color = colors.indicator } },
					{ Text = "▎" },
					{ Foreground = { Color = colors.fg_active } },
					{ Text = display },
				}
			else
				return {
					{ Background = { Color = colors.bg_inactive } },
					{ Foreground = { Color = colors.indicator } },
					{ Text = "▎" },
					{ Foreground = { Color = colors.fg_inactive } },
					{ Text = display },
				}
			end
		else
			if tab.is_active then
				return {
					{ Background = { Color = "#484848" } },
					{ Foreground = { Color = "#e0e0e0" } },
					{ Text = display },
				}
			else
				return {
					{ Background = { Color = "#1a1a1a" } },
					{ Foreground = { Color = "#808080" } },
					{ Text = display },
				}
			end
		end
	end)

	-- 再接続時のグループタブ並べ替え
	wezterm.on("gui-attached", function(domain)
		wezterm.time.call_after(1, function()
			for _, mux_win in ipairs(wezterm.mux.all_windows()) do
				reorder_on_attach(mux_win)
			end
		end)
	end)

	-- 孤立グループのクリーンアップ
	wezterm.on("update-status", function(window, pane)
		if not pane then return end

		local ok, mux_win = pcall(function() return window:mux_window() end)
		if not ok or not mux_win then return end

		local win_id_ok, win_id = pcall(function() return mux_win:window_id() end)
		if not win_id_ok then return end

		local tabs = mux_win:tabs()
		local current_count = #tabs
		local prev_count = last_tab_count[win_id]
		last_tab_count[win_id] = current_count

		if prev_count and current_count < prev_count then
			local group_counts = {}
			local group_single_tab = {}
			for _, t in ipairs(tabs) do
				local gid = get_group_id(t)
				if gid then
					group_counts[gid] = (group_counts[gid] or 0) + 1
					group_single_tab[gid] = t
				end
			end

			for gid, count in pairs(group_counts) do
				if count == 1 then
					clear_group_id(group_single_tab[gid])
				end
			end
		end
	end)
end

return M
