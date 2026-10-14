# Changelog

## 0.1.0 — unreleased

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
