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
- «Пополнить» в раскрываемой карточке виджета открывает `https://api.wikivibe.dev/purchase` в системном браузере. При необходимости сайт попросит отдельный вход; приложение не передаёт токены в URL и не создаёт платёж.
- Карточка «API-ключи»: ключи авторизованного аккаунта, выбор адреса API и настройка Codex, oh-my-pi, OpenCode и Claude Code с предпросмотром и подтверждением.

Виджет показывает аккаунт и баланс. Расходы и статистика не читаются: это отдельная задача. Кнопка «Открыть сайт» ведёт в панель `api.wikivibe.dev`, у которой своя сессия в браузере; вход в приложении её не создаёт, поэтому сайт может попросить пароль — это не сброс входа в приложении.

### Настройка окна аккаунта

Окно можно растягивать; его размер и положение восстанавливаются после перезапуска. Карточки «Аккаунт», «Баланс», «Виджет и язык» и «API-ключи» используют общую сетку, одинаковые отступы и выровненные поля, заполняющие доступную ширину. Пояснения о входе раскрываются отдельно, чтобы не перегружать окно.

Кнопка «Настроить окно» в шапке открывает выбор компоновки: адаптивная сетка до двух столбцов, вертикальная колонка или горизонтальное расположение до трёх столбцов. В узком окне столбцов становится меньше, а длинное содержимое доступно через прокрутку. Здесь же выбираются обычные/компактные отступы, порядок карточек стрелками и их видимость. Настройки сохраняются автоматически; даже если скрыть всё, настройка и сброс остаются доступны в шапке.

Кнопка со стрелкой сброса возвращает исходную компоновку, плотность, порядок и видимость карточек. Она не меняет вход в аккаунт, язык, край/размер/видимость виджета или сохранённые размеры окна. Скрытие баланса не меняет его данные и периодичность обновления.

### API-ключи и настройка агентов

Карточка загружает ключи через сессию самого приложения, со всех страниц `GET /api/v1/keys`. Значения ключей скрыты и остаются в памяти до явной записи в настройки агента. В `UserDefaults` сохраняются только ID выбранного ключа для аккаунта, адрес API и выбранные агенты; токен входа не подставляется вместо API-ключа.

Выберите активный ключ, `https://api.wikivibe.dev/v1` или `https://vapi.wikivibe.dev/v1` и нужных агентов. Кнопка «Загрузить модели и посмотреть изменения…» читает авторизованный каталог `/models` выбранного ключа и показывает модели, файлы и предупреждения. Ограничения протоколов из данных ключа учитываются; неизвестная совместимость не выдаётся за подтверждённую. Генерация и платные запросы для проверки не запускаются.

- **Codex:** после явного подтверждения WikiVibe становится провайдером по умолчанию в `~/.codex/config.toml`; там же подключается `wikivibe-models.json`. Доступная текущая текстовая модель сохраняется, иначе выбирается первая текстовая модель каталога. Прежний выбор профиля сбрасывается, его определение сохраняется. Перезапустите десктопный Codex и начните новый чат: модели появятся в его меню. Для CLI запустите обычный `codex` и используйте `/model`; `-p wikivibe` больше не нужен. Требуется поддержка `model_catalog_json`. При повторном применении прежний CLI-профиль удаляется только если он принадлежит плагину и не изменён; восстановление возвращает исходные настройки. Существующие чаты и нестандартные runtime-home не перенастраиваются.
- **oh-my-pi:** `~/.omp/agent/models.yml` или `.yaml`; существующие фильтры в `config.yml`/`.yaml` расширяются только для WikiVibe, роли моделей сохраняются. Выбор модели: `/model`.
- **OpenCode:** `~/.config/opencode/opencode.json` или `.jsonc`; другие поставщики, активная модель и комментарии вне изменяемого блока сохраняются. Выбирайте модель в меню приложения (`Cmd+'` на macOS). Существующие маршруты WikiVibe обновляются, их имена не превращаются в новые дубликаты.
- **Claude Code:** `~/.claude/settings.json`; глобальные `ANTHROPIC_BASE_URL` и `ANTHROPIC_AUTH_TOKEN` заменяются, доступные модели добавляются в `modelPicker`. Это не отдельный поставщик; предупреждение показывается до записи. Для списка моделей нужна версия 2.1.242 или новее; выбор — `/model` в новой сессии.

