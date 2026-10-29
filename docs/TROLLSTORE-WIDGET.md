# TrollStore 小组件共享权限适配

iOS 15、16 支持 WidgetKit。TrollStore 安装能够启动 App，并不表示主 App 与小组件已取得同一 App Groups 容器。普通签名工具可配置共享组，而原未签名 IPA 的主程序和扩展没有内嵌签名权限，可能造成共享容器不可访问。

## 安装和验证

1. 从对应 Release 选择 `widget-trollstore-appgroups.ipa`，使用 TrollStore 覆盖安装。普通证书签名继续选择 `widget-ready-unsigned.ipa`。
2. 不需要卸载、清除登录或重新领取蓝牙钥匙。先打开主 App 读取一次车况，再查看脱敏诊断中的“主 App 容器”“小组件同步”。
3. 主 App 显示容器可访问后，移除桌面旧小组件并重新添加，查看车况及同步时间是否更新。
4. 如仍失败，提供 App 版本、iOS/TrollStore 版本及脱敏诊断中的共享容器/读取回执。无需发送账号、钥匙材料或安全码。

## 包内处理与限制

- 主 App 与扩展预置相同的 `com.apple.security.application-groups`，与 Info.plist 中的共享组一致。
- 用 macOS 临时签名嵌入权限，不使用开发者证书；保留主 App 与巨魔默认钥匙串身份的兼容配置。TrollStore 安装时仍会重新签名。
- 不请求平台应用、取消沙盒、root 或调试权限。签名后核对程序段和原资源不变，目录/可执行文件755、资源644。
- 附独立 SHA256 和包内权限验证报告。包内校验通过不代表已验证真机容器注册、数据同步或全部车辆功能。
- 专用包是现有版本的安装适配补包，原有普通签名 IPA 保留，不更改车辆协议。

参考：[TrollStore 功能与自定义权限](https://github.com/opa334/TrollStore#features)、[Apple App Groups](https://developer.apple.com/documentation/Xcode/configuring-app-groups)。


## 0.62 分阶段诊断

已知iOS15.5反馈：主App可取得容器并同步车况，但扩展没有回执；更新TrollStore、刷新注册后仍未解决。不能宣称权限适配已在真机通过。

0.62的错误卡直接显示版本、生成时间与W01/W02/W03/W04：分别指容器URL不可用、未同步摘要、摘要格式异常、系统文件读写错误。中/大尺寸同时显示扩展包内共享组声明检查。主App诊断新增两个程序的包内签名信息，读取回执显示真实扩展版本。

覆盖安装后读取一次车况并重新添加组件，反馈组件截图与诊断开头即可，不需要重新领取钥匙或提供抓包。若仍无回执，组件上显示的版本和错误码可帮助区分旧快照与实际运行失败。
