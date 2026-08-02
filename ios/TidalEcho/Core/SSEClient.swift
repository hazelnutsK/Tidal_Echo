import Foundation

final class SSEClient {
    private var task: Task<Void, Never>?

    func start(
        request: URLRequest,
        onEvent: @escaping @Sendable (Data) async -> Void,
        onConnection: @escaping @Sendable (Bool) async -> Void
    ) {
        stop()
        task = Task {
            while !Task.isCancelled {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode) else {
                        throw APIError.invalidResponse
                    }
                    await onConnection(true)

                    var dataLines: [String] = []
                    for try await line in bytes.lines {
                        if Task.isCancelled { return }
                        if line.isEmpty {
                            if !dataLines.isEmpty,
                               let data = dataLines.joined(separator: "\n").data(using: .utf8) {
                                await onEvent(data)
                            }
                            dataLines.removeAll(keepingCapacity: true)
                        } else if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        }
                    }
                } catch {
                    if Task.isCancelled { return }
                }

                await onConnection(false)
                do {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

