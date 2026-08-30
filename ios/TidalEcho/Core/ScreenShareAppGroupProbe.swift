import Foundation

enum ScreenShareAppGroupProbe {
    static let markerKey = "tidalEcho.screenShare.appGroupProbe"
    static let handoffKey = "tidalEcho.screenShare.handoff"

    static var groupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "TidalEchoAppGroupIdentifier") as? String ?? ""
    }

    static func write(marker: String) -> Bool {
        guard !groupIdentifier.isEmpty,
              let defaults = UserDefaults(suiteName: groupIdentifier) else { return false }
        defaults.set(marker, forKey: markerKey)
        defaults.synchronize()
        return defaults.string(forKey: markerKey) == marker
    }

    static func writeHandoff(_ payload: String) -> Bool {
        guard !groupIdentifier.isEmpty,
              let defaults = UserDefaults(suiteName: groupIdentifier) else { return false }
        defaults.set(payload, forKey: handoffKey)
        defaults.synchronize()
        return defaults.string(forKey: handoffKey) == payload
    }

    static func clearHandoff() {
        guard !groupIdentifier.isEmpty,
              let defaults = UserDefaults(suiteName: groupIdentifier) else { return }
        defaults.removeObject(forKey: handoffKey)
        defaults.synchronize()
    }
}
