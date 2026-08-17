import PhotosUI
import SwiftUI
import UIKit

private struct SettingsPageBackground: View {
    let theme: EchoTheme
    let palette: EchoPalette

    @ViewBuilder
    var body: some View {
        if theme == .mist {
            Color.white
        } else {
            palette.background
        }
    }
}

private func settingsRowBackground(theme: EchoTheme, palette: EchoPalette) -> Color {
    theme == .mist ? Color.white : palette.composer.opacity(0.72)
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let onSearch: () -> Void
    let onCall: () -> Void
    @State private var anniversary: AnniversarySummary?
    @State private var greeting: String?
    @Environment(\.dismiss) private var dismiss

    private var palette: EchoPalette { model.theme.palette }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()
                if let image = model.backgroundImage {
                    GeometryReader { geometry in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .opacity(model.backgroundOpacity * 0.46)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }

                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 7) {
                            if let greeting, !greeting.isEmpty {
                                Text(greeting)
                                    .font(.system(size: 13))
                                    .foregroundStyle(palette.text.opacity(0.82))
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(3)
                                    .transition(.opacity)
                            }
                            Text("A PLACE FOR EVERY ECHO")
                                .font(.system(size: 11.5, weight: .medium))
                                .tracking(2.1)
                                .foregroundStyle(palette.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 5)

                        GeometryReader { geometry in
                            let unit = (geometry.size.width - 20) / 3
                            HStack(spacing: 10) {
                                NavigationLink {
                                    EchoCalendarView(model: model)
                                } label: {
                                    AnniversaryWideCard(summary: anniversary, palette: palette)
                                }
                                .frame(width: unit * 2 + 10)

                                Button { leaveHub(for: onSearch) } label: {
                                    HubTile(icon: "magnifyingglass", title: "搜索", subtitle: "全局消息", palette: palette, isMist: model.theme == .mist)
                                }
                                .frame(width: unit)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(height: 104)

                        LazyVGrid(columns: columns, spacing: 10) {
                            HubNavigationTile(icon: "paintpalette", title: "外观与聊天", subtitle: model.theme.title, palette: palette, isMist: model.theme == .mist) {
                                AppearanceSettingsView(model: model)
                            }
                            HubNavigationTile(icon: "brain.head.profile", title: "模型与连接", subtitle: "身体与 Relay", palette: palette, isMist: model.theme == .mist) {
                                ModelSettingsView(model: model)
                            }
                            HubNavigationTile(icon: "gauge.with.dots.needle.50percent", title: "会话与上下文", subtitle: "窗口与切换", palette: palette, isMist: model.theme == .mist) {
                                ContextSettingsView(model: model)
                            }
                            HubNavigationTile(icon: "bell.badge", title: "通知与后台", subtitle: "提醒与音频", palette: palette, isMist: model.theme == .mist) {
                                NotificationSettingsView(model: model)
                            }
                            Button { leaveHub(for: onCall) } label: {
                                HubTile(icon: "phone", title: "打电话", subtitle: model.peerDisplayName, palette: palette, isMist: model.theme == .mist)
                            }
                            HubNavigationTile(icon: "chart.bar", title: "Claude 额度", subtitle: "限额与用量", palette: palette, isMist: model.theme == .mist) {
                                ClaudeQuotaView(model: model)
                            }
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: 11) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Relay")
                                        .font(.caption.weight(.semibold))
                                    Text(model.savedServerAddress)
                                        .font(.caption2)
                                        .foregroundStyle(palette.secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Circle()
                                    .fill(model.isStreamConnected ? Color.green : palette.secondaryText)
                                    .frame(width: 7, height: 7)
                            }
                            Divider().overlay(palette.hairline)
                            HStack {
                                Button("重新加载") { Task { await model.refresh() } }
                                Spacer()
                                Button("退出并清除密钥", role: .destructive) {
                                    dismiss()
                                    model.logout()
                                }
                            }
                            .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(palette.text)
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.hairline))
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(model.theme.preferredColorScheme)
        .task { anniversary = try? await model.relationshipAnniversary() }
        .task { greeting = await model.greetingForCurrentTime() }
    }

    private func leaveHub(for action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { action() }
    }
}

private struct AnniversaryWideCard: View {
    let summary: AnniversarySummary?
    let palette: EchoPalette

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "heart")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("在一起")
                    .font(.system(size: 13, weight: .semibold))
                Text(summary.map { "\($0.daysSince) 天" } ?? "尚未设置")
                    .font(.system(size: summary == nil ? 18 : 26, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(startText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(palette.text)
        .padding(.horizontal, 17)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.hairline))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var startText: String {
        guard let raw = summary?.startDate else { return "从日历添加" }
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: raw) else { return "从 \(raw) 起" }
        let output = DateFormatter()
        output.locale = Locale(identifier: "zh_CN")
        output.dateFormat = "从 M月d日起"
        return output.string(from: date)
    }
}

private struct HubNavigationTile<Destination: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let palette: EchoPalette
    let isMist: Bool
    let destination: Destination

    init(
        icon: String,
        title: String,
        subtitle: String,
        palette: EchoPalette,
        isMist: Bool,
        @ViewBuilder destination: () -> Destination
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.palette = palette
        self.isMist = isMist
        self.destination = destination()
    }

    var body: some View {
        NavigationLink(destination: destination) {
            HubTile(icon: icon, title: title, subtitle: subtitle, palette: palette, isMist: isMist)
        }
    }
}

