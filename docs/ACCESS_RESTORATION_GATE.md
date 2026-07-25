# Access-Control Restoration Gate

Status: **open**. This is the executable checklist that must complete before the V2 URL is shared with teams or the public, or before production cutover. `AGENTS.md` carries the binding rule; this document carries the steps.

## Why this gate exists

The current pre-production review state (approved by Abdel, 14 July 2026) lets every team marked `live` expose its approved aggregate dashboard directly, with no password and no team session. That exception exists solely for Abdel's private review of the V2 site. It is not approval for public production access.

Two consequences are on the record:

1. While team pages are passwordless, anyone with the URL can walk the named team dashboards, match metrics to aliased comparison rows, and reconstruct the full alias→team codebook. This gate therefore protects the codebook itself, not only team privacy. The passwordless URL must remain private to Abdel until the gate closes.
2. Restoring the password boundary is also what closes the league-comparison alias-linkage vector. The comparison tab must not be treated as anonymised until restoration is complete.
3. Each team page now discloses its own alias mapping directly: the viewing club is named in the Team Comparison scatter and pinned, named, at the top of the comparison heat map, while every other club keeps its `Team A` to `Team Z` alias (decision recorded 25 July 2026). That makes one alias mapping explicit rather than inferable per page, so during the passwordless window the full codebook is reconstructible from 16 page visits with no metric matching at all. It reinforces, rather than changes, the rule above: the passwordless URL stays private to Abdel until this gate closes.

## Protected baseline

Commit `2cbfb6e`. Git history retains the reviewed protected-access implementation.

## Restore from baseline

Restore these paths from `2cbfb6e`:

- `app/team/[teamId]/page.tsx`
- `app/api/team-session/`
- `app/unlock/`
- `app/faq/page.tsx`
- `components/dashboard/team-dashboard.tsx`
- `components/unlock-form.tsx`
- `lib/reporting.ts`
- `lib/team-auth.ts`
- `lib/team-session.ts`
- `package.json`
- `scripts/hash-team-password.mjs`
- `tests/team-session*.test.mjs`
- `tests/unlock-form-safety.test.mjs`

Remove `tests/team-dashboard-access.test.mjs`.

## Environment

Do **not** restore `.env.example` wholesale. Preserve `WEB_READER_DB_URL` and add the baseline auth entries:

- `TEAM_PASSWORD_HASHES_JSON`
- `TEAM_SESSION_SIGNING_KEY`
- `TEAM_SESSION_TTL_SECONDS`
- `TEAM_UNLOCK_RATE_LIMIT_ENFORCED`

Treat every legacy password as public and generate new high-entropy V2 passwords.

## Documentation

Replace the temporary passwordless-review rules in `AGENTS.md` and `docs/V2_FOUNDATION.md` with the protected-state contract.

## Configure

- Complete live-team password-hash JSON
- Signing key
- TTL
- Least-privilege reader URL
- Protected preview scope
- A real WAF rule for `POST /api/team-session/unlock`

Verify the deployment-side password, signing, rate-limit, and preview-protection controls independently of application code. Also verify both the live route and its homepage/discovery tile: a valid route can still appear locked if duplicated status is stale.

## Required verification before sharing or cutover

```bash
npm run test:auth
npm run test:auth:routes
npm run typecheck
npm run build
```

Plus browser checks proving:

- exact-team access
- wrong-team denial
- expiry/tamper denial
- logout
- mobile and desktop behavior

## Boundary

An approved database release is not a route/public-promotion action. Any status change in `config/teams.ts`, access-control restoration, deployment, sharing, or production cutover remains a separate explicit approval. Preflight changes none of those boundaries.
