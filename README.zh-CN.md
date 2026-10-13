# WikiVibe macOS 版

[English](README.md) · [Русский](README.ru.md) · [简体中文](README.zh-CN.md)

WikiVibe 是一款 macOS 应用，提供屏幕边缘小组件和菜单栏入口。

**账号接入目前受阻（BLOCKED）。** 应用能构建、能运行。已发现浏览器 PKCE 和账号 API 路由，但公共 desktop client_id、允许的 callback 和桌面令牌适用性尚未确认。应用不会编造余额，不会把缺失数据当成零，也不会把打开网站当成登录成功。

## 现在能做什么

- 使用屏幕边缘小组件、菜单栏入口和账号窗口。
- 调整位置、大小和显示方式，重启后保留设置。
- 在应用内选择 English、Русский 或简体中文。
- 通过系统浏览器打开 `https://auth.wikivibe.dev/`。这只是访问网站，不是登录桌面应用。
- “前往网站充值”按钮打开已确认的 `https://api.wikivibe.dev/purchase`，不传递令牌。浏览器登录和付款由用户自行操作。

目前“刷新”只打开接入条件，不发送账号请求。Keychain 会话存储、浏览器回调、令牌刷新、退出、真实余额/支出，以及带过期数据和错误状态的手动/后台刷新，仍需桌面注册和成功结构，状态为 BLOCKED。本阶段不做 Codex、oh-my-pi 或 OpenCode 一键配置。

## 构建和运行

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

## 启动行为和隐私

`Sources/App/AppDelegate.swift` 只启动 WikiVibe 的界面，不会启动其他服务的账号发现、代理监控、本地费用索引、手机连接服务、凭据迁移或自动更新。渲染不会调用账号发现逻辑。初始化设置时，也不会读取 LM Studio 配置或把旧的自定义接口密钥迁移到 Keychain。

源码中保留提供方库不等于已经接通 WikiVibe。Sparkle 仍是构建依赖，但更新器不会创建，也没有配置更新源、签名身份、更新地址或公开签名密钥。

产品和 Xcode scheme 都叫 `WikiVibe`。应用标识与日志子系统是 `dev.wikivibe.desktop`。

早期开发时，代码审查发现渲染路径会间接触发账号发现。最终验证前，这条路径已删除。此前那次启动是否读取过账号元数据或个人信息，尚未确定；没有为调查此事去查看用户的凭据文件。

## 后端还需要确认什么

[俄文接口规范](BACKEND_SPEC.md)是权威版本，也提供[英文](BACKEND_SPEC.en.md)和[中文](BACKEND_SPEC.zh-CN.md)全文。[BACKEND_CONTRACTS.md](BACKEND_CONTRACTS.md)是索引。公开接口的实际观察与方案建议分开记录；应用不会调用尚未确认的建议接口。

接入顺序：

1. 注册桌面公共客户端，明确浏览器回调或设备授权流程，以及授权码换取令牌的方式。
2. 定义账号标识、令牌有效期、刷新时的轮换规则，以及单个会话的撤销机制。
3. 确认账号会话如何获取余额和支出，包括币种、精度、统计周期、账号或密钥范围、错误语义和轮询限制。
4. 使用已确认的 `https://api.wikivibe.dev/purchase`，不传令牌，不创建付款。
5. 用户自己登录，然后验证回调、重启恢复、真实金额、刷新、离线与过期数据、会话到期、退出，以及充值页面跳转。验证时不付款。

推理 API 密钥和账号会话令牌是两类不同的凭据。需要 API 密钥的 `/v1/usage?days=7` 不能代替已确认的账号会话接口。

## 已做的验证

在语言调整前，`make build` 成功，11 组独立测试共 63 项通过。整个测试模块都完成了编译，但没有执行完整的第三方提供方测试或真实服务测试。命令如下：

```sh
make test TEST_FLAGS='-only-testing:WikiVibeTests/NotchEdgeTests -only-testing:WikiVibeTests/NotchPlacementTests -only-testing:WikiVibeTests/NotchGeometryTests -only-testing:WikiVibeTests/NotchFleetReconcileTests -only-testing:WikiVibeTests/NotchFleetScopeTests -only-testing:WikiVibeTests/NotchVisibilityTests -only-testing:WikiVibeTests/NotchSizeTests -only-testing:WikiVibeTests/NotchPositionPersistenceTests -only-testing:WikiVibeTests/UpdaterOutcomeTests -only-testing:WikiVibeTests/MiniMaxUsageTests -only-testing:WikiVibeTests/OpenCodeUsageTests'
```

实际运行检查覆盖了账号窗口、小组件、菜单、打开浏览器但不改变登录状态、位置与大小调整、显示和隐藏、重新打开设置、退出，以及重启后的外观设置恢复。最初的图像分析服务不可用，因此窗口截图和辅助功能检查不能证明布局没有任何瑕疵。

三语言更新后的 16 项相关原生测试全部通过。实际打开账号窗口，检查了英文、俄文和简体中文：账号与外观文字会随选择更新，菜单退出操作有对应翻译，退出并重新打开后仍保留中文。截图只保存在被忽略的本地 `build/` 中，本文不会链接到未提交的截图。

再次检查公开客户端和实际 /docs，确认浏览器 PKCE、账号 base /api/v1、响应封装和充值跳转。新构建成功；NotchEdgeTests、NotchFleetScopeTests、NotchVisibilityTests 和 NotchSizeTests 共 16 项测试全部通过。重新启动新应用并按下充值按钮，没有浏览器打开错误；应用仍无会话，不显示金额。辅助功能检查确认三语言按钮文字和具体登录条件，已恢复 Русский / Bottom / Large / Show on hover。像素级图像分析不可用，未声称布局完全没有缺陷。

没有进行真实账号登录、会话恢复、余额请求、付款或推理额度消耗。安全验证规则见 [CONTRIBUTING.md](CONTRIBUTING.md)，变更记录见 [CHANGELOG.md](CHANGELOG.md)。

## 许可证

项目采用 [MIT 许可证](LICENSE)。必需的版权声明和依赖许可证保留在仓库及应用资源中。

WikiVibe 图标来自一张 256×256 的本地参考图。较大尺寸是放大生成的，不是高分辨率原图。公开分发二进制版本前，仍需确认品牌使用权，并准备合适的图标源文件。
