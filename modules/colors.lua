-- modules/colors.lua
-- ホスト別背景色
local wezterm = require("wezterm")

local M = {}

--- ホスト名から色を生成する
-- ホスト名のハッシュで色相を決め、彩度・明度は呼び出し側が指定する
---@param hostname string ホスト名
---@param s number 彩度（0-1）
---@param l number 明度（0-1）
---@param alpha number|nil 不透明度（0-1）。指定すると rgba() 形式で返す（#RRGGBBAA は解析されない）
---@return string 色（#RRGGBB または rgba(...) 形式）
function M.host_color(hostname, s, l, alpha)
	-- ホスト名の簡易ハッシュ
	local hash = 0
	for i = 1, #hostname do
		hash = (hash * 31 + string.byte(hostname, i)) % 360
	end
	hash = (hash + 40) % 360

	-- HSL → RGB 変換
	local h = hash / 360

	local function hue_to_rgb(p, q, t)
		if t < 0 then
			t = t + 1
		end
		if t > 1 then
			t = t - 1
		end
		if t < 1 / 6 then
			return p + (q - p) * 6 * t
		end
		if t < 1 / 2 then
			return q
		end
		if t < 2 / 3 then
			return p + (q - p) * (2 / 3 - t) * 6
		end
		return p
	end

	local q = l < 0.5 and l * (1 + s) or l + s - l * s
	local p = 2 * l - q
	local r = math.floor(hue_to_rgb(p, q, h + 1 / 3) * 255)
	local g = math.floor(hue_to_rgb(p, q, h) * 255)
	local b = math.floor(hue_to_rgb(p, q, h - 1 / 3) * 255)

	if alpha then
		return string.format("rgba(%d,%d,%d,%.2f)", r, g, b, alpha)
	end
	return string.format("#%02x%02x%02x", r, g, b)
end

--- ホスト名から背景色を生成する
-- フォーカス状態では変えない。colors はペインのパレットとして mux-server に送られ、
-- 同じペインに接続している他のクライアントにも配られてしまうため
---@param hostname string ホスト名
---@return string 背景色（#RRGGBB形式）
function M.generate_background_for_host(hostname)
	return M.host_color(hostname, 0.2, 0.12)
end

-- ホスト色をどこに出すか（比較用の切り替え）
local TITLEBAR_TINT = true -- タブバーの地の色
local BORDER_TOP = false -- ウィンドウ上端の帯

--- ホスト色を出すタブバーまわりの設定（window_frame はパレットに含まれず GUI ローカル）
-- タブバーの地の色は wezterm がフォーカスに応じて active / inactive を切り替える
-- タブバーには window_background_opacity が掛からないので、透過は色のアルファで指定する
-- 上端の帯はフォーカスを見て Lua 側で切り替える
---@param hostname string ホスト名
---@param is_focused boolean フォーカス状態
---@return table window_frame
function M.window_frame_for_host(hostname, is_focused)
	local frame = {}
	if BORDER_TOP then
		frame.border_top_height = "4px"
		frame.border_top_color = is_focused and M.host_color(hostname, 0.35, 0.3) or M.host_color(hostname, 0.7, 0.5)
	end
	if TITLEBAR_TINT then
		-- 明度は既定の #333333 と同じ 0.2 に留め、アクティブタブ（#484848）との差を保つ
		frame.active_titlebar_bg = M.host_color(hostname, 0.3, 0.2)
		frame.inactive_titlebar_bg = M.host_color(hostname, 0.6, 0.3, 0.7)
	end
	return frame
end

-- window_id → 最後に設定した window_frame の署名
-- window_frame は get_config_overrides で読み戻すと値の表現が変わりうるので、自前で覚えておく
local applied_frame = {}

--- update-status イベントで背景色を設定するハンドラを登録
function M.setup_update_status()
	wezterm.on("update-status", function(window, pane)
		-- paneの有効性をチェック
		if not pane then
			return
		end

		-- ドメインに応じてウィンドウの背景色を設定
		-- paneがmuxに登録されていない場合（接続直後など）はエラーになるので pcall でラップ
		local ok, domain_name = pcall(function()
			return pane:get_domain_name()
		end)
		if not ok then
			return
		end

		-- TermWizTerminalDomain はウィンドウ作成直後の一時的な状態なのでスキップ
		if domain_name == "TermWizTerminalDomain" then
			return
		end

		-- ドメインに応じてホスト名を取得
		local hostname = nil
		if domain_name then
			-- SSHMUX:hostname 形式から抽出
			hostname = domain_name:match("^SSHMUX:(.+)$")
			-- unix または local ドメインの場合はローカルホスト名を使用
			if not hostname and (domain_name == "unix" or domain_name == "local") then
				hostname = wezterm.hostname()
			end
			-- 大文字小文字を正規化（同じホストで色が変わらないように）
			if hostname then
				hostname = hostname:lower()
			end
		end

		-- ホスト名に応じた背景色を設定
		if hostname then
			local is_focused = window:is_focused()
			local bg_color = M.generate_background_for_host(hostname)
			local overrides = window:get_config_overrides() or {}

			-- 更新が必要か判定
			local need_update = false
			overrides.colors = overrides.colors or {}

			-- 背景色（ホスト名ベース）
			if overrides.colors.background ~= bg_color then
				overrides.colors.background = bg_color
				need_update = true
			end

			-- タブバーの地の色と上端の帯にホスト色を出す
			local frame = M.window_frame_for_host(hostname, is_focused)
			local frame_sig = (frame.active_titlebar_bg or "")
				.. (frame.inactive_titlebar_bg or "")
				.. (frame.border_top_color or "")
			local window_id = window:window_id()
			if applied_frame[window_id] ~= frame_sig then
				overrides.window_frame = frame
				applied_frame[window_id] = frame_sig
				need_update = true
			end

			-- ウィンドウの透過度: フォーカスがないウィンドウは半透明に
			-- 透過度は GUI ローカルで、mux 越しに他のクライアントへは伝わらない
			local target_opacity = is_focused and 1.0 or 0.7
			if overrides.window_background_opacity ~= target_opacity then
				overrides.window_background_opacity = target_opacity
				need_update = true
			end

			-- 非アクティブペインの暗さ（ウィンドウのフォーカス状態に関わらず常に適用）
			local target_hsb = { saturation = 0.8, brightness = 0.4 }
			if
				not overrides.inactive_pane_hsb
				or overrides.inactive_pane_hsb.brightness ~= target_hsb.brightness
			then
				overrides.inactive_pane_hsb = target_hsb
				need_update = true
			end

			if need_update then
				window:set_config_overrides(overrides)
			end
		end
	end)
end

return M
