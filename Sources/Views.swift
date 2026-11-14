import SwiftUI
import UIKit

// MARK: - 入口

@main
struct AgentApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.05, blue: 0.09),
                                    Color(red: 0.07, green: 0.09, blue: 0.15)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if !store.ready {
                SetupView()
            } else if store.splashing {
                SplashView()
            } else {
                MainView()
            }
        }
    }
}

// MARK: - 生成图标

struct IconBadge: View {
    var name: String
    var size: CGFloat

    private var seed: Int {
        name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
    }
    private var hue: Double { Double(seed % 360) / 360.0 }
    private var monogram: String { String(name.prefix(1)).isEmpty ? "A" : String(name.prefix(1)) }

    var body: some View {
        let c1 = Color(hue: hue, saturation: 0.68, brightness: 0.38)
        let c2 = Color(hue: (hue + 0.11).truncatingRemainder(dividingBy: 1),
                       saturation: 0.82, brightness: 0.72)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(monogram)
                .font(.system(size: size * 0.44, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: c2.opacity(0.4), radius: size * 0.16, y: size * 0.04)
    }
}

// MARK: - 首次进入：取名

struct SetupView: View {
    @EnvironmentObject var store: Store
    @State private var input: String = ""
    @State private var appear = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            IconBadge(name: input.isEmpty ? "小助手" : input, size: 104)
                .scaleEffect(appear ? 1 : 0.85)
                .opacity(appear ? 1 : 0)

            VStack(spacing: 10) {
                Text("给这个助手取个名字")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text("图标会根据名字自动生成")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
            }

            TextField("比如：小豆", text: $input)
                .textFieldStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.07)))
                .foregroundStyle(.white)
                .padding(.horizontal, 40)

            Button {
                store.createProfile(input)
            } label: {
                Text("开始")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.6, blue: 1.0),
                                                      Color(red: 0.42, green: 0.36, blue: 0.95)],
                                             startPoint: .leading, endPoint: .trailing)))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { appear = true }
        }
    }
}

// MARK: - 启动页

struct SplashView: View {
    @EnvironmentObject var store: Store
    @State private var show = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            IconBadge(name: store.name, size: 116)
                .scaleEffect(show ? 1 : 0.7)
                .opacity(show ? 1 : 0)
            Text(store.name)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .opacity(show ? 1 : 0)
            Spacer()
            Text("正在准备工作区…")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.35))
                .padding(.bottom, 40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { show = true }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeInOut(duration: 0.35)) { store.splashing = false }
        }
    }
}

// MARK: - 主界面

struct MainView: View {
    @EnvironmentObject var store: Store
    @State private var showDevice = false
    @State private var showSettings = false
    @State private var showFree = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.currentID != nil {
                ChatView()
            } else {
                emptyState
            }
            if store.currentConversation?.messages.isEmpty ?? true {
                composer
            }
        }
        .sheet(isPresented: $showDevice) { DeviceSheet() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showFree) { FreeZoneView() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconBadge(name: store.name, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(store.target.title) · \(store.channel.title)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            if !store.conversations.isEmpty {
                Menu {
                    ForEach(store.conversations) { c in
                        Button(c.title.isEmpty ? "新对话" : c.title) { store.currentID = c.id }
                    }
                    Divider()
                    Button("新建对话") { store.newConversation() }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                }
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.25))
            Text("开一个新对话吧")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Button {
                store.newConversation()
            } label: {
                Text("新建对话")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Color(red: 0.24, green: 0.6, blue: 1.0)))
                    .foregroundStyle(.white)
            }
            Spacer()
            Spacer()
        }
    }

    private var composer: some View {
        ComposerBar(showDevice: $showDevice, showFree: $showFree)
    }
}

