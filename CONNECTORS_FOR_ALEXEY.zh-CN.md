# WikiVibe 桌面端：后端接口约定

[English](CONNECTORS_FOR_ALEXEY.en.md) · [Русский — 权威版本](CONNECTORS_FOR_ALEXEY.md) · [简体中文](CONNECTORS_FOR_ALEXEY.zh-CN.md)

状态：**BLOCKED**。服务器端方案由 backend 团队确认。本文只覆盖 macOS 原生应用的登录、账号余额和支出，以及跳转到 HTTPS 充值页面。代理配置和应用内付款不在范围内。如果译文有差异，以俄文规范为准。

## 已确认的公开观察

- `https://auth.wikivibe.dev/` 返回 HTML 单页应用。打开它并不会建立桌面应用会话。
- 检查过的服务发现和文档地址返回的是 HTML，并不是已确认的 OIDC/OpenAPI JSON 约定。
- 未携带凭据的 `GET https://auth.wikivibe.dev/api/v1/auth/me` 返回 HTTP 401，内容为 `{"code":"UNAUTHORIZED","message":"Authorization header is required"}`。成功响应的结构，以及桌面端可使用的凭据类型，都还没确认。
- `GET https://auth.wikivibe.dev/api/v1/auth/sso/config` 返回浏览器 SSO 配置，issuer 为 `https://auth.wikivibe.dev`，并提供面向 `api.wikivibe.dev` 和 `dev.wikivibe.dev` 的重定向地址。这不是 macOS 客户端注册信息。
- 未携带凭据的 `GET https://api.wikivibe.dev/v1/usage?days=7` 返回 HTTP 401，内容为 `{"code":"API_KEY_REQUIRED","message":"Требуется API-ключ"}`。参考客户端在这里使用 Bearer API 密钥。不能把这个接口当作账号会话 API。
- 公开前端中有 login、refresh、logout 和 SSO 路由名称。但这些名称，以及浏览器中的 localStorage 用法，都不能证明桌面回调、PKCE、客户端注册、令牌结构或账号用量结构已经确定。

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

**账号会话接口和成功 JSON 响应结构尚未确认。** 不能用需要 API 密钥的 `/v1/usage?days=7` 代替。需确认 host、GET 方法、路由、scopes，以及是否支持账号会话认证。

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

**跳转约定尚未确认。** 需要固定的 HTTPS URL，或返回该地址的接口，并明确 HTTP 方法、认证、请求和响应结构。建议响应：`url: string`、`expires_at?: UTC ISO-8601 string`。确认允许的域名、登录要求、会话绑定和有效期。不要把账号令牌放进 URL 查询参数，验证时也不要付款。

## 最小接入顺序

1. 桌面公共客户端、浏览器返回、令牌交换和安全的错误结构。
2. 账号身份、有效期、刷新和单个会话撤销。
3. 账号余额和支出结构、单位、统计周期和轮询规则。
4. 官方 HTTPS 充值跳转约定。
5. 用户自己登录。验证回调、重启恢复、真实金额、刷新、离线与过期数据、会话到期、退出和充值页面跳转，不进行付款。验证不需要、也不允许使用其他人的凭据。
