# WikiVibe 桌面端：后端接口约定

[English](BACKEND_SPEC.en.md) · [Русский — 权威版本](BACKEND_SPEC.md) · [简体中文](BACKEND_SPEC.zh-CN.md)

状态：**BLOCKED**。服务器端方案由 backend 团队确认。本文只覆盖 macOS 原生应用的登录、账号余额和支出，以及跳转到 HTTPS 充值页面。代理配置和应用内付款不在范围内。如果译文有差异，以俄文规范为准。

## 已确认的公开观察

- `https://auth.wikivibe.dev/` 返回 HTML 单页应用。打开它并不会建立桌面应用会话。
- 检查过的服务发现和文档地址返回的是 HTML，并不是已确认的 OIDC/OpenAPI JSON 约定。
- 未携带凭据的 `GET https://auth.wikivibe.dev/api/v1/auth/me` 返回 HTTP 401，内容为 `{"code":"UNAUTHORIZED","message":"Authorization header is required"}`。成功响应的结构，以及桌面端可使用的凭据类型，都还没确认。
- `GET https://auth.wikivibe.dev/api/v1/auth/sso/config` 返回浏览器 SSO 配置，issuer 为 `https://auth.wikivibe.dev`，并提供面向 `api.wikivibe.dev` 和 `dev.wikivibe.dev` 的重定向地址。这不是 macOS 客户端注册信息。
- 未携带凭据的 `GET https://api.wikivibe.dev/v1/usage?days=7` 返回 HTTP 401，内容为 `{"code":"API_KEY_REQUIRED","message":"Требуется API-ключ"}`。参考客户端在这里使用 Bearer API 密钥。不能把这个接口当作账号会话 API。
- 再次检查当前客户端，确认浏览器 SSO 使用 PKCE S256 并验证 state。这只证明浏览器流程，不是桌面客户端注册信息。

## 当前客户端调查

检查了公开 scripts、实际渲染的 `/docs` 和最小只读 GET 响应；没有提取浏览器存储、cookies、API 密钥或 Authorization，也没有登录、创建密钥、运行推理或付款。

