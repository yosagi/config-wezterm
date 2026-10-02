-- modules/commands.lua
-- Command Palette 拡張
local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

--- Command Palette にペイン操作コマンドを追加するイベントを設定
function M.setup()
	wezterm.on("augment-command-palette", function(window, pane)
		return {
			{
				brief = "Pane: ← 左へ移動 (Ctrl+, h)",
				icon = "md_arrow_left",
				action = act.ActivatePaneDirection("Left"),
			},
			{
				brief = "Pane: → 右へ移動 (Ctrl+, l)",
				icon = "md_arrow_right",
				action = act.ActivatePaneDirection("Right"),
			},
			{
				brief = "Pane: ↓ 下へ移動 (Ctrl+, j)",
				icon = "md_arrow_down",
				action = act.ActivatePaneDirection("Down"),
			},
			{
				brief = "Pane: ↑ 上へ移動 (Ctrl+, k)",
				icon = "md_arrow_up",
				action = act.ActivatePaneDirection("Up"),
			},
			{
				brief = "Pane: ↻ 次へ移動 (Ctrl+, w)",
				icon = "md_rotate_right",
				action = act.ActivatePaneDirection("Next"),
			},
			{
				brief = "Pane: │ 縦分割 (Ctrl+, v)",
				icon = "md_arrow_split_vertical",
				action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }),
			},
			{
				brief = "Pane: ─ 横分割 (Ctrl+, s)",
				icon = "md_arrow_split_horizontal",
				action = act.SplitVertical({ domain = "CurrentPaneDomain" }),
			},
			{
				brief = "Pane: ✕ 閉じる (Ctrl+, c)",
				icon = "md_close",
				action = act.CloseCurrentPane({ confirm = false }),
			},
		}
	end)
end

return M
