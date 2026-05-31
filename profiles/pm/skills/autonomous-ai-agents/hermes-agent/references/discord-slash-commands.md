# Discord Slash Command Development Pattern

## Overview

Custom Discord slash commands are added to `gateway/platforms/discord.py` in the `DiscordPlatform.setup_hook()` method, alongside the existing `slash_sherlock` command (line ~3060).

## Command Template

```python
@tree.command(name="cmdname", description="Short description of what this does")
@app_commands.describe(
    param_name="Description of parameter",
    optional_param="Description (default: value)",
)
async def slash_cmdname(
    interaction: discord.Interaction,
    param_name: str,
    optional_param: str = "default",
):
    await interaction.response.defer(ephemeral=False)
    import subprocess
    cmd = ["tool_name", param_name, "--flag1", "--flag2"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        output = (proc.stdout + proc.stderr).strip()
        if not output:
            output = f"No results found for `{param_name}`."
    except subprocess.TimeoutExpired:
        output = f"⏱️ tool_name timed out after 120s for `{param_name}`."
    except FileNotFoundError:
        output = "❌ tool_name is not installed. Run: `pip install tool_name`"
    except Exception as e:
        output = f"❌ Error running tool_name: {e}"
    if len(output) > 1900:
        output = output[:1900] + "\n…(truncated)"
    await interaction.edit_original_response(
        content=f"🔍 **tool_name report for `{param_name}`:**\n```\n{output}\n```"
    )
```

## Key Rules

1. **Always `defer` first** — `await interaction.response.defer(ephemeral=False)` — so the 3-second interaction window doesn't expire during tool execution.
2. **Always truncate** — Discord message limit is 2000 chars. Truncate at 1900 to leave room for the header/footer markdown.
3. **Always handle errors** — `TimeoutExpired`, `FileNotFoundError`, and generic `Exception` with user-friendly messages.
4. **Use `ephemeral=False`** — results should be visible to everyone in the channel.
5. **Timeout values** — set `subprocess.run(timeout=...)` to 60-180s depending on the tool. Set the per-tool timeout flag (e.g. `--timeout 30`) lower than the subprocess timeout.
6. **Go binaries** — if a tool is a Go binary installed to `~/go/bin/`, use the full path (e.g. `"/home/frostthejack/go/bin/dnsx"`). The gateway's PATH already includes `~/go/bin` but explicit paths are safer.
7. **Place new commands before the auto-registration block** — the comment `# ── Auto-register any gateway-available commands not yet on the tree ──` marks the boundary.

## Existing Commands (as of 2026-05-16)

| Command | Tool | Target | Install |
|---------|------|--------|---------|
| `/sherlock` | sherlock | username | `pip install sherlock-project` |
| `/holehe` | holehe | email | `pip install holehe` |
| `/h8mail` | h8mail | email | `pip install h8mail` |
| `/dnsx` | dnsx | domain | `go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest` |
| `/maigret` | maigret | username | `pip install maigret` |
| `/socialscan` | socialscan | username | `pip install socialscan` |

## After Adding Commands

1. Save the file
2. Restart the gateway: `hermes gateway restart`
3. Check logs for registration count: `grep "slash command" ~/.hermes/logs/gateway.log | tail -5`
4. Verify in Discord by typing `/` and checking the slash command picker

## Go Tool Installation Pattern

When a tool requires Go (like `dnsx`, `subfinder`, `httpx`, `nuclei`):

```bash
# Install Go to user directory (no sudo needed)
curl -sL https://go.dev/dl/go1.22.3.linux-amd64.tar.gz -o /tmp/go.tar.gz
tar -C $HOME -xzf /tmp/go.tar.gz
export PATH=$HOME/go/bin:$PATH

# Install the tool
go install github.com/projectdiscovery/<tool>/cmd/<tool>@latest
```

The gateway's PATH already includes `~/go/bin`, so Go binaries are automatically available to slash commands.
