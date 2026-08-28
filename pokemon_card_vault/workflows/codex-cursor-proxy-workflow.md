# Codex Cursor Proxy Workflow

Use the **local patched copy** in `tools/codex-cursor-proxy/` (based on
[wellbritto98/codex-cursor-proxy](https://github.com/wellbritto98/codex-cursor-proxy))
to route Cursor's OpenAI-compatible requests through your ChatGPT Plus/Pro Codex
subscription instead of a separate OpenAI API key.

See `tools/codex-cursor-proxy/PATCHES.md` for issue fixes (#1–#3).

This is a **local developer tool**. It does not run on Vercel, Oracle, or
production Pokoin infrastructure.

## Prerequisites

1. **Bun** >= 1.0

```bash
curl -fsSL https://bun.sh/install | bash
```

2. **Codex CLI** authenticated at least once

```bash
npm i -g @openai/codex
codex
```

This creates `~/.codex/auth.json` with the access token the proxy reuses.

3. **Port 3000 free** on your machine (proxy default).

## Start the proxy manually

From the repo root:

```bash
npm run codex:cursor-proxy
```

The script runs the local patched server:

```bash
bun run tools/codex-cursor-proxy/index.ts
```

On startup the proxy prints:

```text
OpenAI Base URL for Cursor: https://<subdomain>.loca.lt
API Key: Anything you like!
```

## Start automatically at login (macOS)

Install the LaunchAgent once:

```bash
npm run codex:cursor-proxy:install-launchagent
```

This registers `com.pokoin.codex-cursor-proxy` under
`~/Library/LaunchAgents/` and starts it immediately.

Logs:

- `~/Library/Logs/codex-cursor-proxy.log`
- `~/Library/Logs/codex-cursor-proxy.error.log`

Stop/disable:

```bash
launchctl bootout "gui/$(id -u)" ~/Library/LaunchAgents/com.pokoin.codex-cursor-proxy.plist
```

## Cursor configuration

1. Open **Cursor Settings → Models → OpenAI**
2. Set **Base URL** to the `loca.lt` URL printed by the proxy
3. Set **API Key** to any non-empty string (for example `x`)
4. Choose a Codex-supported model name (for example `gpt-5.4`)

Leave the proxy running while you use Cursor with that base URL.

## Optional environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `CODEX_CURSOR_PROXY_PORT` | `3000` | Expected local port (checked before start) |

Stable URL is stored in `~/.codex/cursor-proxy/config.json` as `subdomain` and
`tunnelUrl`. Do not delete that file unless you want a new public URL.

## Security notes

- The proxy exposes a **public tunnel** to your local machine while running.
- Stop it when not in use.
- Never commit `~/.codex/auth.json` or tunnel credentials to the repo.

## Related docs

- upstream fork: https://github.com/wellbritto98/codex-cursor-proxy
- original repo: https://github.com/sheikhuzairhussain/codex-cursor-proxy
- Codex CLI: https://github.com/openai/codex
