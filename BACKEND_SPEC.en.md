# WikiVibe desktop: backend integration contracts

[English](BACKEND_SPEC.en.md) · [Русский — canonical specification](BACKEND_SPEC.md) · [简体中文](BACKEND_SPEC.zh-CN.md)

Status: **sign-in implemented; balance and spending out of scope.** The backend owns the server-side decisions. This specification covers native macOS sign-in, account balance and spending, and HTTPS navigation to top-up. Agent configuration and in-app payments are out of scope. If the translations diverge, the Russian specification governs.

Sign-in, session restoration, token refresh and logout are implemented and documented as an existing contract (sections 1, 1a and 2). Balance and spending remain a proposal for a later stage: the app neither requests nor displays them.

## Confirmed public observations

- `https://auth.wikivibe.dev/` serves an HTML single-page application. Opening it does not establish an application session.
- The checked discovery/documentation URLs served HTML rather than a confirmed OIDC/OpenAPI JSON contract.
- Unauthenticated `GET https://auth.wikivibe.dev/api/v1/auth/me` returned HTTP 401 and `{"code":"UNAUTHORIZED","message":"Authorization header is required"}`. The successful response schema and accepted desktop credentials remain unconfirmed.
- `GET https://auth.wikivibe.dev/api/v1/auth/sso/config` returned browser SSO configuration with issuer `https://auth.wikivibe.dev` and redirects for `api.wikivibe.dev` and `dev.wikivibe.dev`. This is not macOS client registration.
- Unauthenticated `GET https://api.wikivibe.dev/v1/usage?days=7` returned HTTP 401 and `{"code":"API_KEY_REQUIRED","message":"Требуется API-ключ"}`. The reference client uses a Bearer API key for this route. It must not be treated as an account-session API.
- Reinspection of the current client confirmed PKCE S256 and state validation in browser SSO. This establishes the browser mechanism, not desktop client registration.

## Current-client investigation

Inspected public scripts, rendered `/docs` and minimal read-only GET responses without extracting browser storage, cookies, API keys or Authorization. No sign-in, key creation, inference or payment was performed.

