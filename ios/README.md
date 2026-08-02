# Tidal Echo for iOS

这是 Tidal Echo 的第一版 SwiftUI 原生客户端。它复用现有 FastAPI relay，不修改 PWA、数据库或 AI 侧进程。

## 当前功能

- HTTPS relay + Bearer 密钥登录
- 密钥保存在 iOS Keychain
- 拉取并显示聊天记录
- SSE 实时消息、输入状态、流式回复预览
- 发送文字与图片
- Thinking / Action 折叠卡片
- 雾绣、纸白、夜港三套原生主题
- GitHub Actions 编译模拟器版本和未签名 IPA

暂未包含原生推送、语音通话、会话管理、搜索、Moments、日历和表情包面板。

## 服务地址

登录页填写 relay 根地址，例如：

```text
https://example.com/relay
```

如果只填写 `https://example.com`，客户端会自动补上 `/relay`。第一版只接受 HTTPS。

## 在 GitHub Actions 构建

仓库中的 `.github/workflows/ios-build.yml` 会：

1. 在 macOS runner 安装 XcodeGen。
2. 从 `ios/Assets/AppIconSource.png` 生成完整 iOS AppIcon。
3. 根据 `project.yml` 生成 Xcode 项目。
4. 编译 iOS Simulator 版本，尽早发现 SwiftUI 编译错误。
5. 编译未签名的真机 `.app`。
6. 打包成 `TidalEcho-unsigned.ipa` 并上传为 workflow artifact。

把代码推送到 GitHub 后，也可以从 Actions 页面手动运行 **iOS Build**。

## 使用 AltStore 安装

1. 下载 Actions 产物 `TidalEcho-unsigned-ipa`。
2. 解压得到 `TidalEcho-unsigned.ipa`。
3. 在 iPhone 的 AltStore 中选择 **My Apps → +**，选择 IPA。
4. 使用免费 Apple ID 时，在 7 天到期前让 AltStore 连接 Windows 上的 AltServer 刷新。

首次使用 iOS 16 或更高版本的侧载 App，需要在系统设置中开启开发者模式。

## 在 Mac 上打开（可选）

```bash
brew install xcodegen
cd ios
bash scripts/prepare-assets.sh
xcodegen generate
open TidalEcho.xcodeproj
```

项目文件由 XcodeGen 生成，不提交到 Git。