struct ComposerBar: View {
    @EnvironmentObject var store: Store
    @Binding var showDevice: Bool
    @Binding var showFree: Bool
    @State private var text: String = ""
    @State private var showKey = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { store.cycleChannel() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: store.channel.symbol).font(.system(size: 11))
                        Text(store.channel.title).font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .foregroundStyle(.white.opacity(0.75))
                }
                Button { showFree = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gift").font(.system(size: 11))
                        Text("不想花钱？点这里").font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(red: 0.36, green: 0.85, blue: 0.55).opacity(0.18)))
                    .foregroundStyle(Color(red: 0.6, green: 0.95, blue: 0.75))
                }
                if !store.verified && !store.usingFree {
                    Button { showKey = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "key.fill").font(.system(size: 11))
                            Text("填密钥").font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(red: 1.0, green: 0.8, blue: 0.3).opacity(0.16)))
                        .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.45))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                Button { showDevice = true } label: {
                    Image(systemName: store.target.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(store.target.tint)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(store.target.tint.opacity(0.14)))
                }

                TextField("说点什么，或者让它去干活…", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.07)))
                    .foregroundStyle(.white)

                Button {
                    let t = text
                    text = ""
                    Task { await store.send(t) }
                } label: {
                    Image(systemName: store.sending ? "hourglass" : "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(text.isEmpty || store.sending
                                                  ? Color.white.opacity(0.1)
                                                  : Color(red: 0.24, green: 0.6, blue: 1.0)))
                }
                .disabled(text.isEmpty || store.sending)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .sheet(isPresented: $showKey) { KeySheet() }
    }
}

// MARK: - 聊天

struct ChatView: View {
    @EnvironmentObject var store: Store
    @State private var expanded: Set<UUID> = []
    @State private var text: String = ""
    @State private var showDevice = false
    @State private var showFree = false
    @State private var showSettings = false
    @State private var showKey = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(store.currentConversation?.messages ?? []) { m in
                        MessageRow(message: m, expanded: $expanded)
                            .id(m.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: store.currentConversation?.messages.count ?? 0) { _ in
                scrollToBottom(proxy)
            }
        }
        .sheet(item: $store.pending) { p in
            ApprovalView(p: p)
        }
        .sheet(isPresented: $showDevice) { DeviceSheet() }
        .sheet(isPresented: $showFree) { FreeZoneView() }
        .safeAreaInset(edge: .bottom) { composer }
    }

    private var needsKey: Bool {
        !store.verified || store.apiKey.isEmpty
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { store.cycleChannel() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: store.channel.symbol).font(.system(size: 11))
                        Text(store.channel.title).font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .foregroundStyle(.white.opacity(0.75))
                }
                Button { showFree = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gift").font(.system(size: 11))
                        Text("不想花钱？点这里").font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(red: 0.36, green: 0.85, blue: 0.55).opacity(0.18)))
                    .foregroundStyle(Color(red: 0.6, green: 0.95, blue: 0.75))
                }
                if !store.verified && !store.usingFree {
                    Button { showKey = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "key.fill").font(.system(size: 11))
                            Text("填密钥").font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(red: 1.0, green: 0.8, blue: 0.3).opacity(0.16)))
                        .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.45))
                    }
                }
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                Button { showDevice = true } label: {
                    Image(systemName: store.target.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(store.target.tint)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(store.target.tint.opacity(0.14)))
                }
                TextField("说点什么…", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.07)))
                    .foregroundStyle(.white)
                Button {
                    let t = text
                    text = ""
                    Task { await store.send(t) }
                } label: {
                    Image(systemName: store.sending ? "hourglass" : "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(text.isEmpty || store.sending
                                                  ? Color.white.opacity(0.1)
                                                  : Color(red: 0.24, green: 0.6, blue: 1.0)))
                }
                .disabled(text.isEmpty || store.sending)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = store.currentConversation?.messages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
    }
}

