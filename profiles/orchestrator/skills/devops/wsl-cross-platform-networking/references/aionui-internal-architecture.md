# AionUI Internal Architecture & Config Format

## What AionUI Is

AionUI (by iOfficeAI) is an Electron-based (Chromium) AI agent desktop application. Version 1.9.24 runs on Electron 37.10.3 / Chromium 138. It provides:

- **Agent orchestration**: Manages multiple AI agents (Aion CLI, Gemini CLI, Claude Code, OpenCode, OpenClaw Gateway, etc.)
- **Pet system**: Desktop overlay pet windows that represent the active agent
- **MCP server integration**: Configurable MCP servers via stdio or TCP
- **Assistant/skills system**: Built-in and custom assistants with skill definitions
- **ACP protocol support**: Claude Agent Protocol integration
- **WebUI**: Built-in web interface for remote access
- **Channel plugins**: Extensible messaging channel system

## Config Storage Format

AionUI stores its main config as **base64-encoded → URL-encoded JSON** in:

```
%APPDATA%\AionUi\config\aionui-config.txt
```

### Decoding

```python
import base64, json, urllib.parse

with open('aionui-config.txt', 'r') as f:
    content = f.read().strip()

# Step 1: Base64 decode
b64_decoded = base64.b64decode(content).decode('utf-8')
# Result is URL-encoded JSON string

# Step 2: URL decode
json_str = urllib.parse.unquote(b64_decoded)

# Step 3: Parse JSON
data = json.loads(json_str)
```

### Key Config Sections

| Key | Description |
|-----|-------------|
| `pet.enabled` | Whether the desktop pet overlay is active |
| `system.closeToTray` | Minimize to system tray on close |
| `theme` | UI theme (`"dark"` or `"light"`) |
| `model.config` | Array of model provider configs (id, platform, name, baseUrl, apiKey, model[]) |
| `aionrs.defaultModel` | Default model for the aionrs agent |
| `guid.lastSelectedAgent` | Last active agent ID (e.g., `"aionrs"`) |
| `assistants` | Array of assistant definitions |
| `mcp.config` | Array of MCP server definitions |
| `webui.desktop.enabled` | Whether desktop WebUI mode is active |
| `acp.cachedInitializeResult` | Cached ACP protocol handshake result |
| `acp.cachedModels` | Cached ACP model list per provider |
| `acp.cachedModes` | Cached ACP mode list per provider |

### webui.config.json (Separate File)

A simpler JSON file at `%APPDATA%\AionUi\webui.config.json`:

```json
{
  "server": { "host": "0.0.0.0", "port": 62936, "allowRemote": true },
  "mcp": { "port": 57978, "allowRemote": true },
  "webui": { "port": 25809 }
}
```

## Pet System

- Pet windows are separate OS windows created by the Electron main process
- Log entries: `[Pet] Pet windows created` / `[Pet] Pet windows destroyed`
- Pet confirm windows: `[PetConfirm] Confirm window destroyed`
- The pet is tied to the `aionrs` agent type
- Pet lifecycle: created on startup, destroyed/recreated on agent switch or config change
- Detailed pet settings (character, animations, position) are stored in the SQLite DB

## Agent Registry

AionUI auto-detects installed CLI agents by scanning PATH for known binaries:
`qwen`, `codex`, `codebuddy`, `goose`, `auggie`, `kimi`, `droid`, `copilot`, `qodercli`, `vibe-acp`, `agent`, `kiro-cli`, `hermes`, `snow`, `nanobot`, `opencode`

Detection uses both `where` and PowerShell `Get-Command`.

## ACP Protocol Support

- Session management (fork, resume, list, close)
- Prompt capabilities (image, embedded context)
- MCP capabilities (stdio, HTTP, SSE)
- Mode switching (auto, default, acceptEdits, plan, dontAsk, bypassPermissions)

## Database

SQLite at `%APPDATA%\AionUi\aionui\aionui.db` — locked while AionUI runs. Contains agent configs, chat history, pet state, and other persistent data.

## File Locations (Windows)

| Path | Description |
|------|-------------|
| `%LOCALAPPDATA%\Programs\AionUi\AionUi.exe` | Main executable (~204MB) |
| `%APPDATA%\AionUi\webui.config.json` | WebUI/server config (plain JSON) |
| `%APPDATA%\AionUi\config\aionui-config.txt` | Main config (b64→URL-encoded JSON) |
| `%APPDATA%\AionUi\aionui\aionui.db` | SQLite database |
| `%APPDATA%\AionUi\logs\` | Log files (daily rotation) |
| `%APPDATA%\AionUi\config\assistants\` | Assistant skill definitions |
| `%APPDATA%\AionUi\config\builtin-skills\` | Built-in skill markdown files |
| `%APPDATA%\AionUi\config\skills\` | User skill symlinks |

## WSL Bridge Script

A Python TCP bridge (`aionui_bridge.py`) forwards traffic between WSL and Windows host IP. Forwards WebUI (port 62936) and MCP (port 57978). Alternative to portproxy/SSH tunnel.

## Version Info (1.9.24)

- Electron: 37.10.3 / Chromium: 138.0.7204.251 / Node: v22.21.1
- Bundled bun for skill execution
- Auto-updater checks on startup
