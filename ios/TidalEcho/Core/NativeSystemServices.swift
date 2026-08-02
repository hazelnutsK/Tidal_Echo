@preconcurrency import AVFoundation
@preconcurrency import CallKit
import Foundation
import UIKit
@preconcurrency import UserNotifications

struct IncomingCallInvite: Identifiable, Equatable {
    let id: Int
    let uuid: UUID
    let text: String
}

@MainActor
final class NativeCallCoordinator: NSObject, ObservableObject, CXProviderDelegate {
    static let shared = NativeCallCoordinator()

    @Published private(set) var acceptedInvite: IncomingCallInvite?
    @Published private(set) var ringingInvite: IncomingCallInvite?
    @Published private(set) var lastCallKitError: String?

    private let provider: CXProvider
    private let controller = CXCallController()
    private var invites: [UUID: IncomingCallInvite] = [:]
    private var activeUUID: UUID?

    override init() {
        let configuration = CXProviderConfiguration(localizedName: "Tidal Echo")
        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        configuration.includesCallsInRecents = false
        configuration.supportedHandleTypes = [.generic]
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    func reportIncoming(messageID: Int, text: String) {
        guard ringingInvite == nil, acceptedInvite == nil, activeUUID == nil else { return }
        let invite = IncomingCallInvite(id: messageID, uuid: UUID(), text: text)
        invites[invite.uuid] = invite
        ringingInvite = invite
        activeUUID = invite.uuid

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: "小克")
        update.localizedCallerName = "小克"
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        provider.reportNewIncomingCall(with: invite.uuid, update: update) { error in
            Task { @MainActor in
                if let error {
                    self.lastCallKitError = error.localizedDescription
                    NativeNotificationCenter.shared.scheduleIncomingCall(invite)
                } else {
                    self.lastCallKitError = nil
                }
            }
        }
    }

    func acceptRingingCall() {
        guard let invite = ringingInvite else { return }
        ringingInvite = nil
        acceptedInvite = invite
        activeUUID = invite.uuid
        let transaction = CXTransaction(action: CXAnswerCallAction(call: invite.uuid))
        controller.request(transaction) { _ in }
    }

    func declineRingingCall() {
        guard let invite = ringingInvite else { return }
        ringingInvite = nil
        acceptedInvite = nil
        endSystemCall(uuid: invite.uuid)
        activeUUID = nil
    }

    func acceptFromNotification(messageID: Int, text: String) {
        let invite = ringingInvite?.id == messageID
            ? ringingInvite!
            : IncomingCallInvite(id: messageID, uuid: UUID(), text: text)
        invites[invite.uuid] = invite
        ringingInvite = nil
        acceptedInvite = invite
        activeUUID = invite.uuid
    }

    func declineFromNotification(messageID: Int) {
        if ringingInvite?.id == messageID { ringingInvite = nil }
        if acceptedInvite?.id == messageID { acceptedInvite = nil }
        if let activeUUID { endSystemCall(uuid: activeUUID) }
    }

    func consumeAcceptedInvite() {
        acceptedInvite = nil
    }

    func finishCurrentCall() {
        guard let activeUUID else { return }
        endSystemCall(uuid: activeUUID)
        self.activeUUID = nil
        ringingInvite = nil
        acceptedInvite = nil
    }

    private func endSystemCall(uuid: UUID) {
        let transaction = CXTransaction(action: CXEndCallAction(call: uuid))
        controller.request(transaction) { _ in }
    }

    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor [weak self] in
            self?.activeUUID = nil
            self?.ringingInvite = nil
            self?.acceptedInvite = nil
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor [weak self] in
            guard let self else { action.fail(); return }
            if let invite = self.invites[action.callUUID] {
                self.ringingInvite = nil
                self.acceptedInvite = invite
                self.activeUUID = action.callUUID
                action.fulfill()
            } else {
                action.fail()
            }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor [weak self] in
            self?.invites.removeValue(forKey: action.callUUID)
            if self?.activeUUID == action.callUUID { self?.activeUUID = nil }
            self?.ringingInvite = nil
            self?.acceptedInvite = nil
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {}
    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}
}

@MainActor
final class NativeNotificationCenter: ObservableObject {
    static let shared = NativeNotificationCenter()

    static let messageCategory = "TIDAL_MESSAGE"
    static let callCategory = "TIDAL_CALL"
    static let answerAction = "TIDAL_ANSWER"
    static let declineAction = "TIDAL_DECLINE"

    @Published private(set) var authorizationText = "未开启"
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "tidalEcho.nativeNotifications") }
    }

    var fetchHandler: (() async -> Bool)?

    private init() {
        enabled = UserDefaults.standard.bool(forKey: "tidalEcho.nativeNotifications")
        Self.registerCategories()
        Task { await refreshAuthorizationStatus() }
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            enabled = granted
            await refreshAuthorizationStatus()
            return granted
        } catch {
            enabled = false
            authorizationText = "请求失败"
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorizationText = enabled ? "已开启" : "已暂停"
        case .denied:
            authorizationText = "系统已拒绝"
            enabled = false
        case .notDetermined:
            authorizationText = "未开启"
        @unknown default:
            authorizationText = "未知"
        }
    }

    func scheduleMessage(_ message: ChatMessage) {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "小克"
        let clean = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = clean.isEmpty ? "给你发来一条消息" : String(clean.prefix(140))
        content.sound = .default
        content.categoryIdentifier = Self.messageCategory
        content.userInfo = ["type": "message", "message_id": message.id]
        let request = UNNotificationRequest(identifier: "tidal-message-\(message.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleIncomingCall(_ invite: IncomingCallInvite) {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "小克来电"
        content.body = invite.text
        content.sound = .defaultRingtone
        content.categoryIdentifier = Self.callCategory
        content.userInfo = ["type": "call", "message_id": invite.id, "text": invite.text]
        let request = UNNotificationRequest(identifier: "tidal-call-\(invite.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleTest() {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "小克"
        content.body = "原生通知已经准备好了。"
        content.sound = .default
        content.categoryIdentifier = Self.messageCategory
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "tidal-test", content: content, trigger: trigger)
        )
    }

    func handle(response: UNNotificationResponse) {
        let info = response.notification.request.content.userInfo
        guard (info["type"] as? String) == "call" else { return }
        let messageID = info["message_id"] as? Int ?? 0
        let text = info["text"] as? String ?? "小克想和你语音通话。"
        if response.actionIdentifier == Self.declineAction {
            NativeCallCoordinator.shared.declineFromNotification(messageID: messageID)
        } else {
            NativeCallCoordinator.shared.acceptFromNotification(messageID: messageID, text: text)
        }
    }

    static func registerCategories() {
        let answer = UNNotificationAction(identifier: answerAction, title: "接听", options: [.foreground])
        let decline = UNNotificationAction(identifier: declineAction, title: "拒绝", options: [.destructive])
        let call = UNNotificationCategory(
            identifier: callCategory,
            actions: [answer, decline],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let message = UNNotificationCategory(identifier: messageCategory, actions: [], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([call, message])
    }
}

final class NativeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NativeNotificationCenter.registerCategories()
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        return true
    }

    func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            guard let handler = NativeNotificationCenter.shared.fetchHandler else {
                completionHandler(.noData)
                return
            }
            completionHandler(await handler() ? .newData : .noData)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            NativeNotificationCenter.shared.handle(response: response)
            completionHandler()
        }
    }
}