| Source | Observed contract |
|---|---|
| [Main script](https://api.wikivibe.dev/assets/index-CCkmicLd.js) | Account baseURL is origin-relative `/api/v1`: on the API host, `https://api.wikivibe.dev/api/v1`. Gateway `/v1` is separate. |
| HTTP interceptor | Envelope `{code, message, data}`; code 0 unwraps data; a nonzero code rejects even with HTTP 200. Browser requests add Bearer access token, GET timezone and Accept-Language. |
| [SSO config](https://api.wikivibe.dev/api/v1/auth/sso/config) | HTTP 200: enabled true, issuer `https://auth.wikivibe.dev`, API redirect `https://api.wikivibe.dev/auth/sso/callback`, dev redirect `https://dev.wikivibe.dev/api/auth/sso/callback/`. No desktop registration fields. |
| Browser authorize | GET `https://auth.wikivibe.dev/api/v1/auth/sso/authorize` with `client_id=api`, redirect_uri, state, code_challenge and S256. The app must not reuse api or bypass the redirect allowlist. |
| [Browser callback](https://api.wikivibe.dev/assets/SsoCallbackView-vPD5d71O.js) and main script | State validation precedes POST `/auth/sso/token`, JSON `{client_id, redirect_uri, code, code_verifier}`. The script sends neither grant_type nor response_type. This is the existing web flow, not a proposed standard OAuth contract. |
| Browser lifecycle | Exchange consumers expect `{access_token, refresh_token?, expires_in?, user}`; user has id. POST `/auth/refresh` sends `{refresh_token}` and consumes access_token, refresh_token and expires_in in seconds. POST `/auth/logout` sends refresh_token; revoke-all-sessions is separate and must not implement local logout. Native rotation/revocation semantics remain unconfirmed. |
| Shared browser session | `/auth/sso/session` installs a browser session; `/auth/sso/logout` ends it. Neither proves that a native app can obtain a session from a browser cookie. |
| [Profile](https://api.wikivibe.dev/assets/user-Sw7qdUw9.js) | GET `/user/profile`; GET `/auth/me` checks identity. Without Bearer both return 401 UNAUTHORIZED. A safe GET profile in the permitted Orca page without extracting Bearer also returned 401. No success JSON observed. |
| [Spending](https://api.wikivibe.dev/assets/usage-bJ4Ifxlm.js) | GET `/usage/stats` accepts period or start_date/end_date and optional api_key_id. Dashboard uses GET `/usage/dashboard/stats`. Both returned 401 without credentials. |
| [Dashboard](https://api.wikivibe.dev/assets/DashboardView-BuNjK2_n.js) | UI consumes user.balance, today_actual_cost and total_actual_cost; the client supplies dates/timezone. Complete schemas, null/precision and period boundaries are unconfirmed. Browser value-or-zero fallback must not be copied. |
| [Public settings](https://api.wikivibe.dev/api/v1/settings/public) | HTTP 200/code 0: balance_unit_name USD, balance_unit_symbol $. Documentation URL is `https://api.wikivibe.dev/docs`. Unit is a server setting, not a client assumption. |
| [Rendered docs](https://api.wikivibe.dev/docs) | Documents gateway API-key Bearer and /v1/usage, not native registration/scopes/callback or successful account schemas. OIDC/OAuth discovery and /openapi.json returned SPA HTML; /api/v1/openapi.json returned 404. |
| [Top-up](https://api.wikivibe.dev/purchase) | Public docs link to /purchase; clicking navigated to that HTTPS route. Browser login required. Navigation alone does not create a payment or carry desktop tokens. |

The public tfcli loopback importer on /keys is for API-key configuration, not confirmed native account login, and is not used. Public documentation searches found no macOS registration. This does not establish that backend cannot provide it.

**The desktop client is registered.** Backend `origin/main` carries a fourth client, `desktop` (`shared_auth.desktop_redirect_uri`, default `http://127.0.0.1/callback`). Its validator accepts any loopback port (RFC 8252 §7.3) while pinning scheme, host and path, and `ResolveClient` binds the client id to that address. Balance and spending are outside this task, so their contracts below remain a proposal.

## 1. System-browser sign-in

Purpose: establish an account session for a native public client without collecting a password or embedding a client secret. Owner: backend.

**Existing method: Authorization Code with PKCE (S256).** Implemented and verified:

- `GET https://auth.wikivibe.dev/api/v1/auth/sso/authorize` with `client_id=desktop`, `redirect_uri=http://127.0.0.1:<port>/callback`, `state`, `code_challenge`, `code_challenge_method=S256`.
- Without a central browser session it answers `302` to `https://auth.wikivibe.dev/login?redirect=…`; with one it answers `302` to the registered callback carrying `code` and the original `state`.
- `POST https://api.wikivibe.dev/api/v1/auth/sso/token` with JSON `{client_id, redirect_uri, code, code_verifier}` returns `access_token`, `refresh_token`, `expires_in` (seconds), `token_type` and `user`. `grant_type` and `response_type` are not used.
- An unregistered `client_id`/`redirect_uri` answers `400 INVALID_REQUEST`; a bad `code_verifier` answers `INVALID_CODE_VERIFIER`.

`state` is required, at most 512 bytes and visible ASCII. `code_verifier` is 43...128 base64url characters. Tokens belong exclusively in macOS Keychain; an inference API key is neither an account token nor a refresh token.

## 1a. Session lifecycle

Implemented and verified: `POST https://api.wikivibe.dev/api/v1/auth/refresh` with JSON `{refresh_token}` returns `access_token`, `refresh_token`, `expires_in`, `token_type`, and the refresh token rotates, so the app stores the one it receives. `POST https://api.wikivibe.dev/api/v1/auth/logout` with `{refresh_token}` revokes that token alone, separately from revoking every session of the account. `GET https://api.wikivibe.dev/api/v1/auth/sso/me` with `Bearer` confirms the account and answers `401` once the session is revoked. The app reads `401`/`403` as an expired session rather than a network failure.

## 2. Account identity, restoration, refresh and logout

Purpose: identify the session owner and define the session lifecycle. Owner: backend. **Implemented.**

Account: `GET https://api.wikivibe.dev/api/v1/auth/sso/me` with `Bearer` returns `{user, telegram_user}` in the standard `{code, message, data}` envelope. The app reads only `id`, `username` and `email` from `user` — enough to show who is signed in, and nothing more is stored. The envelope is authoritative: `code != 0` is an error even at HTTP 200.

Refresh: `POST /api/v1/auth/refresh` with `{refresh_token}`; response `{access_token, refresh_token, expires_in, token_type}`. The refresh token rotates, so the app stores the new one — keeping the old would fail the next refresh as revoked. `expires_in` becomes an absolute expiry at receipt rather than being stored as a duration.

Logout and revocation: `POST /api/v1/auth/logout` with `{refresh_token}` revokes that token alone (not every session of the account, unlike `/auth/revoke-all-sessions`). The local session is cleared from the keychain before the server call and regardless of its outcome: an unreachable server must not leave a user signed in on a machine they signed out of.

Restoration: on launch the app reads the session from the keychain. An expired access token is refreshed; a revoked refresh token (`401`/`403`) signs the app out and says so. A network failure is not a sign-out: the session is kept and the account is shown with an unconfirmed marker. A keychain read failure means neither absence nor expiry.

Session generation boundary: a response from a previous session is never applied after sign-out — sign-out clears the held session before the network call, and an in-flight sign-in closes its own listener.

Logout/revocation: confirm endpoint, method, authentication, request/response schemas, session-specific revocation, its distinction from revoke-all, and idempotency. Local logout must remove the Keychain item and cancel in-flight fetches even when the backend is unavailable. Do not invent server revocation. A Keychain read failure does not mean a credential is absent or expired.

Session-generation boundary: a response from an earlier session must not be applied after logout or an account switch. Supply a stable account identifier and a way to verify that returned data belongs to it.

## 3. Account balance and spending

**Outside the current scope.** The task is authorization: the app shows the account and requests no money. What follows is a proposal for a later stage, not an existing contract. The app calls none of these routes and displays neither balance nor spending.

Purpose (later stage): obtain actual money values and spending from the server, not from local agent logs. Owner: backend.

**Browser account routes are identified, but successful JSON schemas and desktop-session applicability remain unconfirmed.** Clarify `/user/profile` and `/usage/stats` rather than inventing another API. Do not substitute the API-key `/v1/usage?days=7` route. Confirm scopes and compatibility with native account sessions.

**Proposed schema, not an existing API:**

```json
{
  "account_id": "example-account",
  "as_of": "2026-10-13T12:00:00Z",
  "balance": { "amount_minor": 0, "currency": "USD", "scale": 2 },
  "expenses": {
    "amount_minor": 0,
    "currency": "USD",
    "scale": 2,
    "scope": "account",
    "period_start": "2026-10-01T00:00:00Z",
    "period_end": "2026-11-01T00:00:00Z"
  }
}
```

Decimal strings may replace integer minor units, but the contract must define precision, currency, negative balances, rounding, missing/null fields and numeric limits. `0` is a real zero; an absent field is not. Specify account/key scope, UTC ISO-8601 dates, inclusive/exclusive period boundaries, the reporting timezone and a freshness timestamp. A snapshot must be consistent for one account and one point in time.

Define HTTP and business semantics: 401 for expired/revoked credentials; 403 for scope/permission errors; 429 with Retry-After; 5xx and transient network errors; business errors inside HTTP 200 if an envelope is used. State the schema version and required fields. On a network failure, retain the last confirmed amount with its timestamp and a stale indicator. Without a successful fetch, show no amount.

Polling: publish the minimum interval, rate limit and cache/ETag semantics. In the absence of guidance, the proposal is once every 60 seconds with an active confirmed session, one request at a time. Stop on logout, cancel the old request and reject its response. Manual refresh must respect server throttling.

## 4. HTTPS top-up navigation

Purpose: open the official browser flow without creating a payment in the app. Owner: backend.

**Confirmed URL:** `https://api.wikivibe.dev/purchase`. Public documentation and the router identify top-up; navigation was exercised without payment. Browser sign-in is required. The app opens only this fixed HTTPS URL without tokens or session binding in the query. Opening it is neither desktop authentication nor payment completion.

## Minimum connection order

1. ~~Desktop public client, browser return, token exchange and safe error schema.~~ **Done** (section 1).
2. ~~Account identity, expiry, refresh and session-specific revocation.~~ **Done** (sections 1a and 2).
3. Account balance/spending schema, units, reporting period and polling policy. **Not part of the current scope.**
4. `https://api.wikivibe.dev/purchase` remains a website button; no in-app payment.
5. The user signs in themselves. Verify return, restart restoration, expiry and logout. Access to anyone else's credentials is neither required nor permitted.
