# Changelog

## 0.1.0 — unreleased

### Account API keys and agent configuration

- Added a configurable API keys card to account-window visibility, ordering, adaptive layout and Reset. The card reads all account-key pages through the existing signed-in session; remembers only the account's selected key ID, trusted API address and selected agents; and clears in-memory keys and pending requests when dismissed.
- Separated account authentication from gateway authentication: the account credential reads `/api/v1/keys`, while the selected API key reads its gateway's `/v1/models`. Account-key 403 responses and refused gateway keys do not masquerade as expired sign-in. Requests refuse redirects and sanitize upstream errors, model IDs and diagnostic output.
- Serialized rotating-session refresh across wallet and key requests, including already-completed rotation, and reject late key responses after sign-out or reauthentication into the same account.
- Added Codex, oh-my-pi, OpenCode and Claude Code configuration with model catalogs and protocol-aware routing. Confirmed Codex apply activates WikiVibe as the default desktop/CLI provider and attaches its catalog in the root config, rather than creating an undiscoverable CLI-only profile. An available current text model is retained, otherwise the first text model is selected; the previous profile selection is cleared without deleting its definition. Reapplication removes the former plugin-owned profile only while unedited. OMP roles and OpenCode's active model remain intact. Claude Code changes its global Anthropic transport, with a separate warning; its picker requires version 2.1.242 or newer.
- Writes and backup restoration require a file/model preview and explicit confirmation. A canonical request/file fingerprint rejects stale previews without depending on JSON object-field order. Existing path, ownership, link, lock and concurrent-edit checks remain in place.
- Configuration requires local Node.js 22+. The bundled adapter subset and jsonc-parser 3.3.1 / yaml 2.8.1 need no runtime download; their MIT/ISC notices ship with the app. Credentials travel to the child process only over stdin, not argv, environment or request files.
- Show plain-text-key and secret-bearing-backup warnings, per-file partial results, and confirmed restoration that refuses later user edits. Standard config files are supported; custom homes, environment/project overrides, managed policies, SSH and WSL are not configured. A model listing does not prove inference, tools, streaming, reasoning or image support.
- Added English, Russian and Simplified Chinese interface copy and documentation. Legacy localized README entry points now link to the maintained trilingual guide instead of claiming account/agent integration is blocked.
- Verification: `make build` succeeded, and the focused key/session/recovery/wallet run passed 36 tests with zero failures. Regressions cover shared rotating refresh, reauthentication races, secret echoes, protocol routing, file permissions, byte-exact restoration of original Codex defaults, safe old-profile removal, stale previews, and reordered JSON confirmation. A separate runner smoke applied all four agents with reordered request fields, restored the original fixture exactly and refused a changed file, using only an isolated HOME and synthetic credentials. Native Codex smoke also checked unavailable-model fallback, image-only refusal and stale Codex confirmation.
- Actual-app verification loaded account keys and a selected key's model catalog, opened the warning/file/model preview, and cancelled it without applying. Accessibility checks exercised all three languages, card hide/show/reorder/reset and scrolling at 420×620; screenshot pixel review was unavailable. After the final build, the updated application was relaunched and the new Codex default-provider warning was exercised through Preview/Cancel in English, Russian and Simplified Chinese, without confirming a real configuration write.
- Native Codex verification used the desktop-bundled CLI 0.154.0-alpha.6.2 without provider/catalog overrides: `config/read` returned the active WikiVibe route and retained effective model, and `model/list` returned the synthetic catalog. Desktop 26.908.40834 then displayed the same synthetic WikiVibe choices in its actual menu from the repaired adapter output, in an isolated HOME and UI data directory. OpenCode v2.0.1's read-only `/api/provider` and `/api/model` exposed the existing enabled WikiVibe routes and models; its actual desktop model chooser displayed WikiVibe without changing the selected model. OMP v18.10.2 exposed both fixture models through its native catalog command in an isolated HOME. Claude Code CLI was unavailable; its configuration write/restore was integration-tested, not its picker. Verification sent no inference, payment or key mutation requests and did not write real agent configurations. The full provider/live and known-stalling callback-listener suites were not rerun.

### Customizable account window

