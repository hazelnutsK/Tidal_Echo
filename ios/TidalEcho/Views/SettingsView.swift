import SwiftUI

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
    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        List {
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
            }

            Section("消息气泡") {
                Toggle("显示 AI 头像", isOn: $model.showsAIAvatar)

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("气泡透明度")
                        Spacer()
                        Text("\(Int((model.bubbleOpacity * 100).rounded()))%")
                            .foregroundStyle(palette.secondaryText)
                    }
                    Slider(value: $model.bubbleOpacity, in: 0.25...1, step: 0.05)
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

                Button("恢复外观默认值") {
                    model.chatFont = .system
                    model.fontScale = 1
                    model.showsAIAvatar = true
                    model.bubbleOpacity = 1
                    model.bubbleRadius = 18
                }
            }
        }
        .tint(palette.accent)
        .scrollContentBackground(.hidden)
        .background(palette.background.ignoresSafeArea())
        .listRowBackground(palette.composer.opacity(0.72))
        .navigationTitle("外观与聊天")
        .navigationBarTitleDisplayMode(.inline)
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
