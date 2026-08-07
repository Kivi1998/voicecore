# VoiceCore 0.9.0 本地发布候选记录

- 构建日期：2026-08-07
- 版本：0.9.0（构建 1）
- Bundle ID：`dev.voicecore.app`
- 最低系统：macOS 14
- 架构：Apple Silicon `arm64`
- Archive：`build/VoiceCore.xcarchive`
- DMG：`build/VoiceCore.dmg`
- DMG SHA-256：`f22fd956b62e18745ebf23935ae164ab37f5726274411bb1775d465e7cc8bb52`

## 已验证

- SwiftFormat：0 个文件待格式化。
- SwiftLint strict：0 个违规。
- Swift Package XCTest：192/192 通过（Domain 49、Application 33、Data 52、Providers 54、Platform 4）。
- App XCTest：15/15 通过。
- macOS XCUITest：5/5 通过。
- 模型模拟服务器：18/18 场景通过。
- `xcodebuild archive` 成功；归档应用 `codesign --verify --deep --strict` 通过。
- DMG 经 `hdiutil verify` 校验有效，包含 `VoiceCore.app` 与「应用程序」链接。
- 最终应用已安装到 `/Applications/VoiceCore.app` 并成功启动，数据继续使用 `~/Library/Application Support/dev.voicecore.app/`。

## 本地候选限制

- 当前使用“Sign to Run Locally”临时签名，未使用 Developer ID，也未进行 Apple 公证，因此只适合本机开发和验收，不是可直接公开分发的正式包。
- 用户已经授予辅助功能权限并重启最终安装版；独立 `Fn`、`Esc`、真实麦克风和跨应用自动输入仍须由用户实际操作确认。
- 尚未完成全新 macOS 用户账户的安装、覆盖升级和卸载验证。
- 尚未完成 macOS 14 的材质降级、VoiceOver、减少透明度/动态和高对比度人工矩阵。
- GitHub CI 尚待首次远端运行校准；正式 TEST-005 仍需独立审查角色执行。

## 快捷键行为

- 轻按并松开一次 `Fn`：开始录音；再次轻按并松开：结束录音。
- `Fn` 与其他键组合时不会触发 VoiceCore。
- 录音期间按 `Esc`：取消本次录音。
- 辅助功能权限未生效时：自动退回 `⌥Space`，授权并重启后恢复独立 `Fn`。

## 旧构建清理

旧 OpenTypeless Archive、DerivedData 和界面测试沙盒已移动到废纸篓中的可恢复目录：

`~/.Trash/VoiceCore旧构建备份-20260807-051725/`

未发现旧 OpenTypeless 正式用户数据，因此没有迁移或删除数据库、录音与模型配置。覆盖安装前的 VoiceCore 应用副本也保存在废纸篓中。
