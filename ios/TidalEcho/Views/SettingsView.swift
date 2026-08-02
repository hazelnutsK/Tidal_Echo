import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()
                List {
                    Section("主题") {
                        ForEach(EchoTheme.allCases) { theme in
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) { model.theme = theme }
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
                            .listRowBackground(palette.composer.opacity(0.72))
                        }
                    }

                    Section("连接") {
                        LabeledContent("Relay", value: model.savedServerAddress)
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                            .listRowBackground(palette.composer.opacity(0.72))
                        Button("重新加载聊天记录") {
                            Task { await model.refresh() }
                        }
                        .listRowBackground(palette.composer.opacity(0.72))
                    }

                    Section {
                        Button("退出并清除密钥", role: .destructive) {
                            dismiss()
                            model.logout()
                        }
                        .listRowBackground(palette.composer.opacity(0.72))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Tidal Echo")
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
