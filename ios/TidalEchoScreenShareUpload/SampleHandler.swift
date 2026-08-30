import CoreImage
import CoreMedia
import Foundation
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

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        startedAt = Date()
        didStartUpload = false
        appGroupProbe = "__missing__"

        let groupIdentifier = Bundle.main.object(
            forInfoDictionaryKey: "TidalEchoAppGroupIdentifier"
        ) as? String ?? ""
        var groupHandoff: ScreenShareHandoff?
        if !groupIdentifier.isEmpty,
           let defaults = UserDefaults(suiteName: groupIdentifier) {
            if let marker = defaults.string(forKey: "tidalEcho.screenShare.appGroupProbe"),
               !marker.isEmpty {
                appGroupProbe = marker
            }
            if let payload = defaults.string(forKey: "tidalEcho.screenShare.handoff"),
               let data = payload.data(using: .utf8) {
                groupHandoff = try? JSONDecoder().decode(ScreenShareHandoff.self, from: data)
                defaults.removeObject(forKey: "tidalEcho.screenShare.handoff")
                defaults.synchronize()
            }
        }

        let relayString = setupInfo?["relayURL"] as? String ?? groupHandoff?.relayURL
        let handoffTicket = setupInfo?["ticket"] as? String ?? groupHandoff?.ticket
        guard let relayString,
              let relayURL = URL(string: relayString),
              relayURL.scheme?.lowercased() == "https",
              let ticket = handoffTicket,
              !ticket.isEmpty else {
            finish("录屏扩展没有读到共享票据。请回到 Tidal Echo 重新点“准备一次共享”；若仍失败，App Group 可能没有签入。", code: 2)
            return
        }
        self.uploadURL = ["app", "screen-share", "frame"].reduce(relayURL) {
            $0.appendingPathComponent($1)
        }
        self.ticket = ticket
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
    let relayURL: String
    let ticket: String
}