private struct HubTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let palette: EchoPalette
    let isMist: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(palette.accent)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(subtitle)
                .font(.system(size: 9.5))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(isMist ? 0.64 : 1)
        }
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.hairline))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct NotificationSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var notifications = NativeNotificationCenter.shared
    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        List {
            Section("原生通知") {
                Toggle("允许消息提醒", isOn: Binding(
                    get: { notifications.enabled },
                    set: { value in
                        if value {
                            Task { _ = await notifications.requestAuthorization() }
                        } else {
                            notifications.enabled = false
                            Task { await notifications.refreshAuthorizationStatus() }
                        }
                    }
                ))
                LabeledContent("权限状态", value: notifications.authorizationText)
                    .foregroundStyle(palette.secondaryText)
                Button("发送测试通知") { notifications.scheduleTest() }
                    .disabled(!notifications.enabled)
                if notifications.authorizationText == "系统已拒绝" {
                    Button("打开系统设置") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
            }

            Section("后台能力") {
                Label("语音条播放可在锁屏后继续", systemImage: "waveform")
                Label("通话期间保持麦克风和音频会话", systemImage: "phone.fill")
                Label("系统会择机后台刷新新消息", systemImage: "arrow.clockwise")
            }

            Section {
                Text("当前个人 P12 没有 APNs/PushKit 权限：App 被系统彻底结束后，无法保证立即收到原生通知或系统来电。以后换成开发者账号和带推送权限的描述文件，可以直接在这一层接入真正的远程推送。")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .tint(palette.accent)
        .scrollContentBackground(.hidden)
        .background(SettingsPageBackground(theme: model.theme, palette: palette).ignoresSafeArea())
        .listRowBackground(settingsRowBackground(theme: model.theme, palette: palette))
        .navigationTitle("通知与后台")
        .navigationBarTitleDisplayMode(.inline)
        .task { await notifications.refreshAuthorizationStatus() }
    }
}

private struct SettingsRouteLabel: View {
    let icon: String
    let title: String
    let subtitle: String
    let badge: String?
    let palette: EchoPalette

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(palette.accent)
                .frame(width: 38, height: 38)
                .background(palette.aiBubble, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).foregroundStyle(palette.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var backgroundItem: PhotosPickerItem?
    @State private var aiAvatarItem: PhotosPickerItem?
    @State private var humanAvatarItem: PhotosPickerItem?
    @State private var imageError: String?
    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        List {
            Section("昵称备注") {
                TextField("小克", text: $model.peerRemark)
                    .textInputAutocapitalization(.never)
                Text("只改变这台设备上的显示名称。")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }

            Section("主题") {
                ForEach(EchoTheme.allCases) { theme in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { model.applyTheme(theme) }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(theme.palette.background)
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(theme.palette.hairline))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(theme.title).foregroundStyle(palette.text)
                                Text(theme.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryText)
                            }
                            Spacer()
                            if model.theme == theme {
                                Image(systemName: "checkmark").foregroundStyle(palette.accent)
                            }
                        }
                    }
                }
            }

            Section("文字") {
                Picker("聊天字体", selection: $model.chatFont) {
                    ForEach(EchoChatFont.allCases) { font in
                        Text(font.title).tag(font)
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("字体大小")
                        Spacer()
                        Text("\(Int((model.fontScale * 100).rounded()))%")
                            .foregroundStyle(palette.secondaryText)
                    }
                    Slider(value: $model.fontScale, in: 0.85...1.35, step: 0.05)
                        .tint(palette.accent)
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("聊天字重")
                        Spacer()
                        Text("\(Int(model.chatWeight))")
                            .foregroundStyle(palette.secondaryText)
                    }
                    Slider(value: $model.chatWeight, in: 300...800, step: 20)
                        .tint(palette.accent)
                    if model.chatFont == .system {
                        Text(EchoChatFont.weightDiagnostic(model.chatWeight))
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
            }

            bubbleSettingsSection

            Section("聊天背景") {
                if let image = model.backgroundImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(1 + model.backgroundBlur / 260)
                        .blur(radius: model.backgroundBlur)
                        .frame(height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                HStack {
                    PhotosPicker(selection: $backgroundItem, matching: .images) {
                        Label(model.backgroundImage == nil ? "选择图片" : "更换图片", systemImage: "photo")
                    }
                    Spacer()
                    if model.backgroundImage != nil {
                        Button("移除", role: .destructive) {
                            model.removeAppearanceImage(.background)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("背景透明度")
                        Spacer()
                        Text("\(Int(model.backgroundOpacity * 100))%")
                            .foregroundStyle(palette.secondaryText)
                    }
                    Slider(value: $model.backgroundOpacity, in: 0.05...1, step: 0.05)
                        .tint(palette.accent)
                }
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("背景模糊度")
                        Spacer()
                        Text("\(Int(model.backgroundBlur.rounded()))")
                            .foregroundStyle(palette.secondaryText)
                    }
                    Slider(value: $model.backgroundBlur, in: 0...24, step: 1)
                        .tint(palette.accent)
                }
            }

            Section("双方头像") {
                Toggle("显示 AI 头像", isOn: $model.showsAIAvatar)
                Toggle("显示我的头像", isOn: $model.showsHumanAvatar)
                avatarPickerRow(
                    title: "AI 头像",
                    image: model.aiAvatarImage,
                    selection: $aiAvatarItem,
                    kind: .aiAvatar
                )
                avatarPickerRow(
                    title: "我的头像",
                    image: model.humanAvatarImage,
                    selection: $humanAvatarItem,
                    kind: .humanAvatar
                )
            }

        }
        .tint(palette.accent)
        .scrollContentBackground(.hidden)
        .background(SettingsPageBackground(theme: model.theme, palette: palette).ignoresSafeArea())
        .listRowBackground(settingsRowBackground(theme: model.theme, palette: palette))
        .navigationTitle("外观与聊天")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: backgroundItem) { item in loadPhoto(item, kind: .background) }
        .onChange(of: aiAvatarItem) { item in loadPhoto(item, kind: .aiAvatar) }
        .onChange(of: humanAvatarItem) { item in loadPhoto(item, kind: .humanAvatar) }
        .alert("图片保存失败", isPresented: Binding(
            get: { imageError != nil },
            set: { if !$0 { imageError = nil } }
        )) {
            Button("好", role: .cancel) { imageError = nil }
        } message: { Text(imageError ?? "") }
    }

    @ViewBuilder
    private var bubbleSettingsSection: some View {
        Section("消息气泡") {
            Toggle("显示 AI 气泡框", isOn: $model.showsAIBubble)

            Picker("气泡样式", selection: $model.bubbleStyle) {
                ForEach(EchoBubbleStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)

            if model.bubbleStyle != .liquid {
                Picker("气泡形状", selection: $model.bubbleShapeStyle) {
                    ForEach(EchoBubbleShapeStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            if model.bubbleStyle == .liquid {
                VStack(spacing: 12) {
                    HStack {
                        Text("好，就在这里慢慢调")
                            .font(model.chatFont.font(
                                size: PWAChatMetrics.bubbleFontSize(for: model.chatFont) * model.fontScale,
                                numericWeight: model.chatWeight
                            ))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .foregroundStyle(model.resolvedBubbleTextColor(default: palette.text))
                            .background {
                                LiquidGlassBubbleBackground(
                                    tint: model.resolvedAIBubbleColor(default: palette.aiBubble),
                                    tintOpacity: model.bubbleOpacity,
                                    radius: CGFloat(model.bubbleRadius),
                                    settings: model.liquidGlassSettings
                                )
                            }
                        Spacer(minLength: 24)
                    }
                    HStack {
                        Spacer(minLength: 24)
                        Text("气泡再透一点")
                            .font(model.chatFont.font(
                                size: PWAChatMetrics.bubbleFontSize(for: model.chatFont) * model.fontScale,
                                numericWeight: model.chatWeight
                            ))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .foregroundStyle(model.resolvedBubbleTextColor(default: palette.text))
                            .background {
                                LiquidGlassBubbleBackground(
                                    tint: model.resolvedHumanBubbleColor(default: palette.humanBubble),
                                    tintOpacity: model.bubbleOpacity,
                                    radius: CGFloat(model.bubbleRadius),
                                    settings: model.liquidGlassSettings
                                )
                            }
                    }
                }
                .padding(.vertical, 7)
            }

            ColorPicker("AI 气泡颜色", selection: Binding(
                get: { model.resolvedAIBubbleColor(default: palette.aiBubble) },
                set: { model.setAIBubbleColor($0) }
            ), supportsOpacity: false)

            ColorPicker("我的气泡颜色", selection: Binding(
                get: { model.resolvedHumanBubbleColor(default: palette.humanBubble) },
                set: { model.setHumanBubbleColor($0) }
            ), supportsOpacity: false)

            ColorPicker("气泡字体颜色", selection: Binding(
                get: { model.resolvedBubbleTextColor(default: palette.text) },
                set: { model.setBubbleTextColor($0) }
            ), supportsOpacity: false)

            settingSlider(
                title: "气泡透明度",
                valueText: "\(Int((model.bubbleOpacity * 100).rounded()))%",
                value: $model.bubbleOpacity,
                range: 0...1,
                step: 0.05
            )
            settingSlider(
                title: "气泡圆角",
                valueText: "\(Int(model.bubbleRadius.rounded()))",
                value: $model.bubbleRadius,
                range: 4...26,
                step: 1
            )
            settingSlider(
                title: "气泡宽度",
                valueText: "\(Int(model.bubbleWidthScale * 100))%",
                value: $model.bubbleWidthScale,
                range: 0.6...1.3,
                step: 0.05
            )
            settingSlider(
                title: "边框粗细",
                valueText: String(format: "%.1f", model.bubbleBorderWidth),
                value: $model.bubbleBorderWidth,
                range: 0...2,
                step: 0.25
            )

            if model.bubbleStyle == .liquid {
                VStack(alignment: .leading, spacing: 5) {
                    Label("原生 Glass：背景折射、模糊、光照与动态反馈", systemImage: "checkmark.circle")
                    Label("SwiftUI 轻量层：边缘色散、Fresnel 宽度与视觉厚度", systemImage: "slider.horizontal.3")
                    Label("需背景纹理 + Metal：真实扭曲、RGB 位移、放大与手动模糊", systemImage: "cpu")
                    Text("当前未启用 CABackdropLayer；每个消息气泡只创建一个原生 Glass。")
                        .padding(.top, 2)
                }
                .font(.caption)
                .foregroundStyle(palette.secondaryText)

                settingSlider(
                    title: "扭曲 strength",
                    valueText: String(format: "%.1f", model.liquidGlassStrength),
                    value: $model.liquidGlassStrength,
                    range: 0...100,
                    step: 1,
                    note: "原生模式下调节颜色厚度；真实折射强度需要背景纹理。"
                )
                settingSlider(
                    title: "色散 dispersion",
                    valueText: String(format: "%.2f", model.liquidGlassDispersion),
                    value: $model.liquidGlassDispersion,
                    range: 0...1,
                    step: 0.01,
                    note: "当前是轻量边缘色散；真实 RGB 位移需要 Metal 与背景纹理。"
                )
                settingSlider(
                    title: "过渡 rimWidth",
                    valueText: String(format: "%.2f", model.liquidGlassRimWidth),
                    value: $model.liquidGlassRimWidth,
                    range: 0...1,
                    step: 0.01,
                    note: "SwiftUI 调节 Fresnel 边缘宽度，不重复采样背景。"
                )
                settingSlider(
                    title: "放大 magnify",
                    valueText: "需增强玻璃",
                    value: $model.liquidGlassMagnify,
                    range: 0...1,
                    step: 0.01,
                    note: "必须取得气泡后方纹理；纯原生模式暂不执行。",
                    isEnabled: false
                )
                settingSlider(
                    title: "背景模糊 blur",
                    valueText: "原生接管",
                    value: $model.liquidGlassBlur,
                    range: 0...1,
                    step: 0.01,
                    note: "由 iOS 26 Glass 自动处理；连续手动模糊需要背景纹理。",
                    isEnabled: false
                )
                settingSlider(
                    title: "光学尺度 size",
                    valueText: String(format: "%.0f", model.liquidGlassSize),
                    value: $model.liquidGlassSize,
                    range: 80...260,
                    step: 1,
                    note: "SwiftUI 调节视觉厚度与边缘尺度。"
                )
            }

            Button("恢复主题气泡配色") { model.resetBubbleColors() }
            Button("恢复外观默认值") {
                model.chatFont = .system
                model.fontScale = 1
                model.showsAIAvatar = true
                model.showsHumanAvatar = false
                model.showsAIBubble = true
                model.bubbleOpacity = 1
                model.bubbleRadius = 14
                model.bubbleWidthScale = 1
                model.bubbleBorderWidth = 0
                model.bubbleStyle = .classic
                model.bubbleShapeStyle = .standard
                model.liquidGlassStrength = 56.8
                model.liquidGlassDispersion = 0.39
                model.liquidGlassRimWidth = 0.28
                model.liquidGlassMagnify = 0
                model.liquidGlassBlur = 0.94
                model.liquidGlassSize = 174
                model.chatWeight = 400
                model.backgroundOpacity = 1
                model.resetBubbleColors()
            }
        }
    }

    @ViewBuilder
    private func settingSlider(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        note: String? = nil,
        isEnabled: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText).foregroundStyle(palette.secondaryText)
            }
            Slider(value: value, in: range, step: step)
                .tint(palette.accent)
                .disabled(!isEnabled)
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func avatarPickerRow(
        title: String,
        image: UIImage?,
        selection: Binding<PhotosPickerItem?>,
        kind: AppModel.AppearanceImageKind
    ) -> some View {
        HStack(spacing: 12) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: kind == .humanAvatar ? "person.fill" : "sparkle")
                        .foregroundStyle(palette.accent)
                }
            }
            .frame(width: 42, height: 42)
            .background(palette.aiBubble)
            .clipShape(Circle())

            Text(title)
            Spacer()
            PhotosPicker(selection: selection, matching: .images) {
                Text(image == nil ? "选择" : "更换")
            }
            if image != nil {
                Button("移除", role: .destructive) { model.removeAppearanceImage(kind) }
                    .font(.caption)
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?, kind: AppModel.AppearanceImageKind) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw APIError.invalidResponse
                }
                try model.saveAppearanceImage(data: data, kind: kind)
            } catch {
                imageError = error.localizedDescription
            }
            switch kind {
            case .background: backgroundItem = nil
            case .aiAvatar: aiAvatarItem = nil
            case .humanAvatar: humanAvatarItem = nil
            }
        }
    }
}

