import Foundation

/// Transcribes by POSTing the audio to a running `whisper-server` instance,
/// which keeps the model resident — no per-call model reload. Pure HTTP, so it
/// is testable against any URL and carries no process-lifecycle concerns.
public struct WhisperServerTranscriptionEngine: TranscriptionEngine {
    public var baseURL: URL
    public var language: String?
    public var timeoutSeconds: TimeInterval

    public init(baseURL: URL, language: String?, timeoutSeconds: TimeInterval = 60) {
        self.baseURL = baseURL
        self.language = language
        self.timeoutSeconds = timeoutSeconds
    }

    public func transcribe(audioFile: URL) async throws -> String {
        let audio = try Data(contentsOf: audioFile)
        let boundary = "----LocalDictation-\(UUID().uuidString)"

        var request = URLRequest(url: baseURL.appendingPathComponent("inference"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(boundary: boundary, audio: audio, language: language)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranscriptionError.processFailed(-1, "whisper-server request failed: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw TranscriptionError.processFailed(Int32(status), "whisper-server returned HTTP \(status)")
        }

        let text = (try? JSONDecoder().decode(InferenceResponse.self, from: data))?.text
            ?? String(data: data, encoding: .utf8)
            ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptionError.emptyTranscript
        }
        return trimmed
    }

    public static func multipartBody(boundary: String, audio: Data, language: String?) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.appendString("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }

        body.appendString("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(audio)
        body.appendString("\r\n")
        field("response_format", "json")
        field("temperature", "0")
        if let language = language?.trimmingCharacters(in: .whitespacesAndNewlines),
           !language.isEmpty, language.lowercased() != "auto" {
            field("language", language)
        }
        body.appendString("--\(boundary)--\r\n")
        return body
    }
}

private struct InferenceResponse: Decodable {
    let text: String
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
