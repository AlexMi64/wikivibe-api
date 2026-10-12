# WikiVibe for macOS

[Русский](#русский) · [English](#english) · [简体中文](#简体中文)

## Русский

Самостоятельный виджет для macOS на основе [Codenotch](https://github.com/vinzdg/codenotch). Приложение написано на Swift с использованием AppKit и SwiftUI.

**Интеграция аккаунта заблокирована — BLOCKED.** Приложение собирается и запускается, но контракты авторизации настольного клиента и получения данных аккаунта ещё не подтверждены. Оно не показывает вымышленный баланс, не подменяет отсутствие данных нулём и не выдаёт открытие сайта авторизации за успешный вход.

### Что работает

- Исходный виджет у края экрана, пункт в строке меню и окно аккаунта.
- Настройка края экрана, размера и видимости с сохранением после перезапуска.
- Русский, английский и упрощённый китайский интерфейс с выбором языка в приложении.
- Открытие `https://auth.wikivibe.dev/` в системном браузере. Переход на сайт явно отделён от входа в приложение.

Команда обновления пока открывает объяснение необходимых условий интеграции и не обращается к неподтверждённому API. Хранение сессии в Keychain, возврат из браузера, обновление токенов, выход, реальные баланс и расходы, фоновый опрос и переход к пополнению требуют серверных контрактов. Настройка Codex, oh-my-pi и OpenCode одной кнопкой в этот этап не входит.

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

`Sources/App/AppDelegate.swift` запускает только интерфейс WikiVibe. Поиск аккаунтов сторонних сервисов, наблюдение за агентами, индексация локальных расходов, сервис связи с телефоном, миграция учётных данных и автоматические обновления не запускаются. Отрисовка виджета больше не обращается к исходному механизму обнаружения аккаунтов для расчёта расходов. Настройки Codenotch не импортируются; при создании настроек не читается конфигурация LM Studio и не переносятся старые ключи пользовательских API в Keychain.

Библиотека провайдеров исходного проекта сохранена: её типы используются нативными компонентами. Наличие этих исходников не означает работающий коннектор WikiVibe. Sparkle остаётся зависимостью для сборки сохранённого кода, но объект обновления не создаётся, а канал обновлений не настроен. Данные подписи, URL обновлений и открытый ключ исходного приложения удалены из конфигурации продукта.

Продукт и схема Xcode: `WikiVibe`. Идентификатор приложения и подсистема журналирования: `dev.wikivibe.desktop`. Имя Swift-модуля `Codenotch` сохранено для совместимости с импортами существующих тестов и не является названием продукта.

На раннем этапе ревью обнаружило косвенный вызов поиска сторонних аккаунтов из отрисовки. До финальной проверки эту цепочку удалили. Отсутствие чтений метаданных аккаунтов или персональных данных при более раннем запуске не установлено; пользовательские файлы с учётными данными для выяснения этого не исследовались.

### Что требуется от сервера

Каноническая спецификация — [CONNECTORS_FOR_ALEXEY.md](CONNECTORS_FOR_ALEXEY.md); полные переводы доступны на [английском](CONNECTORS_FOR_ALEXEY.en.md) и [китайском](CONNECTORS_FOR_ALEXEY.zh-CN.md). [BACKEND_CONTRACTS.md](BACKEND_CONTRACTS.md) содержит ссылки на все три версии. Наблюдавшиеся публичные ответы отделены от предложений: приложение не вызывает предложенные, но неподтверждённые методы.

Порядок подключения:

1. Зарегистрировать настольный публичный клиент, подтвердить возврат из браузера либо сценарий авторизации устройства и обмен кода на токены.
2. Определить идентификатор аккаунта, сроки действия токенов, ротацию при обновлении и отзыв отдельной сессии.
3. Подтвердить доступ по сессии аккаунта к балансу и расходам: валюту, точность, период, область аккаунта или ключа, ошибки и ограничения опроса.
4. Подтвердить официальный HTTPS-адрес пополнения либо API для его получения.
5. Пользователь самостоятельно входит в аккаунт. Затем проверяются возврат, восстановление после перезапуска, реальные суммы, обновление, устаревшие данные при потере сети, истечение сессии, выход и переход к пополнению без платежа.

Ключи inference API и токены сессии аккаунта — разные учётные данные. Защищённый API-ключом метод `/v1/usage?days=7` не заменяет подтверждённый контракт для сессии аккаунта.

### Проверки

До языковых изменений успешно выполнены `make build` и 63 теста в 11 изолированных наборах для нативных компонентов, парсеров и состояния обновления. Скомпилирован весь импортированный тестовый модуль; полный набор сторонних провайдеров и проверок с реальными сервисами не запускался. Точная команда:

```sh
make test TEST_FLAGS='-only-testing:WikiVibeTests/NotchEdgeTests -only-testing:WikiVibeTests/NotchPlacementTests -only-testing:WikiVibeTests/NotchGeometryTests -only-testing:WikiVibeTests/NotchFleetReconcileTests -only-testing:WikiVibeTests/NotchFleetScopeTests -only-testing:WikiVibeTests/NotchVisibilityTests -only-testing:WikiVibeTests/NotchSizeTests -only-testing:WikiVibeTests/NotchPositionPersistenceTests -only-testing:WikiVibeTests/UpdaterOutcomeTests -only-testing:WikiVibeTests/MiniMaxUsageTests -only-testing:WikiVibeTests/OpenCodeUsageTests'
```

В работающем приложении проверены окно аккаунта, виджет, меню, нажатие браузерной кнопки без смены состояния авторизации, край экрана, размер, видимость, скрытие, повторное открытие настроек, выход и сохранение оформления после перезапуска. Во время первоначальной визуальной проверки сервис анализа изображений был недоступен. Снимки окон и Accessibility не доказывают отсутствие всех дефектов вёрстки.

После добавления трёх языков затронутые нативные наборы прошли 16 тестов без ошибок. В реальном окне проверены английский, русский и упрощённый китайский: текст аккаунта и настройки оформления обновляются при переключении, команда выхода в меню переведена, китайский сохраняется после выхода и повторного запуска. Снимки остаются локально в игнорируемом `build/`; документация не ссылается на них как на опубликованные файлы.

Вход в реальный аккаунт, восстановление его сессии, получение баланса, платежи и списание inference-кредитов не выполнялись. Правила безопасной проверки описаны в [CONTRIBUTING.md](CONTRIBUTING.md), изменения — в [CHANGELOG.md](CHANGELOG.md).

### Авторство и лицензии

Основа импортирована из Codenotch, коммит `bcb28894d1514fef5a810595d64b44a3817c2076`. Исходная MIT [LICENSE](LICENSE) и сведения об авторстве сохранены. Точные копии лицензий Codenotch MIT и Zstandard BSD включены в ресурсы приложения вместе с уведомлениями для графических символов. Windows/Tauri и сайт исходного проекта не импортированы.

Значок WikiVibe взят из локального изображения размером 256×256. Более крупные размеры иконки получены масштабированием, а не из оригинала высокого разрешения. Для публичного распространения бинарной сборки ещё нужны подтверждённые права на бренд и подходящий графический исходник.

## English

A standalone native macOS widget based on [Codenotch](https://github.com/vinzdg/codenotch), built with Swift, AppKit and SwiftUI.

**Account integration is BLOCKED.** The native app builds and runs, but the desktop authentication and account-data contracts have not been confirmed. It does not display an invented balance, treat missing data as zero, or claim that opening the authentication website signs you in.

### What works

- The original native notch, menu-bar entry and account window.
- Screen-edge, size and visibility controls, retained across restarts.
- English, Russian and Simplified Chinese interface text, with an in-app language selector.
- System-browser navigation to `https://auth.wikivibe.dev/`, explicitly separate from application sign-in.

The refresh action currently opens the integration requirements. It does not call an unconfirmed endpoint. Keychain-backed account sessions, browser callbacks, token refresh, logout, real balance and spending, background polling and top-up navigation require the backend contracts below. One-click configuration for Codex, oh-my-pi and OpenCode is outside this stage.

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

`Sources/App/AppDelegate.swift` starts the WikiVibe surface only. It does not start third-party provider discovery, agent monitors, local cost indexing, phone-link services, credential migration or automatic updates. Native rendering no longer calls the upstream cost-account discovery layer. Existing Codenotch preferences are not imported, and preference initialization does not read LM Studio configuration or migrate legacy endpoint keys into Keychain.

The imported provider library remains in the source tree because the native components share its types. Its presence is not an active WikiVibe connector. Sparkle remains a build dependency of retained upstream code; the updater is not instantiated and no appcast is configured. Upstream signing identities, update-feed URLs and public signing keys have been removed from product configuration.

Product and scheme: `WikiVibe`. Bundle identifier and logging subsystem: `dev.wikivibe.desktop`. The Swift module remains `Codenotch` for compatibility with existing test imports; this is not the product name.

During early development, review found an indirect upstream discovery path in rendering. That path was removed before the final verification. Historical absence of account-metadata or PII reads in the earlier launch was not established; user credential files were not inspected to investigate it.

### Backend requirements

The canonical specification is [CONNECTORS_FOR_ALEXEY.md](CONNECTORS_FOR_ALEXEY.md), with complete [English](CONNECTORS_FOR_ALEXEY.en.md) and [Simplified Chinese](CONNECTORS_FOR_ALEXEY.zh-CN.md) translations. [BACKEND_CONTRACTS.md](BACKEND_CONTRACTS.md) indexes all three. Observed public responses and proposed schemas are clearly separated; proposed endpoints are not called by the app.

Connection order:

1. Register a desktop public client and confirm the browser-return or device flow and token exchange.
2. Define account identity, token expiry, refresh rotation and session-specific revocation.
3. Confirm account-session access to balance and spending, including currency, precision, reporting period, account/key scope, errors and polling limits.
4. Confirm the official HTTPS top-up URL or the API that supplies it.
5. Have the user sign in themselves, then verify return, restart restoration, real values, refresh, stale/offline handling, expiry/logout and top-up navigation without making a payment.

Inference API keys are not account-session tokens. The API-key-protected `/v1/usage?days=7` endpoint is not a substitute for a confirmed account-session contract.

### Verification

The preceding implementation passed `make build` and 63 tests across 11 isolated native/parser/updater suites. The entire imported test bundle compiled; the full provider/live suite was not executed. The exact regression command was:

```sh
make test TEST_FLAGS='-only-testing:WikiVibeTests/NotchEdgeTests -only-testing:WikiVibeTests/NotchPlacementTests -only-testing:WikiVibeTests/NotchGeometryTests -only-testing:WikiVibeTests/NotchFleetReconcileTests -only-testing:WikiVibeTests/NotchFleetScopeTests -only-testing:WikiVibeTests/NotchVisibilityTests -only-testing:WikiVibeTests/NotchSizeTests -only-testing:WikiVibeTests/NotchPositionPersistenceTests -only-testing:WikiVibeTests/UpdaterOutcomeTests -only-testing:WikiVibeTests/MiniMaxUsageTests -only-testing:WikiVibeTests/OpenCodeUsageTests'
```

Actual application checks covered the account window, notch and menu, browser-button activation without an authenticated state, edge/size/visibility changes, hiding the notch, reopening settings, quitting and appearance persistence after restart. The image-analysis provider was unavailable during the original visual check; window capture and Accessibility inspection did not establish a pixel-perfect layout review.

The three-language update passed 16 affected native tests with zero failures. The actual account window was exercised in English, Russian and Simplified Chinese; account and appearance labels changed live, the status-menu Quit action was localized, and Chinese persisted through quitting and reopening. Captures remain local under ignored `build/`; no screenshot link in this document depends on an uncommitted file.

No real account sign-in, account-session restoration, balance request, payment or inference expenditure was performed. See [CONTRIBUTING.md](CONTRIBUTING.md) for safe local verification and [CHANGELOG.md](CHANGELOG.md) for changes.

### Attribution

Imported from Codenotch commit `bcb28894d1514fef5a810595d64b44a3817c2076`. The upstream MIT [LICENSE](LICENSE) and copyright are preserved. Exact Codenotch MIT and Zstandard BSD notices are included in application resources alongside glyph notices. Windows/Tauri and the upstream website were not imported.

The WikiVibe icon came from a 256×256 local reference image. Larger app-icon sizes are upscaled, not high-resolution originals. Public binary distribution still requires confirmed brand rights and suitable source artwork.

## 简体中文

这是一个独立的 macOS 原生小组件，基于 [Codenotch](https://github.com/vinzdg/codenotch)，使用 Swift、AppKit 和 SwiftUI 开发。

**账号接入目前受阻（BLOCKED）。** 应用能构建、能运行，但桌面端登录和账号数据的后端接口约定还没确认。它不会编造余额，不会把缺失数据当成零，也不会把打开登录网站当成登录成功。

### 现在能做什么

- 使用原有的屏幕边缘小组件、菜单栏入口和账号窗口。
- 调整位置、大小和显示方式，重启后保留设置。
- 在应用内选择 English、Русский 或简体中文。
- 通过系统浏览器打开 `https://auth.wikivibe.dev/`。这只是访问网站，不是登录桌面应用。

目前点“刷新”会打开接入条件说明，不会调用尚未确认的接口。Keychain 会话存储、浏览器回调、令牌刷新、退出登录、真实余额和支出、后台轮询，以及充值页面跳转，都需要先明确后端约定。这一阶段不做 Codex、oh-my-pi 或 OpenCode 的一键配置。

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

`Sources/App/AppDelegate.swift` 只启动 WikiVibe 的原生界面，不会启动其他服务的账号发现、代理监控、本地费用索引、手机连接服务、凭据迁移或自动更新。小组件渲染已不再调用上游费用模块中的账号发现逻辑。应用不导入 Codenotch 的旧设置；初始化设置时，也不会读取 LM Studio 配置或把旧的自定义接口密钥迁移到 Keychain。

仓库里仍保留上游提供方库，因为原生组件会用到其中的类型。保留源码不等于已经接通 WikiVibe。Sparkle 仍是部分上游代码的构建依赖，但更新器不会创建，也没有配置更新源。产品配置已移除上游签名身份、更新地址和公开签名密钥。

产品和 Xcode scheme 都叫 `WikiVibe`。应用标识与日志子系统是 `dev.wikivibe.desktop`。为兼容现有测试导入，Swift 模块名仍为 `Codenotch`；它不是产品名称。

早期开发时，代码审查发现渲染路径会间接触发上游账号发现。最终验证前，这条路径已删除。此前那次启动是否读取过账号元数据或个人信息，尚未确定；没有为调查此事去查看用户的凭据文件。

### 后端还需要确认什么

[俄文接口规范](CONNECTORS_FOR_ALEXEY.md)是权威版本，也提供[英文](CONNECTORS_FOR_ALEXEY.en.md)和[中文](CONNECTORS_FOR_ALEXEY.zh-CN.md)全文。[BACKEND_CONTRACTS.md](BACKEND_CONTRACTS.md)是索引。公开接口的实际观察与方案建议分开记录；应用不会调用尚未确认的建议接口。

接入顺序：

1. 注册桌面公共客户端，明确浏览器回调或设备授权流程，以及授权码换取令牌的方式。
2. 定义账号标识、令牌有效期、刷新时的轮换规则，以及单个会话的撤销机制。
3. 确认账号会话如何获取余额和支出，包括币种、精度、统计周期、账号或密钥范围、错误语义和轮询限制。
4. 确认官方 HTTPS 充值地址，或获取该地址的 API。
5. 用户自己登录，然后验证回调、重启恢复、真实金额、刷新、离线与过期数据、会话到期、退出，以及充值页面跳转。验证时不付款。

推理 API 密钥和账号会话令牌是两类不同的凭据。需要 API 密钥的 `/v1/usage?days=7` 不能代替已确认的账号会话接口。

### 已做的验证

在语言调整前，`make build` 成功，11 组独立测试共 63 项通过。整个导入的测试模块都完成了编译，但没有执行完整的第三方提供方测试或真实服务测试。命令如下：

```sh
make test TEST_FLAGS='-only-testing:WikiVibeTests/NotchEdgeTests -only-testing:WikiVibeTests/NotchPlacementTests -only-testing:WikiVibeTests/NotchGeometryTests -only-testing:WikiVibeTests/NotchFleetReconcileTests -only-testing:WikiVibeTests/NotchFleetScopeTests -only-testing:WikiVibeTests/NotchVisibilityTests -only-testing:WikiVibeTests/NotchSizeTests -only-testing:WikiVibeTests/NotchPositionPersistenceTests -only-testing:WikiVibeTests/UpdaterOutcomeTests -only-testing:WikiVibeTests/MiniMaxUsageTests -only-testing:WikiVibeTests/OpenCodeUsageTests'
```

实际运行检查覆盖了账号窗口、小组件、菜单、打开浏览器但不改变登录状态、位置与大小调整、显示和隐藏、重新打开设置、退出，以及重启后的外观设置恢复。最初的图像分析服务不可用，因此窗口截图和辅助功能检查不能证明布局没有任何瑕疵。

三语言更新后的 16 项相关原生测试全部通过。实际打开账号窗口，检查了英文、俄文和简体中文：账号与外观文字会随选择更新，菜单退出操作有对应翻译，退出并重新打开后仍保留中文。截图只保存在被忽略的本地 `build/` 中，本文不会链接到未提交的截图。

没有进行真实账号登录、会话恢复、余额请求、付款或推理额度消耗。安全验证规则见 [CONTRIBUTING.md](CONTRIBUTING.md)，变更记录见 [CHANGELOG.md](CHANGELOG.md)。

### 来源和许可证

源码基于 Codenotch 提交 `bcb28894d1514fef5a810595d64b44a3817c2076`。原 MIT [LICENSE](LICENSE) 和版权信息均已保留。应用资源中包含 Codenotch MIT、Zstandard BSD 许可证的完整副本，以及图形标记的许可说明。没有导入 Windows/Tauri 版本或上游网站。

WikiVibe 图标来自一张 256×256 的本地参考图。较大尺寸是放大生成的，不是高分辨率原图。公开分发二进制版本前，仍需确认品牌使用权，并准备合适的图标源文件。
