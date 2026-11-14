import Foundation

struct OAIMessage: Codable {
    let role: String
    let content: String
}

enum AIError: LocalizedError {
    case badURL
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL: return "地址格式不对"
        case .http(let code, let msg): return "\(code)：\(msg)"
        case .empty: return "服务没有返回内容"
        }
    }
}

enum StreamEvent {
    case thinking(String)
    case content(String)
    case error(String)
}

enum Net {

    static func makeRequest(base: String, key: String, model: String,
                            messages: [OAIMessage], stream: Bool) throws -> URLRequest {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSlash = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        let path = trimmedSlash.hasSuffix("/v1") ? "/chat/completions" : "/v1/chat/completions"
        guard let url = URL(string: trimmedSlash + path) else { throw AIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": 0.7,
            "stream": stream
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    static func chat(base: String, key: String, model: String,
                     messages: [OAIMessage]) async throws -> String {
        let req = try makeRequest(base: base, key: key, model: model, messages: messages, stream: false)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AIError.empty }
        if http.statusCode != 200 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String } ?? "请求被拒绝"
            throw AIError.http(http.statusCode, msg)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any]
        else { throw AIError.empty }
        let content = (msg["content"] as? String) ?? ""
        let reasoning = (msg["reasoning_content"] as? String) ?? (msg["reasoning"] as? String) ?? ""
        if content.isEmpty && reasoning.isEmpty { throw AIError.empty }
        if content.isEmpty { return reasoning }
        return reasoning.isEmpty ? content : content
    }

    /// 流式请求，边收边更新「思考」和「正文」两块内容
    static func stream(base: String, key: String, model: String,
                       messages: [OAIMessage]) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = try makeRequest(base: base, key: key, model: model,
                                              messages: messages, stream: true)
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        continuation.yield(.error("服务返回 \(code)，请检查密钥或重新选择模型"))
                        continuation.finish()
                        return
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        if let err = obj["error"] as? [String: Any],
                           let m = err["message"] as? String {
                            continuation.yield(.error(m))
                            break
                        }
                        guard let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any]
                        else { continue }
                        let think = (delta["reasoning_content"] as? String)
                            ?? (delta["reasoning"] as? String)
                            ?? (delta["reasoning_text"] as? String)
                        if let think = think, !think.isEmpty {
                            continuation.yield(.thinking(think))
                        }
                        if let c = delta["content"] as? String, !c.isEmpty {
                            continuation.yield(.content(c))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
