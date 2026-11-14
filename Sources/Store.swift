import Foundation
import SwiftUI

struct FreeModel: Identifiable, Codable {
    var id: String
    var name: String
    var note: String = ""
    var size: String = ""
}

@MainActor
final class Store: ObservableObject {

    @Published var name: String = ""
    @Published var ready: Bool = false
    @Published var splashing: Bool = false

    @Published var apiBase: String = "https://api.openai.com/v1"
    @Published var apiKey: String = ""
    @Published var model: String = "gpt-4o-mini"
    @Published var verified: Bool = false

    @Published var target: DeviceTarget = .phone
    @Published var channel: ActionChannel = .auto
    @Published var pcURL: String = ""
    @Published var cloudURL: String = ""
    @Published var wdaURL: String = "http://127.0.0.1:8100"

    @Published var conversations: [Conversation] = []
    @Published var currentID: UUID? = nil
    @Published var sending: Bool = false
    @Published var pending: PendingApproval? = nil
    @Published var toast: String? = nil
    @Published var lastResult: String = ""

    @Published var freeBase: String = ""
    @Published var freeModels: [FreeModel] = []
    @Published var loadingFree: Bool = false
    @Published var usingFree: Bool = false

    private let d = UserDefaults.standard
    private var streamTask: Task<Void, Never>?

