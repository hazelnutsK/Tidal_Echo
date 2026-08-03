import PhotosUI
import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AppearanceSettingsView(model: model)
                    } label: {
                        SettingsRouteLabel(
                            icon: "paintpalette",
                            title: "外观与聊天",
                            subtitle: "主题、字体、头像与气泡",
                            badge: model.theme.title,
                            palette: palette
                        )
                    }

                    NavigationLink {
                        ModelSettingsView(model: model)
                    } label: {
                        SettingsRouteLabel(
                            icon: "brain.head.profile",
                            title: "模型与连接",
                            subtitle: "身体、模型与 Relay",
                            badge: nil,
                            palette: palette
                        )
                    }

                    NavigationLink {
                        ContextSettingsView(model: model)
                    } label: {
                        SettingsRouteLabel(
                            icon: "gauge.with.dots.needle.50percent",
                            title: "会话与上下文",
                            subtitle: "阈值、自动 Swap 与会话控制",
                            badge: nil,
                            palette: palette
                        )
                    }

                    NavigationLink {
                        NotificationSettingsView(model: model)
                    } label: {
                        SettingsRouteLabel(
                            icon: "bell.badge",
                            title: "通知与后台",
                            subtitle: "锁屏提醒、后台音频与来电",
                            badge: nil,
                            palette: palette
                        )
                    }
                }
                .listRowBackground(palette.composer.opacity(0.72))

                Section("连接") {
                    LabeledContent("Relay", value: model.savedServerAddress)
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                    Button("重新加载聊天记录") { Task { await model.refresh() } }
                }
                .listRowBackground(palette.composer.opacity(0.72))

                Section {
                    Button("退出并清除密钥", role: .destructive) {
                        dismiss()
                        model.logout()
                    }
                }
                .listRowBackground(palette.composer.opacity(0.72))
            }
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(model.theme.preferredColorScheme)
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
        .background(palette.background.ignoresSafeArea())
        .listRowBackground(palette.composer.opacity(0.72))
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
                        withAnimation(.easeInOut(duration: 0.2)) { model.theme = theme }
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
                }
            }

            Section("聊天背景") {
                if let image = model.backgroundImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
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

            Section("消息气泡") {
                Toggle("显示 AI 气泡框", isOn: $model.showsAIBubble)

                Picker("气泡样式", selection: $model.bubbleStyle) {
                    ForEach(EchoBubbleStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                ColorPicker("AI 气泡颜色", selection: Binding(
                    get: { model.resolvedAIBubbleColor(default: palette.aiBubble) },
                    set: { model.setAIBubbleColor($0) }
                ), supportsOpacity: false)

                ColorPicker("我的气泡颜色", selection: Binding(
                    get: { model.resolvedHumanBubbleColor(default: palette.humanBubble) },
                    set: { model.setHumanBubbleColor($0) }
                ), supportsOpacity: false)

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("气泡透明度")
                        Spacer()
                        Text("\(Int((model.bubbleOpacity * 100).rounded()))%")
                            .foregroundStyle(palette.secondaryText)
                    }
                    Slider(value: $model.bubbleOpacity, in: 0...1, step: 0.05)
                        .tint(palette.accent)
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("气泡圆角")
                        Spacer()
                        Text("\(Int(model.bubbleRadius.rounded()))")
                            .foregroundStyle(palette.secondaryText)
                    }
                    Slider(value: $model.bubbleRadius, in: 4...26, step: 1)
                        .tint(palette.accent)
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("气泡宽度")
                        Spacer()
                        Text("\(Int(model.bubbleWidthScale * 100))%")
                            .foregroundStyle(palette.secondaryText)
                    }
                    Slider(value: $model.bubbleWidthScale, in: 0.6...1.3, step: 0.05)
                        .tint(palette.accent)
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("边框粗细")
                        Spacer()
                        Text(String(format: "%.1f", model.bubbleBorderWidth))
                            .foregroundStyle(palette.secondaryText)
                    }
                    Slider(value: $model.bubbleBorderWidth, in: 0...2, step: 0.25)
                        .tint(palette.accent)
                }

                Button("恢复主题气泡颜色") { model.resetBubbleColors() }

                Button("恢复外观默认值") {
                    model.chatFont = .system
                    model.fontScale = 1
                    model.showsAIAvatar = true
                    model.showsHumanAvatar = false
                    model.showsAIBubble = true
                    model.bubbleOpacity = 1
                    model.bubbleRadius = 18
                    model.bubbleWidthScale = 1
                    model.bubbleBorderWidth = 0
                    model.bubbleStyle = .classic
                    model.chatWeight = 400
                    model.backgroundOpacity = 1
                    model.resetBubbleColors()
                }
            }
        }
        .tint(palette.accent)
        .scrollContentBackground(.hidden)
        .background(palette.background.ignoresSafeArea())
        .listRowBackground(palette.composer.opacity(0.72))
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
        .background(palette.background.ignoresSafeArea())
        .listRowBackground(palette.composer.opacity(0.72))
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
                    if let reset = resetText(window.resetsAt) {
                        Text(reset).font(.caption).foregroundStyle(palette.secondaryText)
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
        .background(palette.background.ignoresSafeArea())
        .listRowBackground(palette.composer.opacity(0.72))
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

    private func resetText(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: raw) else { return nil }
        let minutes = max(0, Int(date.timeIntervalSinceNow / 60))
        if minutes < 60 { return "约 \(minutes) 分钟后重置" }
        let hours = minutes / 60
        if hours < 48 { return "约 \(hours) 小时后重置" }
        return "约 \(Int((Double(hours) / 24).rounded())) 天后重置"
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
                                    Text(entry.model ?? "未知模型").lineLimit(1)
                                    Spacer()
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
        .background(palette.background.ignoresSafeArea())
        .listRowBackground(palette.composer.opacity(0.72))
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
        .background(palette.background.ignoresSafeArea())
        .listRowBackground(palette.composer.opacity(0.72))
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
