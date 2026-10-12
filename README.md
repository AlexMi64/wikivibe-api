# WikiVibe for macOS

[English](README.md) · [Русский](README.ru.md) · [简体中文](README.zh-CN.md)

A standalone native macOS widget based on [Codenotch](https://github.com/vinzdg/codenotch), built with Swift, AppKit and SwiftUI.

**Account integration is BLOCKED.** The native app builds and runs, but the desktop authentication and account-data contracts have not been confirmed. It does not display an invented balance, treat missing data as zero, or claim that opening the authentication website signs you in.

## What works

- The original native notch, menu-bar entry and account window.
- Screen-edge, size and visibility controls, retained across restarts.
- English, Russian and Simplified Chinese interface text, with an in-app language selector.
- System-browser navigation to `https://auth.wikivibe.dev/`, explicitly separate from application sign-in.

The refresh action currently opens the integration requirements. It does not call an unconfirmed endpoint. Keychain-backed account sessions, browser callbacks, token refresh, logout, real balance and spending, background polling and top-up navigation require the backend contracts below. One-click configuration for Codex, oh-my-pi and OpenCode is outside this stage.

## Build and run

Requires macOS 15 or later, Xcode with the macOS SDK, and XcodeGen. The checked toolchain was Xcode 26.3 (`17C529`), Swift 6.2.4 and XcodeGen 2.46.0.

```sh
git clone https://github.com/AlexMi64/wikivibe-api.git
cd wikivibe-api
brew install xcodegen
make build
make run
```

With configured GitHub SSH access, use `git@github.com:AlexMi64/wikivibe-api.git` instead.

The app is built at `build/DerivedData/Build/Products/Debug/WikiVibe.app`. `make gen` generates the Xcode project; `make clean` removes generated build output. The project and DerivedData are not committed. `Package.resolved` pins the dependencies; the first build may download public Swift packages.

Local builds are unsigned. No signed or notarized installer is provided, and no release, deployment or publishing command is present in the Makefile.

## Runtime and privacy

`Sources/App/AppDelegate.swift` starts the WikiVibe surface only. It does not start third-party provider discovery, agent monitors, local cost indexing, phone-link services, credential migration or automatic updates. Native rendering no longer calls the upstream cost-account discovery layer. Existing Codenotch preferences are not imported, and preference initialization does not read LM Studio configuration or migrate legacy endpoint keys into Keychain.

The imported provider library remains in the source tree because the native components share its types. Its presence is not an active WikiVibe connector. Sparkle remains a build dependency of retained upstream code; the updater is not instantiated and no appcast is configured. Upstream signing identities, update-feed URLs and public signing keys have been removed from product configuration.

Product and scheme: `WikiVibe`. Bundle identifier and logging subsystem: `dev.wikivibe.desktop`. The Swift module remains `Codenotch` for compatibility with existing test imports; this is not the product name.

During early development, review found an indirect upstream discovery path in rendering. That path was removed before the final verification. Historical absence of account-metadata or PII reads in the earlier launch was not established; user credential files were not inspected to investigate it.

## Backend requirements

The canonical specification is [CONNECTORS_FOR_ALEXEY.md](CONNECTORS_FOR_ALEXEY.md), with complete [English](CONNECTORS_FOR_ALEXEY.en.md) and [Simplified Chinese](CONNECTORS_FOR_ALEXEY.zh-CN.md) translations. [BACKEND_CONTRACTS.md](BACKEND_CONTRACTS.md) indexes all three. Observed public responses and proposed schemas are clearly separated; proposed endpoints are not called by the app.

Connection order:

1. Register a desktop public client and confirm the browser-return or device flow and token exchange.
2. Define account identity, token expiry, refresh rotation and session-specific revocation.
3. Confirm account-session access to balance and spending, including currency, precision, reporting period, account/key scope, errors and polling limits.
4. Confirm the official HTTPS top-up URL or the API that supplies it.
5. Have the user sign in themselves, then verify return, restart restoration, real values, refresh, stale/offline handling, expiry/logout and top-up navigation without making a payment.

Inference API keys are not account-session tokens. The API-key-protected `/v1/usage?days=7` endpoint is not a substitute for a confirmed account-session contract.

## Verification

The preceding implementation passed `make build` and 63 tests across 11 isolated native/parser/updater suites. The entire imported test bundle compiled; the full provider/live suite was not executed. The exact regression command was:

```sh
make test TEST_FLAGS='-only-testing:WikiVibeTests/NotchEdgeTests -only-testing:WikiVibeTests/NotchPlacementTests -only-testing:WikiVibeTests/NotchGeometryTests -only-testing:WikiVibeTests/NotchFleetReconcileTests -only-testing:WikiVibeTests/NotchFleetScopeTests -only-testing:WikiVibeTests/NotchVisibilityTests -only-testing:WikiVibeTests/NotchSizeTests -only-testing:WikiVibeTests/NotchPositionPersistenceTests -only-testing:WikiVibeTests/UpdaterOutcomeTests -only-testing:WikiVibeTests/MiniMaxUsageTests -only-testing:WikiVibeTests/OpenCodeUsageTests'
```

Actual application checks covered the account window, notch and menu, browser-button activation without an authenticated state, edge/size/visibility changes, hiding the notch, reopening settings, quitting and appearance persistence after restart. The image-analysis provider was unavailable during the original visual check; window capture and Accessibility inspection did not establish a pixel-perfect layout review.

The three-language update passed 16 affected native tests with zero failures. The actual account window was exercised in English, Russian and Simplified Chinese; account and appearance labels changed live, the status-menu Quit action was localized, and Chinese persisted through quitting and reopening. Captures remain local under ignored `build/`; no screenshot link in this document depends on an uncommitted file.

No real account sign-in, account-session restoration, balance request, payment or inference expenditure was performed. See [CONTRIBUTING.md](CONTRIBUTING.md) for safe local verification and [CHANGELOG.md](CHANGELOG.md) for changes.

## Attribution

Imported from Codenotch commit `bcb28894d1514fef5a810595d64b44a3817c2076`. The upstream MIT [LICENSE](LICENSE) and copyright are preserved. Exact Codenotch MIT and Zstandard BSD notices are included in application resources alongside glyph notices. Windows/Tauri and the upstream website were not imported.

The WikiVibe icon came from a 256×256 local reference image. Larger app-icon sizes are upscaled, not high-resolution originals. Public binary distribution still requires confirmed brand rights and suitable source artwork.
