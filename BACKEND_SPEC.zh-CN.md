# WikiVibe 桌面端：后端接口约定

[English](BACKEND_SPEC.en.md) · [Русский — 权威版本](BACKEND_SPEC.md) · [简体中文](BACKEND_SPEC.zh-CN.md)

状态：**登录已实现；余额和支出不在范围内。** 服务器端方案由 backend 团队确认。本文只覆盖 macOS 原生应用的登录、账号余额和支出，以及跳转到 HTTPS 充值页面。代理配置和应用内付款不在范围内。如果译文有差异，以俄文规范为准。

登录、会话恢复、令牌刷新和退出已经实现，并作为现行约定记录（第 1、1a、2 节）。余额和支出仍是后续阶段的建议：应用既不请求也不显示它们。

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

**desktop 客户端已注册。** 后端 `origin/main` 新增第四个客户端 `desktop`（`shared_auth.desktop_redirect_uri`，默认 `http://127.0.0.1/callback`）。校验器接受任意 loopback 端口（RFC 8252 §7.3），但固定 scheme、host 和 path，`ResolveClient` 把 client_id 绑定到该地址。余额和支出不在本次任务内，因此其下方的约定仍为建议。

## 1. 通过系统浏览器登录

目的：为原生公共客户端建立账号会话，不在应用内收集密码，也不内置 client secret。负责方：backend。

**现行方式：Authorization Code + PKCE S256。** 已实现并验证：

- `GET https://auth.wikivibe.dev/api/v1/auth/sso/authorize`，参数 `client_id=desktop`、`redirect_uri=http://127.0.0.1:<端口>/callback`、`state`、`code_challenge`、`code_challenge_method=S256`。
- 没有中心浏览器会话时返回 `302` 到 `https://auth.wikivibe.dev/login?redirect=…`；有会话时返回 `302` 到已注册回调，并带上 `code` 和原始 `state`。
- `POST https://api.wikivibe.dev/api/v1/auth/sso/token`，JSON `{client_id, redirect_uri, code, code_verifier}`，返回 `access_token`、`refresh_token`、`expires_in`（秒）、`token_type` 和 `user`。不使用 `grant_type` 和 `response_type`。
- 未注册的 `client_id`/`redirect_uri` 返回 `400 INVALID_REQUEST`；错误的 `code_verifier` 返回 `INVALID_CODE_VERIFIER`。

`state` 必填，不超过 512 字节，且为可见 ASCII。`code_verifier` 为 43…128 个 base64url 字符。令牌只存放在 macOS 钥匙串；推理 API 密钥既不是账号令牌，也不是刷新令牌。

## 1a. 会话生命周期

已实现并验证：`POST https://api.wikivibe.dev/api/v1/auth/refresh`，JSON `{refresh_token}`，返回 `access_token`、`refresh_token`、`expires_in`、`token_type`；refresh token 会轮换，因此应用保存收到的那一个。`POST https://api.wikivibe.dev/api/v1/auth/logout`，`{refresh_token}`，只撤销这一个令牌，与撤销账号全部会话相互独立。`GET https://api.wikivibe.dev/api/v1/auth/sso/me` 带 `Bearer` 确认账号，会话被撤销后返回 `401`。应用把 `401`/`403` 视为会话失效，而不是网络故障。

## 2. 账号身份、恢复、刷新和退出

目的：确定会话归属和生命周期。负责方：backend。**已实现。**

账号：`GET https://api.wikivibe.dev/api/v1/auth/sso/me` 带 `Bearer`，在标准 `{code, message, data}` 外壳中返回 `{user, telegram_user}`。应用只读取 `user` 的 `id`、`username` 和 `email`——足以显示当前登录者，其余一概不保存。外壳具有权威性：即使 HTTP 200，`code != 0` 也是错误。

刷新：`POST /api/v1/auth/refresh`，`{refresh_token}`；响应 `{access_token, refresh_token, expires_in, token_type}`。refresh token 会轮换，因此应用保存新的——沿用旧的会让下次刷新以「已撤销」失败。收到响应时 `expires_in` 就换算成绝对过期时间，而不是以时长形式保存。

退出与撤销：`POST /api/v1/auth/logout`，`{refresh_token}`，只撤销该令牌（不同于 `/auth/revoke-all-sessions` 会撤销账号的全部会话）。本地会话在发起服务器请求之前、且无论请求结果如何都会从钥匙串中清除：服务器不可达不应让用户停留在已经退出的机器上。

恢复：启动时应用从钥匙串读取会话。access token 过期则刷新；refresh token 被撤销（`401`/`403`）则退出登录并明确提示。网络故障不算退出：会话保留，账号显示为未确认状态。钥匙串读取失败既不表示没有凭据，也不表示凭据过期。

会话代际边界：上一会话的响应绝不会在退出后生效——退出在发起网络请求前就清空持有的会话，进行中的登录会关闭自己的监听端口。

## 3. 账号余额和支出

**不在本次范围内。** 本次任务只做授权：应用显示账号，不请求任何金额。以下是后续阶段的建议，不是现行约定。应用不调用这些路由，也不显示余额或支出。

目的（后续阶段）：从服务器获取真实金额和支出，而不是从本地代理日志推算。负责方：backend。

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

1. ~~桌面公共客户端、浏览器返回、令牌交换和安全的错误结构。~~ **已完成**（第 1 节）。
2. ~~账号身份、有效期、刷新和单个会话撤销。~~ **已完成**（第 1a、2 节）。
3. 账号余额和支出结构、单位、统计周期和轮询规则。**不在本次范围内。**
4. `https://api.wikivibe.dev/purchase` 保持为网站按钮，应用内不付款。
5. 用户自己登录。验证回调、重启恢复、会话到期和退出。验证不需要、也不允许使用其他人的凭据。
