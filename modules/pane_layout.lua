-- modules/pane_layout.lua
-- F1/F2/F3/F4 ペインレイアウト、Ctrl+Shift+D
local wezterm = require("wezterm")
local utils = require("modules.utils")

local M = {}

-- モジュール内で保持する initial_cols / initial_rows（apply_to_config で設定）
local initial_cols = 100
local initial_rows = 50

--- ウィンドウをセル数指定でリサイズする（高さは initial_rows に合わせる）
--- セルのピクセル寸法とタブ外の領域（スクロールバー、タブバー等）はアクティブタブから求める
---@param win table wezterm window オブジェクト
---@param target_cols number 目標の列数
local function set_window_cells(win, target_cols)
	local tab_size = win:active_tab():get_size()
	local dims = win:get_dimensions()
	local pixels_per_col = tab_size.pixel_width / tab_size.cols
	local pixels_per_row = tab_size.pixel_height / tab_size.rows
	local extra_width = dims.pixel_width - tab_size.pixel_width
	local extra_height = dims.pixel_height - tab_size.pixel_height
	win:set_inner_size(
		math.floor(target_cols * pixels_per_col) + extra_width,
		math.floor(initial_rows * pixels_per_row) + extra_height
	)
end

--- 横ペイン数に応じた列数（各ペイン initial_cols + セパレーター）
local function cols_for(horizontal_count)
	return initial_cols * horizontal_count + (horizontal_count - 1)
end

--- ウィンドウ内の全タブのうち、最も多い横ペイン数を返す
--- ウィンドウのサイズは全タブ共通なので、カレントタブだけで決めると他の分割タブが潰れる
---@param win table wezterm window オブジェクト
---@return number 横ペイン数の最大値
local function max_horizontal_count(win)
	local max_count = 1
	for _, tab in ipairs(win:mux_window():tabs()) do
		max_count = math.max(max_count, utils.get_horizontal_pane_count(tab))
	end
	return max_count
end

--- ウィンドウ内の全タブに合うサイズにする（最も横ペインが多いタブ基準、高さは initial_rows）
--- どのタブも1ペインなら ResetFontAndWindowSize（フォント倍率も戻す）
---@param win table wezterm window オブジェクト
---@param pane table wezterm pane オブジェクト
---@param min_count number|nil 横ペイン数の下限（Shift-F1 の倍幅用）
local function fit_window_to_tabs(win, pane, min_count)
	local count = math.max(max_horizontal_count(win), min_count or 1)
	if count <= 1 then
		win:perform_action(wezterm.action.ResetFontAndWindowSize, pane)
	else
		set_window_cells(win, cols_for(count))
	end
end

