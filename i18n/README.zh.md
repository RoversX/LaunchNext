# LaunchNext

**语言**: [English](../README.md) | [中文](README.zh.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

## 📥 下载

**[点此下载](https://github.com/RoversX/LaunchNext/releases/latest)** - 获取最新版本

⭐ 请考虑为 [LaunchNext](https://github.com/RoversX/LaunchNext) 和原项目 [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) 点star！

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

### LaunchNext 提供的功能
- ✅ **一键导入老系统 Launchpad** - 直接读取你的原生 Launchpad SQLite 数据库 (`/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db`) 完美重现你现有的文件夹、应用位置和布局
- ✅ **经典 Launchpad 体验** - 与深受喜爱的原版界面完全一致
- ✅ **多语言支持** - 完整国际化支持，包含英文、中文、日文、韩文、法文、西班牙文、意大利文、捷克文、德文、俄文、印地文和越南文
- ✅ **隐藏图标标签** - 当你不需要应用名称时提供简洁的极简视图
- ✅ **自定义图标大小** - 根据你的偏好调整图标尺寸
- ✅ **智能文件夹管理** - 像以前一样创建和整理文件夹
- ✅ **即时搜索和键盘导航** - 快速找到应用

### macOS Tahoe 中我们失去的功能
- ❌ 无法自定义应用组织
- ❌ 无法创建用户文件夹
- ❌ 无拖拽定制功能
- ❌ 无可视化应用管理
- ❌ 强制分类分组

## 功能特性

### 🎯 **即时应用启动**
- 双击图标直接启动应用
- 完整的键盘导航支持
- 实时过滤的闪电搜索

### 📁 **高级文件夹系统**
- 通过拖拽应用创建文件夹
- 内联编辑重命名文件夹
- 自定义文件夹图标和组织
- 无缝拖拽应用进出

### 🔍 **智能搜索**
- 实时模糊匹配
- 搜索所有已安装应用
- 快速访问键盘快捷键

### 🎨 **现代界面设计**
- **液态玻璃效果**: regularMaterial 加优雅阴影
- 全屏和窗口显示模式
- 流畅的动画和过渡
- 简洁响应式布局

### 🔄 **无缝数据迁移**
- **一键 Launchpad 导入** 从原生 macOS 数据库
- 自动应用发现和扫描
- 通过 SwiftData 持久化布局存储
- 系统更新期间零数据丢失

### ⚙️ **系统集成**
- 原生 macOS 应用
- 多显示器感知定位
- 与 Dock 和其他系统应用协同工作
- 背景点击检测（智能关闭）

## 技术架构

### 采用现代技术构建
- **SwiftUI**: 声明式、高性能 UI 框架
- **SwiftData**: 强大的数据持久化层
- **AppKit**: 深度 macOS 系统集成
- **SQLite3**: 直接 Launchpad 数据库读取

### 数据存储
应用数据安全存储在：
```
~/Library/Application Support/LaunchNext/Data.store
```

### 原生 Launchpad 集成
直接从系统 Launchpad 数据库读取：
```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## 安装

### 系统要求
- macOS 26 (Tahoe) 或更高版本
- Apple Silicon 或 Intel 处理器
- Xcode 26（从源码构建）

### 从源码构建

1. **克隆仓库**
   ```bash
   git clone https://github.com/yourusername/LaunchNext.git
   cd LaunchNext/LaunchNext
   ```

2. **在 Xcode 中打开**
   ```bash
   open LaunchNext.xcodeproj
   ```

3. **构建和运行**
   - 选择目标设备
   - 按 `⌘+R` 构建并运行
   - 或按 `⌘+B` 仅构建

### 命令行构建
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

## 使用方法

### 快速入门
1. **首次启动**: LaunchNext 自动扫描所有已安装应用
2. **选择**: 点击选择应用，双击启动
3. **搜索**: 输入即时过滤应用
4. **整理**: 拖拽应用创建文件夹和自定义布局

### 导入你的 Launchpad
1. 打开设置（齿轮图标）
2. 点击 **"Import Launchpad"**
3. 你现有的布局和文件夹将自动导入

### 文件夹管理
- **创建文件夹**: 将一个应用拖到另一个上面
- **重命名文件夹**: 点击文件夹名称
- **添加应用**: 将应用拖入文件夹
- **移除应用**: 将应用从文件夹中拖出

### 显示模式
- **窗口化**: 带圆角的浮动窗口
- **全屏**: 最大可见性的全屏模式
- 在设置中切换模式

## 已知问题

> **当前开发状态**
> - 🔄 **滚动行为**: 某些场景下可能不稳定，特别是快速手势操作时
> - 🎯 **文件夹创建**: 创建文件夹的拖拽命中检测有时不一致
> - 🛠️ **积极开发中**: 这些问题将在即将发布的版本中积极解决

## 故障排除

### 常见问题

**问：应用无法启动？**
答：确保 macOS 26.0+ 并检查系统权限。

**问：导入按钮缺失？**
答：验证 SettingsView.swift 包含导入功能。

**问：搜索不工作？**
答：尝试重新扫描应用或在设置中重置应用数据。

**问：性能问题？**
答：检查图标缓存设置并重启应用。

## 为什么选择 LaunchNext？

### 对比 Apple 的"Applications"界面
| 功能 | Applications (Tahoe) | LaunchNext |
|---------|---------------------|------------|
| 自定义组织 | ❌ | ✅ |
| 用户文件夹 | ❌ | ✅ |
| 拖拽操作 | ❌ | ✅ |
| 可视化管理 | ❌ | ✅ |
| 导入现有数据 | ❌ | ✅ |
| 性能 | 慢 | 快 |

### 对比其他 Launchpad 替代品
- **原生集成**: 直接 Launchpad 数据库读取
- **现代架构**: 使用最新 SwiftUI/SwiftData 构建
- **零依赖**: 纯 Swift，无外部库
- **积极开发**: 定期更新和改进
- **液态玻璃设计**: 高级视觉效果

## 贡献

我们欢迎贡献！请：

1. Fork 仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 打开 Pull Request

### 开发指南
- 遵循 Swift 样式约定
- 为复杂逻辑添加有意义的注释
- 在多个 macOS 版本上测试
- 保持向后兼容性

## 应用管理的未来

随着 Apple 逐渐远离可自定义界面，LaunchNext 代表了社区对用户控制和个性化的承诺。我们相信用户应该决定如何组织他们的数字工作空间。

**LaunchNext** 不仅仅是 Launchpad 的替代品——它是用户选择很重要的声明。


---

**LaunchNext** - 重新掌控你的应用启动器 🚀

*为拒绝在自定义方面妥协的 macOS 用户而构建。*