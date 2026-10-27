# 当前源码范围

自 0.58（42）起，本仓库新增可独立构建的完整 SwiftUI App 与共享车况 Widget，不再仅是界面预览。

## 包含

- 手机号短信登录、易盾图形验证、会话交换和恢复、Keychain 会话存储。
- 车辆列表、真实车况映射、停车位置及消息中心。
- 远程车控指令、二次确认、本机身份验证、安全码授权和车况确认。
- App、Widget、共享 CoreKit、Mock 后端实现、MGControl 图标与车辆资源。
- iOS 16 完整工程配置，以及 macOS GitHub Actions 编译和 IPA 校验工作流。

## 不包含

- 蓝牙数字钥匙开通、分享、恢复及无感控制实现；页面仅提供官方 App 入口。
- 用户个人账号、会话、安全码、真实车辆资料、私有抓包或系统诊断。
- Apple 开发者证书、描述文件或分发签名；Actions 产物为未签名 IPA。
- 参考项目中尚未完成的 MQTT 实时车控通道及原厂 PIN 本地加密实现。

## 原有预览

`Preview/`、`Shared/`、`Widget/`、`MGControl/Views/` 和 `project-preview.yml` 保留原有独立展示用途。完整 App 使用 `CarControl/`、`CarControlWidget/`、`Packages/CoreKit/` 和 `project.yml`，两套入口不参与同一 target 编译。

## 来源与许可

新增登录、车控、车况及 Widget 模块参考用户指定的 `Anthocyanin/carcontrol-ios`，基线提交为 `e7ac5385b541aa9ea5f93a5ed4e2b262f6cf6206`。详见 [第三方源码说明](CARCONTROL-SOURCE.md)。

仓库原有的非商业使用与禁止营利协议继续适用于本衍生工程；新增代码不取消或替换该限制。第三方组件仍分别适用其原始许可。
