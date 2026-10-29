# 书坊 · ShuFang

面向中文小说与故事作者的桌面写作 IDE，帮助作者让文字更接近自己追求的方向。当前唯一活跃客户端使用 Flutter；项目正在整合与改造，计划免费开放，可选自愿赞助入口尚未实现。

## 当前能力

- 本地工作区、章节编辑、保存队列、上一版恢复和 TXT / Markdown 导出。
- 作者主动设置作品目标；选段练笔、改稿案例及明确确认／撤销的作品偏好。
- 写作讨论、续写和表达反馈共享冻结的草稿与上下文预算；不提供统一文笔总分。
- 可配置直连模型服务或按工作区绑定本机引擎。客户端调用记录支持只读核查，不自动重试失败请求；费用缺失时保持未知。
- 亮暗主题与可隐藏的像素助手。正文和作者判断优先。

目标和确认偏好目前已用于练笔；讨论与续写的方向接入仍在推进。真实模型、训练 worker、干净安装和桌面人工交互尚未验收。Python 引擎不包含在此客户端仓库内，也未随应用打包。

## 开发与验证

本机已验证 Flutter **3.29.3**、Dart **3.7.2**；依赖版本见 `pubspec.lock`。Windows 开发需要 Flutter 支持的 Visual Studio C++ 桌面构建工具和 Windows SDK。

在项目根目录使用本机 SDK 的全路径运行。以下沿用当前开发环境的 D 盘约定，可按实际 SDK 所在位置调整；无需修改系统 PATH。

```powershell
$env:PUB_CACHE = 'D:\pub-cache'
& D:\flutter\bin\flutter.bat pub get
& D:\flutter\bin\flutter.bat test --reporter expanded
& D:\flutter\bin\flutter.bat run -d windows
& D:\flutter\bin\flutter.bat build windows --release
```

当前测试是离线和本机模拟服务验证，不需要外部模型密钥。验证范围见[交付状态](docs/current-scope.md)；目录及数据边界见[客户端架构](docs/client-architecture.md)。

## 本地数据

可通过环境变量 `HERMES_STORAGE_ROOT` 指定工作区。否则使用本机应用数据目录；若开发环境存在旧工作区，则继续使用原位置，不自动迁移稿件。

稿件、小说数据集、训练产物、密钥、模型缓存、调用日志和个人配置均不属于公开源码。此仓库只接收审核过的代码、构建配置与明确的测试样例；旧工作目录的 Git 历史不直接导入。

这是开发审阅阶段的源码，正式开源发行及素材授权核对仍在推进。
