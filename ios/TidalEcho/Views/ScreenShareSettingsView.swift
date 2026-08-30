import ReplayKit
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ScreenShareSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: AppModel
    @State private var preparation: ScreenSharePreparation?
    @State private var probeStatus: ScreenShareProbeStatus?
    @State private var isPreparing = false
    @State private var isCheckingProbe = false
    @State private var errorText: String?

    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        List {
            Section("给 Altair 看一眼") {
                Text("这不是持续录像。共享开始后会等你离开系统面板，再取一张压缩画面送进当前对话，然后自动结束。")

                Button {
                    Task { await prepare() }
                } label: {
                    HStack {
                        Label(
                            preparation == nil ? "准备一次共享" : "重新生成临时票据",
                            systemImage: "key.viewfinder"
                        )
                        Spacer()
                        if isPreparing { ProgressView() }
                    }
                }
                .disabled(isPreparing)

                if let preparation {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("临时票据已复制")
                                .font(.subheadline.weight(.semibold))
                            Text("约 \(max(1, preparation.expiresIn / 60)) 分钟内有效")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                        }
                        Spacer()
                        BroadcastPickerButton()
                            .frame(width: 58, height: 58)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("打开系统屏幕共享")
                    }
                }
            }

            Section("App Group 体检") {
                if let preparation {
                    if preparation.localWriteSucceeded {
                        probeStatusLabel
                    } else {
                        Label("主 App 无法写入共享容器", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await checkProbe() }
                    } label: {
                        HStack {
                            Label("检查体检结果", systemImage: "stethoscope")
                            Spacer()
                            if isCheckingProbe { ProgressView() }
                        }
                    }
                    .disabled(isCheckingProbe)
                } else {
                    Text("点“准备一次共享”后，主 App 会写入一个随机暗号。录屏扩展必须读到同一个暗号，才算 App Group 真的可用。")
                        .foregroundStyle(palette.secondaryText)
                }
            } footer: {
                Text("如果 AltStore 在安装阶段就因 App Groups entitlement 报错，说明这条免费签名路径没有把能力签进去；若能安装，请完成一次共享再看这里。")
            }

            Section("怎么用") {
                Label("先点“准备一次共享”", systemImage: "1.circle")
                Label("点右侧系统广播按钮，再选 Tidal Echo", systemImage: "2.circle")
                Label("在配置页点“粘贴票据并开始”", systemImage: "3.circle")
                Label("倒计时后切到想给我看的页面", systemImage: "4.circle")
            }

            Section("你始终看得见") {
                Label("共享期间系统会显示红色录制标记", systemImage: "record.circle")
                Label("只上传一张 JPEG，不采集麦克风或 App 音频", systemImage: "photo")
                Label("票据一次有效，不包含你的长期 Relay 密钥", systemImage: "lock.shield")
                Label("随时可从控制中心停止", systemImage: "xmark.circle")
            }
        }
        .tint(palette.accent)
        .scrollContentBackground(.hidden)
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("屏幕共享")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, preparation != nil else { return }
            Task { await checkProbe(silent: true) }
        }
        .alert(
            "没有准备好",
            isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )
        ) {
            Button("好", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    @MainActor
    private func prepare() async {
        isPreparing = true
        defer { isPreparing = false }
        do {
            let value = try await model.prepareScreenShare()
            UIPasteboard.general.setItems(
                [[UTType.utf8PlainText.identifier: value.pastePayload]],
                options: [
                    .localOnly: true,
                    .expirationDate: Date().addingTimeInterval(TimeInterval(value.expiresIn))
                ]
            )
            preparation = value
            probeStatus = try? await model.screenShareProbeStatus(probeID: value.probeID)
        } catch is CancellationError {
            return
        } catch {
            errorText = error.localizedDescription
        }
    }

    @ViewBuilder
    private var probeStatusLabel: some View {
        switch probeStatus?.status {
        case "passed":
            Label("验证通过：主 App 和录屏扩展读到了同一暗号", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case "failed":
            Label(probeFailureText, systemImage: "xmark.seal.fill")
                .foregroundStyle(.red)
        default:
            Label("主 App 已写入暗号，等待录屏扩展读取", systemImage: "hourglass")
                .foregroundStyle(palette.secondaryText)
        }
    }

    private var probeFailureText: String {
        switch probeStatus?.reason {
        case "extension_could_not_read_group":
            return "验证失败：录屏扩展读不到共享容器"
        case "marker_mismatch":
            return "验证失败：主 App 与扩展读到的暗号不同"
        case "main_app_did_not_supply_marker":
            return "验证失败：主 App 没有生成暗号"
        default:
            return "验证失败：App Group 没有正确共享"
        }
    }

    @MainActor
    private func checkProbe(silent: Bool = false) async {
        guard let preparation else { return }
        isCheckingProbe = true
        defer { isCheckingProbe = false }
        do {
            probeStatus = try await model.screenShareProbeStatus(probeID: preparation.probeID)
        } catch is CancellationError {
            return
        } catch {
            if !silent { errorText = error.localizedDescription }
        }
    }
}

private struct BroadcastPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = uploadExtensionBundleIdentifier
        picker.showsMicrophoneButton = false
        picker.tintColor = .label
        return picker
    }

    func updateUIView(_ picker: RPSystemBroadcastPickerView, context: Context) {
        picker.preferredExtension = uploadExtensionBundleIdentifier
        picker.showsMicrophoneButton = false
    }

    private var uploadExtensionBundleIdentifier: String {
        "\(Bundle.main.bundleIdentifier ?? "com.tidalecho.personal").ScreenShareUpload"
    }
}
