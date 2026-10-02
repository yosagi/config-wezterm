# wezterm 設定

wezterm のカスタム設定ファイル。Claude Code / Codex との連携機能、ペイン操作のカスタムキーバインドなどを含む。

## クイックスタート

### 前提条件

- wezterm がインストール済み
- jq がインストール済み（`sudo apt install jq`）

### 1. AI Mode セットアップ（Codex 連携）

AI Mode キーマップは User Var WEZTERM_AI_HELPER の状態によって自動的に適用する。

**Claude Code**: statuslineで OSC シーケンスを送ることができ、ラッパー不要。直接 `claude` コマンドで起動すれば自動的に AI Mode になる。

**Codex**: 起動時にOSCシーケンスを送るラッパースクリプトが必要。

**通常モードへの復帰**: bashのプロンプトから OSCシーケンスを送る。これも設定が必要。

codexラッパーとbashプロンプトは以下でセットアップできる：

```bash
cd ~/.config/wezterm
./setup-wezterm-ai-mode.sh
```

これにより：
- `~/.local/bin/codex` にラッパースクリプトが作成される
- `~/.bashrc` にシェル統合スクリプトが追加される

セットアップ後、`source ~/.bashrc` を実行するか、新しいシェルを起動する。

詳細: [README-shell-integration.md](README-shell-integration.md)

### 2. Desktop ファイルセットアップ（アプリランチャー用）

アプリケーションランチャーから wezterm を起動するための .desktop ファイルを生成・インストールする。~/.ssh/config にリモートの定義があればこれを拾って SSHMUX で接続する desktop ファイルも生成できる。

```bash
cd ~/.config/wezterm

# .ssh/config からホストを自動検出して設定ファイルを生成
./install-wezterm-desktop.sh generate --from-ssh-config

# 生成された .desktop ファイルをインストール
./install-wezterm-desktop.sh install
```

詳細: [README-desktop.md](README-desktop.md)

## カスタムキーバインド

### グローバルキー

| キー | 動作 |
|------|------|
| `F1` | 横ペイン数に応じてウィンドウ幅を調整（単一ペインはデフォルトサイズにリセット） |
| `Shift+F1` | 倍幅リサイズ（200 cols 相当、TUI ファイルマネージャ等に） |
| `F2` | ウィンドウ幅を2倍にして横2分割（1ペイン時のみ） |
| `F3` | L字型3ペインレイアウト（左1 + 右上下2）/ 3ペイン時は比率サイクル（1:1→1:4→4:1） |
| `Ctrl+,` | ペイン操作モード（pane_mode）を起動 |
| `Ctrl+;` | 編集モード（edit_mode）を起動 |
| `Ctrl+Shift+D` | ペインを閉じてペイン数に応じたサイズに調整 |
| `Ctrl+Shift+X` | Copy mode をクリーンに起動（前回の検索パターンをクリア） |

### pane_mode（Ctrl+, で起動、vim の Ctrl+w 風）

| キー | 動作 |
|------|------|
| `h` | 左のペインへ移動 |
| `j` | 下のペインへ移動 |
| `k` | 上のペインへ移動 |
| `l` | 右のペインへ移動 |
| `w` / `Space` | 次のペインへ循環 |
| `v` | 縦分割（左右に分割） |
| `s` | 横分割（上下に分割） |
| `c` | ペインを閉じる |
| `Escape` | キャンセル |

### edit_mode（Ctrl+; で起動）

| キー | 動作 |
|------|------|
| `Ctrl+;` | Copy mode（前回の検索パターンをクリア） |
| `s` | Search mode |
| `/` | Search mode（vi風） |
| `p` | Quick select mode |
| `d` | アクティブペインの CWD をクリップボードにコピー |
| `y` | yazi をリモート sftp 付きで別ウィンドウに起動（SSHMUX 接続時） |
| `Escape` | キャンセル |

### copy_mode / search_mode 内の追加キー

| キー | 動作 |
|------|------|
| `Ctrl+[` | モードを閉じる（ESC の代替） |
| `Ctrl+;` → `Ctrl+;` | copy mode: パターンクリア / search mode: copy mode へ |
| `Ctrl+;` → `s` or `/` | search mode へ |
| `Ctrl+;` → `p` | quick select へ |

