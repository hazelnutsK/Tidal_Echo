import CoreImage
import CoreMedia
import Foundation
import Network
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private var startedAt = Date()
    private var uploadURL: URL?
    private var ticket = ""
    private var appGroupProbe = "__missing__"
    private var didStartUpload = false

    override func broadcastStarted(withSetupInfo _: [String: NSObject]?) {
        didStartUpload = false
        appGroupProbe = "__missing__"
        guard let handoff = fetchLocalHandoff(),
              handoff.version == 1,
              let relayURL = URL(string: handoff.relayURL),
              relayURL.scheme?.lowercased() == "https",
              !handoff.ticket.isEmpty else {
            finish("录屏扩展没有从 Tidal Echo 取到本机票据。请回到 App 重新点“准备一次共享”，并在票据有效期内开始。", code: 2)
            return
        }
        startedAt = Date()
        self.uploadURL = ["app", "screen-share", "frame"].reduce(relayURL) {
            $0.appendingPathComponent($1)
        }
        self.ticket = handoff.ticket
        self.appGroupProbe = handoff.probeMarker
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        guard sampleBufferType == .video,
              !didStartUpload,
              Date().timeIntervalSince(startedAt) >= 3,
              let uploadURL,
              let jpeg = makeJPEG(from: sampleBuffer) else { return }

        didStartUpload = true
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(ticket)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("TidalEcho-ReplayKit/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue(appGroupProbe, forHTTPHeaderField: "X-TidalEcho-App-Group-Probe")

        session.uploadTask(with: request, from: jpeg) { [weak self] _, response, error in
            guard let self else { return }
            if let error {
                self.finish("画面没有送达：\(error.localizedDescription)", code: 3)
                return
            }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                self.finish("画面没有送达（HTTP \(code)），请回到 Tidal Echo 重试。", code: 4)
                return
            }
            self.finish("这一眼已经送达，屏幕共享已结束。", code: 0)
        }.resume()
    }

    override func broadcastFinished() {
        session.invalidateAndCancel()
    }

    private func fetchLocalHandoff() -> ScreenShareHandoff? {
        let queue = DispatchQueue(label: "TidalEcho.ScreenShareClaim")
        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: 49_271)!,
            using: .tcp
        )
        let finished = DispatchSemaphore(value: 0)
        var received = Data()
        var didFinish = false

        func finish() {
            guard !didFinish else { return }
            didFinish = true
            finished.signal()
        }

        func receiveNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
                data, _, isComplete, error in
                if let data { received.append(data) }
                if isComplete || error != nil {
                    finish()
                } else {
                    receiveNext()
                }
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                receiveNext()
            case .failed, .cancelled:
                finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
        guard finished.wait(timeout: .now() + 3) == .success else {
            connection.cancel()
            return nil
        }
        connection.cancel()
        return try? JSONDecoder().decode(ScreenShareHandoff.self, from: received)
    }

    private func makeJPEG(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        if let orientation = CMGetAttachment(
            sampleBuffer,
            key: RPVideoSampleOrientationKey as CFString,
            attachmentModeOut: nil
        ) as? NSNumber {
            image = image.oriented(forExifOrientation: orientation.int32Value)
        }

        let longestSide = max(image.extent.width, image.extent.height)
        if longestSide > 720 {
            let scale = 720 / longestSide
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return context.jpegRepresentation(
            of: image,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
    }

    private func finish(_ message: String, code: Int) {
        finishBroadcastWithError(NSError(
            domain: "TidalEcho.ScreenShare",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        ))
    }
}

private struct ScreenShareHandoff: Decodable {
    let version: Int
    let relayURL: String
    let ticket: String
    let expiresAt: String
    let probeMarker: String
}
