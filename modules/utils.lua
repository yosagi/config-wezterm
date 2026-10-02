-- modules/utils.lua
-- 共有ヘルパー関数
local M = {}

--- 横方向のペイン列数を取得する
---@param tab table wezterm Tab オブジェクト
---@return number 横方向のペイン列数
function M.get_horizontal_pane_count(tab)
	local panes_info = tab:panes_with_info()
	local unique_left_positions = {}

	for _, info in ipairs(panes_info) do
		unique_left_positions[info.left] = true
	end

	local count = 0
	for _ in pairs(unique_left_positions) do
		count = count + 1
	end

	return count
end

return M