private struct ModelChoice: Identifiable {
    let title: String
    let desktopID: String
    let directAPIID: String
    let openRouterID: String
    var id: String { title }
}

private struct ModelSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var brain: BrainTarget = .desktop
    @State private var currentModelID = ""
    @State private var loopURL = ""
    @State private var loopChainCount = 1
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var notice: String?
    @State private var pendingDesktopChoice: ModelChoice?

    private var palette: EchoPalette { model.theme.palette }
    private let choices = [
        ModelChoice(title: "Opus 4.6", desktopID: "claude-opus-4-6", directAPIID: "[按量]claude-opus-4-6-thinking", openRouterID: "anthropic/claude-opus-4.6"),
        ModelChoice(title: "Opus 4.7", desktopID: "claude-opus-4-7", directAPIID: "[按量]claude-opus-4-7-thinking", openRouterID: "anthropic/claude-opus-4.7"),
        ModelChoice(title: "Opus 4.8", desktopID: "claude-opus-4-8", directAPIID: "[按量]claude-opus-4-8-thinking", openRouterID: "anthropic/claude-opus-4.8"),
        ModelChoice(title: "Fable 5", desktopID: "claude-fable-5[1m]", directAPIID: "[按量]claude-fable-5-thinking", openRouterID: "anthropic/claude-fable-5")
    ]

    var body: some View {
        List {
            Section("联系身体") {
                Picker("当前身体", selection: Binding(
                    get: { brain },
                    set: { target in Task { await switchBrain(to: target) } }
                )) {
                    ForEach(BrainTarget.allCases) { target in
                        Text(target.title).tag(target)
                    }
                }
                .pickerStyle(.segmented)

                Text(brain == .desktop
                     ? "Claude Code channel 正在接收消息。"
                     : "服务器 API loop 正在接收消息。")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            Section("模型选择") {
                if brain == .desktop {
                    Button {
                        pendingDesktopChoice = ModelChoice(title: "默认模型", desktopID: "", directAPIID: "", openRouterID: "")
                    } label: {
                        modelRow(title: "默认模型", id: "")
                    }
                }

                ForEach(choices) { choice in
                    Button {
                        if brain == .desktop {
                            pendingDesktopChoice = choice
                        } else {
                            Task { await saveAPIModel(choice) }
                        }
                    } label: {
                        modelRow(title: choice.title, id: modelID(for: choice))
                    }
                }

                if isBusy { ProgressView().tint(palette.accent) }
                if let notice {
                    Text(notice).font(.caption).foregroundStyle(palette.secondaryText)
                }
            }

            Section("连接") {
                LabeledContent("Relay", value: model.savedServerAddress)
                    .font(.footnote)
                if brain == .loop, !loopURL.isEmpty {
                    LabeledContent("API", value: loopURL)
                        .font(.footnote)
                }
                Button("刷新模型状态") { Task { await load() } }
            }

            Section("额度与 API") {
                NavigationLink("Claude 额度") {
                    ClaudeQuotaView(model: model)
                }
                NavigationLink("API 接口与用量") {
                    APIControlView(model: model)
                }
            }
        }
        .tint(palette.accent)
        .scrollContentBackground(.hidden)
        .background(SettingsPageBackground(theme: model.theme, palette: palette).ignoresSafeArea())
        .listRowBackground(settingsRowBackground(theme: model.theme, palette: palette))
        .navigationTitle("模型与连接")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Desktop 模型切换", isPresented: Binding(
            get: { pendingDesktopChoice != nil },
            set: { if !$0 { pendingDesktopChoice = nil } }
        )) {
            Button("取消", role: .cancel) { pendingDesktopChoice = nil }
            Button("切换并 Swap", role: .destructive) {
                guard let choice = pendingDesktopChoice else { return }
                pendingDesktopChoice = nil
                Task { await saveDesktopModel(choice) }
            }
        } message: {
            Text("会重启 Desktop 会话，最近对话将交接到新窗口，期间可能断开几十秒。")
        }
        .alert("模型设置失败", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("好", role: .cancel) { errorText = nil }
        } message: { Text(errorText ?? "") }
    }

    @ViewBuilder
    private func modelRow(title: String, id: String) -> some View {
        HStack {
            Text(title).foregroundStyle(palette.text)
            Spacer()
            if currentModelID == id {
                Image(systemName: "checkmark").foregroundStyle(palette.accent)
            }
        }
    }

    private func modelID(for choice: ModelChoice) -> String {
        if brain == .desktop { return choice.desktopID }
        return loopURL.contains("openrouter.ai") ? choice.openRouterID : choice.directAPIID
    }

    private func load() async {
        isBusy = true
        defer { isBusy = false }
        do {
            brain = try await model.settingsBrain()
            try await loadCurrentModel()
            notice = brain == .desktop ? "Desktop 切换模型会自动 Swap。" : "API 模型切换后立即生效。"
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadCurrentModel() async throws {
        if brain == .desktop {
            currentModelID = try await model.settingsDesktopModel().model
        } else {
            let config = try await model.settingsLoopConfig()
            loopChainCount = max(1, config.mainChain.count)
            loopURL = config.mainChain.first?.url ?? ""
            currentModelID = config.mainChain.first?.model ?? ""
        }
    }

    private func switchBrain(to target: BrainTarget) async {
        guard target != brain else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            brain = try await model.updateSettingsBrain(target)
            try await loadCurrentModel()
            notice = brain == .desktop ? "已切到 Desktop。" : "已切到 API。"
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func saveAPIModel(_ choice: ModelChoice) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let id = modelID(for: choice)
            let config = try await model.updateLoopModel(id, chainCount: loopChainCount)
            loopURL = config.mainChain.first?.url ?? loopURL
            currentModelID = config.mainChain.first?.model ?? id
            notice = "API 模型已切到 \(choice.title)。"
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func saveDesktopModel(_ choice: ModelChoice) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let response = try await model.updateDesktopModel(choice.desktopID)
            currentModelID = response.model
            notice = response.applied == true
                ? "Desktop 正在切换，稍等它带着交接回来。"
                : (response.note ?? "已保存，下次重启生效。")
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct QuotaWindow: Identifiable {
    let key: String
    let utilization: Double
    let resetsAt: String
    var id: String { key }

    var title: String {
        switch key {
        case "five_hour": return "5 小时窗口"
        case "seven_day": return "本周（全模型）"
        case "seven_day_opus": return "本周 Opus"
        case "seven_day_sonnet": return "本周 Sonnet"
        case "seven_day_oauth_apps": return "本周 OAuth 应用"
        case "extra_usage": return "超额用量"
        default:
            if key.localizedCaseInsensitiveContains("fable") { return "本周 Fable" }
            if key.localizedCaseInsensitiveContains("opus") { return "本周 Opus" }
            return key.replacingOccurrences(of: "_", with: " ")
        }
    }

    var percent: Double {
        let normalized = utilization > 0 && utilization <= 1 ? utilization * 100 : utilization
        return min(max(normalized, 0), 100)
    }
}

private struct ClaudeQuotaView: View {
    @ObservedObject var model: AppModel
    @State private var windows: [QuotaWindow] = []
    @State private var isLoading = false
    @State private var errorText: String?
    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        List {
            if isLoading && windows.isEmpty {
                ProgressView("读取 Claude 账号额度…").tint(palette.accent)
            }
            ForEach(windows) { window in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(window.title)
                        Spacer()
                        Text("\(Int(window.percent.rounded()))%")
                            .font(.headline.monospacedDigit())
                    }
                    ProgressView(value: window.percent, total: 100)
                        .tint(window.percent >= 90 ? .red : (window.percent >= 70 ? .orange : palette.accent))
                    if !window.resetsAt.isEmpty {
                        QuotaResetCountdown(resetsAt: window.resetsAt, palette: palette)
                    }
                }
                .padding(.vertical, 4)
            }
            if !isLoading && windows.isEmpty {
                Text("没有解析出可显示的额度窗口。")
                    .foregroundStyle(palette.secondaryText)
            }
            Button("刷新额度") { Task { await load() } }
        }
        .scrollContentBackground(.hidden)
        .background(SettingsPageBackground(theme: model.theme, palette: palette).ignoresSafeArea())
        .listRowBackground(settingsRowBackground(theme: model.theme, palette: palette))
        .navigationTitle("Claude 额度")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("额度读取失败", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("好", role: .cancel) { errorText = nil }
        } message: { Text(errorText ?? "") }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var rows: [QuotaWindow] = []
            collectQuota(model: try await model.settingsQuota().raw, into: &rows)
            windows = rows
                .filter { !($0.key.localizedCaseInsensitiveContains("extra") && $0.percent == 0) }
                .sorted { quotaRank($0.key) < quotaRank($1.key) }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func collectQuota(model value: JSONValue, into rows: inout [QuotaWindow]) {
        switch value {
        case .object(let object):
            if case .number(let utilization)? = object["utilization"] {
                let reset: String
                if case .string(let value)? = object["resets_at"] { reset = value }
                else if case .string(let value)? = object["resetsAt"] { reset = value }
                else { reset = "" }
                rows.append(QuotaWindow(key: "unknown", utilization: utilization, resetsAt: reset))
                return
            }
            for (key, child) in object {
                if case .object(let detail) = child,
                   case .number(let utilization)? = detail["utilization"] {
                    let reset: String
                    if case .string(let value)? = detail["resets_at"] { reset = value }
                    else if case .string(let value)? = detail["resetsAt"] { reset = value }
                    else { reset = "" }
                    rows.append(QuotaWindow(key: key, utilization: utilization, resetsAt: reset))
                } else {
                    collectQuota(model: child, into: &rows)
                }
            }
        case .array(let values):
            values.forEach { collectQuota(model: $0, into: &rows) }
        default:
            break
        }
    }

    private func quotaRank(_ key: String) -> Int {
        ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet", "seven_day_oauth_apps", "extra_usage"]
            .firstIndex(of: key) ?? 99
    }

}

private struct QuotaResetCountdown: View {
    let resetsAt: String
    let palette: EchoPalette

    private var resetDate: Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: resetsAt) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: resetsAt)
    }

    var body: some View {
        if let resetDate {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(countdownText(to: resetDate, from: context.date))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .monospacedDigit()
            }
        }
    }

    private func countdownText(to resetDate: Date, from now: Date) -> String {
        let seconds = max(0, Int(resetDate.timeIntervalSince(now)))
        guard seconds > 0 else { return "额度即将刷新" }
        let totalMinutes = max(1, Int(ceil(Double(seconds) / 60)))
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return "距离额度刷新还有 \(days) 天 \(hours) 小时"
        }
        if hours > 0 {
            return "距离额度刷新还有 \(hours) 小时 \(minutes) 分"
        }
        return "距离额度刷新还有 \(minutes) 分钟"
    }
}

