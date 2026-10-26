# 私有源码、公开构建流程

完整源码继续保存在私有仓库 `alanpfx/MGControl`；本仓库只增加构建工作流和构建辅助脚本，不同步车控、蓝牙协议源码或私有仓库提交历史。

## 仓库所有者的一次性配置

1. 在 GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens 创建凭证。
2. Resource owner 选择 `alanpfx`；Repository access 选择 Only select repositories，仅勾选私有 `MGControl`。
3. Repository permissions 中仅设置 Contents: Read-only；Metadata 的默认只读权限保留。不需要 Contents Write、Actions Write 或账户管理权限。设置适当到期日。
4. 将凭证直接保存到 **MGControl-Public** → Settings → Secrets and variables → Actions → New repository secret，名称为 `MGCONTROL_SOURCE_TOKEN`。不要发送到聊天、提交到源码或放入 Variables。
5. 本仓库 Actions → Build MGControl from private source → Run workflow，选择 `main` 并运行。

工作流固定读取经过审查的私有源码提交 `401a52d5f0ddba853b1aba44f139e9057e733f63`（0.56 / 40），只允许所有者在本仓库 main 手动触发。更新版本时须审查并修改固定提交与版本检查。没有 pull_request / pull_request_target / 外部代码触发入口。

## 产物与日志

- 成功后生成两份 unsigned IPA 和 SHA256SUMS。标准公开 GitHub 托管运行器的构建分钟适用公开仓库计费规则；账户付款或平台限制仍可能阻止启动。
- 公共控制台仅显示构建阶段的成功/失败，不输出编译日志、源码片段、测试报告、截图或完整源码压缩包。
- 详细文本日志使用仓库内公开证书加密后保存为 `.p7m`，解密私钥仅保存在所有者本机。不得把解密后的日志提交至公开仓库或公开评论。
- 安装包本身是已编译程序，可被下载和逆向分析；本方案只保证不直接发布完整源码，不承诺编译产物不可逆向。
- 构建产物先进入 Actions Artifacts，完成包校验、配置准备和界面检查后再单独发布 Release，工作流不会自动覆盖现有发布。
- 不得给不可信协作者工作流修改权限；能修改该工作流的人可能使用仓库 Secret。读凭证只用于 checkout，`persist-credentials: false`，不作为环境变量传给编译脚本。

原有非商业使用协议继续适用于安装包与公开源码。
