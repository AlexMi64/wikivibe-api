# WikiVibe for macOS

[Русский](#русский) · [English](#english) · [简体中文](#简体中文)

## Русский

WikiVibe — приложение для macOS с виджетом у края экрана и меню в строке состояния.

**Вход в аккаунт и баланс реализованы.** Приложение входит в аккаунт WikiVibe через системный браузер (Authorization Code + PKCE S256) и хранит сессию в связке ключей macOS. Баланс читается с сервера — обычный, бонусный и замороженный — и обновляется сам. Приложение не показывает вымышленные суммы, не подменяет отсутствие данных нулём и не выдаёт открытие сайта за успешный вход.

### Что работает

- Виджет у края экрана, пункт в строке меню и окно аккаунта.
- Настройка края экрана, размера и видимости с сохранением после перезапуска.
- Русский, английский и упрощённый китайский интерфейс с выбором языка в приложении.
- Вход в аккаунт WikiVibe: браузер открывает `https://auth.wikivibe.dev/`, возврат приходит на loopback-адрес приложения, код обменивается на токены и сессия сохраняется в Keychain.
- Восстановление сессии после перезапуска, обновление токена и выход.
- Баланс аккаунта: обычный, бонусный и замороженный, в единице сервера. Обновляется раз в минуту, и раз в 15 секунд, пока открыто окно.
- Карточка «API-ключи»: ключи авторизованного аккаунта, выбор адреса API и настройка Codex, oh-my-pi, OpenCode и Claude Code с предпросмотром и подтверждением.

Виджет показывает аккаунт и баланс. Расходы и статистика не читаются: это отдельная задача. Кнопка «Открыть сайт» ведёт в панель `api.wikivibe.dev`, у которой своя сессия в браузере; вход в приложении её не создаёт, поэтому сайт может попросить пароль — это не сброс входа в приложении.

### Настройка окна аккаунта

Окно можно растягивать; его размер и положение восстанавливаются после перезапуска. Карточки «Аккаунт», «Баланс», «Виджет и язык» и «API-ключи» используют общую сетку, одинаковые отступы и выровненные поля, заполняющие доступную ширину. Пояснения о входе раскрываются отдельно, чтобы не перегружать окно.

Кнопка «Настроить окно» в шапке открывает выбор компоновки: адаптивная сетка до двух столбцов, вертикальная колонка или горизонтальное расположение до трёх столбцов. В узком окне столбцов становится меньше, а длинное содержимое доступно через прокрутку. Здесь же выбираются обычные/компактные отступы, порядок карточек стрелками и их видимость. Настройки сохраняются автоматически; даже если скрыть всё, настройка и сброс остаются доступны в шапке.

Кнопка со стрелкой сброса возвращает исходную компоновку, плотность, порядок и видимость карточек. Она не меняет вход в аккаунт, язык, край/размер/видимость виджета или сохранённые размеры окна. Скрытие баланса не меняет его данные и периодичность обновления.

### API-ключи и настройка агентов

Карточка загружает ключи через сессию самого приложения, со всех страниц `GET /api/v1/keys`. Значения ключей скрыты и остаются в памяти до явной записи в настройки агента. В `UserDefaults` сохраняются только ID выбранного ключа для аккаунта, адрес API и выбранные агенты; токен входа не подставляется вместо API-ключа.

Выберите активный ключ, `https://api.wikivibe.dev/v1` или `https://vapi.wikivibe.dev/v1` и нужных агентов. Кнопка «Загрузить модели и посмотреть изменения…» читает авторизованный каталог `/models` выбранного ключа и показывает модели, файлы и предупреждения. Ограничения протоколов из данных ключа учитываются; неизвестная совместимость не выдаётся за подтверждённую. Генерация и платные запросы для проверки не запускаются.

- **Codex:** регистрация поставщика в `~/.codex/config.toml`, отдельные `wikivibe.config.toml` и `wikivibe-models.json`. Запуск: `codex -p wikivibe`, затем `/model`. Исходные модель и поставщик по умолчанию сохраняются. Нужна версия с профильными файлами и `model_catalog_json`; список моделей Desktop/Orca не гарантируется.
- **oh-my-pi:** `~/.omp/agent/models.yml` или `.yaml`; существующие фильтры в `config.yml`/`.yaml` расширяются только для WikiVibe, роли моделей сохраняются. Выбор модели: `/model`.
- **OpenCode:** `~/.config/opencode/opencode.json` или `.jsonc`; другие поставщики, активная модель и комментарии вне изменяемого блока сохраняются. Выбор: `/models`.
- **Claude Code:** `~/.claude/settings.json`; глобальные `ANTHROPIC_BASE_URL` и `ANTHROPIC_AUTH_TOKEN` заменяются, доступные модели добавляются в `modelPicker`. Это не отдельный поставщик; предупреждение показывается до записи. Для списка моделей нужна версия 2.1.242 или новее; выбор — `/model` в новой сессии.

Настройка требует локальный **Node.js 22+**: `/opt/homebrew/bin/node`, `/usr/local/bin/node` или унаследованный приложением `PATH`. Адаптеры и парсеры поставляются с приложением, ничего не скачивается при применении. Без Node.js доступен список ключей, но не запись настроек. Наличие самих агентов не проверяется. Нестандартные домашние папки агентов, настройки проекта, переменные окружения и управляемые политики могут переопределять эти стандартные файлы; SSH и WSL не настраиваются.

Запись начинается только после «Подтвердить и записать файлы». Ключ записывается **открытым текстом**; файлы имеют права `0600`. Копии исходных файлов лежат рядом в `.wikivibe-gateway-backups` с правами `0700` на папку и `0600` на файлы; они тоже могут содержать секреты. Каждый файл записывается отдельно: возможен частичный результат с перечнем изменённых файлов и ошибок. «Посмотреть восстановление из копий…» также требует подтверждения и не перезаписывает последующие пользовательские правки. Сложные/неоднозначные форматы, небезопасные ссылки и конфликты не заменяются автоматически. Каталог не доказывает поддержку tools, streaming, reasoning или генерации изображений.

### Восстановление после обрыва интернета

Исправлено зависание баланса с ошибкой `unreadable response (HTTP 401)` после восстановления связи. HTTP `401`/`403` распознаются до разбора JSON; при опросе баланса истёкший access token обновляется. Если сервер отклонил ещё действующий по локальным часам токен, приложение обновляет сессию и повторяет запрос один раз. Временная сетевая ошибка не удаляет сессию: следующий опрос снова пытается получить данные, в том числе после запуска без интернета. Если refresh token отклонён или повторный запрос снова не авторизован, требуется повторный вход.

Проверены пять изолированных HTTP-сценариев восстановления и ещё 20 тестов сессии/баланса; сборка успешна. В обновлённом приложении баланс загрузился, ручное обновление прошло без ошибки. Отключение интернета на Mac не выполнялось. Ограничение более широкого callback-прогона зафиксировано в [CHANGELOG.md](CHANGELOG.md#balance-recovery-after-connectivity-loss).

### Как устроен вход

Приложение — публичный клиент `desktop`, зарегистрированный на сервере. В браузере пароль вводится на сайте WikiVibe, приложение его не видит. Обратно приходит одноразовый код, привязанный к PKCE-верификатору, который сгенерирован в приложении и никуда не передаётся. Возврат принимает одноразовый HTTP-листенер на `127.0.0.1`; порт выбирает ОС, потому что фиксированный порт ломал бы вход, когда его заняло другое приложение. Сессия (access/refresh токены и аккаунт) хранится одним элементом Keychain; в `UserDefaults` и логи токены не попадают.

Регистрация клиента `desktop` находится в серверной части WikiVibe (`shared_auth.desktop_redirect_uri`, по умолчанию `http://127.0.0.1/callback`). Без неё `authorize` отвечает `INVALID_REQUEST`.

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

`Sources/App/AppDelegate.swift` запускает интерфейс WikiVibe и вход в аккаунт. Поиск аккаунтов сторонних сервисов, наблюдение за агентами, индексация локальных расходов, сервис связи с телефоном, миграция учётных данных и автоматические обновления не запускаются. Отрисовка не обращается к механизму обнаружения аккаунтов. При создании настроек не читается конфигурация LM Studio и не переносятся старые ключи пользовательских API в Keychain.

Во время входа приложение открывает один HTTP-листенер на `127.0.0.1` и закрывает его, когда попытка заканчивается. Листенер отвечает только на зарегистрированный путь `/callback`, сверяет `state` и не принимает запросы других методов; порт освобождается на любом исходе — успехе, отказе, тайм-ауте и выходе из приложения. Пароль вводится на сайте WikiVibe в браузере и в приложение не попадает; сохраняются только токены сессии и поля аккаунта (`id`, `username`, `email`).

Наличие библиотек провайдеров в исходниках не означает работающий коннектор WikiVibe. Sparkle остаётся зависимостью сборки, но объект обновления не создаётся, а канал обновлений не настроен. Данные подписи, URL обновлений и открытый ключ не настроены.

Продукт и схема Xcode: `WikiVibe`. Идентификатор приложения и подсистема журналирования: `dev.wikivibe.desktop`.

На раннем этапе ревью обнаружило косвенный вызов поиска сторонних аккаунтов из отрисовки. До финальной проверки эту цепочку удалили. Отсутствие чтений метаданных аккаунтов или персональных данных при более раннем запуске не установлено; пользовательские файлы с учётными данными для выяснения этого не исследовались.

### Что требуется от сервера

Каноническая спецификация — [BACKEND_SPEC.md](BACKEND_SPEC.md); полные переводы доступны на [английском](BACKEND_SPEC.en.md) и [китайском](BACKEND_SPEC.zh-CN.md). [BACKEND_CONTRACTS.md](BACKEND_CONTRACTS.md) содержит ссылки на все три версии.

Что уже сделано:

1. Зарегистрирован настольный публичный клиент `desktop`; подтверждены возврат из браузера и обмен кода на токены.
2. Определены идентификатор аккаунта, сроки действия токенов, ротация при обновлении и отзыв отдельной сессии.

Что осталось — только если понадобятся баланс и расходы (сейчас вне объёма): валюта и точность, период и часовой пояс, область аккаунта или ключа, ошибки и ограничения опроса. Это предложение, а не действующий контракт, и приложение эти методы не вызывает.

Ключи inference API и токены сессии аккаунта — разные учётные данные. Защищённый API-ключом метод `/v1/usage?days=7` не заменяет контракт для сессии аккаунта.

### Проверки

Авторизация: `Sources/Auth` и `Tests/WikiVibeAuthTests.swift` компилируются; 341 утверждение из этого набора выполнено против настоящего loopback-листенера и жизненного цикла сессии, 0 ошибок. Проверялись в том числе отказ от чужого `state`, тайм-аут, отмена, ротация refresh token, сохранение сессии при недоступном сервере и выход при недоступном сервере. `make build`, `make test` и запуск приложения на этой машине не выполнялись: Xcode не установлен, поэтому `xcodebuild` и XCTest недоступны. Это ограничение проверки, а не результат.

Серверная часть: `go test -tags=unit ./internal/config/ ./internal/service/ ./internal/handler/` — наборы shared-auth проходят.

До языковых изменений успешно выполнены `make build` и 63 теста в 11 изолированных наборах для нативных компонентов, парсеров и состояния обновления. Скомпилирован весь тестовый модуль; полный набор сторонних провайдеров и проверок с реальными сервисами не запускался. Точная команда:

```sh
make test TEST_FLAGS='-only-testing:WikiVibeTests/NotchEdgeTests -only-testing:WikiVibeTests/NotchPlacementTests -only-testing:WikiVibeTests/NotchGeometryTests -only-testing:WikiVibeTests/NotchFleetReconcileTests -only-testing:WikiVibeTests/NotchFleetScopeTests -only-testing:WikiVibeTests/NotchVisibilityTests -only-testing:WikiVibeTests/NotchSizeTests -only-testing:WikiVibeTests/NotchPositionPersistenceTests -only-testing:WikiVibeTests/UpdaterOutcomeTests -only-testing:WikiVibeTests/MiniMaxUsageTests -only-testing:WikiVibeTests/OpenCodeUsageTests'
```

В работающем приложении проверены окно аккаунта, виджет, меню, нажатие браузерной кнопки без смены состояния авторизации, край экрана, размер, видимость, скрытие, повторное открытие настроек, выход и сохранение оформления после перезапуска. Во время первоначальной визуальной проверки сервис анализа изображений был недоступен. Снимки окон и Accessibility не доказывают отсутствие всех дефектов вёрстки.

После добавления трёх языков затронутые нативные наборы прошли 16 тестов без ошибок. В реальном окне проверены английский, русский и упрощённый китайский: текст аккаунта и настройки оформления обновляются при переключении, команда выхода в меню переведена, китайский сохраняется после выхода и повторного запуска. Снимки остаются локально в игнорируемом `build/`; документация не ссылается на них как на опубликованные файлы.

Повторное исследование публичного web-клиента и отрисованного `/docs` подтвердило браузерный PKCE, account base `/api/v1`, envelope и переход к пополнению. Новая сборка успешна; 16 тестов в `NotchEdgeTests`, `NotchFleetScopeTests`, `NotchVisibilityTests`, `NotchSizeTests` прошли без ошибок. Пересобранное приложение перезапущено, top-up action нажат без ошибки открытия браузера; сессия не появилась, суммы остались недоступными. Подписи кнопки и точные условия входа проверены через Accessibility на трёх языках; восстановлены Русский / Bottom / Large / Show on hover. Pixel-level анализ изображения недоступен; отсутствие всех дефектов вёрстки не заявляется.

Авторизация реализована, но на машине, где велась эта работа, не установлен Xcode: `xcodebuild` и XCTest недоступны, поэтому приложение не собиралось и не запускалось, а вход в реальный аккаунт не выполнялся. Проверено то, что можно проверить без Xcode: `Sources/Auth` и тестовый файл компилируются, а 341 утверждение из набора тестов выполнено против настоящего loopback-листенера и жизненного цикла сессии без ошибок. Баланс, расходы, платежи и списание inference-кредитов не выполнялись. Правила безопасной проверки описаны в [CONTRIBUTING.md](CONTRIBUTING.md), изменения — в [CHANGELOG.md](CHANGELOG.md).

### Лицензии

Лицензия проекта — [MIT](LICENSE). Обязательные уведомления об авторских правах и лицензии зависимостей сохранены в репозитории и ресурсах приложения.

Настройка агентов использует встроенные jsonc-parser 3.3.1 (MIT) и yaml 2.8.1 (ISC). Тексты лицензий включены в `Sources/Resources/AgentSetup/JSONC-PARSER-LICENSE.txt` и `YAML-LICENSE.txt` и поставляются в приложении.

Значок WikiVibe взят из локального изображения размером 256×256. Более крупные размеры иконки получены масштабированием, а не из оригинала высокого разрешения. Для публичного распространения бинарной сборки ещё нужны подтверждённые права на бренд и подходящий графический исходник.

## English

WikiVibe is a macOS app with a screen-edge widget and a menu-bar entry.

**Account sign-in and the balance are implemented.** The app signs in to a WikiVibe account through the system browser (Authorization Code + PKCE S256) and keeps the session in the macOS keychain. The balance is read from the server — regular, bonus and on hold — and refreshes on its own. The app does not invent amounts, treat missing data as zero or claim that opening a website signs you in.

### What works

- The screen-edge widget, menu-bar entry and account window.
- Screen-edge, size and visibility controls, retained across restarts.
- English, Russian and Simplified Chinese interface text, with an in-app language selector.
- WikiVibe account sign-in: the browser opens `https://auth.wikivibe.dev/`, the return arrives at the app's loopback address, the code is exchanged for tokens and the session is stored in the keychain.
- Session restore across restarts, token refresh and sign-out.
- The account balance: regular, bonus and on hold, in the server's own unit. Re-read every minute, and every 15 seconds while the window is open.
- API keys card: keys from the signed-in account, API address selection, and Codex, oh-my-pi, OpenCode and Claude Code setup with preview and confirmation.

The widget shows the account and its balance. Spending and usage statistics are not read: that is a separate task. “Open the website” leads to the `api.wikivibe.dev` panel, which keeps its own session in the browser; signing in here does not create it, so the site may ask for a password — that is not the app's session being lost.

### Customize the account window

The window is resizable and restores its size and position after restart. Account, Balance, Widget and language, and API keys cards share a grid, consistent spacing and aligned controls that fill the available width. Sign-in explanations expand separately to keep the main view concise.

“Customize window” in the header offers an adaptive grid with up to two columns, a vertical stack, or a horizontal layout with up to three columns. Narrow windows use fewer columns and scroll when necessary. Choose comfortable/compact spacing, move cards with the arrow buttons, and hide or show them. Changes save automatically; Customize and Reset remain available in the header even when every card is hidden.

The reset-arrow button restores the original layout, spacing, card order and visibility. It does not change sign-in, language, widget edge/size/visibility, or saved window dimensions. Hiding Balance does not change its data or polling schedule.

### API keys and agent configuration

The card reads every page of `GET /api/v1/keys` through the app's own account session. Key values are hidden and stay in memory until an explicit agent configuration write. Only the account's selected key ID, API address and selected agents are saved in `UserDefaults`; the account sign-in token is never substituted for an API key.

Choose an active key, `https://api.wikivibe.dev/v1` or `https://vapi.wikivibe.dev/v1`, and the agents to configure. “Load models and preview…” reads that key's authenticated `/models` catalog and shows the models, affected files and warnings. Reported protocol restrictions are respected; unknown compatibility is not presented as verified. No inference or paid request is used to check the connection.

- **Codex:** provider registration in `~/.codex/config.toml`, plus separate `wikivibe.config.toml` and `wikivibe-models.json`. Run `codex -p wikivibe`, then `/model`. Existing default model/provider choices stay intact. Requires support for profile files and `model_catalog_json`; Desktop/Orca pickers are not guaranteed.
- **oh-my-pi:** `~/.omp/agent/models.yml` or `.yaml`; existing `config.yml`/`.yaml` filters expand only for WikiVibe, and model roles stay intact. Choose with `/model`.
- **OpenCode:** `~/.config/opencode/opencode.json` or `.jsonc`; other providers, the active model and comments outside the changed block stay intact. Choose with `/models`.
- **Claude Code:** `~/.claude/settings.json`; replaces global `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` and adds available models to `modelPicker`. This is not a separate provider; the warning appears before writing. The picker requires 2.1.242 or newer; choose with `/model` in a new session.

Configuration requires local **Node.js 22+**, found at `/opt/homebrew/bin/node`, `/usr/local/bin/node`, or on the app's inherited `PATH`. Adapters and parsers ship with the app; applying does not download code. Without Node.js the key list remains available, but configuration writes are unavailable. Agent installation is not checked. Custom agent homes, project settings, environment variables and managed policies can override these standard files; SSH and WSL are not configured.

Only “Confirm and write files” starts a write. The key is stored **in plain text**, with file permissions `0600`. Original-file backups are stored beside the configuration in `.wikivibe-gateway-backups`, using directory permissions `0700` and file permissions `0600`; backups may also contain secrets. Each file is written separately, so a partial result lists changed files and failures. “Preview restoring agent backups…” also requires confirmation and refuses to overwrite later user edits. Complex/ambiguous formats, unsafe links and conflicts are not replaced automatically. The catalog does not prove tools, streaming, reasoning or image-generation support.

### Recovery after connectivity loss

Fixed the balance getting stuck at `unreadable response (HTTP 401)` after connectivity returns. HTTP `401`/`403` is classified before JSON decoding, and expired access tokens are renewed during balance polling. If the server rejects a token that still looks valid locally, the app renews the session and retries once. Temporary network failures retain the session for the next poll, including after an offline launch. A rejected refresh token or another authentication failure on the retry requires sign-in again.

Five isolated HTTP recovery scenarios and 20 session/wallet tests passed; the build succeeded. In the updated running app, the balance loaded and manual refresh completed without an error. System connectivity was not disabled. The broader callback-suite verification limit is recorded in [CHANGELOG.md](CHANGELOG.md#balance-recovery-after-connectivity-loss).

### How sign-in works

The app is the public client `desktop`, registered server-side. The password is typed on the WikiVibe site in the browser; the app never sees it. What comes back is a one-time code bound to a PKCE verifier generated in the app and sent nowhere. The return is caught by a one-shot HTTP listener on `127.0.0.1`; the OS picks the port, because a fixed one would break sign-in whenever something else already holds it. The session (access and refresh tokens plus the account) is one keychain item; tokens never reach `UserDefaults` or a log.

The `desktop` client registration lives in the WikiVibe backend (`shared_auth.desktop_redirect_uri`, default `http://127.0.0.1/callback`). Without it, `authorize` answers `INVALID_REQUEST`.

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

`Sources/App/AppDelegate.swift` starts the WikiVibe interface and account sign-in. It does not start third-party provider discovery, agent monitors, local cost indexing, phone-link services, credential migration or automatic updates. Rendering does not call account discovery. Preference initialization does not read LM Studio configuration or migrate legacy endpoint keys into Keychain.

While a sign-in is in progress the app opens one HTTP listener on `127.0.0.1` and closes it when the attempt ends. The listener answers only the registered `/callback` path, verifies `state` and rejects other methods; the port is released on every outcome — success, refusal, timeout and app termination. The password is typed on the WikiVibe site in the browser and never reaches the app; only the session tokens and the account fields (`id`, `username`, `email`) are stored.

Provider libraries in the source tree are not an active WikiVibe connector. Sparkle remains a build dependency, but the updater is not instantiated. No signing identity, update feed or public signing key is configured.

Product and scheme: `WikiVibe`. Bundle identifier and logging subsystem: `dev.wikivibe.desktop`.

During early development, review found an indirect account-discovery path in rendering. That path was removed before the final verification. Historical absence of account-metadata or PII reads in the earlier launch was not established; user credential files were not inspected to investigate it.

### Backend requirements

The canonical specification is [BACKEND_SPEC.md](BACKEND_SPEC.md), with complete [English](BACKEND_SPEC.en.md) and [Simplified Chinese](BACKEND_SPEC.zh-CN.md) translations. [BACKEND_CONTRACTS.md](BACKEND_CONTRACTS.md) indexes all three.

Done:

1. The public desktop client `desktop` is registered; browser return and token exchange are confirmed.
2. Account identity, token expiry, refresh rotation and session-specific revocation are defined.

What remains — only if balance and spending are wanted, which is out of scope today: currency and precision, reporting period and timezone, account/key scope, errors and polling limits. That is a proposal, not an existing contract, and the app calls none of those routes.

Inference API keys are not account-session tokens. The API-key-protected `/v1/usage?days=7` endpoint is not a substitute for an account-session contract.

### Verification

Authorization: `Sources/Auth` and `Tests/WikiVibeAuthTests.swift` compile; 341 assertions from that suite ran against the real loopback listener and the session lifecycle with zero failures. They cover a callback carrying a foreign `state`, the timeout, cancellation, refresh-token rotation, keeping the session when the server is unreachable, and signing out when it is. `make build`, `make test` and launching the app were not performed on this machine: Xcode is not installed, so `xcodebuild` and XCTest are unavailable. That is a verification limit, not a result.

Backend: `go test -tags=unit ./internal/config/ ./internal/service/ ./internal/handler/` — the shared-auth suites pass.

The preceding implementation passed `make build` and 63 tests across 11 isolated native/parser/updater suites. The entire test bundle compiled; the full provider/live suite was not executed. The exact regression command was:

```sh
make test TEST_FLAGS='-only-testing:WikiVibeTests/NotchEdgeTests -only-testing:WikiVibeTests/NotchPlacementTests -only-testing:WikiVibeTests/NotchGeometryTests -only-testing:WikiVibeTests/NotchFleetReconcileTests -only-testing:WikiVibeTests/NotchFleetScopeTests -only-testing:WikiVibeTests/NotchVisibilityTests -only-testing:WikiVibeTests/NotchSizeTests -only-testing:WikiVibeTests/NotchPositionPersistenceTests -only-testing:WikiVibeTests/UpdaterOutcomeTests -only-testing:WikiVibeTests/MiniMaxUsageTests -only-testing:WikiVibeTests/OpenCodeUsageTests'
```

Actual application checks covered the account window, notch and menu, browser-button activation without an authenticated state, edge/size/visibility changes, hiding the notch, reopening settings, quitting and appearance persistence after restart. The image-analysis provider was unavailable during the original visual check; window capture and Accessibility inspection did not establish a pixel-perfect layout review.

The three-language update passed 16 affected native tests with zero failures. The actual account window was exercised in English, Russian and Simplified Chinese; account and appearance labels changed live, the status-menu Quit action was localized, and Chinese persisted through quitting and reopening. Captures remain local under ignored `build/`; no screenshot link in this document depends on an uncommitted file.

Fresh public-client and rendered /docs investigation confirmed browser PKCE, account base /api/v1, the envelope and top-up navigation. The new build succeeded; 16 tests in NotchEdgeTests, NotchFleetScopeTests, NotchVisibilityTests and NotchSizeTests passed with zero failures. Relaunched the rebuilt app and pressed its top-up action without a browser-opening error; no session or amounts appeared. Accessibility verified the button labels and specific sign-in prerequisites in all three languages. Restored Russian / Bottom / Large / Show on hover. Pixel-level image analysis remained unavailable; no defect-free layout claim is made.

Authorization is implemented, but the machine this work was done on has no Xcode: `xcodebuild` and XCTest are unavailable, so the app was neither built nor launched and no real account sign-in was performed. What could be verified without Xcode was: `Sources/Auth` and the test file compile, and 341 assertions from the suite ran against the real loopback listener and the session lifecycle with zero failures. No balance request, payment or inference expenditure was performed. See [CONTRIBUTING.md](CONTRIBUTING.md) for safe local verification and [CHANGELOG.md](CHANGELOG.md) for changes.

### License

The project uses the [MIT license](LICENSE). Required copyright notices and dependency licenses are preserved in the repository and application resources.

Agent configuration uses bundled jsonc-parser 3.3.1 (MIT) and yaml 2.8.1 (ISC). Their licenses are included in `Sources/Resources/AgentSetup/JSONC-PARSER-LICENSE.txt` and `YAML-LICENSE.txt` and ship with the app.

The WikiVibe icon came from a 256×256 local reference image. Larger app-icon sizes are upscaled, not high-resolution originals. Public binary distribution still requires confirmed brand rights and suitable source artwork.

## 简体中文

WikiVibe 是一款 macOS 应用，提供屏幕边缘小组件和菜单栏入口。

**账号登录和余额已实现。** 应用通过系统浏览器完成 WikiVibe 账号登录（Authorization Code + PKCE S256），会话保存在 macOS 钥匙串中。余额从服务器读取——普通、赠送和冻结——并自动刷新。应用不会编造金额，不会把缺失数据当成零，也不会把打开网站当成登录成功。

### 现在能做什么

- 使用屏幕边缘小组件、菜单栏入口和账号窗口。
- 调整位置、大小和显示方式，重启后保留设置。
- 在应用内选择 English、Русский 或简体中文。
- WikiVibe 账号登录：浏览器打开 `https://auth.wikivibe.dev/`，回调回到应用的 loopback 地址，授权码换成令牌，会话写入钥匙串。
- 重启后恢复会话、刷新令牌、退出登录。
- 账号余额：普通、赠送和冻结，使用服务器自己的单位。每分钟刷新一次；窗口打开时每 15 秒刷新一次。
- API 密钥卡片：读取已登录账号的密钥，选择 API 地址，为 Codex、oh-my-pi、OpenCode 和 Claude Code 配置密钥和模型，写入前预览并确认。

小组件显示账号和余额。支出和使用统计不读取：那是另一项任务。“打开网站”跳转到 `api.wikivibe.dev` 面板，它在浏览器里有自己的会话；在这里登录不会创建那个会话，所以网站可能要求输入密码——这不是应用里的登录被清除。

### 自定义账号窗口

窗口可调整大小，重启后恢复大小和位置。账号、余额、小组件与语言、API 密钥四张卡片使用统一网格、间距和对齐方式，控件填满可用宽度。登录说明可单独展开，避免主界面堆积文字。

窗口顶部的“自定义窗口”提供最多两列的自适应网格、纵向排列和最多三列的横向排列。窄窗口自动减少列数，内容过长时可滚动。还可以选择舒适或紧凑间距，用箭头调整卡片顺序，以及隐藏或显示卡片。修改自动保存；即使隐藏所有卡片，顶部的自定义和重置按钮仍然可用。

重置箭头恢复初始布局、间距、卡片顺序和显示状态，不改变登录、语言、小组件的位置/大小/显示方式，也不改变已保存的窗口大小。隐藏余额卡片不会更改余额数据或刷新频率。

### API 密钥与代理配置

卡片通过应用自身的账号会话读取 `GET /api/v1/keys` 的所有分页。密钥值已隐藏，仅保留在内存中，直到明确确认写入代理配置。`UserDefaults` 仅保存账号所选密钥的 ID、API 地址和代理选项；账号登录令牌绝不会代替 API 密钥。

选择有效密钥、`https://api.wikivibe.dev/v1` 或 `https://vapi.wikivibe.dev/v1`，以及要配置的代理。“加载模型并预览…”读取该密钥经过认证的 `/models` 目录，并显示模型、受影响文件和警告。应用遵守密钥报告的协议限制，不会把未知兼容性描述为已验证。检查连接不会执行推理或付费请求。

- **Codex：**在 `~/.codex/config.toml` 注册提供商，并创建独立的 `wikivibe.config.toml` 和 `wikivibe-models.json`。运行 `codex -p wikivibe`，再使用 `/model`。保留原有默认模型与提供商。需要支持配置档文件及 `model_catalog_json` 的版本；不保证 Desktop/Orca 的选择器支持。
- **oh-my-pi：**使用 `~/.omp/agent/models.yml` 或 `.yaml`；仅为 WikiVibe 扩展现有 `config.yml`/`.yaml` 的筛选条件，保留模型角色。用 `/model` 选择。
- **OpenCode：**使用 `~/.config/opencode/opencode.json` 或 `.jsonc`；保留其他提供商、当前模型和更改块之外的注释。用 `/models` 选择。
- **Claude Code：**使用 `~/.claude/settings.json`；替换全局 `ANTHROPIC_BASE_URL` 和 `ANTHROPIC_AUTH_TOKEN`，并在 `modelPicker` 添加可用模型。这不是独立提供商，写入前会显示警告。模型选择器需要 2.1.242 或更新版本；请在新会话中用 `/model` 选择。

配置需要本机 **Node.js 22+**，应用从 `/opt/homebrew/bin/node`、`/usr/local/bin/node` 或继承的 `PATH` 查找。适配器与解析器随应用提供，应用配置时不下载代码。没有 Node.js 仍可查看密钥，但无法写入代理配置。不检查代理是否已安装。自定义代理目录、项目设置、环境变量和托管策略可能覆盖标准文件；不配置 SSH 或 WSL。

只有“确认并写入文件”才会开始写入。密钥以**明文**保存，文件权限为 `0600`。原始文件备份保存在配置旁的 `.wikivibe-gateway-backups`，目录权限为 `0700`，文件权限为 `0600`；备份也可能包含机密。各文件分别写入，因此可能部分成功，结果会列出已更改文件和错误。“预览恢复代理备份…”同样需要确认，并拒绝覆盖之后的用户修改。复杂或有歧义的格式、不安全链接及冲突不会被自动替换。模型目录不证明支持工具、流式响应、推理或图像生成。

### 断网后的恢复

修复恢复连接后余额停留在 `unreadable response (HTTP 401)` 的问题。应用在解析 JSON 前识别 HTTP `401`/`403`，并在余额轮询时刷新过期的 access token。如果服务器拒绝本地看来仍有效的令牌，应用会刷新会话并重试一次。临时网络故障不会删除会话，下次轮询会再次请求数据，包括离线启动后的恢复。如果 refresh token 被拒绝，或重试仍未通过身份验证，则需要重新登录。

五个隔离的 HTTP 恢复场景和另外 20 项会话/余额测试通过，构建成功。更新后的应用已加载余额，手动刷新没有报错。验证时未断开 Mac 的网络连接。更广泛 callback 测试的验证限制记录在 [CHANGELOG.md](CHANGELOG.md#balance-recovery-after-connectivity-loss)。

### 登录是怎么实现的

应用是服务端注册的公共客户端 `desktop`。密码在浏览器的 WikiVibe 网站上输入，应用看不到它。回来的是绑定 PKCE verifier 的一次性授权码，该 verifier 由应用生成且不发送到任何地方。回调由 `127.0.0.1` 上的一次性 HTTP 监听接收；端口由系统分配，因为固定端口一旦被其他应用占用就会让登录失败。会话（access/refresh 令牌和账号）是钥匙串中的一个条目；令牌不会进入 `UserDefaults` 或日志。

`desktop` 客户端注册在 WikiVibe 后端（`shared_auth.desktop_redirect_uri`，默认 `http://127.0.0.1/callback`）。没有它，`authorize` 会返回 `INVALID_REQUEST`。

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

`Sources/App/AppDelegate.swift` 启动 WikiVibe 的界面和账号登录，不会启动其他服务的账号发现、代理监控、本地费用索引、手机连接服务、凭据迁移或自动更新。渲染不会调用账号发现逻辑。初始化设置时，也不会读取 LM Studio 配置或把旧的自定义接口密钥迁移到 Keychain。

登录期间应用会在 `127.0.0.1` 上打开一个 HTTP 监听端口，并在本次尝试结束时关闭。该监听只响应已注册的 `/callback` 路径，校验 `state`，拒绝其他方法；无论成功、被拒、超时还是应用退出，端口都会释放。密码在浏览器的 WikiVibe 网站上输入，不会进入应用；只有会话令牌和账号字段（`id`、`username`、`email`）会被保存。

源码中保留提供方库不等于已经接通 WikiVibe。Sparkle 仍是构建依赖，但更新器不会创建，也没有配置更新源、签名身份、更新地址或公开签名密钥。

产品和 Xcode scheme 都叫 `WikiVibe`。应用标识与日志子系统是 `dev.wikivibe.desktop`。

早期开发时，代码审查发现渲染路径会间接触发账号发现。最终验证前，这条路径已删除。此前那次启动是否读取过账号元数据或个人信息，尚未确定；没有为调查此事去查看用户的凭据文件。

### 后端还需要确认什么

[俄文接口规范](BACKEND_SPEC.md)是权威版本，也提供[英文](BACKEND_SPEC.en.md)和[中文](BACKEND_SPEC.zh-CN.md)全文。[BACKEND_CONTRACTS.md](BACKEND_CONTRACTS.md)是索引。

已完成：公共桌面客户端 `desktop` 已注册，浏览器回调和令牌交换已确认；账号标识、令牌有效期、刷新轮换和单会话撤销也已确定。

仅当需要余额和支出时（当前不在范围内）才需要继续补充：币种与精度、统计周期与时区、账号或密钥范围、错误语义与轮询限制。那只是建议，不是现行约定，应用不会调用这些路由。

推理 API 密钥和账号会话令牌是两类不同的凭据。需要 API 密钥的 `/v1/usage?days=7` 不能代替账号会话接口。

### 已做的验证

授权部分：`Sources/Auth` 和 `Tests/WikiVibeAuthTests.swift` 可以编译；该测试集的 341 项断言针对真实 loopback 监听器和会话生命周期执行，零失败，覆盖了携带他人 `state` 的回调、超时、取消、refresh token 轮换、服务器不可达时保留会话，以及服务器不可达时退出。本机没有执行 `make build`、`make test` 和启动应用：未安装 Xcode，`xcodebuild` 和 XCTest 不可用。这是验证限制，不是结果。

后端：`go test -tags=unit ./internal/config/ ./internal/service/ ./internal/handler/`，shared-auth 相关测试通过。

在语言调整前，`make build` 成功，11 组独立测试共 63 项通过。整个测试模块都完成了编译，但没有执行完整的第三方提供方测试或真实服务测试。命令如下：

```sh
make test TEST_FLAGS='-only-testing:WikiVibeTests/NotchEdgeTests -only-testing:WikiVibeTests/NotchPlacementTests -only-testing:WikiVibeTests/NotchGeometryTests -only-testing:WikiVibeTests/NotchFleetReconcileTests -only-testing:WikiVibeTests/NotchFleetScopeTests -only-testing:WikiVibeTests/NotchVisibilityTests -only-testing:WikiVibeTests/NotchSizeTests -only-testing:WikiVibeTests/NotchPositionPersistenceTests -only-testing:WikiVibeTests/UpdaterOutcomeTests -only-testing:WikiVibeTests/MiniMaxUsageTests -only-testing:WikiVibeTests/OpenCodeUsageTests'
```

实际运行检查覆盖了账号窗口、小组件、菜单、打开浏览器但不改变登录状态、位置与大小调整、显示和隐藏、重新打开设置、退出，以及重启后的外观设置恢复。最初的图像分析服务不可用，因此窗口截图和辅助功能检查不能证明布局没有任何瑕疵。

三语言更新后的 16 项相关原生测试全部通过。实际打开账号窗口，检查了英文、俄文和简体中文：账号与外观文字会随选择更新，菜单退出操作有对应翻译，退出并重新打开后仍保留中文。截图只保存在被忽略的本地 `build/` 中，本文不会链接到未提交的截图。

再次检查公开客户端和实际 /docs，确认浏览器 PKCE、账号 base /api/v1、响应封装和充值跳转。新构建成功；NotchEdgeTests、NotchFleetScopeTests、NotchVisibilityTests 和 NotchSizeTests 共 16 项测试全部通过。重新启动新应用并按下充值按钮，没有浏览器打开错误；应用仍无会话，不显示金额。辅助功能检查确认三语言按钮文字和具体登录条件，已恢复 Русский / Bottom / Large / Show on hover。像素级图像分析不可用，未声称布局完全没有缺陷。

授权已实现，但完成这项工作的机器没有安装 Xcode：`xcodebuild` 和 XCTest 不可用，因此应用既没有构建也没有启动，也没有进行真实账号登录。在无 Xcode 条件下能验证的部分已做：`Sources/Auth` 与测试文件可以编译，测试集中的 341 项断言针对真实 loopback 监听器和会话生命周期执行，零失败。没有进行余额请求、付款或推理额度消耗。安全验证规则见 [CONTRIBUTING.md](CONTRIBUTING.md)，变更记录见 [CHANGELOG.md](CHANGELOG.md)。

### 许可证

项目采用 [MIT 许可证](LICENSE)。必需的版权声明和依赖许可证保留在仓库及应用资源中。

代理配置使用内置的 jsonc-parser 3.3.1（MIT）和 yaml 2.8.1（ISC）。许可证位于 `Sources/Resources/AgentSetup/JSONC-PARSER-LICENSE.txt` 和 `YAML-LICENSE.txt`，并随应用一起提供。

WikiVibe 图标来自一张 256×256 的本地参考图。较大尺寸是放大生成的，不是高分辨率原图。公开分发二进制版本前，仍需确认品牌使用权，并准备合适的图标源文件。