private struct APIControlView: View {
    @ObservedObject var model: AppModel
    @State private var presets: [APIPreset] = []
    @State private var stats: APIUsageStats?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var pendingPreset: APIPreset?
    @State private var showingAddPreset = false
    @State private var showingRecent = false
    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        List {
            Section("API 接口") {
                ForEach(presets) { preset in
                    Button { if !preset.active { pendingPreset = preset } } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.name).foregroundStyle(palette.text)
                                Text(preset.url).font(.caption).foregroundStyle(palette.secondaryText).lineLimit(1)
                                Text("\(preset.model) · \(preset.keyMasked)")
                                    .font(.caption2)
                                    .foregroundStyle(palette.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if preset.active {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.accent)
                            }
                        }
                    }
                    .swipeActions {
                        if presets.count > 1 {
                            Button("删除", role: .destructive) { Task { await deletePreset(preset) } }
                        }
                    }
                }
                Button { showingAddPreset = true } label: {
                    Label("添加 API 接口", systemImage: "plus")
                }
            }

            if let stats {
                Section("API 用量") {
                    metric("消息数", value: "\(stats.messages)")
                    metric("缓存命中率", value: "\(Int((stats.cacheHitRate * 100).rounded()))%")
                    metric("输入（全价）", value: tokenText(stats.total.input))
                    metric("输出", value: tokenText(stats.total.output))
                    metric("缓存命中", value: tokenText(stats.total.cacheRead))
                    metric("缓存写入", value: tokenText(stats.total.cacheWrite))
                    metric("累计估价", value: String(format: "$%.2f", stats.totalCostUSD))
                    metric("每条均价", value: String(format: "$%.4f", stats.average.costUSD ?? 0))
                    Text("心跳 \(stats.keepalive.beats) 次 ≈ \(String(format: "$%.3f", stats.keepalive.costUSD)) · 缓存 \(stats.cacheTTL)")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }

                Section {
                    DisclosureGroup("最近用量明细", isExpanded: $showingRecent) {
                        ForEach(stats.recent) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Circle()
                                        .fill(cacheStateColor(entry))
                                        .frame(width: 7, height: 7)
                                    Text(entry.model ?? "未知模型").lineLimit(1)
                                    Spacer()
                                    Text(cacheHitText(entry))
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(cacheStateColor(entry))
                                    Text(String(format: "$%.4f", entry.costUSD)).monospacedDigit()
                                }
                                Text("读 \(tokenText(entry.cacheRead)) · 写 \(tokenText(entry.cacheWrite)) · 入 \(tokenText(entry.input)) · 出 \(tokenText(entry.output))")
                                    .font(.caption2)
                                    .foregroundStyle(palette.secondaryText)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }

            if isLoading { ProgressView().tint(palette.accent) }
            Button("刷新接口与用量") { Task { await load() } }
        }
        .tint(palette.accent)
        .scrollContentBackground(.hidden)
        .background(SettingsPageBackground(theme: model.theme, palette: palette).ignoresSafeArea())
        .listRowBackground(settingsRowBackground(theme: model.theme, palette: palette))
        .navigationTitle("API 接口与用量")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showingAddPreset) {
            AddAPIPresetView(model: model, existing: presets) { config in
                presets = config.apiPresets
                stats = try? await model.settingsAPIUsage()
            }
        }
        .confirmationDialog("切换 API 接口？", isPresented: Binding(
            get: { pendingPreset != nil },
            set: { if !$0 { pendingPreset = nil } }
        ), titleVisibility: .visible) {
            Button("切换") {
                guard let preset = pendingPreset else { return }
                pendingPreset = nil
                Task { await activate(preset) }
            }
            Button("取消", role: .cancel) { pendingPreset = nil }
        } message: {
            Text(pendingPreset.map { "\($0.name)\n\($0.url)\n\($0.model)" } ?? "")
        }
        .alert("API 面板错误", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("好", role: .cancel) { errorText = nil }
        } message: { Text(errorText ?? "") }
    }

    private func metric(_ title: String, value: String) -> some View {
        LabeledContent(title, value: value)
    }

    private func tokenText(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return String(value)
    }

    private func cacheHitText(_ entry: APIUsageEntry) -> String {
        guard let rate = entry.cacheHitRate else { return "命中 —" }
        return "命中 \(Int((rate * 100).rounded()))%"
    }

    private func cacheStateColor(_ entry: APIUsageEntry) -> Color {
        if entry.cacheRead > 0 { return .green }
        if entry.cacheWrite > 0 { return .orange }
        return .red
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            presets = try await model.settingsLoopConfig().apiPresets
        } catch {
            errorText = "接口列表：\(error.localizedDescription)"
        }
        do {
            stats = try await model.settingsAPIUsage()
        } catch {
            if errorText == nil { errorText = "用量统计：\(error.localizedDescription)" }
        }
    }

    private func activate(_ preset: APIPreset) async {
        isLoading = true
        defer { isLoading = false }
        do { presets = try await model.activateAPIPreset(preset.index).apiPresets }
        catch { errorText = error.localizedDescription }
    }

    private func deletePreset(_ preset: APIPreset) async {
        let remaining = presets.filter { $0.id != preset.id }.map {
            APIPresetInput(name: $0.name, url: $0.url, key: "", model: $0.model)
        }
        do { presets = try await model.replaceAPIPresets(remaining).apiPresets }
        catch { errorText = error.localizedDescription }
    }
}