struct MessageRow: View {
    @EnvironmentObject var store: Store
    var message: ChatMessage
    @Binding var expanded: Set<UUID>

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            if message.role == .system {
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
                    .frame(maxWidth: .infinity)
            } else {
                if !message.thinking.isEmpty {
                    ThinkingBlock(text: message.thinking,
                                  open: message.streaming || expanded.contains(message.id),
                                  toggle: {
                                      if expanded.contains(message.id) { expanded.remove(message.id) }
                                      else { expanded.insert(message.id) }
                                  })
                }
                if !message.text.isEmpty || message.streaming {
                    Text(message.text.isEmpty ? " " : message.text)
                        .font(.system(size: 15))
                        .foregroundStyle(message.role == .user ? .white : .white.opacity(0.92))
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(message.role == .user
                                      ? Color(red: 0.24, green: 0.6, blue: 1.0).opacity(0.85)
                                      : Color.white.opacity(0.07))
                        )
                        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                }
                if let a = message.pendingAction {
                    HStack(spacing: 6) {
                        Image(systemName: message.actionDone ? "checkmark.circle.fill" : "lock")
                            .font(.system(size: 11))
                        Text(message.actionDone ? "已执行：\(a.summary)" : "待授权：\(a.summary)")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(message.actionDone
                                     ? Color(red: 0.5, green: 0.9, blue: 0.7)
                                     : Color(red: 1.0, green: 0.78, blue: 0.35))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

struct ThinkingBlock: View {
    var text: String
    var open: Bool
    var toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: open ? "brain.fill" : "brain")
                        .font(.system(size: 11))
                    Text(open ? "思考中…" : "思考")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .foregroundStyle(Color(red: 0.62, green: 0.72, blue: 1.0))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color(red: 0.45, green: 0.55, blue: 1.0).opacity(0.12)))
            }
            .buttonStyle(.plain)

            if open {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(red: 0.5, green: 0.6, blue: 1.0).opacity(0.18), lineWidth: 1))
            }
        }
    }
}

// MARK: - 密钥卡片

struct KeyCard: View {
    @EnvironmentObject var store: Store
    @State private var key: String = ""
    @State private var base: String = ""
    @State private var model: String = ""
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill").foregroundStyle(.yellow)
                Text("先把 AI 密钥填上").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            }
            Text("填一次就会自动校验，之后所有对话都用它。")
                .font(.footnote).foregroundStyle(.white.opacity(0.45))

            TextField("接口地址，例如 https://api.openai.com/v1", text: $base)
                .padding(11).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                .foregroundStyle(.white).autocapitalization(.none).keyboardType(.URL)

            TextField("模型名，例如 gpt-4o-mini", text: $model)
                .padding(11).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                .foregroundStyle(.white).autocapitalization(.none)

            SecureField("粘贴密钥", text: $key)
                .padding(11).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                .foregroundStyle(.white).autocapitalization(.none)

            Button {
                store.apiBase = base
                store.apiKey = key
                store.model = model
                checking = true
                Task {
                    _ = await store.verifyKey()
                    checking = false
                }
            } label: {
                HStack(spacing: 6) {
                    if checking { ProgressView().tint(.white) }
                    Text(checking ? "正在校验…" : "校验并保存")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.24, green: 0.6, blue: 1.0)))
                .foregroundStyle(.white)
            }
            .disabled(key.isEmpty || checking)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.05)))
        .onAppear {
            base = store.apiBase
            model = store.model
        }
    }
}

// MARK: - 授权

struct ApprovalView: View {
    @EnvironmentObject var store: Store
    var p: PendingApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(Color.white.opacity(0.2)).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 10)

            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22)).foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("需要你授权").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    Text("\(p.target.title) · \(p.channel.title)")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(p.action.summary)
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                if !p.action.value.isEmpty && p.action.type == "shell" {
                    Text(p.action.value)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))

            HStack(spacing: 12) {
                Button {
                    store.reject()
                } label: {
                    Text("取消").font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Button {
                    Task { await store.approve() }
                } label: {
                    Text("允许").font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Color(red: 0.24, green: 0.6, blue: 1.0)))
                        .foregroundStyle(.white)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.height(300)])
        .presentationBackground(.regularMaterial)
    }
}

// MARK: - 操控设备选择

struct DeviceSheet: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(DeviceTarget.allCases) { t in
                        Button {
                            store.setTarget(t)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: t.symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(t.tint)
                                    .frame(width: 42, height: 42)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(t.tint.opacity(0.14)))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(t.title).font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text(t.subtitle).font(.caption).foregroundStyle(.white.opacity(0.45))
                                }
                                Spacer()
                                if store.target == t {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(t.tint)
                                }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(store.target == t ? 0.09 : 0.04)))
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("当前模式的真实能力")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                        Text(store.target.capabilityText)
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
                }
                .padding(16)
            }
            .background(Color(red: 0.06, green: 0.07, blue: 0.11))
            .navigationTitle("操控哪台设备")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

// MARK: - 免费模型区

