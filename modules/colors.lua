-- modules/colors.lua
-- ホスト別背景色
local wezterm = require("wezterm")

local M = {}

--- ホスト名から背景色を生成する
-- 元の背景色をベースに、ホスト名のハッシュで色相を変える
---@param hostname string ホスト名
---@param is_focused boolean|nil フォーカス状態（nilはtrue扱い）
---@return string 背景色（#RRGGBB形式）
function M.generate_background_for_host(hostname, is_focused)
	-- ホスト名の簡易ハッシュ
	local hash = 0
	for i = 1, #hostname do
		hash = (hash * 31 + string.byte(hostname, i)) % 360
	end
	hash = (hash + 40) % 360

	-- HSL → RGB 変換
	-- フォーカスなしのときは彩度・明度を上げて、透過による色の薄まりを補償
	local h = hash / 360
	local s, l
	if is_focused == false then
		s = 0.5
		l = 0.20
	else
		s = 0.2
		l = 0.12
	end

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

	return string.format("#%02x%02x%02x", r, g, b)
end

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
			local bg_color = M.generate_background_for_host(hostname, is_focused)
			local overrides = window:get_config_overrides() or {}

			-- 更新が必要か判定
			local need_update = false
			overrides.colors = overrides.colors or {}

			-- 背景色（ホスト名ベース、フォーカスなしのときは彩度・明度を補償）
			if overrides.colors.background ~= bg_color then
				overrides.colors.background = bg_color
				need_update = true
			end

			-- ウィンドウの透過度: フォーカスがないウィンドウは半透明に
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
