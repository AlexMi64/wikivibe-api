# Changelog

## 0.1.0 — unreleased

### Native application

- Imported native macOS Codenotch at `bcb28894d1514fef5a810595d64b44a3817c2076`; preserved MIT LICENSE and bundled third-party notices.
- Set WikiVibe product/scheme/display name, `dev.wikivibe.desktop` bundle ID and logging subsystem; kept macOS 15.0 minimum.
- Reused the upstream notch/fleet, appearance preferences, model status and glyph rendering; added WikiVibe icon assets from the read-only local reference.
- Replaced upstream startup with a WikiVibe-only native surface. No automatic credential discovery, agent monitoring, local cost indexing, phone serving, token refreshing or update feed initialization.
- Removed the hidden `Costs.decorate` and `CostSection.rowCount` dependency from native snapshot publication/card measurement; neither rendering nor initial WikiVibe snapshot constructs `CostAccountStore`.
- Removed LM Studio config discovery and legacy custom-endpoint Keychain migration from `Preferences` initialization.
- Included exact Codenotch MIT and vendored Zstandard BSD license copies in application resources, alongside retained glyph notices.
- Removed upstream signing-team/feed/key settings and release/publish recipes. Local build/test output is unsigned.
- Added an explicit integration-required state and system-browser navigation to the public auth website. Browser opening never changes account state or displays a balance.
- Removed the unimplemented account-provider scaffold and its browser-route extension; no fake backend connector or numeric account fixtures were introduced.
- Added English, Russian and Simplified Chinese prerequisite messages and an in-app language selector; preserved upstream attribution in the visible footer and license.
- Removed obsolete author-handle and current-upstream-version assertions; updater timeout test checks its state transition, not download-site wording.
- Fixed upstream MiniMax/OpenCode test arithmetic inference with explicit `TimeInterval` values; expected durations remain unchanged.

### Backend boundary

- Added the canonical Russian `CONNECTORS_FOR_ALEXEY.md` and complete English and Simplified Chinese translations, linked from `BACKEND_CONTRACTS.md`. Confirmed public evidence is separate from proposed desktop auth/session/account-money/top-up contracts.
- Account Keychain persistence, browser return/token exchange, real balance/expenses, refresh/logout, stale-session handling and top-up remain **BLOCKED** on backend contracts.
- One-button agent configuration is not implemented.

### Observed verification

- Generated WikiVibe Xcode project and completed native build (`BUILD SUCCEEDED`).
- Compiled the full test bundle and executed 11 isolated suites: 63 tests, zero failures (`TEST SUCCEEDED`). Full provider/live execution was not performed.
- Launched the final application; observed account/notch/menu windows and inspected account UI text through macOS Accessibility. Browser-button activation left the app unavailable with no invented values.
- Exercised edge/size/visibility controls, Hide, menu-bar settings and Quit. Left / Small / Always show persisted across an actual application restart; original appearance was then restored.
- Captured final account and notch windows in `build/wikivibe-account-smoke.png` and `build/wikivibe-notch-smoke.png`. Pixel-level inspection was unavailable because the image-analysis provider returned 429; no end-to-end authentication/balance or clipping claim is made.
- Verified exact MIT/BSD notices in the built application. Source review severed a hidden upstream discovery path; historical absence of metadata/PII reads in the early development launch was not established.

### Three-language source publication

- Added complete English, Russian and Simplified Chinese README versions and contribution guidance. Chinese uses natural conversational technical wording, not proficiency-certification claims.
- Reused `Preferences.language`, `L10n.t` and the existing string catalog. Account copy and status-menu actions update live; fleet integration-menu entries now propagate to existing notch controllers.
- Completed the affected native regression: 16 tests across four suites, zero failures (`TEST SUCCEEDED`); the full imported test bundle compiled.
- Observed English → Russian → Simplified Chinese through the actual language picker. Account labels and unavailable-data messages localized correctly; the Chinese status-menu Quit action terminated the app, and Chinese survived reopening. Verified the settings command and native notch integration/Quit entries in all three languages, including live changes on existing controllers. After temporarily keeping the notch visible, restored the original Russian / Bottom / Large / Show on hover settings.
- Final `make build` completed (`BUILD SUCCEEDED`) after binding the settings command to the existing persisted language key. Standard AppKit chrome still follows the system language; the app does not rewrite `AppleLanguages`.
- Sanitized private workspace paths in the historical plan and recorded the owner's later source-publication authorization. No release, deployment, payment or backend mutation is authorized by this cutover.

### Русский

Добавлены русский, английский и упрощённый китайский интерфейс, выбор языка, три версии README и полной серверной спецификации. Переключение проверено в работающем приложении; китайский выбор сохранился после выхода через меню и перезапуска. Затронутая регрессия: 16 тестов, 0 ошибок. Интеграция аккаунта, реальные суммы и платежи не выполнялись; серверная граница остаётся **BLOCKED**.

### 简体中文

新增英文、俄文和简体中文界面、应用内语言选择，以及三种语言的 README 和完整后端规范。实际运行时检查了语言切换；通过中文菜单退出并重新打开后，中文选择仍然保留。受影响的 16 项回归测试全部通过。没有进行账号登录、金额请求或付款，后端接入仍为 **BLOCKED**。
