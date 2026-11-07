# 私有源码、公开构建流程

完整源码继续保存在私有仓库 `alanpfx/MGControl`；本仓库只增加构建工作流和构建辅助脚本，不同步车控、蓝牙协议源码或私有仓库提交历史。

## 仓库所有者的一次性配置

1. 在 GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens 创建凭证。
2. Resource owner 选择 `alanpfx`；Repository access 选择 Only select repositories，仅勾选私有 `MGControl`。
3. Repository permissions 中仅设置 Contents: Read-only；Metadata 的默认只读权限保留。不需要 Contents Write、Actions Write 或账户管理权限。设置适当到期日。
4. 将凭证直接保存到 **MGControl-Public** → Settings → Secrets and variables → Actions → New repository secret，名称为 `MGCONTROL_SOURCE_TOKEN`。不要发送到聊天、提交到源码或放入 Variables。
5. 本仓库 Actions → Build MGControl from private source → Run workflow，选择 `main` 并运行。

正式构建以 `.github/workflows/build-private-source.yml` 中经过审查的完整私有提交 SHA 与版本检查为准；测试以 `review-private-source.yml` 中的固定 SHA 为准。只允许所有者在本仓库 main 手动触发，或由所有者更新相应工作流/辅助文件触发。更新版本时须审查固定提交与版本检查。没有 pull_request / pull_request_target / 外部代码取得私有源码凭证的触发入口。

## 所有构建和测试统一在 public 执行

- `MGControl-Public` 承担正式测试、IPA 构建、发布、TrollStore 制包和临时原生回归。使用标准 `macos-15`、`ubuntu-latest` 运行器，不使用收费的大型运行器。
- 私有 `MGControl` 仅保存源码与固定提交，不承担 Actions 执行；停用其仓库 Actions，避免旧分支的工作流再次触发私有计费任务。读取私有 Git 内容不依赖私库 Actions 开关。
- `Review private MGControl source` 只做原生单元/交互检查，不生成 IPA、不创建 Release，也不触发正式发布链。其私有源码 pin 可以是尚未发布的审查分支。
- 公共审查结果仅包含版本、固定源码 SHA 和测试数量。详细日志与原生预览使用现有公开证书加密为 `.p7m`，保留 3 天；私钥、解密结果、源码压缩包和原始 xcresult 不上传。
- 当前原生审查使用已交付模型作为测试基线，尚未交付的车模候选仍须单独完成设备/GPU验证，不能用原生测试结果代替。

GitHub 的标准托管运行器在公开仓库适用[公开运行分钟免费规则](https://docs.github.com/en/actions/concepts/billing-and-usage)；[大型运行器另行计费](https://docs.github.com/en/actions/concepts/runners/larger-runners)。本流程不调整账户账单或消费限额。

## 产物与日志

- 成功后生成两份 unsigned IPA 和 SHA256SUMS。标准公开 GitHub 托管运行器的构建分钟适用公开仓库计费规则；账户付款或平台限制仍可能阻止启动。
- 公共控制台仅显示构建阶段的成功/失败，不输出编译日志、源码片段、测试报告、截图或完整源码压缩包。
- 详细文本日志使用仓库内公开证书加密后保存为 `.p7m`，解密私钥仅保存在所有者本机。不得把解密后的日志提交至公开仓库或公开评论。
- 安装包本身是已编译程序，可被下载和逆向分析；本方案只保证不直接发布完整源码，不承诺编译产物不可逆向。
- 正式构建产物先进入 Actions Artifacts，构建成功后由独立发布工作流自动核对版本与包校验结果，再创建对应版本 Release；不会替换已经发布的安装资产。临时原生审查只上传数字摘要和加密诊断，不生成 IPA，也不会进入发布链。
- 不得给不可信协作者工作流修改权限；能修改该工作流的人可能使用仓库 Secret。读凭证只用于 checkout，`persist-credentials: false`，不作为环境变量传给编译脚本。

原有非商业使用协议继续适用于安装包与公开源码。

## 成功编译后自动发布

公开构建成功后，发布工作流会核对版本、校验两份 IPA、补入已公开分发的应用登录参数，并上传对应版本 Release，同时记录校验和与构建链接。README、CHANGELOG 与 RELEASE-NOTES 必须先准备为同一版本；版本不符或构建失败不会发布。安装包不包含个人会话或车辆钥匙。

发布仅使用公开仓库的写权限，不增加私有源码读取凭证的权限；原始编译日志和完整源码不随 Release 上传。
