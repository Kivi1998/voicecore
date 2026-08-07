# OpenTypeless

OpenTypeless 是一个面向个人使用的本地优先语音输入应用。第一版只支持 Apple 芯片 Mac：按一次全局快捷键开始录音，再按一次结束；应用完成语音识别和文字改写后，将结果直接写入当前输入框。

本仓库是全新创建的独立项目，不包含此前克隆的同名上游仓库代码，也不隶属于其他语音输入产品。界面遵循 Apple 平台设计语言，但不会复制第三方品牌、标志、文案或受保护素材。

## 第一版目标

- Apple 芯片 macOS，建议最低支持 macOS 14。
- SwiftUI 构建原生界面，AppKit 实现 macOS 专属窗口、菜单栏、全局快捷键和辅助功能集成。
- AVFoundation 负责录音，URLSession 负责模型请求，GRDB 与 SQLite 负责本地数据。
- 在支持的新版 macOS 使用系统 Liquid Glass；不支持该效果的系统版本（最低 macOS 14）使用原生材质降级。
- SQLite 保存设置、模型配置、词典、历史记录和 API 密钥。
- 所有录音永久保留，失败任务保留原录音并支持重试。
- 语音识别首先支持 OpenAI 兼容音频转录协议，并预留千问、豆包原生适配器。
- 文字改写支持 OpenAI 兼容协议和 Anthropic 兼容协议。
- 无登录、会员、订阅、额度、推荐奖励和云同步。

## 核心功能

- 今日、本周、累计口述量及口述时长统计。
- 任意日期范围的历史查询、全文搜索、状态筛选和收藏筛选。
- 每条历史记录支持复制文字、下载录音、收藏、删除和失败重试。
- 区分语音识别失败与文字改写失败；改写失败时复用已保存的原始转录。
- 手动添加和删除单个词典词语。
- 多套语音模型与改写模型配置，支持切换和连接测试。
- 转录成功后默认写入当前应用的光标位置，并尽可能恢复原剪贴板。

## 文档入口

用户文档：

- [用户手册](docs/USER_GUIDE.md)
- [故障排查](docs/TROUBLESHOOTING.md)
- [数据位置与备份](docs/DATA_LOCATIONS.md)

设计与开发文档：

- [产品需求](docs/PRODUCT_REQUIREMENTS.md)
- [Apple 原生设计系统](DESIGN.md)
- [界面设计规范](docs/UI_SPEC.md)
- [架构设计](docs/ARCHITECTURE.md)
- [开发指南](docs/DEVELOPMENT.md)
- [数据模型](docs/DATA_MODEL.md)
- [模型协议](docs/PROVIDER_PROTOCOLS.md)
- [任务清单](tasklist.md)
- [执行待办](todolist.md)
- [工作树并行指南](docs/WORKTREE_GUIDE.md)
- [Kimi K3 完整开发提示词](KIMI_PROMPT.md)
- [审查与验收](docs/REVIEW_AND_QA.md)

## 开发命令

统一入口为仓库根 `Makefile`（README 只引用该入口）：

```sh
make resolve         # 解析 Swift Package 依赖
make build-packages  # 六包编译（仅 Command Line Tools 即可）
make test-packages   # 六包单元测试（需要完整 Xcode / XCTest）
make format-check    # SwiftFormat 检查
make lint            # SwiftLint 静态检查
make dev             # 打开 Xcode 工程（需要完整 Xcode）
make test-app        # macOS App 单元测试（需要完整 Xcode）
make mock-server     # 模型协议模拟服务器（TEST-003，Python 标准库）
make mock-smoke      # 模拟服务器冒烟验证（自动起停）
make archive         # 归档生产应用（需要完整 Xcode 与签名）
```

本地开发当前需要：完整 Xcode（`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`），SwiftFormat 0.62.x 与 SwiftLint 0.65.x（`brew install swiftformat swiftlint`）用于格式与静态检查；SwiftLint 运行需要完整 Xcode 的 sourcekitd 布局。

## 当前状态

G0–G3 业务代码已按任务依赖完成实现：六个 Swift Package（Domain、Application、Data、Providers、Audio、Platform）＋ App 本地包全部可经 `swift build` 编译；XCTest 用例已编写约百个但尚未执行（开发机待安装完整 Xcode，见 todolist.md 阻塞项 B-001）。Xcode 工程、真机端到端、独立审查与 DMG 发布待 Xcode 就绪后按 G4/G5 推进。

## 数据原则

- 历史、录音和配置默认只保存在本机。
- API 密钥第一版以明文形式保存在本机 SQLite；这是已知风险，后续再引入加密方案。
- 调用云端模型时，录音或文字会发送给用户自行配置的服务商。
- 不采集遥测，不上传历史，不提供托管模型额度。

## 许可证

本项目采用 MIT 许可证，详见 [LICENSE](LICENSE)。