- Replaced the fixed-width account column with Account, Balance, and Widget and language cards on a shared grid. Controls fill their column, labels and balance values align, and sign-in explanations expand separately.
- Added a resizable window with saved size/position; adaptive (up to two columns), vertical, and horizontal (up to three columns) layouts; comfortable/compact spacing; card reorder and visibility controls. Narrow windows reduce columns and scroll instead of clipping controls.
- Persist layout choices in `Preferences`. Customize and layout-only Reset remain reachable in the header when every card is hidden. Reset preserves authentication, language, widget preferences and window dimensions; hiding Balance does not change polling.
- Added English, Russian and Simplified Chinese labels and accessibility descriptions for the new controls.
- Verification: `make build` succeeded. A throwaway runtime smoke exercised column-width boundaries, card order/hide/show, JSON round-trip and duplicate-order normalization. In the actual macOS app, Accessibility actions verified vertical/adaptive/three-column horizontal geometry, compact spacing, reorder/hide/all-hidden recovery, reset preserving language/widget values, scrolling at 420-point window width, and all three interface languages. A quit/relaunch restored the 420×620 window frame, reordered cards and hidden Account card. Restored Russian, all cards and adaptive layout afterward. Geometry/control checks used macOS Accessibility; screenshot pixel review was unavailable. Authentication/backend/provider behavior was not changed; no full provider/live test run was performed.

### Balance recovery after connectivity loss

- Classify HTTP 401/403 before decoding the success envelope, including string-code JSON, HTML and empty error bodies. These responses no longer get stuck as `unreadable response (HTTP 401)`.
- Renew expired access tokens during balance polling. On an unexpected authentication failure, rotate and save the session, then retry the balance once. A network failure keeps the session for the next poll; a refused refresh or repeated authentication failure requires sign-in.
- Keep polling after an offline startup. Serialize startup renewal with balance loading and discard responses belonging to a session that was signed out.
- Verified: 25 recovery/session/wallet tests passed, including five isolated HTTP-transport recovery scenarios; `make build` succeeded. In the running updated app, the balance loaded and manual refresh completed without a visible error. System connectivity was not disabled during this smoke check.
- Verification limit: the broader auth suite passed before the final startup-serialization change; its later rerun stalled in the existing callback-listener cancellation test with a SwiftNIO event-loop-shutdown error. The final focused run above excludes that callback suite.

### Desktop authorization