    init() {
        name = d.string(forKey: "name") ?? ""
        ready = d.bool(forKey: "ready")
        apiBase = d.string(forKey: "apiBase") ?? "https://api.openai.com/v1"
        apiKey = d.string(forKey: "apiKey") ?? ""
        model = d.string(forKey: "model") ?? "gpt-4o-mini"
        verified = d.bool(forKey: "verified")
        pcURL = d.string(forKey: "pcURL") ?? ""
        cloudURL = d.string(forKey: "cloudURL") ?? ""
        wdaURL = d.string(forKey: "wdaURL") ?? "http://127.0.0.1:8100"
        freeBase = d.string(forKey: "freeBase") ?? ""
        usingFree = d.bool(forKey: "usingFree")
        if let raw = d.string(forKey: "target"), let t = DeviceTarget(rawValue: raw) { target = t }
        if let raw = d.string(forKey: "channel"), let c = ActionChannel(rawValue: raw) { channel = c }
        if let data = d.data(forKey: "conversations"),
           let list = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = list
        }
        currentID = conversations.first?.id
    }

    func save() {
        d.set(name, forKey: "name")
        d.set(ready, forKey: "ready")
        d.set(apiBase, forKey: "apiBase")
        d.set(apiKey, forKey: "apiKey")
        d.set(model, forKey: "model")
        d.set(verified, forKey: "verified")
        d.set(pcURL, forKey: "pcURL")
        d.set(cloudURL, forKey: "cloudURL")
        d.set(wdaURL, forKey: "wdaURL")
        d.set(target.rawValue, forKey: "target")
        d.set(channel.rawValue, forKey: "channel")
        d.set(freeBase, forKey: "freeBase")
        d.set(usingFree, forKey: "usingFree")
        if let data = try? JSONEncoder().encode(conversations) {
            d.set(data, forKey: "conversations")
        }
    }

    func createProfile(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        name = trimmed.isEmpty ? "小助手" : trimmed
        ready = true
        splashing = true
        save()
    }

    // MARK: 设备与通道

    func setTarget(_ t: DeviceTarget) {
        target = t
        save()
    }

    /// 单个按钮：循环切换操控通道
    func cycleChannel() {
        let all = ActionChannel.allCases
        let idx = all.firstIndex(of: channel) ?? 0
        channel = all[(idx + 1) % all.count]
        save()
        toast = "操控通道：\(channel.title)"
    }

    var endpoints: Endpoints {
        Endpoints(pc: pcURL, cloud: cloudURL, wda: wdaURL, token: apiKey)
    }

    // MARK: 对话

    var currentConversation: Conversation? {
        guard let id = currentID else { return nil }
        return conversations.first { $0.id == id }
    }

    var currentIndex: Int? {
        guard let id = currentID else { return nil }
        return conversations.firstIndex { $0.id == id }
    }

    func newConversation() {
        let c = Conversation()
        conversations.insert(c, at: 0)
        currentID = c.id
        save()
    }

    func delete(_ c: Conversation) {
        conversations.removeAll { $0.id == c.id }
        if currentID == c.id { currentID = conversations.first?.id }
        save()
    }

    func append(_ m: ChatMessage) {
        guard let idx = currentIndex else { return }
        conversations[idx].messages.append(m)
        if m.role == .user, conversations[idx].messages.count <= 2 {
            conversations[idx].title = String(m.text.prefix(18))
        }
        save()
    }

    func mutateMessage(_ id: UUID, conversation cid: UUID? = nil, _ body: (inout ChatMessage) -> Void) {
        let targetID = cid ?? currentID
        guard let targetID = targetID,
              let idx = conversations.firstIndex(where: { $0.id == targetID }),
              let midx = conversations[idx].messages.firstIndex(where: { $0.id == id })
        else { return }
        body(&conversations[idx].messages[midx])
    }

    // MARK: 发送（带思考过程）

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sending else { return }
        if currentIndex == nil { newConversation() }
        sending = true
        defer { sending = false }

        append(ChatMessage(role: .user, text: trimmed))

        let replyID = UUID()
        append(ChatMessage(id: replyID, role: .assistant, text: "", thinking: "", streaming: true))

        let history = (currentConversation?.messages ?? [])
            .filter { $0.role != .system || $0.text.hasPrefix("已完成") }
            .suffix(12)
            .map { OAIMessage(role: $0.role == .user ? "user" : "assistant", content: $0.text) }

        var messages = [OAIMessage(role: "system", content: systemPrompt)]
        messages.append(contentsOf: history)

        let base = apiBase
        let key = usingFree ? "free" : apiKey
        let mdl = model

        var full = ""
        var think = ""

        do {
            for try await ev in Net.stream(base: base, key: key, model: mdl, messages: messages) {
                switch ev {
                case .thinking(let t):
                    think += t
                    mutateMessage(replyID) { $0.thinking = think }
                case .content(let c):
                    full += c
                    mutateMessage(replyID) {
                        let (clean, _) = Store.splitAction(full)
                        $0.text = clean.isEmpty ? full : clean
                    }
                case .error(let msg):
                    mutateMessage(replyID) {
                        $0.streaming = false
                        $0.text = $0.text.isEmpty ? "出错了：\(msg)" : $0.text
                    }
                }
            }
        } catch {
            mutateMessage(replyID) {
                $0.streaming = false
                if $0.text.isEmpty { $0.text = "出错了：\(error.localizedDescription)" }
            }
        }

        mutateMessage(replyID) { $0.streaming = false }

        if full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && think.isEmpty {
            mutateMessage(replyID) { $0.text = "这次没有收到内容，检查一下密钥或换个模型试试。" }
            save()
            return
        }

        let (clean, action) = Store.splitAction(full)
        if !clean.isEmpty {
            mutateMessage(replyID) { $0.text = clean }
        }
        if let action = action, let cid = currentID {
            mutateMessage(replyID) { $0.pendingAction = action }
            pending = PendingApproval(action: action, target: target, channel: channel,
                                      messageID: replyID, conversationID: cid)
        }
        save()
    }

    func stop() {
        streamTask?.cancel()
        sending = false
    }

    var systemPrompt: String {
        var s = """
        你是「\(name)」，运行在 Apple 设备上的中文 AI 助手。说话简洁、直接、可以开玩笑、可以像朋友一样聊。
        当前操控目标：\(target.title)，操控通道：\(channel.title)。

        """
        switch target {
        case .phone:
            s += """
            手机可执行动作：
            - open_app（value 为应用名）
            - open_url（value 为网址或链接）
            - appstore（value 为要搜索的应用名）
            - settings
            - clipboard_write（value 为文字）
            - clipboard_read
            - tap（x、y 为 0~1 的屏幕比例坐标）
            - swipe（x、y 起点，x2、y2 终点）
            - type（value 为要输入的文字）
            """
        case .computer, .cloud:
            s += """
            电脑可执行动作：
            - screenshot
            - click / tap（x、y 为像素坐标）
            - swipe（x、y 起点，x2、y2 终点）
            - type（value 为文字）
            - key（value 为 enter、esc、tab、win 等）
            - launch（value 为程序名）
            - shell（value 为命令行）
            - open_url
            """
        }
        s += """

        规则：
        1. 闲聊时正常聊天，不要输出动作。
        2. 需要操作设备时，在回复最后单独一行写：
        [[ACTION]]{"type":"open_app","value":"微信"}
        3. 一次最多一个动作，做完等用户反馈再继续。
        4. 除动作行以外全部用中文，不要解释这个格式。
        """
        return s
    }

    static func splitAction(_ text: String) -> (String, DeviceAction?) {
        guard let r = text.range(of: "[[ACTION]]") else { return (text, nil) }
        let tail = String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = tail.components(separatedBy: "\n").first ?? tail
        let clean = String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = firstLine.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = dict["type"] as? String
        else { return (clean, nil) }

        func num(_ k: String) -> Double? {
            if let v = dict[k] as? Double { return v }
            if let v = dict[k] as? Int { return Double(v) }
            if let v = dict[k] as? String { return Double(v) }
            return nil
        }
        var a = DeviceAction(type: type, value: (dict["value"] as? String) ?? "")
        a.x = num("x"); a.y = num("y"); a.x2 = num("x2"); a.y2 = num("y2")
        return (clean, a)
    }

    // MARK: 授权执行

    func approve() async {
        guard let p = pending else { return }
        pending = nil
        let result = await Device.run(p.action, target: p.target, channel: p.channel, ep: endpoints)
        lastResult = result
        mutateMessage(p.messageID, conversation: p.conversationID) { $0.actionDone = true }
        guard let idx = conversations.firstIndex(where: { $0.id == p.conversationID }) else { return }
        conversations[idx].messages.append(ChatMessage(role: .system, text: "已完成：\(result)"))
        save()
    }

    func reject() {
        pending = nil
        append(ChatMessage(role: .system, text: "已取消这次操作。"))
    }

    // MARK: 密钥

    func verifyKey() async -> Bool {
        do {
            _ = try await Net.chat(base: apiBase, key: apiKey, model: model,
                                   messages: [OAIMessage(role: "user", content: "只回复 ok")])
            verified = true
            usingFree = false
            save()
            return true
        } catch {
            verified = false
            toast = "校验失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: 免费小模型区

    func loadFreeModels() async {
        guard !freeBase.isEmpty else { toast = "先填服务器地址"; return }
        loadingFree = true
        defer { loadingFree = false }
        let root = freeBase.hasSuffix("/") ? String(freeBase.dropLast()) : freeBase
        guard let u = URL(string: root + "/api/models") else { return }
        do {
            var req = URLRequest(url: u)
            req.timeoutInterval = 20
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                toast = "服务器返回 \((resp as? HTTPURLResponse)?.statusCode ?? 0)"
                return
            }
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let arr = (obj?["models"] as? [[String: Any]]) ?? []
            freeModels = arr.compactMap { item in
                guard let id = item["id"] as? String else { return nil }
                return FreeModel(id: id,
                                 name: (item["name"] as? String) ?? id,
                                 note: (item["note"] as? String) ?? "",
                                 size: (item["size"] as? String) ?? "")
            }
            d.set(freeBase, forKey: "freeBase")
            if freeModels.isEmpty { toast = "服务器上还没有加载模型" }
        } catch {
            toast = "连不上免费服务器：\(error.localizedDescription)"
        }
    }

    func useFreeModel(_ m: FreeModel) {
        let root = freeBase.hasSuffix("/") ? String(freeBase.dropLast()) : freeBase
        apiBase = root + "/v1"
        model = m.id
        usingFree = true
        verified = true
        save()
        toast = "已切到免费模型 \(m.name)"
    }

    // MARK: 连通性

    func pingComputer() async -> Bool {
        let url = target == .cloud ? cloudURL : pcURL
        let root = url.hasSuffix("/") ? String(url.dropLast()) : url
        guard !root.isEmpty, let u = URL(string: root + "/health") else { return false }
        var req = URLRequest(url: u)
        req.timeoutInterval = 4
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    func pingWDA() async -> Bool {
        await Device.ping(wdaURL + "/status")
    }
}