**Генерация изображений:** при наличии `gpt-image-*`, текстовой GPT‑5+ модели и разрешённого Responses API адаптер oh-my-pi добавляет отсутствующую роль `modelRoles.image` и включает `generate_image.enabled`, если настройка ещё не задана. Существующая роль, явный `enabled: false` и последующее удаление роли пользователем сохраняются. Инструмент `generate_image` отправляет Responses-запрос с текстовой моделью-носителем и `tools: [{type: "image_generation", model: "gpt-image-…"}]`; подробности — в [документации oh-my-pi](https://github.com/can1357/oh-my-pi/blob/main/docs/tools/generate_image.md). Codex, OpenCode и Claude Code не получают image ID: текущие адаптеры не подключают им инструмент генерации. Формирование запроса проверено локально в oh-my-pi 18.10.2; генерация через WikiVibe gateway без платного запроса не подтверждена. После обновления приложения повторно примените настройку и начните новую сессию агента.

**Уровень рассуждений в Codex:** повторно примените настройку Codex из обновлённого WikiVibe, затем перезапустите Codex и откройте новый чат. Нажмите на модель/уровень под полем ввода и выберите reasoning (в новых версиях — ползунок Power); горячая клавиша не нужна. Для известных GPT ID уровни и значения по умолчанию взяты из [официального каталога Codex](https://github.com/openai/codex/blob/main/codex-rs/models-manager/models.json): например, GPT‑5.5 — `low`, `medium`, `high`, `xhigh`; GPT‑6.1‑sol дополнительно объявляет `max` и `ultra`. Конкретное отображение зависит от версии Codex.

Для точных non-GPT ID используются параметры провайдеров: [DeepSeek V4.1 Flash](https://api-docs.deepseek.com/guides/thinking_mode) (оба ID: `deepseek-v4.1-flash` и `deepseek/deepseek-v4.1-flash`) — `none`, `low`, `high`, `max`, по умолчанию `high`; [Gemini 3.8 Flash](https://ai.google.dev/gemini-api/docs/generate-content/thinking#thinking-levels) — `low`, `medium`, `high`, по умолчанию `medium`; Gemini 3.1 Flash-Lite Preview — уровни семейства `minimal`, `low`, `medium`, `high`, по умолчанию `minimal`; [GLM 5.3 и 5.3 Flash](https://docs.z.ai/guides/capabilities/thinking) — `low`, `high`, `max`, по умолчанию `max`. Только DeepSeek позволяет отключить reasoning; `minimal` у Gemini не означает гарантированное отключение. Google [снял Preview с обслуживания](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-lite-preview): ID WikiVibe сохраняется без подмены модели, а описание предупреждает о непроверенном маршруте. Неизвестным и image ID уровни не назначаются. Выбор в меню не доказывает, что WikiVibe преобразует Responses `reasoning.effort` и провайдер применяет его; платный inference при настройке не выполняется.

В проверенной чистой сессии десктопного Codex 26.1007.71326 собственный фильтр интерфейса скрывал `none`, `minimal` и `max`, хотя нативный `model/list` возвращал полный каталог. Мышью проверены DeepSeek `low`, Gemini 3.8 `high`, Flash-Lite Preview `medium` и обе GLM `high`; сохранение подтверждено через `config/read`. Адаптер не подменяет скрытые уровни GPT-алиасами и не изменяет файлы Codex. Доступность всех положений зависит также от настроек возможностей клиента, а не только от каталога.

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

`make dmg` собирает универсальный Release для Intel и Apple Silicon и создаёт `build/WikiVibe.dmg`. Для установки на macOS 15+ откройте образ, закройте уже запущенный WikiVibe и перетащите `WikiVibe.app` на ссылку `Applications` («Программы»). Затем извлеките образ и запускайте приложение из «Программ». Node.js 22+ для настройки агентов устанавливается отдельно и не входит в DMG.

`make build` остаётся неподписанной отладочной сборкой. DMG использует локальную ad-hoc-подпись, а не Developer ID; проверки Apple (notarization) нет. Для этой сборки Hardened Runtime отключён: без Team ID его проверка библиотек блокирует Sparkle при запуске на Apple Silicon. Отладочные entitlements не добавляются; упаковка проверяет флаги подписи обеих архитектур. Это настройка приложения, а не отключение защиты macOS. Если macOS блокирует доверенную копию, после попытки запуска используйте «Системные настройки → Конфиденциальность и безопасность → Всё равно открыть». Не отключайте Gatekeeper целиком. Готовые DMG публикуются вручную в [GitHub Releases](https://github.com/AlexMi64/wikivibe-api/releases); автоматические обновления не настроены.

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
- “Top up” in the widget's hover card opens `https://api.wikivibe.dev/purchase` in the system browser. The website may require its own sign-in; the app does not put tokens in the URL or create a payment.
- API keys card: keys from the signed-in account, API address selection, and Codex, oh-my-pi, OpenCode and Claude Code setup with preview and confirmation.

The widget shows the account and its balance. Spending and usage statistics are not read: that is a separate task. “Open the website” leads to the `api.wikivibe.dev` panel, which keeps its own session in the browser; signing in here does not create it, so the site may ask for a password — that is not the app's session being lost.

### Customize the account window

The window is resizable and restores its size and position after restart. Account, Balance, Widget and language, and API keys cards share a grid, consistent spacing and aligned controls that fill the available width. Sign-in explanations expand separately to keep the main view concise.

“Customize window” in the header offers an adaptive grid with up to two columns, a vertical stack, or a horizontal layout with up to three columns. Narrow windows use fewer columns and scroll when necessary. Choose comfortable/compact spacing, move cards with the arrow buttons, and hide or show them. Changes save automatically; Customize and Reset remain available in the header even when every card is hidden.

The reset-arrow button restores the original layout, spacing, card order and visibility. It does not change sign-in, language, widget edge/size/visibility, or saved window dimensions. Hiding Balance does not change its data or polling schedule.

### API keys and agent configuration

The card reads every page of `GET /api/v1/keys` through the app's own account session. Key values are hidden and stay in memory until an explicit agent configuration write. Only the account's selected key ID, API address and selected agents are saved in `UserDefaults`; the account sign-in token is never substituted for an API key.

Choose an active key, `https://api.wikivibe.dev/v1` or `https://vapi.wikivibe.dev/v1`, and the agents to configure. “Load models and preview…” reads that key's authenticated `/models` catalog and shows the models, affected files and warnings. Reported protocol restrictions are respected; unknown compatibility is not presented as verified. No inference or paid request is used to check the connection.

- **Codex:** after explicit confirmation, WikiVibe becomes the default provider in `~/.codex/config.toml`, which also loads `wikivibe-models.json`. An available current text model is retained; otherwise the first text model in the catalog is selected. The previous profile selection is cleared, not its definition. Restart desktop Codex and start a new chat to see the models in its menu. For the CLI, run ordinary `codex` and use `/model`; `-p wikivibe` is no longer needed. Requires `model_catalog_json` support. Reapplying removes the former CLI profile only if it is plugin-owned and unedited; restoration returns the original configuration. Existing chats and custom runtime homes are not reconfigured.
- **oh-my-pi:** `~/.omp/agent/models.yml` or `.yaml`; existing `config.yml`/`.yaml` filters expand only for WikiVibe, and model roles stay intact. Choose with `/model`.
- **OpenCode:** `~/.config/opencode/opencode.json` or `.jsonc`; other providers, the active model and comments outside the changed block stay intact. Choose a model in the app's menu (`Cmd+'` on macOS). Existing WikiVibe routes are updated without adding duplicate aliases.
- **Claude Code:** `~/.claude/settings.json`; replaces global `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` and adds available models to `modelPicker`. This is not a separate provider; the warning appears before writing. The picker requires 2.1.242 or newer; choose with `/model` in a new session.

**Image generation:** when `gpt-image-*`, a GPT‑5+ text model and the Responses protocol are available, the oh-my-pi adapter adds a missing `modelRoles.image` and enables `generate_image.enabled` only if unset. Existing roles, an explicit `enabled: false` and subsequent user role removals are preserved. The `generate_image` tool sends a Responses request with a text carrier and `tools: [{type: "image_generation", model: "gpt-image-…"}]`; see the [oh-my-pi tool documentation](https://github.com/can1357/oh-my-pi/blob/main/docs/tools/generate_image.md). Codex, OpenCode and Claude Code do not receive image IDs because the current adapters do not wire up image generation. Request construction was exercised locally in oh-my-pi 18.10.2; generation through the WikiVibe gateway remains unverified without a paid request. After updating the app, reapply configuration and start a new agent session.

**Codex reasoning effort:** reapply Codex setup from the updated WikiVibe app, restart Codex and open a new chat. Click the model/effort below the composer and choose reasoning (the Power slider in newer versions); no hotkey is required. Known GPT IDs use defaults and effort presets from the [official Codex catalog](https://github.com/openai/codex/blob/main/codex-rs/models-manager/models.json): for example, GPT‑5.5 offers `low`, `medium`, `high`, `xhigh`, while GPT‑6.1‑sol additionally advertises `max` and `ultra`. Presentation depends on the Codex version.

Exact non-GPT IDs use provider-specific presets: [DeepSeek V4.1 Flash](https://api-docs.deepseek.com/guides/thinking_mode) (both `deepseek-v4.1-flash` and `deepseek/deepseek-v4.1-flash`) — `none`, `low`, `high`, `max`, default `high`; [Gemini 3.8 Flash](https://ai.google.dev/gemini-api/docs/generate-content/thinking#thinking-levels) — `low`, `medium`, `high`, default `medium`; Gemini 3.1 Flash-Lite Preview — family presets `minimal`, `low`, `medium`, `high`, default `minimal`; [GLM 5.3 and 5.3 Flash](https://docs.z.ai/guides/capabilities/thinking) — `low`, `high`, `max`, default `max`. Only DeepSeek can disable reasoning; Gemini's `minimal` does not guarantee that thinking is off. Google has [shut down the Preview](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-lite-preview): its WikiVibe ID is retained without model substitution, and its description warns about the unverified route. Unknown and image IDs receive no presets. Menu selection does not prove that WikiVibe converts Responses `reasoning.effort` or that the provider honors it; setup performs no paid inference.

In the checked clean desktop Codex 26.1007.71326 session, the client's own UI filter hid `none`, `minimal`, and `max`, although native `model/list` returned the full catalog. Mouse selections of DeepSeek `low`, Gemini 3.8 `high`, Flash-Lite Preview `medium`, and both GLMs `high` were confirmed by `config/read`. The adapter does not substitute GPT aliases for hidden levels or modify Codex files. Visibility of every position also depends on the client's enabled capabilities, not just the catalog.

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

`make dmg` builds a universal Release for Intel and Apple Silicon at `build/WikiVibe.dmg`. To install on macOS 15+, open the image, quit any running WikiVibe, and drag `WikiVibe.app` onto the `Applications` shortcut. Eject the image and launch the app from Applications. Node.js 22+ for agent configuration is installed separately and is not included in the DMG.

`make build` remains an unsigned debug build. The DMG uses local ad-hoc signing, not Developer ID, and is not notarized by Apple. Hardened Runtime is disabled for this build: without a Team ID, its library validation blocks Sparkle at launch on Apple Silicon. Debug entitlements are not injected; packaging checks both architectures' signature flags. This is an app build policy, not a system security override. If macOS blocks a trusted copy, attempt to launch it and use System Settings → Privacy & Security → Open Anyway. Do not disable Gatekeeper globally. Installers are published manually in [GitHub Releases](https://github.com/AlexMi64/wikivibe-api/releases); automatic updates are not configured.

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
- 小组件悬浮卡片中的“充值”会在系统浏览器中打开 `https://api.wikivibe.dev/purchase`。网站可能要求单独登录；应用不会在 URL 中传递令牌，也不会创建付款。
- API 密钥卡片：读取已登录账号的密钥，选择 API 地址，为 Codex、oh-my-pi、OpenCode 和 Claude Code 配置密钥和模型，写入前预览并确认。

小组件显示账号和余额。支出和使用统计不读取：那是另一项任务。“打开网站”跳转到 `api.wikivibe.dev` 面板，它在浏览器里有自己的会话；在这里登录不会创建那个会话，所以网站可能要求输入密码——这不是应用里的登录被清除。

### 自定义账号窗口

窗口可调整大小，重启后恢复大小和位置。账号、余额、小组件与语言、API 密钥四张卡片使用统一网格、间距和对齐方式，控件填满可用宽度。登录说明可单独展开，避免主界面堆积文字。

窗口顶部的“自定义窗口”提供最多两列的自适应网格、纵向排列和最多三列的横向排列。窄窗口自动减少列数，内容过长时可滚动。还可以选择舒适或紧凑间距，用箭头调整卡片顺序，以及隐藏或显示卡片。修改自动保存；即使隐藏所有卡片，顶部的自定义和重置按钮仍然可用。

重置箭头恢复初始布局、间距、卡片顺序和显示状态，不改变登录、语言、小组件的位置/大小/显示方式，也不改变已保存的窗口大小。隐藏余额卡片不会更改余额数据或刷新频率。

### API 密钥与代理配置

卡片通过应用自身的账号会话读取 `GET /api/v1/keys` 的所有分页。密钥值已隐藏，仅保留在内存中，直到明确确认写入代理配置。`UserDefaults` 仅保存账号所选密钥的 ID、API 地址和代理选项；账号登录令牌绝不会代替 API 密钥。

选择有效密钥、`https://api.wikivibe.dev/v1` 或 `https://vapi.wikivibe.dev/v1`，以及要配置的代理。“加载模型并预览…”读取该密钥经过认证的 `/models` 目录，并显示模型、受影响文件和警告。应用遵守密钥报告的协议限制，不会把未知兼容性描述为已验证。检查连接不会执行推理或付费请求。

- **Codex：**明确确认后，WikiVibe 将成为 `~/.codex/config.toml` 中的默认提供商，并在该文件中加载 `wikivibe-models.json`。若当前文本模型可用则保留，否则选择目录中的第一个文本模型。将清除原先选中的配置档，但保留其定义。请重启桌面 Codex 并新建聊天，在菜单中选择模型。CLI 使用普通 `codex` 和 `/model`，不再需要 `-p wikivibe`。需要支持 `model_catalog_json`。重新应用时，仅删除由插件创建且未被修改的旧 CLI 配置档；恢复会还原原始配置。不更改现有聊天及自定义运行目录。
- **oh-my-pi：**使用 `~/.omp/agent/models.yml` 或 `.yaml`；仅为 WikiVibe 扩展现有 `config.yml`/`.yaml` 的筛选条件，保留模型角色。用 `/model` 选择。
- **OpenCode：**使用 `~/.config/opencode/opencode.json` 或 `.jsonc`；保留其他提供商、当前模型和更改块之外的注释。在应用菜单中选择模型（macOS 为 `Cmd+'`）。更新现有 WikiVibe 路由，不添加重复别名。
- **Claude Code：**使用 `~/.claude/settings.json`；替换全局 `ANTHROPIC_BASE_URL` 和 `ANTHROPIC_AUTH_TOKEN`，并在 `modelPicker` 添加可用模型。这不是独立提供商，写入前会显示警告。模型选择器需要 2.1.242 或更新版本；请在新会话中用 `/model` 选择。

**图像生成：**当目录中有 `gpt-image-*` 和 GPT‑5+ 文本模型且允许 Responses 协议时，oh-my-pi 适配器添加缺失的 `modelRoles.image`，并仅在未设置时启用 `generate_image.enabled`。保留已有角色、明确的 `enabled: false` 以及用户之后删除角色的操作。`generate_image` 工具通过文本载体模型发送 Responses 请求，包含 `tools: [{type: "image_generation", model: "gpt-image-…"}]`；参见 [oh-my-pi 工具文档](https://github.com/can1357/oh-my-pi/blob/main/docs/tools/generate_image.md)。Codex、OpenCode 和 Claude Code 不会收到图像 ID，因为当前适配器没有接入图像生成工具。已在 oh-my-pi 18.10.2 中通过本地端点验证请求构建；未发送付费请求，因此尚未确认 WikiVibe 网关的实际生成能力。更新应用后，请重新应用配置并新建代理会话。

**Codex 推理强度：**在新版 WikiVibe 中重新应用 Codex 配置，重启 Codex 并新建聊天。点击输入框下方的模型／推理强度，选择级别（新版本显示 Power 滑块），无需快捷键。已知 GPT ID 的默认值及级别来自 [Codex 官方目录](https://github.com/openai/codex/blob/main/codex-rs/models-manager/models.json)：例如 GPT‑5.5 提供 `low`、`medium`、`high`、`xhigh`，GPT‑6.1‑sol 还声明 `max` 和 `ultra`。显示方式取决于 Codex 版本。

非 GPT 模型按确切 ID 使用提供商定义的级别：[DeepSeek V4.1 Flash](https://api-docs.deepseek.com/guides/thinking_mode)（`deepseek-v4.1-flash` 和 `deepseek/deepseek-v4.1-flash`）提供 `none`、`low`、`high`、`max`，默认 `high`；[Gemini 3.8 Flash](https://ai.google.dev/gemini-api/docs/generate-content/thinking#thinking-levels) 提供 `low`、`medium`、`high`，默认 `medium`；Gemini 3.1 Flash-Lite Preview 使用该系列的 `minimal`、`low`、`medium`、`high`，默认 `minimal`；[GLM 5.3 和 5.3 Flash](https://docs.z.ai/guides/capabilities/thinking) 提供 `low`、`high`、`max`，默认 `max`。只有 DeepSeek 可以关闭推理；Gemini 的 `minimal` 不保证完全不思考。Google 已[停止 Preview 服务](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-lite-preview)：保留 WikiVibe ID，不替换模型，并在描述中提示路由尚未验证。未知 ID 和图像模型不声明推理级别。菜单选择不证明 WikiVibe 转换了 Responses `reasoning.effort`，也不证明提供商采用了该强度；配置时不执行付费推理。

在干净的桌面 Codex 26.1007.71326 会话中，客户端自身的界面筛选隐藏了 `none`、`minimal` 和 `max`，但原生 `model/list` 返回完整目录。已用鼠标选择 DeepSeek `low`、Gemini 3.8 `high`、Flash-Lite Preview `medium` 和两款 GLM 的 `high`，并通过 `config/read` 确认保存。适配器不会用 GPT 别名替代隐藏级别，也不会修改 Codex 文件。能否显示全部位置还取决于客户端启用的功能，而不只是模型目录。

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

`make dmg` 为 Intel 与 Apple Silicon 构建通用 Release，并生成 `build/WikiVibe.dmg`。在 macOS 15 或更新版本上安装时，打开磁盘映像，退出已运行的 WikiVibe，将 `WikiVibe.app` 拖到 `Applications`（应用程序）快捷方式。弹出映像后，从“应用程序”启动。代理配置需要另行安装 Node.js 22+，DMG 不包含 Node.js。

`make build` 仍生成未签名的调试版本。DMG 使用本地 ad-hoc 签名，而非 Developer ID，且未经过 Apple 公证。此构建关闭 Hardened Runtime：缺少 Team ID 时，其库验证会在 Apple Silicon 上阻止 Sparkle 加载。构建不注入调试 entitlements，打包会检查两种架构的签名标志。这是应用的构建策略，不会关闭系统安全保护。如果 macOS 阻止可信副本，请先尝试启动，再到“系统设置 → 隐私与安全性 → 仍要打开”允许运行。不要全局禁用 Gatekeeper。安装包手动发布到 [GitHub Releases](https://github.com/AlexMi64/wikivibe-api/releases)，尚未配置自动更新。

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
