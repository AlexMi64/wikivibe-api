# Contributing / Участие в разработке

[English](#english) · [Русский](#русский) · [简体中文](#简体中文)

## English

### Local development

Requires macOS 15+, Xcode and XcodeGen:

```sh
brew install xcodegen
make build
make run
make test TEST_FLAGS='-only-testing:WikiVibeTests/NotchEdgeTests -only-testing:WikiVibeTests/NotchFleetScopeTests'
```

`make gen` generates the Xcode project. Unsigned local output lives under `build/DerivedData`; it is not a notarized distribution. The product, scheme and bundle identity are WikiVibe. The Makefile has no publication or deployment targets.

### Credentials and backend work

`Sources/App/AppDelegate.swift` owns startup. Retain the native notch architecture and explicit unavailable-account state until a desktop contract is confirmed. Do not enable third-party provider discovery, agent-log indexing, phone listeners, credential migration or update feeds as part of WikiVibe integration.

Do not read another application's credentials during verification. Never print tokens, cookies, keys or PII. Account-session tokens and inference API keys are separate credentials. Once the backend contract exists, store desktop session credentials only in macOS Keychain. Opening the browser is not evidence of authentication.

Read [the backend specification](BACKEND_SPEC.en.md) before implementing a connector. Proposals are not confirmed API contracts. Isolated parser fixtures and opt-in live checks do not prove WikiVibe integration. Do not enable live-test flags or use personal credentials to run tests.

### Changes and publication

- Use `L10n.t` with English source keys and Russian and Simplified Chinese translations in `Sources/Localizable.xcstrings`. Verify the real window in all three languages, including switches and restart persistence. Keep UI copy concise; precision matters more than elaborate vocabulary.
- Distinguish missing data, unsupported integration, authentication errors and stale confirmed values through the existing status model. Missing data is not zero.
- Add deterministic behavioral tests for actual boundaries, transitions and precedence. Do not test source text, incidental wording or mock echoes.
- Run affected tests and the actual app. Capture only app-owned windows, not the desktop or another application's account screen.
- Update all three README versions and the changelog with observed evidence. Preserve licenses and attribution.
- Commit and push only with the repository owner's authorization. Source publication does not authorize releases, deployment, account operations or payments. Never include build output or user credentials.

Inspect app-owned logs only; redact sensitive data before sharing:

```sh
/usr/bin/log show --last 10m --predicate 'subsystem == "dev.wikivibe.desktop"' --info
```

## Русский

### Локальная разработка

Нужны macOS 15+, Xcode и XcodeGen. Команды сборки и изолированных тестов приведены выше. `make gen` создаёт проект Xcode. Неподписанная локальная сборка находится в `build/DerivedData` и не предназначена для распространения как проверенный Apple установщик. Продукт, схема Xcode и идентификатор приложения относятся к WikiVibe. Команд публикации и развёртывания в Makefile нет.

### Учётные данные и серверная интеграция

Запуском управляет `Sources/App/AppDelegate.swift`. До подтверждения контракта настольного клиента сохраняйте архитектуру виджета и явное состояние недоступной интеграции. Не подключайте поиск сторонних аккаунтов, индексацию журналов агентов, сервис связи с телефоном, миграцию учётных данных или каналы обновлений.

При проверке не читайте учётные данные других приложений. Не выводите токены, cookies, ключи и персональные данные. Токены сессии аккаунта и ключи inference API — разные сущности. После подтверждения серверного контракта храните сессию настольного клиента только в macOS Keychain. Открытие браузера не доказывает успешный вход.

Перед реализацией коннектора прочитайте [серверную спецификацию](BACKEND_SPEC.md). Предложения не являются подтверждёнными API-контрактами. Изолированные данные для парсеров и проверки с реальными сервисами не доказывают интеграцию WikiVibe. Не включайте флаги тестов с реальными сервисами и не используйте личные учётные данные в тестах.

### Изменения и публикация

- Используйте `L10n.t` с английскими исходными ключами и русскими и упрощёнными китайскими переводами в `Sources/Localizable.xcstrings`. Проверяйте реальное окно на всех трёх языках, переключение и сохранение выбора после перезапуска. Текст интерфейса должен быть кратким и точным.
- Различайте отсутствие данных, неподдерживаемую интеграцию, ошибки входа и устаревшие подтверждённые значения средствами существующей модели состояний. Отсутствие данных не равно нулю.
- Добавляйте воспроизводимые поведенческие тесты для реальных границ, переходов и приоритетов. Не проверяйте текст исходников, случайную формулировку или повтор данных из мока.
- Запускайте затронутые тесты и само приложение. Снимайте только его окна, а не рабочий стол или экран чужого аккаунта.
- Обновляйте все три версии README и журнал изменений по результатам наблюдавшихся проверок. Сохраняйте лицензии и сведения об авторстве.
- Делайте commit и push только с разрешения владельца репозитория. Публикация исходников не разрешает выпуск бинарных версий, развёртывание, операции с аккаунтами или платежи. Не включайте результаты сборки и пользовательские секреты.

Команда просмотра журналов приведена выше. Исследуйте только диагностику приложения; перед передачей удаляйте чувствительные данные.

## 简体中文

### 本地开发

需要 macOS 15 或更新版本、Xcode 和 XcodeGen。构建、运行和独立测试命令见上文。`make gen` 生成 Xcode 项目；本地不签名的构建产物位于 `build/DerivedData`，不是经过 Apple 公证的发行版。产品、scheme 和应用标识使用 WikiVibe。Makefile 没有发布或部署目标。

### 凭据和后端接入

`Sources/App/AppDelegate.swift` 负责启动。桌面接口约定确认前，保留原生小组件架构和明确的接入不可用状态。不要启用第三方账号发现、代理日志索引、手机连接服务、凭据迁移或更新源。

验证时不要读取其他应用的凭据，也不要使用其他人的账号。不要输出令牌、cookies、密钥或个人信息。账号会话令牌和推理 API 密钥必须分开。后端约定确认后，桌面会话凭据只能放在 macOS Keychain 中。打开浏览器不代表登录成功。

实现连接器前，先读[后端规范](BACKEND_SPEC.zh-CN.md)。建议方案不是已确认的 API。解析测试数据和真实服务检查不能证明 WikiVibe 已接通。不要启用真实服务测试开关，也不要用个人凭据运行测试。

### 修改和发布

- 使用现有的 `L10n.t` 和 `Sources/Localizable.xcstrings`，保留英文源键，补齐俄文和简体中文。实际打开应用，检查三种语言、切换和重启后的保存。文字要自然、简洁、准确。
- 使用现有状态模型区分无数据、接入不支持、登录错误和已过期的确认数据。无数据不是零。
- 为真实边界、状态转换和优先级写可重复的行为测试，不要测试源代码文本、偶然的措辞或模拟数据的原样返回。
- 运行受影响的测试和应用本身。截图只包含应用自己的窗口，不要截整个桌面或其他账号页面。
- 按实际验证结果更新三份 README 和变更记录，保留许可证与作者信息。
- 只有仓库所有者授权后才能 commit 和 push。发布源码不等于获准发布二进制、部署、操作账号或付款。不要提交构建产物或用户凭据。

日志查看命令见上文。只检查本应用的诊断信息，分享前先去掉敏感内容。
