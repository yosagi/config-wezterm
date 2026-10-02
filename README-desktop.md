# WezTerm .desktopファイル管理

このディレクトリには、WezTermの複数接続先（Unix domain、SSHMUX、SSH）用の.desktopファイルを生成・管理するヘルパースクリプトが含まれています。

## 機能

- **Unix domain接続**: ローカルのUnix domainソケット経由での接続（`wezterm connect {DOMAIN}`）自動検出
- **SSHMUX接続**: 事前に設定したSSHドメインへの接続（`wezterm connect SSHMUX:{HOST}`）デフォルト
- **SSH接続**: 通常のSSH接続（`wezterm connect SSH:{HOST}`）

各接続先ごとに個別の.desktopファイル（`wezterm-{HOSTNAME}.desktop`）を作成し、アプリケーションランチャーから簡単に起動できます。

**Unix domain自動検出**: `wezterm.lua`の`config.unix_domains`設定を自動的に検出して、Unix domain用の.desktopファイルを生成します。

## 使い方

### 方法1: .ssh/configから自動生成（推奨）

.ssh/configに既にSSHホストが設定されている場合、自動的に設定ファイルを生成できます：

```bash
# .ssh/configからSSHMUX接続設定を生成（デフォルト）
./install-wezterm-desktop.sh generate --from-ssh-config

# SSH接続として生成
./install-wezterm-desktop.sh generate --from-ssh-config --type ssh

# カスタムSSH設定ファイルを使用
./install-wezterm-desktop.sh generate --from-ssh-config --ssh-config /path/to/config
```

これにより、.ssh/configに定義されているすべてのホスト（ワイルドカードを除く）が自動的に検出され、`wezterm-connections.conf` が生成されます。

**デフォルトはSSHMUX接続です**。SSH接続を使用する場合は `--type ssh` を指定してください。

**実行例:**

.ssh/configに以下のようなホスト定義がある場合：
```
Host devserver
    HostName dev.example.com
    User developer

Host prodserver
    HostName prod.example.com
    User admin
```

`./install-wezterm-desktop.sh generate --from-ssh-config` を実行すると、以下の設定ファイルが生成されます（デフォルトはSSHMUX）：
```
sshmux|WezTerm (Devserver)|devserverへSSHMUX接続|connect SSHMUX:devserver
sshmux|WezTerm (Prodserver)|prodserverへSSHMUX接続|connect SSHMUX:prodserver
```

SSH接続を使用する場合（`--type ssh` 指定時）：
```
ssh|WezTerm (Devserver)|devserverへSSH接続|connect SSH:devserver
ssh|WezTerm (Prodserver)|prodserverへSSH接続|connect SSH:prodserver
```

そして、以下の.desktopファイルが生成されます：
- `wezterm-unix.desktop` (wezterm.luaのunix_domainsから自動生成)
- `wezterm-devserver.desktop`
- `wezterm-prodserver.desktop`

### 方法2: 手動で設定ファイルを作成

#### 1. サンプル設定ファイルの生成

```bash
./install-wezterm-desktop.sh generate
```

これにより `wezterm-connections.conf` が生成されます。

#### 2. 設定ファイルの編集

`wezterm-connections.conf` を開いて、接続先を追加・編集します：

```bash
vim wezterm-connections.conf
```

**設定ファイルの書式:**
```
TYPE|NAME|COMMENT|EXEC_ARGS
```

- `TYPE`: 接続タイプ（sshmux, ssh）
- `NAME`: 表示名（例: WezTerm (MyServer)）
- `COMMENT`: コメント
- `EXEC_ARGS`: weztermコマンドの引数

**例:**
```
# SSHMUX接続（wezterm.luaでssh_domainsを設定済みの場合）
sshmux|WezTerm (DevServer)|DevServerへSSHMUX接続|connect SSHMUX:devserver
sshmux|WezTerm (ProdServer)|ProdServerへSSHMUX接続|connect SSHMUX:prodserver

# SSH接続
ssh|WezTerm (Build)|Buildサーバーへ接続|connect SSH:build
```

