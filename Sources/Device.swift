import Foundation
import UIKit

struct Endpoints {
    var pc: String
    var cloud: String
    var wda: String
    var local: String = "http://127.0.0.1:8765"
    var token: String
}

enum Device {

    static func run(_ a: DeviceAction, target: DeviceTarget, channel: ActionChannel,
                    ep: Endpoints) async -> String {
        switch target {
        case .computer:
            return await remote(a, base: ep.pc, ep: ep, label: "电脑")
        case .cloud:
            return await remote(a, base: ep.cloud, ep: ep, label: "云端电脑")
        case .phone:
            let ch = await resolve(channel, ep: ep)
            switch ch {
            case .wda:
                return await wdaRun(a, ep: ep)
            case .troll, .jail:
                return await inject(a, channel: ch, ep: ep)
            case .local:
                return await inject(a, channel: .local, ep: ep)
            default:
                return await localRun(a, ep: ep)
            }
        }
    }

    // MARK: 通道探测

    static func resolve(_ channel: ActionChannel, ep: Endpoints) async -> ActionChannel {
        if channel != .auto { return channel }
        if await ping(ep.wda + "/status") { return .wda }
        if await ping(ep.local + "/health") { return .local }
        return .guide
    }

    static func ping(_ urlString: String) async -> Bool {
        guard let u = URL(string: urlString) else { return false }
        var req = URLRequest(url: u)
        req.timeoutInterval = 2.5
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    // MARK: 本机直接动作（所有通道通用）

    private static func openSystemURL(_ urlString: String, fallback: String) async -> String {
        guard let url = URL(string: urlString) else { return "链接不合法" }
        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:]) { result in
                    cont.resume(returning: result)
                }
            }
        }
        if ok { return fallback }
        if let alt = URL(string: "https://www.apple.com") {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async {
                    UIApplication.shared.open(alt, options: [:]) { _ in cont.resume() }
                }
            }
        }
        return "系统拒绝了这个跳转，已打开 Safari"
    }

    static func scheme(for app: String) -> String? {
        let map: [String: String] = [
            "微信": "weixin://", "wechat": "weixin://", "weixin": "weixin://",
            "qq": "mqq://", "QQ": "mqq://",
            "支付宝": "alipay://", "alipay": "alipay://",
            "备忘录": "mobilenotes://", "notes": "mobilenotes://",
            "设置": "App-Prefs:", "settings": "App-Prefs:",
            "b站": "bilibili://", "哔哩哔哩": "bilibili://", "bilibili": "bilibili://",
            "抖音": "snssdk1128://", "douyin": "snssdk1128://",
            "小红书": "xhsdiscover://", "xiaohongshu": "xhsdiscover://",
            "淘宝": "taobao://", "taobao": "taobao://",
            "京东": "openapp.jdmobile://", "jd": "openapp.jdmobile://",
            "instagram": "instagram://", "youtube": "youtube://"
        ]
        return map[app] ?? map[app.lowercased()]
    }

    private static func localRun(_ a: DeviceAction, ep: Endpoints) async -> String {
        switch a.type {
        case "open_app":
            if let s = scheme(for: a.value), !s.isEmpty {
                return await openSystemURL(s, fallback: "已打开\(a.value)")
            }
            return await openSystemURL("itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?term=" +
                                       percent(a.value), fallback: "已跳 App Store 搜索 \(a.value)")
        case "open_url":
            return await openSystemURL(a.value, fallback: "已打开链接")
        case "appstore":
            return await openSystemURL("itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?term=" +
                                       percent(a.value), fallback: "已在 App Store 搜索 \(a.value)")
        case "settings":
            return await openSystemURL(UIApplication.openSettingsURLString, fallback: "已打开设置")
        case "clipboard_write":
            await MainActor.run { UIPasteboard.general.string = a.value }
            return "已写入剪贴板"
        case "clipboard_read":
            let s = await MainActor.run { UIPasteboard.general.string ?? "" }
            return s.isEmpty ? "剪贴板是空的" : "剪贴板内容：\(s)"
        case "tap", "click", "swipe", "type", "screenshot":
            return "这一步需要真实触摸通道。已经在「\(标语(ActionChannel.auto))」里自动备选：WDA、巨魔、越狱或本机代理，都未连通时会转成引导模式。"
        default:
            return "这个动作在手机上暂时没有对应实现"
        }
    }

    private static func 标语(_ c: ActionChannel) -> String { c.title }

    private static func percent(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    // MARK: WDA

    private static var wdaSessionID: String?

    private static func wdaCall(_ path: String, method: String = "GET",
                                body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let url = URL(string: path.hasPrefix("http") ? path : Ep + path) else { throw AIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode < 300 else {
            throw AIError.http((resp as? HTTPURLResponse)?.statusCode ?? 0, "WDA 无响应")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static var Ep = "http://127.0.0.1:8100"

    private static func wdaSession(_ ep: Endpoints) async throws -> String {
        if let s = wdaSessionID { return s }
        Ep = ep.wda
        let dict = try await wdaCall(ep.wda + "/session", method: "POST",
                                     body: ["capabilities": ["alwaysMatch": [:] as [String: Any]]])
        let value = dict["value"] as? [String: Any]
        let sid = (value?["sessionId"] as? String) ?? (dict["sessionId"] as? String) ?? ""
        if sid.isEmpty { throw AIError.empty }
        wdaSessionID = sid
        return sid
    }

    private static func wdaSize(_ ep: Endpoints) async -> (Double, Double) {
        do {
            let sid = try await wdaSession(ep)
            let d = try await wdaCall(ep.wda + "/session/" + sid + "/window/size")
            if let v = d["value"] as? [String: Any],
               let w = v["width"] as? Double, let h = v["height"] as? Double {
                return (w, h)
            }
        } catch { }
        return (768, 1024)
    }

    private static func wdaRun(_ a: DeviceAction, ep: Endpoints) async -> String {
        do {
            let sid = try await wdaSession(ep)
            let base = ep.wda + "/session/" + sid
            switch a.type {
            case "tap", "click":
                let (w, h) = await wdaSize(ep)
                var px = a.x ?? 0.5
                var py = a.y ?? 0.5
                if px <= 1 && py <= 1 { px = px * w; py = py * h }
                _ = try await wdaCall(base + "/actions", method: "POST", body: [
                    "actions": [[
                        "type": "pointer", "id": "finger1", "parameters": ["pointerType": "touch"],
                        "actions": [
                            ["type": "pointerMove", "duration": 0, "x": px, "y": py],
                            ["type": "pointerDown", "button": 0],
                            ["type": "pause", "duration": 0.12],
                            ["type": "pointerUp", "button": 0]
                        ]
                    ]]
                ])
                return "已真实点击 (\(Int(px)), \(Int(py)))"
            case "swipe":
                let (w, h) = await wdaSize(ep)
                var sx = a.x ?? 0.5, sy = a.y ?? 0.8
                var ex = a.x2 ?? 0.5, ey = a.y2 ?? 0.2
                if sx <= 1 { sx *= w }; if sy <= 1 { sy *= h }
                if ex <= 1 { ex *= w }; if ey <= 1 { ey *= h }
                _ = try await wdaCall(base + "/actions", method: "POST", body: [
                    "actions": [[
                        "type": "pointer", "id": "finger1", "parameters": ["pointerType": "touch"],
                        "actions": [
                            ["type": "pointerMove", "duration": 0, "x": sx, "y": sy],
                            ["type": "pointerDown", "button": 0],
                            ["type": "pointerMove", "duration": 0.4, "x": ex, "y": ey],
                            ["type": "pointerUp", "button": 0]
                        ]
                    ]]
                ])
                return "已真实滑动"
            case "type":
                _ = try await wdaCall(base + "/wda/keys", method: "POST", body: ["value": [a.value]])
                return "已输入文字"
            case "screenshot":
                let d = try await wdaCall(ep.wda + "/screenshot")
                let has = (d["value"] as? String)?.isEmpty == false
                return has ? "已截取手机屏幕" : "截屏没有返回画面"
            case "open_app":
                let bundles = ["微信": "com.tencent.xin", "qq": "com.tencent.mqq",
                               "设置": "com.apple.Preferences", "备忘录": "com.apple.mobilenotes",
                               "safari": "com.apple.mobilesafari", "照片": "com.apple.mobileslideshow"]
                if let b = bundles[a.value] {
                    _ = try await wdaCall(base + "/wda/apps/launch", method: "POST", body: ["bundleId": b])
                    return "已真实启动 \(a.value)"
                }
                return await localRun(a, ep: ep)
            default:
                return await localRun(a, ep: ep)
            }
        } catch {
            return "WDA 没连上（\(error.localizedDescription)），改用直接跳转：" + (await localRun(a, ep: ep))
        }
    }

    // MARK: 巨魔 / 越狱 / 本机代理

    private static func inject(_ a: DeviceAction, channel: ActionChannel, ep: Endpoints) async -> String {
        guard let u = URL(string: ep.local + "/api/inject") else { return "本机代理地址不对" }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["type": a.type, "value": a.value, "channel": channel.rawValue,
                                   "token": ep.token]
        if let x = a.x { body["x"] = x }
        if let y = a.y { body["y"] = y }
        if let x2 = a.x2 { body["x2"] = x2 }
        if let y2 = a.y2 { body["y2"] = y2 }
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                return "本机代理返回 \(code)，这次改走跳转：" + (await localRun(a, ep: ep))
            }
            let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let msg = (obj["message"] as? String) ?? "已执行"
            return msg
        } catch {
            return "本机代理未连通，这次改走跳转：" + (await localRun(a, ep: ep))
        }
    }

    // MARK: 电脑 / 云端

    private static func remote(_ a: DeviceAction, base: String, ep: Endpoints, label: String) async -> String {
        let root = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard !root.isEmpty, let u = URL(string: root + "/api/action") else {
            return "还没有填\(label)的地址"
        }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 40
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["type": a.type, "value": a.value, "token": ep.token]
        if let x = a.x { body["x"] = x }
        if let y = a.y { body["y"] = y }
        if let x2 = a.x2 { body["x2"] = x2 }
        if let y2 = a.y2 { body["y2"] = y2 }
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return "\(label)没有回应" }
            if http.statusCode == 401 { return "密钥对不上，请确认\(label)上填的是同一把密钥" }
            guard http.statusCode == 200 else { return "\(label)返回 \(http.statusCode)" }
            let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            return (obj["message"] as? String) ?? "\(label)已执行"
        } catch {
            return "连不上\(label)：\(error.localizedDescription)"
        }
    }
}
