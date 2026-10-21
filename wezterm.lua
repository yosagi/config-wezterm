-- wezterm.lua (modularized)
-- メインの設定ファイル
-- mux-server と GUI の両方で評価される。GUI 専用の設定は wezterm.gui ガード内に配置する。
local wezterm = require("wezterm")

-- 設定オブジェクトの作成
local config = wezterm.config_builder()

--------------------------------------------------------------------------------
-- 基本設定（mux-server でも必要）
--------------------------------------------------------------------------------

-- Unix domainの設定
config.unix_domains = {
	{
		name = "unix",
	},
}

-- 初期サイズ
config.initial_cols = 100
config.initial_rows = 50

-- フォント
-- ホストごとの値は wezterm.local.lua で上書きできる（末尾を参照）
config.font_size = 13
config.font = wezterm.font("HackGen Console NF")

-- カラースキーム
local scheme = wezterm.get_builtin_color_schemes()["Tomorrow (dark) (terminal.sexy)"]
scheme.scrollbar_thumb = "#555555"
local fg = wezterm.color.parse(scheme.foreground)
local bg = wezterm.color.parse(scheme.background)
scheme.compose_fg = fg:lighten(0.5)
scheme.compose_bg = bg:lighten(0.2)
config.color_schemes = {
	["Custom Scheme"] = scheme,
}
config.color_scheme = "Custom Scheme"

-- スクロールバー
config.enable_scroll_bar = true

-- 非アクティブペインを暗くする
config.inactive_pane_hsb = {
	saturation = 0.8,
	brightness = 0.4,
}

-- IME
config.use_ime = true

--------------------------------------------------------------------------------
-- GUI 専用の設定（mux-server では wezterm.gui が nil なのでスキップ）
--------------------------------------------------------------------------------
if wezterm.gui then
	-- モジュールの読み込み
	local colors = require("modules.colors")
	local pane_layout = require("modules.pane_layout")
	local pane_mode = require("modules.pane_mode")
	local edit_mode = require("modules.edit_mode")
	local claude_mode = require("modules.claude_mode")
	local tab_group = require("modules.tab_group")
	local yazi = require("modules.yazi")
	local commands = require("modules.commands")
	local events = require("modules.events")

	-- キーバインドの初期化
	config.keys = {}
	config.key_tables = {}

	-- 独立モジュールの適用
	pane_mode.apply_to_config(config)
	edit_mode.apply_to_config(config)
	pane_layout.apply_to_config(config)

	-- tab_group モジュールの適用（pane_mode キーテーブルにキーを追加）
	tab_group.apply_to_config(config)

	-- yazi モジュールの適用（edit_mode キーテーブルにキーを追加）
	yazi.apply_to_config(config)

	-- claude_mode への依存関係の注入
	-- 他のモードへのキーを claude_mode に追加（claude_mode 中でも使えるように）
	claude_mode.add_inherited_keys({
		pane_mode.get_activation_entry(),
		edit_mode.get_activation_entry(),
	})
	claude_mode.apply_to_config(config)

	-- イベントハンドラの設定
	colors.setup_update_status()
	claude_mode.setup_update_status()
	tab_group.setup()
	commands.setup()
	events.setup()
end

--------------------------------------------------------------------------------
-- マシン固有の設定（wezterm.local.lua があれば読む）
--------------------------------------------------------------------------------
-- ホスト名や内部の接続先など、公開したくない設定はこちらに置く。
-- ファイルは function(config, wezterm) を返し、config を直接書き換える。
-- dofile で読んだファイルは自動再読み込みの対象外なので、監視リストに加える。
local local_path = wezterm.config_dir .. "/wezterm.local.lua"
local local_file = io.open(local_path, "r")
if local_file then
	local_file:close()
	wezterm.add_to_config_reload_watch_list(local_path)
	dofile(local_path)(config, wezterm)
end

--------------------------------------------------------------------------------
-- 設定を返す
--------------------------------------------------------------------------------
return config