生成される.desktopファイル名は `wezterm-{HOSTNAME}.desktop` 形式になります（例: `wezterm-devserver.desktop`）。

### 共通: .desktopファイルの生成とインストール

設定ファイル（`wezterm-connections.conf`）が生成されたら、.desktopファイルを生成してインストールします：

```bash
# 設定ファイルから.desktopファイルを生成してインストール
./install-wezterm-desktop.sh all

# または個別に実行
./install-wezterm-desktop.sh generate  # 既存の設定ファイルから.desktopファイルを生成
./install-wezterm-desktop.sh install   # 生成済みファイルをインストール
```

**注意**: `generate --from-ssh-config` を使用した場合は、設定ファイルの生成と.desktopファイルの生成が同時に行われるため、次は `install` コマンドを実行するだけです：

```bash
# .ssh/configから自動生成してインストール
./install-wezterm-desktop.sh generate --from-ssh-config
./install-wezterm-desktop.sh install
```

### インストール確認

```bash
./install-wezterm-desktop.sh list
```

アプリケーションランチャーから「WezTerm」で検索すると、設定した接続先が表示されます。

### 5. アンインストール

```bash
./install-wezterm-desktop.sh uninstall
```

## SSHMUX接続の設定

SSHMUX接続を使用する場合は、`wezterm.lua` でSSHドメインを事前に設定する必要があります：

```lua
config.ssh_domains = {
  {
    name = "devserver",
    remote_address = "dev.example.com",
    username = "yourname",
    -- オプション: SSHの設定
    -- ssh_option = {
    --   identityfile = "/home/yourname/.ssh/id_rsa",
    -- },
  },
  {
    name = "prodserver",
    remote_address = "prod.example.com",
    username = "yourname",
  },
}
```

設定後、.desktopファイルで以下のように使用できます：

```
sshmux|WezTerm (DevServer)|DevServerへSSHMUX接続|connect SSHMUX:devserver
```

## ファイル構成

```
.
├── install-wezterm-desktop.sh  # ヘルパースクリプト
├── wezterm-connections.conf    # 接続設定ファイル（生成後）
├── wezterm-*.desktop           # 生成された.desktopファイル
├── wezterm.lua                 # WezTermメイン設定
└── README-desktop.md           # このファイル
```

## インストール先

.desktopファイルは以下のディレクトリにインストールされます：

```
${XDG_DATA_HOME:-$HOME/.local/share}/applications
```

通常は `~/.local/share/applications/` です。

## トラブルシューティング

### アプリケーションランチャーに表示されない

1. デスクトップデータベースを手動で更新：
   ```bash
   update-desktop-database ~/.local/share/applications
   ```

2. デスクトップ環境を再起動するか、ログアウト/ログイン

### SSHMUX接続ができない

1. `wezterm.lua` でSSHドメインが正しく設定されているか確認
2. 接続先にSSHで手動接続できるか確認：
   ```bash
   ssh user@hostname
   ```
3. weztermのログを確認：
   ```bash
   wezterm start --always-new-process
   ```

### Unix domain接続について

Unix domain接続は、`wezterm.lua`の設定から自動的に検出されます。

`wezterm.lua`でUnix domainを設定：
```lua
config.unix_domains = {
  { name = "unix" },
}
```

この設定があると、`./install-wezterm-desktop.sh generate`実行時に自動的に`wezterm-unix.desktop`が生成されます。

weztermのmuxサーバーが起動しているか確認：
```bash
wezterm cli list
```

## 参考リンク

- [WezTerm公式ドキュメント - Multiplexing](https://wezfurlong.org/wezterm/multiplexing.html)
- [WezTerm公式ドキュメント - SSH Domains](https://wezfurlong.org/wezterm/config/lua/SshDomain.html)
- [Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/)
