# Alist Photo

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.24.5-blue" alt="Flutter Version">
  <img src="https://img.shields.io/badge/Android-13+-green" alt="Android Support">
  <img src="https://img.shields.io/badge/iOS-16+-lightgrey" alt="iOS Support">
  <img src="https://img.shields.io/github/license/RhineLT/Alist-Photo" alt="License">
</p>

一个基于 Flutter 开发的跨平台 Alist 图片浏览应用，支持 Android 和 iOS 平台。

## ✨ 特性

- 📱 **跨平台支持** - 支持 Android 13+ 和 iOS 16+
- 🖼️ **图片浏览** - 支持常见图片格式浏览和缩放
- 📁 **文件夹导航** - 直观的文件夹浏览和导航
- 🔍 **缩略图显示** - 平铺视图显示图片缩略图
- 👁️ **全屏查看** - 支持手势缩放、滑动切换的图片查看器
- ⚙️ **服务器配置** - 简单易用的 Alist 服务器配置界面
- 🔒 **安全连接** - 支持 HTTP 和 HTTPS 协议
- 📱 **响应式设计** - 适配不同屏幕尺寸

## 📸 截图

*截图将在应用构建完成后添加*

## 🚀 快速开始

### 安装应用

#### Android 用户
1. 前往 [Releases 页面](https://github.com/RhineLT/Alist-Photo/releases)
2. 下载最新版本的 `app-release.apk`
3. 在设备上启用"未知来源"安装权限
4. 安装 APK 文件

#### iOS 用户
由于需要苹果开发者证书签名，iOS 版本需要：
1. 下载 `.ipa` 文件
2. 使用 Xcode 或第三方工具签名
3. 通过 TestFlight 或其他方式安装

### 配置使用

1. **启动应用** - 首次启动会自动打开设置页面
2. **配置服务器**：
   - 服务器地址：输入您的 Alist 服务器地址 (如: `http://192.168.1.100:5244`)
   - 用户名：输入 Alist 账户用户名
   - 密码：输入 Alist 账户密码
3. **保存配置** - 点击"保存并测试连接"
4. **开始使用** - 配置成功后即可浏览您的图片

## 🛠️ 开发

### 环境要求

- Flutter 3.24.5 或更高版本
- Dart 3.4.3 或更高版本
- Android Studio / VS Code
- Android SDK (API level 33+)
- Xcode (仅 macOS，用于 iOS 开发)

### 本地构建

```bash
# 克隆仓库
git clone https://github.com/RhineLT/Alist-Photo.git
cd Alist-Photo/alist_photo

# 安装依赖
flutter pub get

# 运行应用
flutter run

# 构建 APK
flutter build apk --release

# 构建 iOS (仅 macOS)
flutter build ios --release
```

### 项目结构

```
alist_photo/
├── lib/
│   ├── main.dart              # 应用入口
│   ├── services/
│   │   └── alist_api_client.dart  # Alist API 客户端
│   └── pages/
│       ├── home_page.dart         # 主页面
│       ├── settings_page.dart     # 设置页面
│       └── photo_viewer_page.dart # 图片查看器
├── android/                   # Android 配置
├── ios/                       # iOS 配置
└── pubspec.yaml              # 依赖配置
```

## 📋 API 支持

应用严格遵循 Alist v3 API 规范：

- **认证** - `/api/auth/login/hash` (使用 SHA256 哈希密码)
- **文件列表** - `/api/fs/list` (获取文件夹内容)
- **文件信息** - `/api/fs/get` (获取单个文件信息)
- **缩略图** - 支持 Alist 生成的缩略图
- **直链下载** - 支持原始文件访问

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建您的特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交您的更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开一个 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🙏 致谢

- [Alist](https://github.com/alist-org/alist) - 优秀的文件列表程序
- [Flutter](https://flutter.dev) - 跨平台 UI 框架
- [photo_view](https://pub.dev/packages/photo_view) - 图片查看组件
- [cached_network_image](https://pub.dev/packages/cached_network_image) - 网络图片缓存

## 🐛 问题反馈

如果您在使用过程中遇到问题，请：

1. 查看 [Issues 页面](https://github.com/RhineLT/Alist-Photo/issues)
2. 搜索是否已有相关问题
3. 创建新的 Issue 并提供详细信息：
   - 设备信息（型号、操作系统版本）
   - 应用版本
   - 详细的错误描述
   - 复现步骤（如有）

## 🔮 计划功能

- [ ] 支持视频文件预览
- [ ] 批量下载功能
- [ ] 本地收藏夹
- [ ] 多服务器管理
- [ ] 深色模式
- [ ] 更多图片格式支持
- [ ] 幻灯片播放
- [ ] 图片信息显示（EXIF）

---

**注意**: 本应用需要有效的 Alist 服务器和账户才能正常使用。
