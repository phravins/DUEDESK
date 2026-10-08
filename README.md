# DueDesk

DueDesk tracks business obligations, renewals and documents so they are
handled before they become overdue. Built by OSWORKS for REALSME Solutions
Pvt Ltd (duedesk.in).

Phoenix 1.8 · LiveView · PostgreSQL · Tailwind CSS.

## Local development

Requirements: Elixir 1.18 / OTP 27 and a local PostgreSQL server.

Dev and test connect to Postgres on `localhost:5432` and use the databases
`duedesk_dev` and `duedesk_test`. Set these if your server differs:

| Variable | Default |
|---|---|
| `DB_HOST` | `localhost` |
| `DB_PORT` | `5432` |
| `DB_USERNAME` | `postgres` |
| `DB_PASSWORD` | `postgres` |

The role needs `CREATEDB` so `mix setup` can create the databases, e.g.
`sudo -u postgres createuser --createdb --pwprompt duedesk`, then
`export DB_USERNAME=duedesk DB_PASSWORD=...` in your shell profile.

```sh
mix setup                   # deps, database, seeds, assets
mix phx.server              # http://localhost:4000
```

`mix setup` runs `priv/repo/seeds.exs`, which creates demo accounts (Free,
Business, Entrepreneur) and an operator login, and prints their generated
passwords once. Re-run with `mix ecto.reset`.

- Sent emails (confirmation, password reset) appear at <http://localhost:4000/dev/mailbox>.
- Operator console: <http://localhost:4000/admin>. Create an operator with
  `mix duedesk.create_operator EMAIL "NAME"`.

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
| `lib/duedesk/documents` | Documents on DueItem cycles and the storage adapters |
| `lib/duedesk_web` | Customer app (LiveView) |
| `lib/duedesk_admin` | Internal operator console at `/admin` |

Rules: every tenant query takes a `Scope` and filters by its account; every
permission check goes through `DueDesk.Permissions`; dates display as
`15 Mar 2027` and "today" is computed in the account timezone.

## Documents

Documents belong to a cycle of a DueItem and are never overwritten: a
renewal starts a new cycle with its own documents. Any file type is
accepted, up to 30 MB each; downloads are always attachments
(`GET /documents/:id/download`), never shown in the browser. Plan storage
only blocks new uploads; nothing is deleted automatically.

Two deliberate differences from the Architecture document:

- **Uploads pass through the app** instead of going straight to the
  bucket. The server measures the size and SHA-256 itself, one code path
  serves local disk and S3, the bucket needs no CORS, abandoned uploads
  leave nothing behind, and a malware scan can later hook in at one
  place. The cost is that files up to 30 MB pass through the app server,
  which is fine at pilot scale; direct uploads can be added behind the
  same `DueDesk.Documents.Storage` behaviour if load requires it.
- **One `documents` table** with `due_item_id`, `cycle_id` and `role`
  (`current`, `supporting`, `completion`) instead of a separate link
  table: in V1 a file belongs to exactly one cycle and is never shared.

Storage:

- Development stores files in `uploads/` at the repository root (ignored
  by git); tests use a temporary directory.
- Production uses a **private** S3 or Cloudflare R2 bucket when
  `S3_BUCKET` is set (with `S3_REGION`, `S3_ENDPOINT`, `S3_ACCESS_KEY_ID`,
  `S3_SECRET_ACCESS_KEY`), or a persistent directory in `UPLOADS_DIR`. The
  app refuses to boot without one. Block all public access on the bucket;
  no CORS rules are needed. Downloads redirect to a signed URL valid for
  five minutes.
- `customer_accounts.storage_used_bytes` is kept in step with each upload
  and removal. To recompute it from the stored documents:
  `bin/duedesk eval "DueDesk.Release.reconcile_storage()"` (scheduled
  nightly once background jobs arrive).

## Deployment

`MIX_ENV=prod mix release` builds a release. Required environment variables
are listed in `.env.example`. Run migrations with `bin/migrate` before
`bin/server`.
