-- modules/events.lua
-- その他のイベントハンドラ（format-window-title, window-config-reloaded）
local wezterm = require("wezterm")

local M = {}

--- イベントハンドラを設定する
function M.setup()
	-- ウィンドウタイトルにドメイン名を表示
	wezterm.on("format-window-title", function(tab, pane, tabs, panes, config)
		local domain = pane.domain_name or "local"
		local title = tab.active_pane.title or "wezterm"

		-- mux経由でworkspaceを取得
		local mux = wezterm.mux
		local workspace = mux.get_active_workspace() or "default"

		return string.format("[%s] %s - %s", domain, workspace, title)
	end)
end

return M
