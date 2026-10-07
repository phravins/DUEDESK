# DueDesk

DueDesk tracks business obligations, renewals and documents so they are
handled before they become overdue. Built by OSWORKS for REALSME Solutions
Pvt Ltd (duedesk.in).

Phoenix 1.8 · LiveView · PostgreSQL · Tailwind/daisyUI.

## Local development

Requirements: Elixir 1.18 / OTP 27, Docker.

```sh
docker compose up -d        # Postgres on :5435, MinIO on :9000 (console :9001)
mix setup                   # deps, database, seeds, assets
mix phx.server              # http://localhost:4000
```

`mix setup` runs `priv/repo/seeds.exs`, which creates demo accounts (Free,
Business, Entrepreneur) and an operator login, and prints their generated
passwords once. Re-run with `mix ecto.reset`.

- Sent emails (confirmation, password reset) appear at <http://localhost:4000/dev/mailbox>.
- Operator console: <http://localhost:4000/admin>. Create an operator with
  `mix duedesk.create_operator EMAIL "NAME"`.
- Set `DB_PORT` to use a different Postgres port.

## Checks

```sh
mix precommit   # compile --warnings-as-errors, unused deps, format, tests
```

CI (`.github/workflows/ci.yml`) runs the same checks on every push.

## Code map

| Path | What |
|---|---|
| `lib/duedesk/accounts` | Users, sessions, `Scope` (user + account + role) |
| `lib/duedesk/tenancy` | Customer Accounts, memberships, invitations |
| `lib/duedesk/permissions.ex` | Every role check |
| `lib/duedesk/audit.ex` | Append-only audit log (DB trigger blocks update/delete) |
| `lib/duedesk/billing/plans.ex` | Free / Business / Entrepreneur limits |
| `lib/duedesk_web` | Customer app (LiveView) |
| `lib/duedesk_admin` | Internal operator console at `/admin` |

Rules: every tenant query takes a `Scope` and filters by its account; every
permission check goes through `DueDesk.Permissions`; dates display as
`15 Mar 2027` and "today" is computed in the account timezone.

## Deployment

`Dockerfile` builds a release. Required environment variables are listed in
`.env.example`. Run migrations with `bin/migrate` before `bin/server`.
