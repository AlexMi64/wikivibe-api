# Backend contracts / Контракты сервера

**Status / Статус: BLOCKED.** Owner / Ответственный: backend.

- [Русский — каноническая спецификация](BACKEND_SPEC.md)
- [English — complete translation](BACKEND_SPEC.en.md)
- [简体中文 — 完整译文](BACKEND_SPEC.zh-CN.md)

Required: registered desktop public client_id and allowed callback, native token applicability, account-session lifecycle and successful account balance/spending schemas. Current browser PKCE routes and frontend-consumed fields are documented separately from successful server schemas and proposals. HTTPS top-up navigation to `https://api.wikivibe.dev/purchase` is confirmed and implemented; no payment was made.

Требуются зарегистрированный публичный desktop client_id и разрешённый callback, применимость токенов к настольному клиенту, жизненный цикл сессии и успешные схемы баланса/расходов. Браузерный PKCE и поля, которые читает web-клиент, отделены от успешных серверных ответов и предложений. HTTPS-переход на `https://api.wikivibe.dev/purchase` подтверждён и реализован; платёж не выполнялся.

仍需注册的公共 desktop client_id、允许的 callback、桌面令牌适用性、会话生命周期和余额/支出成功结构。已发现的浏览器 PKCE 和前端读取字段与服务器成功响应、建议方案分开记录。HTTPS 充值跳转 `https://api.wikivibe.dev/purchase` 已确认并实现，没有付款。
