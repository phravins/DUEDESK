# DueDesk

DueDesk tracks business obligations, renewals and documents so they are
handled before they become overdue. Built by OSWORKS for REALSME Solutions
Pvt Ltd (duedesk.in).

Phoenix 1.8 · LiveView · PostgreSQL · Tailwind CSS.

## Local development

Requirements: Elixir 1.18 / OTP 27 and a local PostgreSQL server.

Dev and test connect to Postgres on `localhost:5432` and use the databases
`duedesk_dev` and `duedesk_test`. Credentials live in a gitignored `.env`
file, never in `config/`:

```sh
cp .env.example .env        # then set DB_USERNAME / DB_PASSWORD
```

`config/config.exs` loads `.env` in dev and test (shell variables win).
Without it the defaults are `localhost:5432`, `postgres`/`postgres`.

The role needs `CREATEDB` so `mix setup` can create the databases:
`sudo -u postgres psql`, then `CREATE ROLE duedesk LOGIN CREATEDB;` and
`\password duedesk`.

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
  `bin/duedesk eval "DueDesk.Release.reconcile_storage()"`. It also runs
  nightly at 02:30 IST as a background job.

## Reminders & notifications

Background jobs run on [Oban](https://hexdocs.pm/oban) in the app's own
Postgres database (queues `reminders`, `email`, `whatsapp`, `maintenance`).

- **Schedule.** Every 15 minutes a scan queues, per account, the reminders
  that fall due by the account's today. A reminder falls on the cycle's
  Due Date (else Expiry Date) plus each active reminder rule's offset;
  after the last rule it repeats weekly while the DueItem stays overdue.
- **Catch-up.** A scan looks back 2 days, so a short outage loses
  nothing, but older reminders are never sent in bulk. Reminders that
  fall before the cycle began are skipped.
- **Recipients.** The Primary Responsible and Additional Assignees. Once
  overdue, reminders are escalated: Administrators and Super Admins get
  them too. Only active members who turned the channel on in Settings.
- **Exactly once.** Each delivery has a unique key (cycle, rule, date,
  person, channel), so repeated scans and retries never send twice. A job
  re-checks the DueItem before sending; renewing, completing, archiving or
  reassigning it marks queued reminders as skipped. Failed deliveries are
  retried 5 times and never change a DueItem's status.
- **Event emails.** Assignment, a renewal to review and a completed
  DueItem awaiting a decision send an email, queued in the same
  transaction as the change.
- **Log.** Administrators see the last 20 deliveries on a DueItem's page.

Email: development uses the local mailbox at
[`/dev/mailbox`](http://localhost:4000/dev/mailbox). Production needs
`MAIL_ADAPTER` (`postmark`, `brevo`, `resend` or `mailgun`), `MAIL_API_KEY`
and, for Mailgun, `MAIL_DOMAIN`; `MAIL_FROM` sets the sender address.

WhatsApp goes through an n8n webhook when `N8N_WEBHOOK_URL` and
`N8N_SIGNING_SECRET` are set; otherwise Settings shows the channel as
unavailable. Each request is JSON signed in the `x-duedesk-signature`
header as `t=<unix time>,v1=<hex HMAC-SHA256 of "<t>.<body>">`; verify it
and use `delivery_id` to drop repeats.

To queue reminders by hand: `mix run -e "DueDesk.Release.run_reminders()"`
(or `bin/duedesk eval` in a release).

## Deployment

`MIX_ENV=prod mix release` builds a release. Required environment variables
are listed in `.env.example`. Run migrations with `bin/migrate` before
`bin/server`.
