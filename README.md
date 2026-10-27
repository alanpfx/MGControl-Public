# MGControl · MG 车控助手

面向 iPhone 的第三方 MG Live 车辆信息与远程车控客户端。当前源码版 **0.58（42）**，最低支持 **iOS 16.0**。

## 已实现功能

- 手机号与短信验证码登录：易盾图形验证、60 秒重发倒计时、错误提示。
- 会话管理：tocToken / swapToken 交换与恢复，优先使用本机 Keychain 保存。
- 车辆与车况：车辆列表、SOC、续航、里程、温度、电压、胎压、门窗及锁止状态、停车位置。
- 远程控制：锁车、解锁、开车窗、关车窗、开空调、关空调、后备箱、寻车。
- 控制确认：危险操作二次确认、生物识别/设备密码、安全码授权及车况反向确认。
- 消息、充电信息展示和共享车况小组件；小组件深链仅导航或刷新，不直接下发车辆指令。
- 调试 Mock：`MG_MOCK=1` 时使用演示后端，验证码为 `123456`；发布构建默认使用真实服务。

## 构建 IPA

macOS 安装 Xcode 16.4、XcodeGen 和 ldid：

```sh
brew install xcodegen ldid
./scripts/build-ipa.sh --target 16.0 --appgroup
python3 scripts/check-ipa.py dist/MGControl-Release-unsigned.ipa --target 16.0
```

也可以安装 Xcode 后运行 `xcodegen generate`，再打开 `MGControl.xcodeproj`。普通 Apple 签名安装时，请将主 App、Widget 和 App Group 修改为自己开发者账号下的唯一标识，并保持一致。

## GitHub Actions

工作流 [Build source IPA (iOS 16)](.github/workflows/build-source-ipa.yml) 使用 `macos-15` 和 Xcode 16.4：

1. 打开仓库 **Actions → Build source IPA (iOS 16) → Run workflow**。
2. 默认最低版本为 `16.0`，保留 App Group 选项。
3. 构建成功后下载 `MGControl-<运行编号>-ios16-unsigned` Artifact，其中包含未签名 IPA 与 SHA256 校验和。
4. 工作流同时检查每个 `Info.plist` 的 `MinimumOSVersion` 与 Mach-O 的 `minos`，高于目标版本会使构建失败。

无需私有源码令牌或 Apple 开发者证书即可生成未签名 IPA。安装到自己的设备时，可使用自己的签名方式；使用共享小组件需要正确签名 App Group。

## 工程结构

```text
CarControl/                    SwiftUI 登录、车况、车控、消息与设置
CarControlWidget/              共享车况小组件
Packages/CoreKit/              业务模型、API 协议、Mock、Widget 存储与路由
MGControl/Assets.xcassets/     MGControl 图标和车辆素材
Shared/、Widget/、Preview/     原有独立界面预览模块
scripts/                       未签名 IPA 打包和 iOS 最低版本校验
project.yml                    完整 MGControl App + Widget 工程
project-preview.yml            原有独立界面预览工程
```

## 源码来源与许可

短信登录和车控实现以 [Anthocyanin/carcontrol-ios](https://gitee.com/Anthocyanin/carcontrol-ios) 的 `e7ac5385b541aa9ea5f93a5ed4e2b262f6cf6206` 为参考基线导入，并针对 MGControl 调整名称、Bundle ID、深链、App Group、资源与构建配置。参考项目采用 MIT 许可，其说明见 [第三方源码说明](docs/CARCONTROL-SOURCE.md)。

MGControl 原有代码、资源及本衍生工程继续适用根目录的 **MGControl 非商业使用与禁止营利协议**，不是 MIT/Apache 许可。请同时阅读 [免责声明](docs/DISCLAIMER.md)、[安装说明](docs/INSTALL.md) 和 [源码范围](docs/SOURCE-SCOPE.md)。不得移除原项目的非商业限制或来源说明。

本项目为独立第三方客户端，不隶属上汽或 MG。账号、接口权限与车型支持取决于实际服务；短信下发、控车安全码和车辆指令仍需使用本人账号及车辆真机验证。请不要在 Issues 或构建日志中发布手机号、会话令牌、安全码、完整 VIN 或车辆位置。