| 来源 | 实际观察 |
|---|---|
| [主 script](https://api.wikivibe.dev/assets/index-CCkmicLd.js) | 账号 baseURL 为当前 origin 下的 `/api/v1`；API 域名对应 `https://api.wikivibe.dev/api/v1`。网关 `/v1` 是另一套接口。 |
| HTTP 拦截器 | 响应封装为 `{code, message, data}`；code 0 取 data，非零 code 即使 HTTP 200 也视为错误。浏览器发送 Bearer access token、GET timezone 和 Accept-Language。 |
| [SSO config](https://api.wikivibe.dev/api/v1/auth/sso/config) | HTTP 200：enabled true，issuer 为 auth.wikivibe.dev，API callback 为 `https://api.wikivibe.dev/auth/sso/callback`，dev callback 为 `https://dev.wikivibe.dev/api/auth/sso/callback/`。没有桌面注册字段。 |
| 浏览器授权 | GET `https://auth.wikivibe.dev/api/v1/auth/sso/authorize`，参数为 client_id=api、redirect_uri、state、code_challenge 和 S256。应用不得借用 api 客户端或绕过回调白名单。 |
| [浏览器回调](https://api.wikivibe.dev/assets/SsoCallbackView-vPD5d71O.js)及主 script | 验证 state 后 POST `/auth/sso/token`，JSON 为 `{client_id, redirect_uri, code, code_verifier}`。script 不发送 grant_type 或 response_type。这是现有 web 流程，不是建议的标准 OAuth 约定。 |
| 浏览器会话 | 交换响应被读取为 `{access_token, refresh_token?, expires_in?, user}`，user 有 id。POST `/auth/refresh` 发送 refresh_token，读取 access_token、refresh_token 和以秒计的 expires_in。POST `/auth/logout` 发送 refresh_token；revoke-all-sessions 是另一操作，不能用来实现本地退出。桌面令牌轮换和撤销语义尚未确认。 |
| 共享浏览器会话 | `/auth/sso/session` 安装浏览器会话，`/auth/sso/logout` 结束它。这不证明原生应用可以从 browser cookie 获取会话。 |
| [账号资料](https://api.wikivibe.dev/assets/user-Sw7qdUw9.js) | GET `/user/profile`；GET `/auth/me` 检查身份。没有 Bearer 时均返回 401 UNAUTHORIZED。在指定 Orca 页面不提取 Bearer 的安全 GET 也返回 401，没有观察到成功 JSON。 |
| [支出](https://api.wikivibe.dev/assets/usage-bJ4Ifxlm.js) | GET `/usage/stats` 接收 period 或 start_date/end_date，以及可选 api_key_id；dashboard 使用 GET `/usage/dashboard/stats`。无凭据时均返回 401。 |
| [Dashboard](https://api.wikivibe.dev/assets/DashboardView-BuNjK2_n.js) | UI 读取 user.balance、today_actual_cost、total_actual_cost；日期和 timezone 由客户端传入。完整结构、null/精度和周期边界未由成功响应确认。不能照搬浏览器缺失值变零的写法。 |
| [公开设置](https://api.wikivibe.dev/api/v1/settings/public) | HTTP 200/code 0：balance_unit_name 为 USD，balance_unit_symbol 为 $；文档地址为 `https://api.wikivibe.dev/docs`。单位由服务器设置决定，不能猜。 |
| [实际文档](https://api.wikivibe.dev/docs) | 说明网关 API-key Bearer 和 /v1/usage，没有桌面注册/scopes/callback 或账号成功结构。OIDC/OAuth discovery 和 /openapi.json 返回 SPA HTML；/api/v1/openapi.json 返回 404。 |
| [充值](https://api.wikivibe.dev/purchase) | 公开文档指向 /purchase；点击后实际进入该 HTTPS 路由。需要浏览器登录。导航不会创建付款，也不传递桌面令牌。 |

公开 tfcli loopback 是 /keys 的 API 密钥配置导入，不是已确认的原生账号登录，本应用不使用它。公开文档搜索没有找到 macOS 注册信息；这不表示 backend 无法提供。

**明确的外部前提：** 注册的公共 desktop client_id、允许的 callback/loopback 和端口规则（或设备授权）、授权码交换适用性、audience/scopes，以及脱敏的账号和金额成功结构。刷新/退出需要有效期、轮换、终止错误及当前会话撤销规则。金额需要精度/null、周期/timezone、账号归属和轮询限制。没有合法桌面会话，Keychain 恢复、刷新/退出、真实金额、轮询/过期数据/迟到响应处理仍为 BLOCKED。已确认的充值跳转单独实现。

## 1. 通过系统浏览器登录

目的：为原生公共客户端建立账号会话，不在应用中收集密码，也不在二进制中放入 client secret。负责方：backend。

**桌面端接口尚未确认。** 需要发布 HTTP 方法、URL、参数和成功响应结构。应用不会调用下面提出但尚未确认的路由或流程。

**建议方案，不是现有 API：** Authorization Code 配合 PKCE（S256）。注册公共客户端，并确定一种允许的返回方式：localhost HTTP loopback，附带明确的端口选择规则；或受保护的已注册 callback。如果只支持设备授权，就发布设备授权流程，不要假设 OAuth 回调可用。

明确授权请求字段：`client_id`、`redirect_uri`、`response_type`、scopes、`state`、`code_challenge` 和 `code_challenge_method`。回调应返回一次性 `code` 与原始 `state`，或明确的错误名称。POST 令牌交换需定义内容类型，以及 `grant_type`、`client_id`、`code`、`redirect_uri`、`code_verifier` 字段。

建议的令牌响应：`access_token: string`、`token_type: "Bearer"`、`expires_in: integer seconds > 0`、`refresh_token?: string`、`scope?: string`。实际字段名、响应封装，以及可选字段和 `null` 的规则，仍需确认。令牌只保存在 macOS Keychain 中。推理 API 密钥不是账号令牌，也不是刷新令牌。

说明取消、错误的 state/redirect/code、过期或重复使用的授权码、超时、HTTP 400/401/403/429/5xx、业务错误码、安全的用户提示和 Retry-After。明确授权码有效期、尝试次数限制和重放保护。令牌交换成功且账号身份确认前，即使浏览器已打开，应用也仍未登录。

## 2. 账号身份、恢复、刷新和退出

目的：确定会话归属，并定义完整的会话生命周期。负责方：backend。

已观察到的 GET `/api/v1/auth/me` 并未确认成功响应结构。需要确认 host、path、method 和认证方式。建议的账号响应：稳定且不含敏感信息的 `account_id: string`，以及 `display_name?: string`。明确响应封装和最低 scopes。示例中不要放真实个人信息。

刷新：确认 POST 接口、请求结构、有效期单位、令牌轮换规则、旧 refresh token 的失效方式，以及并发或重复请求的处理。建议请求为 `refresh_token: string`，响应沿用上述令牌结构。还需给出 refresh token 的有效期，以及会话过期或被撤销时的终止错误。

退出和撤销：确认地址、HTTP 方法、认证、请求与响应结构、只撤销当前会话的语义、它与撤销全部会话的区别，以及幂等性。即使后端不可用，本地退出也必须删除 Keychain 条目并取消未完成的数据请求。不能假造服务器撤销操作。Keychain 读取失败，不等于凭据不存在或已过期。

会话代际边界：退出或切换账号后，不能再应用旧会话请求的响应。后端需提供稳定的账号标识，并让客户端能够核对返回数据属于哪个账号。

## 3. 账号余额和支出

目的：从服务器获取真实金额和支出，而不是从本地代理日志推算。负责方：backend。

**已发现浏览器账号路由，但成功 JSON 结构和桌面会话适用性尚未确认。** 应明确 `/user/profile` 和 `/usage/stats`，而不是另造接口。不能用需要 API 密钥的 `/v1/usage?days=7` 代替。还需确认 scopes 和原生会话兼容性。

**建议的数据结构，不是现有 API：**

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

可以用十进制字符串代替整数最小货币单位，但必须明确精度、币种、负余额、舍入、字段缺失、`null` 和数值范围。`0` 是真实的零，字段缺失不是零。还需说明账号或密钥范围、UTC ISO-8601 日期、周期边界是否包含端点、统计时区，以及数据时间戳。一份快照应对应同一个账号和同一时点。

明确 HTTP 与业务错误语义：凭据过期或撤销用 401；权限或 scopes 错误用 403；限流用 429 并带 Retry-After；说明 5xx 和临时网络错误；如果响应有封装，也要说明 HTTP 200 中的业务错误。给出结构版本和必填字段。网络失败时保留最近一次确认的金额、获取时间和过期提示；从未成功获取过数据，就不显示金额。

轮询：发布最短间隔、限流规则，以及缓存/ETag 语义。如果还没有建议，暂定方案是仅在已确认的活跃会话下每 60 秒请求一次，同一时间只发一个请求。退出时停止轮询、取消旧请求，并拒绝应用旧响应。手动刷新也要遵守服务器限流。

## 4. 跳转到 HTTPS 充值页面

目的：打开官方浏览器流程，不由应用创建付款。负责方：backend。

**已确认 URL：** `https://api.wikivibe.dev/purchase`。公开文档与 router 将它定义为充值；已实际验证跳转，没有付款。页面需要浏览器登录。应用只打开这个固定 HTTPS URL，不在查询参数中传令牌或绑定会话。打开页面不代表桌面登录成功，也不代表付款完成。

## 最小接入顺序

1. 桌面公共客户端、浏览器返回、令牌交换和安全的错误结构。
2. 账号身份、有效期、刷新和单个会话撤销。
3. 账号余额和支出结构、单位、统计周期和轮询规则。
4. 使用已确认的 `https://api.wikivibe.dev/purchase`，不创建付款。
5. 用户自己登录。验证回调、重启恢复、真实金额、刷新、离线与过期数据、会话到期、退出和充值页面跳转，不进行付款。验证不需要、也不允许使用其他人的凭据。