private struct AddAPIPresetView: View {
    @ObservedObject var model: AppModel
    let existing: [APIPreset]
    let onSaved: (LoopConfigResponse) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var key = ""
    @State private var modelID = ""
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("接口信息") {
                    TextField("名称，例如 OpenRouter", text: $name)
                    TextField("https://…/v1", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key", text: $key)
                    TextField("模型 ID", text: $modelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("Key 只提交给你自己的 relay/api_loop；保存后原生 App 只会收到掩码。")
                        .font(.caption)
                }
            }
            .tint(model.theme.palette.accent)
            .scrollContentBackground(.hidden)
            .background(SettingsPageBackground(theme: model.theme, palette: model.theme.palette).ignoresSafeArea())
            .listRowBackground(settingsRowBackground(theme: model.theme, palette: model.theme.palette))
            .navigationTitle("添加 API 接口")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSaving { ProgressView() }
                    else { Button("保存") { Task { await save() } }.disabled(!canSave) }
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("好", role: .cancel) { errorText = nil }
            } message: { Text(errorText ?? "") }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && URL(string: url)?.scheme?.lowercased() == "https"
            && !key.isEmpty && !modelID.isEmpty
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let rows = existing.map {
            APIPresetInput(name: $0.name, url: $0.url, key: "", model: $0.model)
        } + [APIPresetInput(name: name, url: url, key: key, model: modelID)]
        do {
            let config = try await model.replaceAPIPresets(rows)
            await onSaved(config)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private enum ContextCommand: String, Identifiable {
    case reset
    case swap
    case resume
    var id: String { rawValue }
    var title: String {
        switch self {
        case .reset: return "Reset 新窗口"
        case .swap: return "Swap 交接重开"
        case .resume: return "Resume 接回窗口"
        }
    }
    var explanation: String {
        switch self {
        case .reset: return "会重启 Desktop，开一个不带交接的全新窗口。"
        case .swap: return "会重启 Desktop，并把最近对话原文交接给新窗口。"
        case .resume: return "会重启 Desktop，并接回 pending 会话。"
        }
    }
}

private struct ContextSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var status: ContextStatus?
    @State private var triggerK = 200.0
    @State private var autoSwap = false
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var notice: String?
    @State private var pendingCommand: ContextCommand?
    @State private var chatMode: ChatMode = .long

    private var palette: EchoPalette { model.theme.palette }
    private var usageK: Double { Double(status?.usageTokens ?? 0) / 1000 }
    private var progress: Double { min(max(usageK / max(triggerK, 1), 0), 1) }

    var body: some View {
        List {
            Section("当前上下文") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(Int(usageK.rounded()))k")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Text("阈值 \(Int(triggerK))k")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                    ProgressView(value: progress).tint(palette.accent)
                }
                if let sid = status?.activeSID, !sid.isEmpty {
                    LabeledContent("Active SID", value: shortSID(sid))
                        .font(.footnote)
                }
                if let pending = status?.pending?.newSID {
                    LabeledContent("Pending SID", value: shortSID(pending))
                        .font(.footnote)
                }
                Button("刷新状态") { Task { await load() } }
            }

            Section("自动管理") {
                Toggle("自动 Swap", isOn: Binding(
                    get: { autoSwap },
                    set: { value in
                        autoSwap = value
                        Task { await saveAutoSwap(value) }
                    }
                ))
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("触发阈值")
                        Spacer()
                        Text("\(Int(triggerK))k")
                            .foregroundStyle(palette.secondaryText)
                    }
                    Slider(value: $triggerK, in: 80...500, step: 20)
                        .tint(palette.accent)
                    Button("保存阈值") { Task { await saveThreshold() } }
                }
                Text("仅影响 Desktop；到达触发线后会带最近对话自动交接重开。")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            Section("聊天节奏") {
                Picker("回复方式", selection: Binding(
                    get: { chatMode },
                    set: { mode in
                        chatMode = mode
                        Task { await saveChatMode(mode) }
                    }
                )) {
                    ForEach(ChatMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(chatMode == .short
                     ? "回复会按段落拆成最多五条气泡连发。"
                     : "一整段回复显示为一条气泡。")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            Section("会话操作") {
                Button("Swap · 交接重开") { pendingCommand = .swap }
                Button("Reset · 全新窗口", role: .destructive) { pendingCommand = .reset }
                if status?.pending?.newSID != nil {
                    Button("Resume · 接回 Pending") { pendingCommand = .resume }
                }
                if isBusy { ProgressView().tint(palette.accent) }
                if let notice {
                    Text(notice).font(.caption).foregroundStyle(palette.secondaryText)
                }
            }
        }
        .tint(palette.accent)
        .scrollContentBackground(.hidden)
        .background(SettingsPageBackground(theme: model.theme, palette: palette).ignoresSafeArea())
        .listRowBackground(settingsRowBackground(theme: model.theme, palette: palette))
        .navigationTitle("会话与上下文")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog(
            pendingCommand?.title ?? "会话操作",
            isPresented: Binding(
                get: { pendingCommand != nil },
                set: { if !$0 { pendingCommand = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认执行", role: .destructive) {
                guard let command = pendingCommand else { return }
                pendingCommand = nil
                Task { await run(command) }
            }
            Button("取消", role: .cancel) { pendingCommand = nil }
        } message: {
            Text(pendingCommand?.explanation ?? "")
        }
        .alert("上下文操作失败", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("好", role: .cancel) { errorText = nil }
        } message: { Text(errorText ?? "") }
    }

    private func shortSID(_ sid: String) -> String {
        sid.count > 12 ? String(sid.prefix(9)) + "…" : sid
    }

    private func load() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let next = try await model.settingsContextStatus()
            status = next
            triggerK = Double(next.triggerK)
            autoSwap = next.auto
            if let mode = try? await model.settingsChatMode() { chatMode = mode }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func saveThreshold() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let next = try await model.updateContextThreshold(triggerK: Int(triggerK))
            triggerK = Double(next.triggerK)
            autoSwap = next.auto
            notice = "上下文阈值已保存。"
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func saveAutoSwap(_ value: Bool) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let next = try await model.updateContextThreshold(auto: value)
            triggerK = Double(next.triggerK)
            autoSwap = next.auto
            notice = next.auto ? "自动 Swap 已开启。" : "自动 Swap 已关闭。"
        } catch {
            autoSwap.toggle()
            errorText = error.localizedDescription
        }
    }

    private func saveChatMode(_ mode: ChatMode) async {
        isBusy = true
        defer { isBusy = false }
        do {
            chatMode = try await model.updateChatMode(mode)
            notice = chatMode == .short ? "短聊已开启。" : "长聊已开启。"
        } catch {
            chatMode = mode == .short ? .long : .short
            errorText = error.localizedDescription
        }
    }

    private func run(_ command: ContextCommand) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let sid = command == .resume ? status?.pending?.newSID : nil
            _ = try await model.performContextAction(command.rawValue, sid: sid)
            notice = command == .swap ? "Swap 已触发，正在交接。" : "\(command.title) 已触发。"
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let next = try await model.settingsContextStatus()
            status = next
            triggerK = Double(next.triggerK)
            autoSwap = next.auto
        } catch {
            errorText = error.localizedDescription
        }
    }
}