### AI Mode（Claude Code / Codex 実行時に自動起動）

| キー | 動作 |
|------|------|
| `Enter` | LF (0x0a) を送信 |
| `Shift+Enter` | CR (0x0d) を送信 |
| `Ctrl+Enter` | CR (0x0d) を送信 |
| `Ctrl+,` | pane_mode を起動 |
| `Ctrl+;` | edit_mode を起動 |
| `Ctrl+B` | ← キー送信（Claude Code バグ #21008 の暫定対処） |
| `Ctrl+Shift+R` | 設定リロード |

## 特殊機能

### ホスト名に応じた背景色

接続先ホストごとにウィンドウの背景色が自動的に変わる。同じホストなら接続方法（unix domain / SSHMUX）に関わらず同じ色になる。

### AI Mode

User Var `WEZTERM_AI_HELPER` が設定されると、自動的に AI Mode に切り替わる。これにより Enter キーの動作が変わり、複数行入力がしやすくなる。

- **Claude Code**: status line から OSC シーケンスで user_var を設定するため、ラッパー不要(別途 status lineの設定は必要)
- **Codex**: 起動ラッパー（`setup-wezterm-ai-mode.sh` でインストール）が OSC シーケンスを送信

### フォーカス視認性

- ウィンドウがフォーカスを失うと半透明化（opacity 0.7）
- 非アクティブペインは暗く表示（brightness 0.4）
- フォーカスなし時はホスト別背景色の彩度・明度を補償

### wezterm-launcher

unix domain 経由で wezterm を起動するためのランチャースクリプト。

```bash
cp wezterm-launcher.sh ~/.local/bin/wezterm-launcher
```

**動作:**
- ローカル GUI がない場合: `wezterm connect unix` でセッション復帰（または新規作成）
- ローカル GUI がある場合: 新しいウィンドウを追加

mux-server にセッションが残っていれば復帰し、sshmux 接続中の GUI は無視してローカルの unix domain のみを対象にする。.desktop ファイルの Exec に指定して使う。

## 詳細ドキュメント

| ドキュメント | 内容 |
|-------------|------|
| [README-shell-integration.md](README-shell-integration.md) | AI Mode のシェル統合、トラブルシューティング |
| [README-desktop.md](README-desktop.md) | .desktop ファイルの生成・管理、SSHMUX 設定 |

## yazi リモートファイル転送

SSHMUX 接続先との間で yazi + sftp を使ったファイル転送ができる。

- `Ctrl+; y` でアクティブペインの接続先ホストに対し、sftp 付きの yazi を別ウィンドウで起動
- タブ1 = リモート（接続先の CWD に同期）、タブ2 = ローカル HOME
- 同じホストの複数ペインが1つの yazi インスタンスを共有
- 既に起動済みの場合は CWD を同期してフォーカス移動

前提: yazi, ya コマンドがインストール済みであること。yaziでvfsの設定によりリモートホストにアクセスできるようにしていること。

## パッチ適用済み wezterm

`patches/` ディレクトリに wezterm 本体へのバグ修正パッチを含む。
パッチ適用済みの fork: [yosagi/wezterm](https://github.com/yosagi/wezterm)（`patched` ブランチ）

### 適用済みパッチ

| パッチ | 内容 | 出所 |
|--------|------|------|
| `fix/5117-pane-size-corruption` | ペインサイズ破損修正 | [Issue #5117](https://github.com/wezterm/wezterm/issues/5117) |
| `fix/5832-user-vars-mux-sync` | user_vars の mux 再接続時同期 | [Issue #5832](https://github.com/wezterm/wezterm/issues/5832) |
| `strackeror/sequence-pane-focus-events` | フォーカス無限ループ修正 | [PR #7399](https://github.com/wezterm/wezterm/pull/7399) |
| `fix/2056-ime-selected-string` | IME プリエディットハイライト | [PR #2056](https://github.com/wezterm/wezterm/pull/2056)（kumattau） |

### ビルド方法

```bash
git clone https://github.com/yosagi/wezterm
cd wezterm
git checkout patched
cargo build --release
```

ビルド済みバイナリ（wezterm, wezterm-gui, wezterm-mux-server）を `~/.local/bin/` にコピーして使用。GitHub Actions でのクロスプラットフォームビルドも可能（fork の Actions タブから手動実行）。
