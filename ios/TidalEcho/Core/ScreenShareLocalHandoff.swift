import Foundation
import Network
import UIKit

@MainActor
enum ScreenShareLocalHandoff {
    static let port = NWEndpoint.Port(rawValue: 49_271)!

    private static let queue = DispatchQueue(label: "TidalEcho.ScreenShareHandoff")
    private static var listener: NWListener?
    private static var payload = Data()
    private static var expirationTask: Task<Void, Never>?
    private static var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    static func publish(_ text: String, expiresIn: Int) -> Bool {
        stop()
        guard let data = text.data(using: .utf8) else { return false }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
            let newListener = try NWListener(using: parameters, on: port)
            let readySignal = DispatchSemaphore(value: 0)
            var didSignal = false
            var isReady = false

            payload = data
            listener = newListener
            newListener.newConnectionHandler = { connection in
                Task { @MainActor in serve(connection) }
            }
            newListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !didSignal {
                        isReady = true
                        didSignal = true
                        readySignal.signal()
                    }
                case .failed:
                    if !didSignal {
                        didSignal = true
                        readySignal.signal()
                    }
                default:
                    break
                }
            }
            newListener.start(queue: queue)

            guard readySignal.wait(timeout: .now() + 2) == .success, isReady else {
                stop()
                return false
            }

            backgroundTask = UIApplication.shared.beginBackgroundTask(
                withName: "TidalEcho.ScreenShareHandoff"
            ) {
                Task { @MainActor in stop() }
            }
            let lifetime = max(30, min(expiresIn, 600))
            expirationTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(lifetime) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                stop()
            }
            return true
        } catch {
            stop()
            return false
        }
    }

    static func stop() {
        expirationTask?.cancel()
        expirationTask = nil
        listener?.cancel()
        listener = nil
        payload = Data()
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    private static func serve(_ connection: NWConnection) {
        guard case let .hostPort(host, _) = connection.endpoint,
              ["127.0.0.1", "::1"].contains(String(describing: host)),
              !payload.isEmpty else {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        connection.send(
            content: payload,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in
                connection.cancel()
                Task { @MainActor in stop() }
            }
        )
    }
}
