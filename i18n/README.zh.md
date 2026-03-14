# LaunchNext

**语言**: [English](../README.md) | [中文](README.zh.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

## 📥 下载

**[点此下载](https://github.com/RoversX/LaunchNext/releases/latest)** - 获取最新版本

🌐 **网站**: [closex.org/launchnext](https://closex.org/launchnext/)  
📚 **文档**: [docs.closex.org/launchnext](https://docs.closex.org/launchnext/)

⭐ 请考虑为 [LaunchNext](https://github.com/RoversX/LaunchNext) 和原项目 [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) 点 star！

| | |
|:---:|:---:|
| ![](../public/banner.webp) | ![](../public/setting1.webp) |
| ![](../public/setting2.webp) | ![](../public/setting3.webp) |

macOS Tahoe 移除了 Launchpad，新的界面很难用，也不能充分利用你的 Bio GPU。苹果，至少给用户一个切换回去的选项吧。在此之前，这里是 LaunchNext。

*基于 [LaunchNow](https://github.com/ggkevinnnn/LaunchNow)（作者 ggkevinnnn）开发——非常感谢原项目！❤️*

*LaunchNow 选择了 GPL 3 许可证，LaunchNext 遵循相同的许可条款。*

⚠️ **如果 macOS 阻止应用运行，请在终端执行：**
```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNext.app
```
**原因**：我买不起苹果的开发者证书（$99/年），所以 macOS 会阻止未签名应用。这个命令移除隔离标记让应用正常运行。**仅对信任的应用使用此命令。**

## LaunchNext 提供什么

- ✅ **一键导入旧系统 Launchpad** - 直接读取你的原生 Launchpad SQLite 数据库，重建文件夹、应用位置和布局
- ✅ **手动整理应用** - 移动应用、创建文件夹，并按你的方式保留布局
- ✅ **两套渲染路径** - `Legacy Engine` 用于兼容性，`Next Engine + Core Animation` 提供最佳体验
- ✅ **紧凑和全屏模式** - 支持分别保存设置
- ✅ **键盘优先工作流** - 快速搜索、导航与启动
- ✅ **CLI / TUI 自动化支持** - 可通过终端检查和管理布局
- ✅ **Hot Corner 与原生手势激活** - 提供多种全局打开方式
- ✅ **直接拖动应用到 Dock** - 在 Core Animation 引擎中可用
- ✅ **支持 Markdown 发布说明的更新中心** - 更丰富的应用内更新体验
- ✅ **备份与恢复工具** - 更安全的导出与恢复流程
- ✅ **可访问性与控制器支持** - 语音反馈和手柄导航都有增强
- ✅ **多语言支持** - 覆盖较广的本地化语言

## macOS Tahoe 拿走了什么

- ❌ 无法自定义应用组织
- ❌ 无法创建用户文件夹
- ❌ 无拖拽定制功能
- ❌ 无可视化应用管理
- ❌ 强制分类分组

## 数据存储

应用数据保存在：

```text
~/Library/Application Support/LaunchNext/Data.store
```

## 原生 Launchpad 集成

LaunchNext 可以直接读取系统 Launchpad 数据库：

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## 安装

### 系统要求

- macOS 26（Tahoe）或更高版本
- Apple Silicon 或 Intel 处理器
- Xcode 26（从源码构建时需要）

### 从源码构建

1. **克隆仓库**
   ```bash
   git clone https://github.com/RoversX/LaunchNext.git
   cd LaunchNext
   ```

2. **在 Xcode 中打开**
   ```bash
   open LaunchNext.xcodeproj
   ```

3. **构建并运行**
   - 选择目标设备
   - 按 `⌘+R` 构建并运行
   - 或按 `⌘+B` 仅构建

### 命令行构建

**常规构建：**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

**通用二进制构建（Intel + Apple Silicon）：**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## 使用方法

### 快速开始

1. LaunchNext 首次启动时会扫描所有已安装应用
2. 导入旧 Launchpad 布局，或从空布局开始
3. 通过搜索、键盘导航、鼠标拖拽和文件夹整理应用
4. 在设置中配置引擎、布局模式、激活方式和自动化功能

### 导入你的 Launchpad

1. 打开设置
2. 点击 **Import Launchpad**
3. 现有布局和文件夹会自动导入

### 引擎与布局模式

- **Legacy Engine** - 保留旧渲染路径，优先兼容性
- **Next Engine + Core Animation** - 推荐，整体体验和新功能支持更好
- **紧凑 / 全屏** - LaunchNext 支持两种模式，并可分别保存设置

## 关键功能

### 激活与输入

- **Hot Corner 支持** - 从可配置的屏幕角落打开 LaunchNext
- **实验性原生手势支持** - 四指 pinch / tap 动作
- **全局快捷键支持** - 从任何位置打开 LaunchNext
- **拖动应用到 Dock** - 在 Core Animation 引擎中将应用直接交给 macOS Dock

### 自动化与高级工作流

- **CLI / TUI 支持** - 查看布局、搜索应用、创建文件夹、移动应用并自动化工作流
- **对 agent 友好** - 适合终端型 AI agent 和 shell 自动化
- **设置中启用命令行** - 可安装或移除托管的 `launchnext` 命令

### 更新体验

- **应用内更新中心** - 不离开应用即可检查更新
- **Markdown 发布说明** - 在设置中直接显示更丰富的发布说明
- **现代通知 API** - 适配更新后的 macOS 通知机制

### 备份与恢复

- 在设置中创建和恢复备份
- 更可靠的备份导出行为
- 更安全的临时文件和清理逻辑处理

### 可访问性与导航

- **语音反馈支持** - 导航时播报应用和文件夹名称
- **控制器支持** - 可用游戏手柄操作 LaunchNext 和文件夹
- **键盘优先交互** - 不依赖鼠标也能快速搜索和导航

## 性能与稳定性

- 智能图标缓存，保证浏览流畅
- 延迟加载和后台扫描，适配大型应用库
- 更好的设置和导航状态同步
- 更新处理、备份导出和手势恢复的可靠性提升

## 故障排除

### 常见问题

**问：应用无法启动？**  
答：请确认系统版本为 macOS 26 或更高，必要时移除 quarantine，并确保你运行的是可信构建。

**问：应该使用哪个引擎？**  
答：推荐使用 `Next Engine + Core Animation`。如果你确实需要旧兼容路径，再使用 `Legacy Engine`。

**问：为什么还没有 CLI 命令？**  
答：先在设置中启用命令行接口。LaunchNext 可以为你安装和移除托管的 `launchnext` shim。

## 贡献

欢迎贡献。

1. Fork 仓库
2. 创建功能分支（`git checkout -b feature/amazing-feature`）
3. 提交更改（`git commit -m 'Add amazing feature'`）
4. 推送分支（`git push origin feature/amazing-feature`）
5. 打开 Pull Request

### 开发指南

- 遵循 Swift 风格约定
- 为复杂逻辑添加有意义的注释
- 尽可能在多个 macOS 版本上测试
- 避免把实验性功能散落到无关文件中
- 尽量隔离可移除的集成

## 应用管理的未来

随着 Apple 逐渐远离可自定义的应用启动界面，LaunchNext 试图在现代 macOS 上保留手动组织、用户控制和高效访问。

**LaunchNext** 不只是 Launchpad 的替代品，它是对工作流退化的一种实际回应。

---

**LaunchNext** - 重新掌控你的应用启动器 🚀

*为拒绝在定制化上妥协的 macOS 用户打造。*

## 开发工具

- Claude Code
- Cursor
- OpenAI Codex CLI
- Perplexity
- Google

- 实验性手势支持基于 [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) 及其 [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport) 分支。❤️

![GitHub downloads](https://img.shields.io/github/downloads/RoversX/LaunchNext/total)
