# MGControl 0.54（38）测试版

**严禁营利性与商业性使用。** 源码、文档及发布包适用 [非商业使用与禁止营利协议](https://github.com/alanpfx/MGControl-Public/blob/main/LICENSE)，禁止收费分发、付费安装配置、广告变现及商业捆绑。

## 本次更新

- 统一 IPA 最低支持 iOS 15.0，可用于 iOS 15、16、17 及更新系统。
- 兼容旧系统的导航、分享、粘贴、空白页面、字体和小组件布局。
- iOS 15 保留车况、远程控制和蓝牙钥匙；实时活动在 iOS 16.2 及以上启用，灵动岛还需支持的机型。
- 包含 0.53 的首次登录改进：完整包内置应用登录参数，新用户用自己的 MG Live 手机号正常验证登录，无需另外导入测试配置。每台设备、账号和蓝牙钥匙仍分别授权，不继承官方 App 私有资料。
- 不改动蓝牙认证、指令、信号阈值和后台策略。内置内容不包含个人账号会话、车辆信息或蓝牙钥匙。

## 下载与升级

- `MGControl-V0.54-widget-ready-unsigned.ipa`：含桌面小组件，需正确签名主 App、扩展及共享组。
- `MGControl-V0.54-app-only-ready-unsigned.ipa`：不含小组件；签名环境不支持 App Groups 时使用。
- 两个包均已内置应用登录参数、支持 iOS 15 及以上，均需使用自己的合法方式重新签名安装。
- `SHA256SUMS.txt`：安装包完整性校验；`LICENSE.txt`：非商业协议。
- 尽量保持原安装标识、签名身份和应用数据覆盖升级；勿为了升级先卸载，或重复领取已可用的钥匙。

## 验证范围

316 项自动化测试通过，两种 arm64 安装包编译通过。已核对主 App 与扩展的安装元数据及实际可执行文件最低系统为 iOS 15.0，实时活动框架采用弱链接。

**iOS 15 真机首次登录、蓝牙配对、手动开关锁、后台连接与小组件仍需实际验证。** 自动化测试和编译不能代替实车测试，后台自动锁车与常驻连接均不保证。请保留官方 App 与实体钥匙，先在停车状态测试。

本标签只含原有独立展示源码快照及更新文档，不能重建完整车控程序；账号、车控接口、蓝牙协议和内部开发历史不公开。公开界面预览工程仍以 iOS 17 为目标。

[安装与使用](https://github.com/alanpfx/MGControl-Public/blob/main/docs/INSTALL.md) · [完整更新日志](https://github.com/alanpfx/MGControl-Public/blob/main/CHANGELOG.md) · [免责声明](https://github.com/alanpfx/MGControl-Public/blob/main/docs/DISCLAIMER.md)