struct FreeZoneView: View {
    @EnvironmentObject var store: Store
    @State private var server: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "gift.fill").foregroundStyle(Color(red: 0.55, green: 0.95, blue: 0.7))
                        Text("不想花钱？随便用")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    }
                    Text("这些小模型跑在服务器上，不用密钥、不占用你的额度。选一个就能直接聊。")
                        .font(.footnote).foregroundStyle(.white.opacity(0.45))

                    HStack(spacing: 8) {
                        TextField("免费服务器地址，如 http://1.2.3.4:8080", text: $server)
                            .padding(11)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                            .foregroundStyle(.white).autocapitalization(.none).keyboardType(.URL)
                        Button {
                            store.freeBase = server
                            Task { await store.loadFreeModels() }
                        } label: {
                            if store.loadingFree {
                                ProgressView().tint(.white).frame(width: 52, height: 40)
                            } else {
                                Text("连接").font(.system(size: 14, weight: .medium))
                                    .frame(width: 52, height: 40)
                                    .background(RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(red: 0.24, green: 0.6, blue: 1.0)))
                                    .foregroundStyle(.white)
                            }
                        }
                    }

                    if !store.freeModels.isEmpty {
                        ForEach(store.freeModels) { m in
                            Button {
                                if m.ready { store.useFreeModel(m) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "cpu")
                                        .foregroundStyle(Color(red: 0.55, green: 0.95, blue: 0.7))
                                        .frame(width: 38, height: 38)
                                        .background(RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(red: 0.55, green: 0.95, blue: 0.7).opacity(0.14)))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(m.name).font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Text(m.note.isEmpty ? m.id : m.note)
                                            .font(.caption).foregroundStyle(.white.opacity(0.45))
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(m.ready ? "可用" : "未下载")
                                            .font(.caption2)
                                            .foregroundStyle(m.ready
                                                             ? Color(red: 0.55, green: 0.95, blue: 0.7)
                                                             : .white.opacity(0.3))
                                        Text(m.size).font(.caption2).foregroundStyle(.white.opacity(0.35))
                                    }
                                }
                                .padding(13)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Text(store.freeBase.isEmpty ? "先填地址再点连接" : "点「连接」拉取服务器上的模型列表")
                            .font(.footnote).foregroundStyle(.white.opacity(0.35))
                    }

                    if store.usingFree {
                        Text("当前正在用免费模型：\(store.model)")
                            .font(.caption).foregroundStyle(Color(red: 0.55, green: 0.95, blue: 0.7))
                    }
                }
                .padding(18)
            }
            .background(Color(red: 0.06, green: 0.07, blue: 0.11))
            .navigationTitle("免费模型")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                server = store.freeBase
                if server.isEmpty == false { Task { await store.loadFreeModels() } }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var checkingPC = false
    @State private var checkingWDA = false

    var body: some View {
        NavigationStack {
            Form {
                Section("AI") {
                    TextField("接口地址", text: $store.apiBase)
                    TextField("模型", text: $store.model)
                    SecureField("密钥", text: $store.apiKey)
                    Button("重新校验密钥") {
                        Task { _ = await store.verifyKey() }
                    }
                }
                Section("电脑") {
                    TextField("本地电脑地址，如 http://192.168.1.5:8765", text: $store.pcURL)
                    TextField("云端电脑地址", text: $store.cloudURL)
                    Button(checkingPC ? "检测中…" : "检测连接") {
                        checkingPC = true
                        Task {
                            let ok = await store.pingComputer()
                            store.toast = ok ? "已连上" : "暂时没连上"
                            checkingPC = false
                        }
                    }
                }
                Section("手机通道") {
                    TextField("WDA 地址", text: $store.wdaURL)
                    Button(checkingWDA ? "检测中…" : "检测 WDA") {
                        checkingWDA = true
                        Task {
                            let ok = await store.pingWDA()
                            store.toast = ok ? "WDA 在线" : "WDA 未启动"
                            checkingWDA = false
                        }
                    }
                    Text("巨魔 / 越狱通道走本机 8765 端口的代理，装好后会自动出现。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("免费模型") {
                    TextField("免费服务器地址", text: $store.freeBase)
                    Text("当前模型：\(store.model)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { store.save(); dismiss() }
                }
            }
            .onDisappear { store.save() }
        }
        .presentationDetents([.large])
    }
}

// MARK: - 密钥单独入口

struct KeySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                KeyCard()
                    .padding(16)
            }
            .background(Color(red: 0.06, green: 0.07, blue: 0.11))
            .navigationTitle("AI 密钥")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}
