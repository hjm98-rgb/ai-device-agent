import Foundation
import SwiftUI

// MARK: - 设备目标

enum DeviceTarget: String, CaseIterable, Identifiable, Codable {
    case phone, computer, cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phone: return "本地手机"
        case .computer: return "本地电脑"
        case .cloud: return "云端电脑"
        }
    }

    var subtitle: String {
        switch self {
        case .phone: return "在当前这台 iPad / iPhone 上操作"
        case .computer: return "连接同一密钥的 Windows 电脑"
        case .cloud: return "在云服务器上替你干活"
        }
    }

    var symbol: String {
        switch self {
        case .phone: return "iphone"
        case .computer: return "desktopcomputer"
        case .cloud: return "cloud"
        }
    }

    var tint: Color {
        switch self {
        case .phone: return Color(red: 0.24, green: 0.62, blue: 1.0)
        case .computer: return Color(red: 0.16, green: 0.78, blue: 0.62)
        case .cloud: return Color(red: 0.36, green: 0.78, blue: 0.38)
        }
    }

    var capabilityText: String {
        switch self {
        case .phone:
            return "打开应用、跳转设置、搜索 App Store、复制粘贴；接上 WDA 或本机代理后可真实点击、输入、滑动。"
        case .computer:
            return "截屏、鼠标点击与拖动、键盘输入、启动软件、执行命令、打开网址。"
        case .cloud:
            return "与本地电脑相同，但整台机器在云端，随时在线。"
        }
    }
}

// MARK: - 操控通道

enum ActionChannel: String, CaseIterable, Identifiable, Codable {
    case auto, wda, troll, jail, local, guide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "自动选择"
        case .wda: return "WDA 测试通道"
        case .troll: return "巨魔商店"
        case .jail: return "越狱通道"
        case .local: return "本机代理"
        case .guide: return "引导模式"
        }
    }

    var symbol: String {
        switch self {
        case .auto: return "sparkles"
        case .wda: return "hammer"
        case .troll: return "shippingbox"
        case .jail: return "wrench.and.screwdriver"
        case .local: return "dot.radiowaves.left.and.right"
        case .guide: return "hand.point.up.left"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "按顺序探测可用通道，谁通用谁"
        case .wda: return "Apple 官方 XCUITest 通道，真实点击、输入、滑动、截屏"
        case .troll: return "巨魔商店环境下的全局触摸注入，需要已安装巨魔"
        case .jail: return "越狱环境下的底层触摸注入，需要 root 权限"
        case .local: return "连接本机 8765 端口的控制代理（蓝牙 HID / 外设也走这里）"
        case .guide: return "不越狱也能用：屏幕上高亮目标位置，一步一步带你点"
        }
    }

    var isRealTouch: Bool {
        self == .wda || self == .troll || self == .jail || self == .local
    }
}

// MARK: - 动作

struct DeviceAction: Codable, Equatable {
    var type: String
    var value: String = ""
    var x: Double? = nil
    var y: Double? = nil
    var x2: Double? = nil
    var y2: Double? = nil

    var summary: String {
        switch type {
        case "open_app": return "打开应用「\(value)」"
        case "open_url": return "打开链接 \(value)"
        case "appstore": return "在 App Store 搜索「\(value)」"
        case "settings": return "跳转到系统设置"
        case "clipboard_write": return "写入剪贴板"
        case "clipboard_read": return "读取剪贴板"
        case "tap", "click": return "点击 (\(fmt(x)), \(fmt(y))"
        case "swipe": return "滑动 (\(fmt(x)),\(fmt(y)) → \(fmt(x2)),\(fmt(y2))"
        case "type": return "输入文字「\(value)」"
        case "key": return "按键 \(value)"
        case "launch": return "启动程序 \(value)"
        case "shell": return "执行命令"
        case "screenshot": return "截取屏幕"
        case "highlight": return "高亮屏幕位置 (\(fmt(x)), \(fmt(y))"
        default: return "执行 \(type)"
        }
    }

    private func fmt(_ v: Double?) -> String { String(format: "%.2f", v ?? 0) }

    var isSensitive: Bool {
        ["shell", "open_url", "clipboard_read", "type", "key", "launch"].contains(type)
    }

    var shortLabel: String {
        switch type {
        case "tap", "click": return "点击"
        case "swipe": return "滑动"
        case "type": return "输入"
        case "shell": return "命令"
        case "open_app": return "开应用"
        case "open_url": return "开链接"
        case "screenshot": return "截屏"
        case "highlight": return "高亮"
        default: return type
        }
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: Role
    var text: String
    var thinking: String = ""
    var date = Date()
    var streaming: Bool = false
    var pendingAction: DeviceAction? = nil
    var actionDone: Bool = false
}

enum Role: String, Codable {
    case user, assistant, system
}

struct Conversation: Identifiable, Codable {
    var id = UUID()
    var title: String = "新对话"
    var messages: [ChatMessage] = []
    var createdAt = Date()
}

struct PendingApproval: Identifiable {
    var id = UUID()
    var action: DeviceAction
    var target: DeviceTarget
    var channel: ActionChannel
    var messageID: UUID
    var conversationID: UUID
}
