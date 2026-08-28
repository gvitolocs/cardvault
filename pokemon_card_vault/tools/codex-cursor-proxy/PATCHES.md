# Local patches (wellbritto98/codex-cursor-proxy)

Upstream issues addressed in this vendored copy:

| Issue | Fix |
| --- | --- |
| [#1](https://github.com/sheikhuzairhussain/codex-cursor-proxy/issues/1) Windows `~` auth paths | Already fixed upstream via `homedir()` |
| [#2](https://github.com/sheikhuzairhussain/codex-cursor-proxy/issues/2) Bun 10s idle timeout | `idleTimeout: 0` on `Bun.serve` |
| [#3](https://github.com/sheikhuzairhussain/codex-cursor-proxy/issues/3) Premature stop / no auto-continue | Map incomplete responses to `finish_reason: "length"`; default `max_output_tokens: 32768` |

Additional hardening:

- `GET /` health JSON for Cursor connectivity probes
- Persist `tunnelUrl` beside `subdomain` in `~/.codex/cursor-proxy/config.json`
- Reuse the same subdomain across restarts (stable `loca.lt` URL)
- Fail fast when localtunnel cannot bind the reserved subdomain

Known limits (not fixable in proxy alone):

- OpenAI/Codex **429 rate limits** still surface as upstream errors
- `localtunnel` availability depends on third-party infrastructure
- Expired `~/.codex/auth.json` tokens require re-running `codex` login