- Implemented WikiVibe account sign-in: Authorization Code with PKCE S256 against the registered `desktop` public client, in the system browser. The password is typed on the WikiVibe site; the app never sees it and no client secret ships in the binary.
- Added a one-shot loopback listener on `127.0.0.1` that catches the browser return. The port is chosen by the OS (RFC 8252 §7.3) because a fixed one would break sign-in whenever something else holds it; only the registered scheme, host and path are accepted. `state` is verified, so a callback from a different attempt cannot settle the current one, and unrelated requests (a browser's `favicon.ico`) are answered without ending the wait.
- Added `WikiVibeSessionStore`: the session (access and refresh tokens plus the account) is a single keychain item under service `wikivibe-desktop-session`. Tokens never reach `UserDefaults`, a log or the web-view store.
- Added session lifecycle: restore on launch, refresh of an expired access token with the rotated refresh token stored, sign-out that clears the keychain before and regardless of the server call, and account confirmation against `/api/v1/auth/sso/me`. `401`/`403` means an expired session; a network failure keeps the session and marks it unconfirmed rather than signing the user out.
- Replaced the prerequisite placeholder window with an account window: sign-in, cancel, sign-out, live state, and "Open WikiVibe" as a plain browser navigation. The notch row reports the signed-in account.
- Localized the new copy into Russian, Simplified Chinese and English; removed the obsolete prerequisite keys and the dead "no confirmed data" rows.
- Balance and spending are deliberately not implemented: this task is authorization only. The app requests no money and displays no amount.

### Account balance and the website button

- Added the account balance: regular, bonus and on hold, read from `/api/v1/user/profile` with the unit taken from `/api/v1/settings/public`. The unit is an operator setting, so it is read rather than assumed.
- A missing field is not zero, and a balance that could not be read stays unread: the app reports it and keeps the session, because only the number is unknown. An explicit zero from the server is shown as data.
- The balance refreshes on its own — every minute, and every 15 seconds while the account window is open — through one poll that exists only while a session does and stops on sign-out.
- Retargeted "Open the website" from the issuer (`auth.wikivibe.dev`, a separate origin with its own cookie) to the panel (`api.wikivibe.dev`), which keeps a first-party session and renews it itself. The old target looked like being signed out, because the app had a session and the browser did not. The button and its hint now say what actually happens.
- Verified in production: the widget shows the balance, and the poll is visible in the nginx access log as `settings/public` + `user/profile` pairs every ~16 seconds. 36 tests pass, zero failures.

### Observed verification

- Backend: added a fourth registered client `desktop` (`shared_auth.desktop_redirect_uri`, default `http://127.0.0.1/callback`) with validator, port matcher and `ResolveClient` binding. `go test -tags=unit ./internal/config/ ./internal/service/ ./internal/handler/` — shared-auth suites pass.
- Client: `Sources/Auth` and the test file compile. 341 assertions executed against the real callback listener and the session lifecycle, zero failures. Xcode is not installed on the verifying machine, so XCTest itself could not be linked and the app was not launched; see the README for that limit.
- Live endpoints confirmed unauthenticated: `authorize` answers `400 INVALID_REQUEST` for the unregistered desktop callback today, and the flow returns `302` once the client is registered.

### Native application

- Added the native macOS application; preserved required licenses and bundled third-party notices.
- Set WikiVibe product/scheme/display name, `dev.wikivibe.desktop` bundle ID and logging subsystem; kept macOS 15.0 minimum.
- Added the screen-edge interface, appearance preferences, model status, glyph rendering and WikiVibe icon assets.
- Limited startup to the WikiVibe interface. No automatic credential discovery, agent monitoring, local cost indexing, phone serving, token refreshing or update feed initialization.
- Removed the hidden `Costs.decorate` and `CostSection.rowCount` dependency from native snapshot publication/card measurement; neither rendering nor initial WikiVibe snapshot constructs `CostAccountStore`.
- Removed LM Studio config discovery and legacy custom-endpoint Keychain migration from `Preferences` initialization.
- Included MIT, Zstandard BSD and graphic-asset license notices in application resources.
- Removed unused signing-team/feed/key settings and release/publish recipes. Local build/test output is unsigned.
- Added an explicit integration-required state and system-browser navigation to the public auth website. Browser opening never changes account state or displays a balance.
- Removed the unimplemented account-provider scaffold and its browser-route extension; no fake backend connector or numeric account fixtures were introduced.
- Added English, Russian and Simplified Chinese prerequisite messages and an in-app language selector.
- Removed obsolete author-handle and version-wording assertions; the updater timeout test checks its state transition, not download-site wording.
- Fixed MiniMax/OpenCode test arithmetic inference with explicit `TimeInterval` values; expected durations remain unchanged.

### Backend boundary

- Added the canonical Russian `BACKEND_SPEC.md` and complete English and Simplified Chinese translations, linked from `BACKEND_CONTRACTS.md`. Confirmed public evidence is separate from proposed desktop auth/session/account-money/top-up contracts.
- Account Keychain persistence, browser return/token exchange, refresh/logout and session restore were blocked at this stage on a registered desktop client; they were implemented later in the same unreleased version (see *Desktop authorization*). Balance/expenses remain out of scope, and top-up is a website button.
- One-button agent configuration is not implemented.

### Observed verification

- Generated WikiVibe Xcode project and completed native build (`BUILD SUCCEEDED`).
- Compiled the full test bundle and executed 11 isolated suites: 63 tests, zero failures (`TEST SUCCEEDED`). Full provider/live execution was not performed.
- Launched the final application; observed account/notch/menu windows and inspected account UI text through macOS Accessibility. Browser-button activation left the app unavailable with no invented values.
- Exercised edge/size/visibility controls, Hide, menu-bar settings and Quit. Left / Small / Always show persisted across an actual application restart; original appearance was then restored.
- Captured final account and notch windows in `build/wikivibe-account-smoke.png` and `build/wikivibe-notch-smoke.png`. Pixel-level inspection was unavailable because the image-analysis provider returned 429; no end-to-end authentication/balance or clipping claim is made.
- Verified exact MIT/BSD notices in the built application. Source review severed a hidden account-discovery path; historical absence of metadata/PII reads in the early development launch was not established.

### Three-language source publication

- Added complete English, Russian and Simplified Chinese README versions and contribution guidance. Chinese uses natural conversational technical wording, not proficiency-certification claims.
- Placed the complete Russian, English and Simplified Chinese texts directly in the main `README.md`, with Russian first and language-section navigation. Separate localized README files remain available.
- Reused `Preferences.language`, `L10n.t` and the existing string catalog. Account copy and status-menu actions update live; fleet integration-menu entries now propagate to existing notch controllers.
- Completed the affected native regression: 16 tests across four suites, zero failures (`TEST SUCCEEDED`); the full test bundle compiled.
- Observed English → Russian → Simplified Chinese through the actual language picker. Account labels and unavailable-data messages localized correctly; the Chinese status-menu Quit action terminated the app, and Chinese survived reopening. Verified the settings command and native notch integration/Quit entries in all three languages, including live changes on existing controllers. After temporarily keeping the notch visible, restored the original Russian / Bottom / Large / Show on hover settings.
- Final `make build` completed (`BUILD SUCCEEDED`) after binding the settings command to the existing persisted language key. Standard AppKit chrome still follows the system language; the app does not rewrite `AppleLanguages`.
- Sanitized private workspace paths in the historical plan and recorded the owner's later source-publication authorization. No release, deployment, payment or backend mutation is authorized by this cutover.
- Tightened product descriptions and removed the account footer. Required copyright and license notices remain in the repository and application resources.
- Rebuilt after the text cleanup (`BUILD SUCCEEDED`) and relaunched the resulting executable. Accessibility inspection confirmed the footer was absent in Russian, English and Simplified Chinese; Russian / Bottom / Large / Show on hover remained set afterward. The string catalog parsed, GitHub rendered the trilingual README, local documentation links resolved and bundled license notices matched their source files. Screenshot analysis was unavailable (429); no pixel-level clipping claim is made.

### Confirmed web contracts and native top-up navigation

- Preserved the owner's backend-documentation rename to `BACKEND_SPEC.md`, `BACKEND_SPEC.en.md` and `BACKEND_SPEC.zh-CN.md`; updated the index and complete RU-first trilingual README.
- Reinspected public assets, rendered `/docs`, SSO config, public settings and unauthenticated account routes. Documented browser PKCE S256, `/api/v1` base, envelope and frontend-consumed profile/spending fields separately from successful server schemas. No browser credentials were extracted, and no account, API-key, inference or payment operation was performed.
- Confirmed official `https://api.wikivibe.dev/purchase` by navigating its documentation link. Added a localized native button using the existing system-browser pattern, without tokens or a payment request.
- Clarified the then-remaining external prerequisite: a registered public desktop client_id, allowed callback/loopback or device flow, token applicability/scopes and successful account/money contracts. No dormant connector or fake data was added. The desktop client and native authorization were added later in the same unreleased version (see *Desktop authorization*); account money contracts remain a proposal.
- New `make build`: `BUILD SUCCEEDED`; four affected native suites: 16 tests, zero failures, `TEST SUCCEEDED`. The full test bundle compiled; no full provider/live suite ran.
- Quit the old executable and launched the new build. Pressed its top-up action with no browser-opening error; the app remained unauthenticated with missing amounts. App-window Accessibility verified Russian, English and Simplified Chinese prerequisite and button labels. Restored Russian / Bottom / Large / Show on hover. Captured only the app-owned window; image analysis was unavailable, so pixel-level clipping is not asserted. Temporary smoke helpers and this stage's capture were removed after verification.

### Русский

Добавлены русский, английский и упрощённый китайский интерфейс, выбор языка, три версии README и полной серверной спецификации. Переключение проверено в работающем приложении; китайский выбор сохранился после выхода через меню и перезапуска. Затронутая регрессия: 16 тестов, 0 ошибок. На том этапе вход в аккаунт ещё не был реализован; он добавлен позже в этой же невыпущенной версии (см. *Desktop authorization*). Баланс и расходы вне объёма.

### 简体中文

新增英文、俄文和简体中文界面、应用内语言选择，以及三种语言的 README 和完整后端规范。实际运行时检查了语言切换；通过中文菜单退出并重新打开后，中文选择仍然保留。受影响的 16 项回归测试全部通过。该阶段尚未实现账号登录；登录已在同一未发布版本中补上（见 *Desktop authorization*）。余额和支出不在范围内。
