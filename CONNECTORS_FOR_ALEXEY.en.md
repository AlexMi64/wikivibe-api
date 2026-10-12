# WikiVibe desktop: backend integration contracts

[English](CONNECTORS_FOR_ALEXEY.en.md) · [Русский — canonical specification](CONNECTORS_FOR_ALEXEY.md) · [简体中文](CONNECTORS_FOR_ALEXEY.zh-CN.md)

Status: **BLOCKED**. The backend owns the server-side decisions. This specification covers native macOS sign-in, account balance and spending, and HTTPS navigation to top-up. Agent configuration and in-app payments are out of scope. If the translations diverge, the Russian specification governs.

## Confirmed public observations

- `https://auth.wikivibe.dev/` serves an HTML single-page application. Opening it does not establish an application session.
- The checked discovery/documentation URLs served HTML rather than a confirmed OIDC/OpenAPI JSON contract.
- Unauthenticated `GET https://auth.wikivibe.dev/api/v1/auth/me` returned HTTP 401 and `{"code":"UNAUTHORIZED","message":"Authorization header is required"}`. The successful response schema and accepted desktop credentials remain unconfirmed.
- `GET https://auth.wikivibe.dev/api/v1/auth/sso/config` returned browser SSO configuration with issuer `https://auth.wikivibe.dev` and redirects for `api.wikivibe.dev` and `dev.wikivibe.dev`. This is not macOS client registration.
- Unauthenticated `GET https://api.wikivibe.dev/v1/usage?days=7` returned HTTP 401 and `{"code":"API_KEY_REQUIRED","message":"Требуется API-ключ"}`. The reference client uses a Bearer API key for this route. It must not be treated as an account-session API.
- The public frontend contains login, refresh, logout and SSO route names. Those names and browser localStorage use do not establish desktop callback support, PKCE, client registration, token schemas or an account-usage schema.

## 1. System-browser sign-in

Purpose: establish an account session for a native public client without collecting a password or embedding a client secret. Owner: backend.

**No desktop endpoint is confirmed.** Publish the method, URL, parameters and successful response schema. The app calls none of the proposed routes or flows below.

**Proposal, not an existing API:** Authorization Code with PKCE (S256). Register a public client and one permitted return mechanism: HTTP loopback on localhost with an agreed port policy, or a protected registered callback. If only device authorization is supported, publish that flow instead.

Define the authorization request fields: `client_id`, `redirect_uri`, `response_type`, scopes, `state`, `code_challenge` and `code_challenge_method`. The callback must return a single-use `code` and the original `state`, or a named error. For the POST token exchange, define the content type and `grant_type`, `client_id`, `code`, `redirect_uri` and `code_verifier` fields.

Proposed token response: `access_token: string`, `token_type: "Bearer"`, `expires_in: integer seconds > 0`, `refresh_token?: string`, `scope?: string`. Confirm the actual names, envelope and optional/null semantics. Tokens belong exclusively in macOS Keychain. An inference API key is neither an account token nor a refresh token.

Specify cancellation, invalid state/redirect/code, expired or reused code, timeout, HTTP 400/401/403/429/5xx, business error codes, safe user-facing messages and Retry-After. Define the code lifetime, attempt limits and replay protection. Until exchange succeeds and account identity is confirmed, opening the browser leaves the app unauthenticated.

## 2. Account identity, restoration, refresh and logout

Purpose: identify the session owner and define the session lifecycle. Owner: backend.

The observed GET `/api/v1/auth/me` does not establish a successful schema. Confirm the host, path, method and authentication scheme. Proposed account response: stable, non-sensitive `account_id: string`, `display_name?: string`. Define the envelope and minimum scopes. Examples must contain no real PII.

Refresh: confirm the POST endpoint, request schema, expiry units, rotation policy, invalidation of the previous refresh token, and handling of concurrent or repeated requests. Proposed request: `refresh_token: string`; proposed response: the token schema above. Supply the refresh-token lifetime and the terminal expired/revoked-session error.

Logout/revocation: confirm endpoint, method, authentication, request/response schemas, session-specific revocation, its distinction from revoke-all, and idempotency. Local logout must remove the Keychain item and cancel in-flight fetches even when the backend is unavailable. Do not invent server revocation. A Keychain read failure does not mean a credential is absent or expired.

Session-generation boundary: a response from an earlier session must not be applied after logout or an account switch. Supply a stable account identifier and a way to verify that returned data belongs to it.

## 3. Account balance and spending

Purpose: obtain actual money values and spending from the server, not from local agent logs. Owner: backend.

**No account-session endpoint or successful JSON schema is confirmed.** Do not substitute the API-key `/v1/usage?days=7` route. Confirm the host, GET method, route, scopes and compatibility with account-session authentication.

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

**No navigation contract is confirmed.** Supply either a fixed HTTPS URL or an endpoint that returns one, with method, authentication and request/response schemas. Proposed response: `url: string`, `expires_at?: UTC ISO-8601 string`. Confirm allowed hosts, sign-in requirements, session binding and lifetime. Do not put account tokens in query strings or make a payment during verification.

## Minimum connection order

1. Desktop public client, browser return, token exchange and safe error schema.
2. Account identity, expiry, refresh and session-specific revocation.
3. Account balance/spending schema, units, reporting period and polling policy.
4. Official HTTPS top-up navigation contract.
5. The user signs in themselves. Verify return, restart restoration, real amounts, refresh, offline/stale handling, expiry/logout and top-up navigation without payment. Access to anyone else's credentials is neither required nor permitted.
