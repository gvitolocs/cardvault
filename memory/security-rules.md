# Security rules (Pokoin)

## Payments & money

- Stripe and server-side payment handlers are the source of truth.
- Never assume success from client callbacks or UI state alone.
- Never fake payment success in tests, demos, or agent responses.

## Balance & wallet (PKN)

- No client-side balance mutation without server confirmation.
- Read Oracle API and DB state before changing wallet logic.

## Authentication

- Session/tokens must be validated server-side for protected routes and APIs.
- Do not weaken auth checks for convenience.

## Database

- Migrations on Oracle/Postgres primary must be reviewed and reversible when possible.
- No destructive changes without explicit user approval.

## Blockchain

- Treat on-chain state as external source of truth; handle failures and reorgs explicitly.
- No silent retries that could double-spend or double-credit.

## Secrets

- Never commit `.env.local`, `.env.honcho.local`, keys, or Honcho/API tokens.
- Redact secrets in logs and memory updates.
- **Where to find them:** see `memory/secrets-workflow.md` and Codevira locked decisions `D000001`–`D000004` in `AGENTS.md`.

## Agent behavior

- For critical areas: explain risk, propose minimal diffs, and verify with tests or explicit API checks.