--- ウィンドウ幅調整 + ペイン均等化の共通処理
---@param win table wezterm window オブジェクト
---@param pane table wezterm pane オブジェクト
---@param double_width_for_single boolean シングルペイン時に倍幅にするか
local function resize_and_equalize(win, pane, double_width_for_single)
	local tab = win:active_tab()
	local horizontal_count = utils.get_horizontal_pane_count(tab)

	-- ウィンドウサイズは全タブの最大横ペイン数で決める（Shift-F1 はシングルペインでも倍幅以上）
	local min_count = (double_width_for_single and horizontal_count <= 1) and 2 or 1
	fit_window_to_tabs(win, pane, min_count)

	if horizontal_count <= 1 then
		return -- シングルペインなので均等化は不要
	end

	-- ペイン均等化（アクティブペインが属するグループ）
	local panes_info = tab:panes_with_info()
	if #panes_info < 2 then
		return
	end

	-- 各ペインの left 位置でグループ化
	local left_positions = {}
	for _, info in ipairs(panes_info) do
		left_positions[info.left] = left_positions[info.left] or {}
		table.insert(left_positions[info.left], info)
	end

	-- 左から順にソート
	local sorted_lefts = {}
	for left, _ in pairs(left_positions) do
		table.insert(sorted_lefts, left)
	end
	table.sort(sorted_lefts)

	-- 横方向の均等化（2グループ以上ある場合）
	if #sorted_lefts >= 2 then
		local widths = {}
		local total_width_eq = 0
		for _, left in ipairs(sorted_lefts) do
			local w = left_positions[left][1].width
			table.insert(widths, w)
			total_width_eq = total_width_eq + w
		end
		local target_width_eq = math.floor(total_width_eq / #sorted_lefts)

		-- アクティブペインのグループを特定
		local active_group_idx = nil
		for i, left in ipairs(sorted_lefts) do
			for _, info in ipairs(left_positions[left]) do
				if info.is_active then
					active_group_idx = i
					break
				end
			end
			if active_group_idx then
				break
			end
		end

		if active_group_idx then
			local current_width = widths[active_group_idx]
			local diff = current_width - target_width_eq

			if math.abs(diff) > 1 then
				local direction
				if active_group_idx == 1 then
					direction = diff > 0 and "Left" or "Right"
				else
					direction = diff > 0 and "Right" or "Left"
				end
				win:perform_action(wezterm.action.AdjustPaneSize({ direction, math.abs(diff) }), pane)
			end
		end
	end

	-- 縦方向の均等化（アクティブペインが属する縦グループ）
	for _, panes_at_left in pairs(left_positions) do
		if #panes_at_left >= 2 then
			table.sort(panes_at_left, function(a, b)
				return a.top < b.top
			end)

			-- アクティブペインがこのグループにいるか
			local active_idx = nil
			for i, info in ipairs(panes_at_left) do
				if info.is_active then
					active_idx = i
					break
				end
			end

			if active_idx then
				local total_height = 0
				for _, info in ipairs(panes_at_left) do
					total_height = total_height + info.height
				end
				local target_height = math.floor(total_height / #panes_at_left)

				local diff = panes_at_left[active_idx].height - target_height
				if math.abs(diff) > 1 then
					local direction
					if active_idx == 1 then
						direction = diff > 0 and "Up" or "Down"
					else
						direction = diff > 0 and "Down" or "Up"
					end
					win:perform_action(wezterm.action.AdjustPaneSize({ direction, math.abs(diff) }), pane)
				end
			end
		end
	end
end

--- 設定に pane_layout キーバインドを適用する
---@param config table wezterm config オブジェクト
function M.apply_to_config(config)
	config.keys = config.keys or {}

	-- config.initial_cols を取得（設定されていなければデフォルト値を使用）
	initial_cols = config.initial_cols or 100
	initial_rows = config.initial_rows or 50

	-- F1: ウィンドウ幅調整 + ペイン均等化（アクティブペインのグループ）
	-- 単一ペインの場合はデフォルトサイズにリセット
	table.insert(config.keys, {
		key = "F1",
		mods = "NONE",
		action = wezterm.action_callback(function(win, pane)
			resize_and_equalize(win, pane, false)
		end),
	})

	-- Shift-F1: ウィンドウ幅調整 + ペイン均等化
	-- 単一ペインの場合でも倍幅（2ペイン分）にリサイズ
	table.insert(config.keys, {
		key = "F1",
		mods = "SHIFT",
		action = wezterm.action_callback(function(win, pane)
			resize_and_equalize(win, pane, true)
		end),
	})

	-- F2: ウィンドウ幅を2倍にして横2分割（各ペインが initial_cols を維持、1ペイン時のみ動作）
	table.insert(config.keys, {
		key = "F2",
		mods = "NONE",
		action = wezterm.action_callback(function(win, pane)
			local tab = win:active_tab()
			local panes = tab:panes()

			-- 2ペイン以上ある場合は何もしない
			if #panes >= 2 then
				return
			end

			local tab_size = tab:get_size()
			local dims = win:get_dimensions()

			-- スクロールバー等の非文字表示領域の幅
			local scrollbar_width = dims.pixel_width - tab_size.pixel_width
			local pixels_per_col = tab_size.pixel_width / tab_size.cols

			-- 目標: 左右 initial_cols + セパレーター1
			local target_cols = initial_cols * 2 + 1
			local target_width = math.floor(target_cols * pixels_per_col) + scrollbar_width

			win:set_inner_size(target_width, dims.pixel_height)
			-- リサイズ完了を待ってから分割（set_inner_sizeは非同期のため）
			wezterm.time.call_after(0.1, function()
				pane:split({ direction = "Right", size = 0.5 })
			end)
		end),
	})

	-- F3: L字型3ペインレイアウト（左1 + 右上下2）+ 比率サイクル
	-- 1ペイン/2ペイン → 3ペイン作成
	-- 3ペイン（右にフォーカス）→ 右側の比率サイクル: 1:1 → 1:4 → 4:1 → 1:1
	table.insert(config.keys, {
		key = "F3",
		mods = "NONE",
		action = wezterm.action_callback(function(win, pane)
			local tab = win:active_tab()
			local panes_info = tab:panes_with_info()
			local pane_count = #panes_info

			if pane_count == 1 then
				-- 1ペイン: ウィンドウ幅拡大 + 横分割 + 右を上下分割
				local tab_size = tab:get_size()
				local dims = win:get_dimensions()

				local scrollbar_width = dims.pixel_width - tab_size.pixel_width
				local pixels_per_col = tab_size.pixel_width / tab_size.cols

				local target_cols = initial_cols * 2 + 1
				local target_width = math.floor(target_cols * pixels_per_col) + scrollbar_width

				win:set_inner_size(target_width, dims.pixel_height)
				wezterm.time.call_after(0.1, function()
					local new_pane = pane:split({ direction = "Right", size = 0.5 })
					wezterm.time.call_after(0.1, function()
						new_pane:split({ direction = "Bottom", size = 0.5 })
					end)
				end)
			elseif pane_count == 2 then
				-- 2ペイン: 右ペインを上下分割
				local right_pane = nil
				local max_left = -1

				for _, info in ipairs(panes_info) do
					if info.left > max_left then
						max_left = info.left
						right_pane = info.pane
					end
				end

				if right_pane then
					right_pane:split({ direction = "Bottom", size = 0.5 })
				end
			elseif pane_count == 3 then
				-- 3ペイン: 右側の比率サイクル（右ペインにフォーカス時のみ）
				local right_panes = {}
				local active_is_right = false
				for _, info in ipairs(panes_info) do
					if info.left > 0 then
						table.insert(right_panes, info)
						if info.is_active then
							active_is_right = true
						end
					end
				end

				-- 右側が2ペインでない、またはアクティブが右側でない場合は何もしない
				if #right_panes ~= 2 or not active_is_right then
					return
				end

				-- top でソート（上が先）
				table.sort(right_panes, function(a, b)
					return a.top < b.top
				end)

				local top_pane = right_panes[1]
				local bottom_pane = right_panes[2]
				local total_height = top_pane.height + bottom_pane.height

				-- 現在の比率を判定（上ペインの割合）
				local top_ratio = top_pane.height / total_height

				-- 次の比率を決定: 1:1 → 1:4 → 4:1 → 1:1
				local target_top_ratio
				if top_ratio > 0.6 then
					target_top_ratio = 0.5  -- 4:1 → 1:1
				elseif top_ratio < 0.4 then
					target_top_ratio = 0.8  -- 1:4 → 4:1
				else
					target_top_ratio = 0.2  -- 1:1 → 1:4
				end

				local target_top_height = math.floor(total_height * target_top_ratio)
				local diff = target_top_height - top_pane.height

				if math.abs(diff) <= 1 then
					return
				end

				-- 上下どちらがアクティブでも同じ方向で動作
				local direction = diff > 0 and "Down" or "Up"
				local amount = math.abs(diff)

				win:perform_action(wezterm.action.AdjustPaneSize({ direction, amount }), pane)
			end
			-- 4ペイン以上: 何もしない
		end),
	})

	-- F4: （予約: 将来の拡張用）

	-- Ctrl+Shift+D: ペインを閉じてペイン数に応じたサイズに調整（分割時のみ動作）
	table.insert(config.keys, {
		key = "D",
		mods = "CTRL|SHIFT",
		action = wezterm.action_callback(function(win, pane)
			local tab = win:active_tab()
			local panes = tab:panes()
			if #panes > 1 then
				win:perform_action(wezterm.action.CloseCurrentPane({ confirm = false }), pane)
				-- ペインが閉じた後に少し遅延してリサイズ
				wezterm.time.call_after(0.1, function()
					-- 残ったタブ構成（全タブの最大横ペイン数）に合わせてリサイズ
					fit_window_to_tabs(win, win:active_pane())
				end)
			end
		end),
	})
end

return M
