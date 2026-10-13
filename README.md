# WikiVibe for macOS

[Русский](#русский) · [English](#english) · [简体中文](#简体中文)

## Русский

WikiVibe — приложение для macOS с виджетом у края экрана и меню в строке состояния.

**Интеграция аккаунта заблокирована — BLOCKED.** Приложение собирается и запускается. Браузерный PKCE и маршруты account API обнаружены, но публичный desktop client_id, разрешённый callback и применимость токенов к настольному клиенту не подтверждены. Оно не показывает вымышленный баланс, не подменяет отсутствие данных нулём и не выдаёт открытие сайта за успешный вход.

### Что работает

- Виджет у края экрана, пункт в строке меню и окно аккаунта.
- Настройка края экрана, размера и видимости с сохранением после перезапуска.
- Русский, английский и упрощённый китайский интерфейс с выбором языка в приложении.
- Открытие `https://auth.wikivibe.dev/` в системном браузере. Переход на сайт явно отделён от входа в приложение.
- Открытие подтверждённого `https://api.wikivibe.dev/purchase` кнопкой «Пополнить на сайте», без передачи токенов. Вход в браузере и оплата остаются у пользователя.

Команда обновления пока открывает объяснение необходимых условий интеграции и не выполняет account-запросы. Хранение сессии в Keychain, возврат из браузера, обновление токенов, выход, реальные баланс и расходы, ручное/фоновое обновление со stale/error состояниями остаются BLOCKED до desktop-регистрации и подтверждения успешных схем. Настройка Codex, oh-my-pi и OpenCode одной кнопкой в этот этап не входит.

### Сборка и запуск

Нужны macOS 15 или новее, Xcode с macOS SDK и XcodeGen. Проверенная среда: Xcode 26.3 (`17C529`), Swift 6.2.4 и XcodeGen 2.46.0.

```sh
git clone https://github.com/AlexMi64/wikivibe-api.git
cd wikivibe-api
brew install xcodegen
make build
make run
```

Если доступ к GitHub по SSH настроен, вместо HTTPS можно использовать `git@github.com:AlexMi64/wikivibe-api.git`.

Приложение появится в `build/DerivedData/Build/Products/Debug/WikiVibe.app`. Команда `make gen` создаёт проект Xcode; `make clean` удаляет результаты сборки и сгенерированный проект. Эти файлы не входят в репозиторий. Версии зависимостей закреплены в `Package.resolved`; при первой сборке могут загружаться публичные Swift-пакеты.

Локальная сборка не подписана. Подписанного установщика или сборки, прошедшей проверку Apple, нет; Makefile не содержит команд выпуска, публикации или развёртывания.

### Запуск и конфиденциальность

`Sources/App/AppDelegate.swift` запускает только интерфейс WikiVibe. Поиск аккаунтов сторонних сервисов, наблюдение за агентами, индексация локальных расходов, сервис связи с телефоном, миграция учётных данных и автоматические обновления не запускаются. Отрисовка не обращается к механизму обнаружения аккаунтов. При создании настроек не читается конфигурация LM Studio и не переносятся старые ключи пользовательских API в Keychain.

Наличие библиотек провайдеров в исходниках не означает работающий коннектор WikiVibe. Sparkle остаётся зависимостью сборки, но объект обновления не создаётся, а канал обновлений не настроен. Данные подписи, URL обновлений и открытый ключ не настроены.

Продукт и схема Xcode: `WikiVibe`. Идентификатор приложения и подсистема журналирования: `dev.wikivibe.desktop`.

На раннем этапе ревью обнаружило косвенный вызов поиска сторонних аккаунтов из отрисовки. До финальной проверки эту цепочку удалили. Отсутствие чтений метаданных аккаунтов или персональных данных при более раннем запуске не установлено; пользовательские файлы с учётными данными для выяснения этого не исследовались.

### Что требуется от сервера

Каноническая спецификация — [BACKEND_SPEC.md](BACKEND_SPEC.md); полные переводы доступны на [английском](BACKEND_SPEC.en.md) и [китайском](BACKEND_SPEC.zh-CN.md). [BACKEND_CONTRACTS.md](BACKEND_CONTRACTS.md) содержит ссылки на все три версии. Наблюдавшиеся публичные ответы отделены от предложений: приложение не вызывает предложенные, но неподтверждённые методы.

Порядок подключения:

1. Зарегистрировать настольный публичный клиент, подтвердить возврат из браузера либо сценарий авторизации устройства и обмен кода на токены.
2. Определить идентификатор аккаунта, сроки действия токенов, ротацию при обновлении и отзыв отдельной сессии.
3. Подтвердить доступ по сессии аккаунта к балансу и расходам: валюту, точность, период, область аккаунта или ключа, ошибки и ограничения опроса.
4. Использовать подтверждённый `https://api.wikivibe.dev/purchase`; не передавать токены и не создавать платёж.
5. Пользователь самостоятельно входит в аккаунт. Затем проверяются возврат, восстановление после перезапуска, реальные суммы, обновление, устаревшие данные при потере сети, истечение сессии, выход и переход к пополнению без платежа.

Ключи inference API и токены сессии аккаунта — разные учётные данные. Защищённый API-ключом метод `/v1/usage?days=7` не заменяет подтверждённый контракт для сессии аккаунта.

### Проверки

До языковых изменений успешно выполнены `make build` и 63 теста в 11 изолированных наборах для нативных компонентов, парсеров и состояния обновления. Скомпилирован весь тестовый модуль; полный набор сторонних провайдеров и проверок с реальными сервисами не запускался. Точная команда:

```sh
make test TEST_FLAGS='-only-testing:WikiVibeTests/NotchEdgeTests -only-testing:WikiVibeTests/NotchPlacementTests -only-testing:WikiVibeTests/NotchGeometryTests -only-testing:WikiVibeTests/NotchFleetReconcileTests -only-testing:WikiVibeTests/NotchFleetScopeTests -only-testing:WikiVibeTests/NotchVisibilityTests -only-testing:WikiVibeTests/NotchSizeTests -only-testing:WikiVibeTests/NotchPositionPersistenceTests -only-testing:WikiVibeTests/UpdaterOutcomeTests -only-testing:WikiVibeTests/MiniMaxUsageTests -only-testing:WikiVibeTests/OpenCodeUsageTests'
```

В работающем приложении проверены окно аккаунта, виджет, меню, нажатие браузерной кнопки без смены состояния авторизации, край экрана, размер, видимость, скрытие, повторное открытие настроек, выход и сохранение оформления после перезапуска. Во время первоначальной визуальной проверки сервис анализа изображений был недоступен. Снимки окон и Accessibility не доказывают отсутствие всех дефектов вёрстки.

После добавления трёх языков затронутые нативные наборы прошли 16 тестов без ошибок. В реальном окне проверены английский, русский и упрощённый китайский: текст аккаунта и настройки оформления обновляются при переключении, команда выхода в меню переведена, китайский сохраняется после выхода и повторного запуска. Снимки остаются локально в игнорируемом `build/`; документация не ссылается на них как на опубликованные файлы.

Повторное исследование публичного web-клиента и отрисованного `/docs` подтвердило браузерный PKCE, account base `/api/v1`, envelope и переход к пополнению. Новая сборка успешна; 16 тестов в `NotchEdgeTests`, `NotchFleetScopeTests`, `NotchVisibilityTests`, `NotchSizeTests` прошли без ошибок. Пересобранное приложение перезапущено, top-up action нажат без ошибки открытия браузера; сессия не появилась, суммы остались недоступными. Подписи кнопки и точные условия входа проверены через Accessibility на трёх языках; восстановлены Русский / Bottom / Large / Show on hover. Pixel-level анализ изображения недоступен; отсутствие всех дефектов вёрстки не заявляется.

Вход в реальный аккаунт, восстановление его сессии, получение баланса, платежи и списание inference-кредитов не выполнялись. Правила безопасной проверки описаны в [CONTRIBUTING.md](CONTRIBUTING.md), изменения — в [CHANGELOG.md](CHANGELOG.md).

### Лицензии

Лицензия проекта — [MIT](LICENSE). Обязательные уведомления об авторских правах и лицензии зависимостей сохранены в репозитории и ресурсах приложения.

Значок WikiVibe взят из локального изображения размером 256×256. Более крупные размеры иконки получены масштабированием, а не из оригинала высокого разрешения. Для публичного распространения бинарной сборки ещё нужны подтверждённые права на бренд и подходящий графический исходник.

## English

WikiVibe is a macOS app with a screen-edge widget and a menu-bar entry.

**Account integration is BLOCKED.** The native app builds and runs. Browser PKCE and account API routes are identified, but a public desktop client_id, allowed callback and native token applicability remain unconfirmed. The app does not invent balances, treat missing data as zero or claim that opening a website signs you in.

### What works

- The screen-edge widget, menu-bar entry and account window.
- Screen-edge, size and visibility controls, retained across restarts.
- English, Russian and Simplified Chinese interface text, with an in-app language selector.
- System-browser navigation to `https://auth.wikivibe.dev/`, explicitly separate from application sign-in.
- A “Top up on website” button opens confirmed `https://api.wikivibe.dev/purchase` without tokens. Browser sign-in and payment remain user-operated.

Refresh currently opens the integration requirements and makes no account request. Keychain-backed sessions, browser return, token refresh, logout, actual balance/spending and manual/background refresh with stale/error states remain BLOCKED pending desktop registration and successful schemas. One-click configuration for Codex, oh-my-pi and OpenCode is outside this stage.

### Build and run

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

### Runtime and privacy

`Sources/App/AppDelegate.swift` starts the WikiVibe interface only. It does not start third-party provider discovery, agent monitors, local cost indexing, phone-link services, credential migration or automatic updates. Rendering does not call account discovery. Preference initialization does not read LM Studio configuration or migrate legacy endpoint keys into Keychain.

Provider libraries in the source tree are not an active WikiVibe connector. Sparkle remains a build dependency, but the updater is not instantiated. No signing identity, update feed or public signing key is configured.

Product and scheme: `WikiVibe`. Bundle identifier and logging subsystem: `dev.wikivibe.desktop`.

During early development, review found an indirect account-discovery path in rendering. That path was removed before the final verification. Historical absence of account-metadata or PII reads in the earlier launch was not established; user credential files were not inspected to investigate it.

### Backend requirements

The canonical specification is [BACKEND_SPEC.md](BACKEND_SPEC.md), with complete [English](BACKEND_SPEC.en.md) and [Simplified Chinese](BACKEND_SPEC.zh-CN.md) translations. [BACKEND_CONTRACTS.md](BACKEND_CONTRACTS.md) indexes all three. Observed public responses and proposed schemas are clearly separated; proposed endpoints are not called by the app.

Connection order:

1. Register a desktop public client and confirm the browser-return or device flow and token exchange.
2. Define account identity, token expiry, refresh rotation and session-specific revocation.
3. Confirm account-session access to balance and spending, including currency, precision, reporting period, account/key scope, errors and polling limits.
4. Use confirmed `https://api.wikivibe.dev/purchase`; do not pass tokens or create a payment.
5. Have the user sign in themselves, then verify return, restart restoration, real values, refresh, stale/offline handling, expiry/logout and top-up navigation without making a payment.

Inference API keys are not account-session tokens. The API-key-protected `/v1/usage?days=7` endpoint is not a substitute for a confirmed account-session contract.

### Verification

The preceding implementation passed `make build` and 63 tests across 11 isolated native/parser/updater suites. The entire test bundle compiled; the full provider/live suite was not executed. The exact regression command was:

```sh
make test TEST_FLAGS='-only-testing:WikiVibeTests/NotchEdgeTests -only-testing:WikiVibeTests/NotchPlacementTests -only-testing:WikiVibeTests/NotchGeometryTests -only-testing:WikiVibeTests/NotchFleetReconcileTests -only-testing:WikiVibeTests/NotchFleetScopeTests -only-testing:WikiVibeTests/NotchVisibilityTests -only-testing:WikiVibeTests/NotchSizeTests -only-testing:WikiVibeTests/NotchPositionPersistenceTests -only-testing:WikiVibeTests/UpdaterOutcomeTests -only-testing:WikiVibeTests/MiniMaxUsageTests -only-testing:WikiVibeTests/OpenCodeUsageTests'
```

Actual application checks covered the account window, notch and menu, browser-button activation without an authenticated state, edge/size/visibility changes, hiding the notch, reopening settings, quitting and appearance persistence after restart. The image-analysis provider was unavailable during the original visual check; window capture and Accessibility inspection did not establish a pixel-perfect layout review.

The three-language update passed 16 affected native tests with zero failures. The actual account window was exercised in English, Russian and Simplified Chinese; account and appearance labels changed live, the status-menu Quit action was localized, and Chinese persisted through quitting and reopening. Captures remain local under ignored `build/`; no screenshot link in this document depends on an uncommitted file.

Fresh public-client and rendered /docs investigation confirmed browser PKCE, account base /api/v1, the envelope and top-up navigation. The new build succeeded; 16 tests in NotchEdgeTests, NotchFleetScopeTests, NotchVisibilityTests and NotchSizeTests passed with zero failures. Relaunched the rebuilt app and pressed its top-up action without a browser-opening error; no session or amounts appeared. Accessibility verified the button labels and specific sign-in prerequisites in all three languages. Restored Russian / Bottom / Large / Show on hover. Pixel-level image analysis remained unavailable; no defect-free layout claim is made.

No real account sign-in, account-session restoration, balance request, payment or inference expenditure was performed. See [CONTRIBUTING.md](CONTRIBUTING.md) for safe local verification and [CHANGELOG.md](CHANGELOG.md) for changes.

### License

The project uses the [MIT license](LICENSE). Required copyright notices and dependency licenses are preserved in the repository and application resources.

The WikiVibe icon came from a 256×256 local reference image. Larger app-icon sizes are upscaled, not high-resolution originals. Public binary distribution still requires confirmed brand rights and suitable source artwork.

## 简体中文

WikiVibe 是一款 macOS 应用，提供屏幕边缘小组件和菜单栏入口。

**账号接入目前受阻（BLOCKED）。** 应用能构建、能运行。已发现浏览器 PKCE 和账号 API 路由，但公共 desktop client_id、允许的 callback 和桌面令牌适用性尚未确认。应用不会编造余额，不会把缺失数据当成零，也不会把打开网站当成登录成功。

### 现在能做什么

- 使用屏幕边缘小组件、菜单栏入口和账号窗口。
- 调整位置、大小和显示方式，重启后保留设置。
- 在应用内选择 English、Русский 或简体中文。
- 通过系统浏览器打开 `https://auth.wikivibe.dev/`。这只是访问网站，不是登录桌面应用。
- “前往网站充值”按钮打开已确认的 `https://api.wikivibe.dev/purchase`，不传递令牌。浏览器登录和付款由用户自行操作。

目前“刷新”只打开接入条件，不发送账号请求。Keychain 会话存储、浏览器回调、令牌刷新、退出、真实余额/支出，以及带过期数据和错误状态的手动/后台刷新，仍需桌面注册和成功结构，状态为 BLOCKED。本阶段不做 Codex、oh-my-pi 或 OpenCode 一键配置。

### 构建和运行

需要 macOS 15 或更新版本、带 macOS SDK 的 Xcode，以及 XcodeGen。此前验证使用的是 Xcode 26.3（`17C529`）、Swift 6.2.4 和 XcodeGen 2.46.0。

```sh
git clone https://github.com/AlexMi64/wikivibe-api.git
cd wikivibe-api
brew install xcodegen
make build
make run
```

如果已配置 GitHub SSH 访问，也可以用 `git@github.com:AlexMi64/wikivibe-api.git` 克隆。

应用生成在 `build/DerivedData/Build/Products/Debug/WikiVibe.app`。`make gen` 生成 Xcode 项目；`make clean` 删除构建产物和生成的项目。它们不会提交到仓库。依赖版本固定在 `Package.resolved` 中，首次构建可能需要下载公开的 Swift 软件包。

本地构建不签名，也没有经过 Apple 公证的安装包。Makefile 不包含发布或部署命令。

### 启动行为和隐私

`Sources/App/AppDelegate.swift` 只启动 WikiVibe 的界面，不会启动其他服务的账号发现、代理监控、本地费用索引、手机连接服务、凭据迁移或自动更新。渲染不会调用账号发现逻辑。初始化设置时，也不会读取 LM Studio 配置或把旧的自定义接口密钥迁移到 Keychain。

源码中保留提供方库不等于已经接通 WikiVibe。Sparkle 仍是构建依赖，但更新器不会创建，也没有配置更新源、签名身份、更新地址或公开签名密钥。

产品和 Xcode scheme 都叫 `WikiVibe`。应用标识与日志子系统是 `dev.wikivibe.desktop`。

早期开发时，代码审查发现渲染路径会间接触发账号发现。最终验证前，这条路径已删除。此前那次启动是否读取过账号元数据或个人信息，尚未确定；没有为调查此事去查看用户的凭据文件。

### 后端还需要确认什么

[俄文接口规范](BACKEND_SPEC.md)是权威版本，也提供[英文](BACKEND_SPEC.en.md)和[中文](BACKEND_SPEC.zh-CN.md)全文。[BACKEND_CONTRACTS.md](BACKEND_CONTRACTS.md)是索引。公开接口的实际观察与方案建议分开记录；应用不会调用尚未确认的建议接口。

接入顺序：

1. 注册桌面公共客户端，明确浏览器回调或设备授权流程，以及授权码换取令牌的方式。
2. 定义账号标识、令牌有效期、刷新时的轮换规则，以及单个会话的撤销机制。
3. 确认账号会话如何获取余额和支出，包括币种、精度、统计周期、账号或密钥范围、错误语义和轮询限制。
4. 使用已确认的 `https://api.wikivibe.dev/purchase`，不传令牌，不创建付款。
5. 用户自己登录，然后验证回调、重启恢复、真实金额、刷新、离线与过期数据、会话到期、退出，以及充值页面跳转。验证时不付款。

推理 API 密钥和账号会话令牌是两类不同的凭据。需要 API 密钥的 `/v1/usage?days=7` 不能代替已确认的账号会话接口。

### 已做的验证

在语言调整前，`make build` 成功，11 组独立测试共 63 项通过。整个测试模块都完成了编译，但没有执行完整的第三方提供方测试或真实服务测试。命令如下：

```sh
make test TEST_FLAGS='-only-testing:WikiVibeTests/NotchEdgeTests -only-testing:WikiVibeTests/NotchPlacementTests -only-testing:WikiVibeTests/NotchGeometryTests -only-testing:WikiVibeTests/NotchFleetReconcileTests -only-testing:WikiVibeTests/NotchFleetScopeTests -only-testing:WikiVibeTests/NotchVisibilityTests -only-testing:WikiVibeTests/NotchSizeTests -only-testing:WikiVibeTests/NotchPositionPersistenceTests -only-testing:WikiVibeTests/UpdaterOutcomeTests -only-testing:WikiVibeTests/MiniMaxUsageTests -only-testing:WikiVibeTests/OpenCodeUsageTests'
```

实际运行检查覆盖了账号窗口、小组件、菜单、打开浏览器但不改变登录状态、位置与大小调整、显示和隐藏、重新打开设置、退出，以及重启后的外观设置恢复。最初的图像分析服务不可用，因此窗口截图和辅助功能检查不能证明布局没有任何瑕疵。

三语言更新后的 16 项相关原生测试全部通过。实际打开账号窗口，检查了英文、俄文和简体中文：账号与外观文字会随选择更新，菜单退出操作有对应翻译，退出并重新打开后仍保留中文。截图只保存在被忽略的本地 `build/` 中，本文不会链接到未提交的截图。

再次检查公开客户端和实际 /docs，确认浏览器 PKCE、账号 base /api/v1、响应封装和充值跳转。新构建成功；NotchEdgeTests、NotchFleetScopeTests、NotchVisibilityTests 和 NotchSizeTests 共 16 项测试全部通过。重新启动新应用并按下充值按钮，没有浏览器打开错误；应用仍无会话，不显示金额。辅助功能检查确认三语言按钮文字和具体登录条件，已恢复 Русский / Bottom / Large / Show on hover。像素级图像分析不可用，未声称布局完全没有缺陷。

没有进行真实账号登录、会话恢复、余额请求、付款或推理额度消耗。安全验证规则见 [CONTRIBUTING.md](CONTRIBUTING.md)，变更记录见 [CHANGELOG.md](CHANGELOG.md)。

### 许可证

项目采用 [MIT 许可证](LICENSE)。必需的版权声明和依赖许可证保留在仓库及应用资源中。

WikiVibe 图标来自一张 256×256 的本地参考图。较大尺寸是放大生成的，不是高分辨率原图。公开分发二进制版本前，仍需确认品牌使用权，并准备合适的图标源文件。
