import SwiftUI
import CoreKit

// MARK: - 状态机 ViewModel

@MainActor
final class MG4DashboardViewModel: ObservableObject {
    enum State: Equatable {
        case loggedOut
        case loading
        case expired
        case noVehicle
        case loaded(MG4VehicleData)
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var isRefreshing = false
    @Published private(set) var busyAction: MG4ControlAction?
    @Published var toast: String?

    private let api: MG4API

    init(api: MG4API = MG4APIProvider.make()) {
        self.api = api
    }

    func load(token: String?) async {
        guard let token, !token.isEmpty else {
            state = .loggedOut
            return
        }
        if case .loaded = state {
            // 保留当前内容，避免刷新闪烁
        } else {
            state = .loading
        }
        do {
            let data = try await api.fetchMG4Status(token: token)
            state = .loaded(data)
            // 车辆页是小组件的数据源，加载成功后立即写共享快照
            WidgetBridge.sync(data)
        } catch let error as APIError {
            switch error.code {
            case "14101": state = .expired
            case "10500702": state = .noVehicle
            default: state = .failed(error.message)
            }
        } catch {
            state = .failed("加载失败，请稍后重试")
        }
    }

    func refresh(token: String?, silent: Bool = false) async {
        guard let token, !token.isEmpty else {
            state = .loggedOut
            return
        }
        guard !isRefreshing else { return }
        if !silent { isRefreshing = true }
        defer { if !silent { isRefreshing = false } }
        do {
            let data = silent
                ? try await api.fetchMG4Status(token: token)
                : try await api.refreshMG4Status(token: token)
            state = .loaded(data)
            WidgetBridge.sync(data)
            if !silent { toast = "车辆信息已刷新" }
        } catch let error as APIError {
            if error.code == "14101" { state = .expired }
            else if !silent { toast = error.message }
        } catch {
            if !silent { toast = "刷新失败，请稍后重试" }
        }
    }

    /// 进入页面后启动：先加载一次，然后每 60 秒静默刷新
    func startPolling(token: String?) async {
        await load(token: token)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if case .loaded = state {
                await refresh(token: token, silent: true)
            }
        }
    }

    func control(_ action: MG4ControlAction, token: String?) async {
        guard let token, !token.isEmpty else {
            state = .loggedOut
            return
        }
        busyAction = action
        defer { busyAction = nil }
        do {
            try await api.controlMG4(token: token, action: action)
            switch action {
            case .lock: toast = "车辆已上锁"
            case .unlock: toast = "车辆已解锁"
            case .closeWindows: toast = "车窗关闭指令已下发"
            case .openWindows: toast = "车窗开启指令已下发"
            }
            await load(token: token)
        } catch let error as APIError {
            if error.code == "14101" { state = .expired }
            else { toast = error.message }
        } catch {
            toast = "指令执行失败"
        }
    }
}

// MARK: - 页面

struct MG4DashboardView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = MG4DashboardViewModel()
    @State private var showLogin = false
    @State private var showFullStatus = false
    @State private var showExpiredAlert = false
    /// 快捷车控的待确认指令（与「控制」页一致，先确认再下发）
    @State private var pendingQuickCommand: CommandType?
    @State private var showQuickConfirm = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            StatusPalette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 16) {
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                }
                .refreshable {
                    await vm.refresh(token: app.token)
                }
                .modifier(DebugScrollAnchor())
            }
            .overlay(alignment: .bottom) { toastStack }
        }
        .preferredColorScheme(.dark)
        .task(id: app.token) {
            await vm.startPolling(token: app.token)
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["MG_SHOW_FULL_STATUS"] != nil {
                showFullStatus = true
            }
            #endif
        }
        .onChange(of: vm.state) { newState in
            if case .expired = newState { showExpiredAlert = true }
        }
        .sheet(isPresented: $showLogin) {
            LoginView().environmentObject(app)
        }
        .sheet(isPresented: $showFullStatus) {
            VehicleHomeView().environmentObject(app)
        }
        .confirmationDialog("确认执行", isPresented: $showQuickConfirm) {
            Button(pendingQuickCommand?.title ?? "执行", role: .destructive) {
                guard let command = pendingQuickCommand else { return }
                Task {
                    await app.run(command)
                    await vm.refresh(token: app.token, silent: true)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将向当前车辆下发「\(pendingQuickCommand?.title ?? "")」指令")
        }
        .alert("登录已过期", isPresented: $showExpiredAlert) {
            Button("去登录") {
                app.logout()
                showLogin = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请重新登录后查看车辆状态")
        }
    }

    // MARK: - 提示气泡

    private var toastStack: some View {
        VStack(spacing: 8) {
            if let toast = vm.toast {
                toastBubble(toast) { vm.toast = nil }
            }
            if let message = app.commandMessage {
                toastBubble(message) { app.commandMessage = nil }
            }
        }
        .padding(.bottom, 20)
        .animation(.default, value: vm.toast)
        .animation(.default, value: app.commandMessage)
    }

    private func toastBubble(_ text: String, onTap: @escaping () -> Void) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.75))
            .clipShape(Capsule())
            .onTapGesture(perform: onTap)
            .transition(.opacity)
    }

    // MARK: 头部
    private var header: some View {
        ZStack {
            Text("车况")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 18) {
                Spacer()

                if case .loggedOut = vm.state {
                    Button("登录") { showLogin = true }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(StatusPalette.blue)
                } else {
                    Button {
                        Task { await vm.refresh(token: app.token) }
                    } label: {
                        if vm.isRefreshing {
                            ProgressView().controlSize(.small).tint(StatusPalette.blue)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(StatusPalette.blue)
                        }
                    }
                    .disabled(vm.isRefreshing)

                    Button {
                        showFullStatus = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(StatusPalette.blue)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(StatusPalette.bg)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loggedOut:
            LoggedOutCard { showLogin = true }

        case .loading:
            DashboardSkeleton()

        case .expired:
            ZStack {
                DashboardSkeleton().opacity(0.35).allowsHitTesting(false)
                ExpiredCard {
                    app.logout()
                    showLogin = true
                }
            }

        case .noVehicle:
            NoVehicleCard {
                openURL(URL(string: "mglive://") ?? URL(string: "https://www.mglive.com.cn")!)
            }

        case .failed(let message):
            ErrorCard(message: message) {
                Task { await vm.load(token: app.token) }
            }

        case .loaded(let data):
            MG4StatusPage(data: data, isRefreshing: vm.isRefreshing, onRefresh: {
                Task { await vm.refresh(token: app.token) }
            }, onControl: { action in
                // 快捷车控先确认，再走统一入口：Face ID → 安全码 → 下发 → 车况确认
                let command: CommandType
                switch action {
                case .lock: command = .lock
                case .unlock: command = .unlock
                case .closeWindows: command = .windowClose
                case .openWindows: command = .windowOpen
                }
                pendingQuickCommand = command
                showQuickConfirm = true
            })
        }
    }
}

// MARK: - 调试辅助

private struct DebugScrollAnchor: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *),
           ProcessInfo.processInfo.environment["MG_SCROLL_BOTTOM"] != nil {
            content.defaultScrollAnchor(.bottom)
        } else {
            content
        }
    }
}

// MARK: - 状态卡片

struct LoggedOutCard: View {
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 130)
                Image(systemName: "car.side.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.white.opacity(0.18))
            }
            Text("登录后查看爱车状态")
                .font(.headline)
                .foregroundStyle(.white)
            Text("续航、电量、胎压、停车位置与远程控制")
                .font(.caption)
                .foregroundStyle(BrandTheme.textSecondary)
            Button(action: onLogin) {
                Text("点击登录")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(BrandTheme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .brandCard(padding: 20)
    }
}

struct DashboardSkeleton: View {
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SkeletonBlock(height: 20).frame(width: 110)
                    Spacer()
                    SkeletonBlock(height: 12).frame(width: 70)
                }
                SkeletonBlock(height: 36).frame(width: 140)
                SkeletonBlock(height: 8)
            }
            .brandCard()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SkeletonBlock(height: 18).frame(width: 150)
                    Spacer()
                    SkeletonBlock(height: 14).frame(width: 40)
                }
                SkeletonBlock(height: 8)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 34) }
                }
                SkeletonBlock(height: 22).frame(width: 140)
                SkeletonBlock(height: 40)
            }
            .brandCard()

            VStack(alignment: .leading, spacing: 14) {
                SkeletonBlock(height: 20).frame(width: 180)
                SkeletonBlock(height: 10)
                SkeletonBlock(height: 50)
                SkeletonBlock(height: 44)
            }
            .brandCard()
        }
    }
}

struct ExpiredCard: View {
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(BrandTheme.warning)
            Text("登录已过期")
                .font(.headline)
                .foregroundStyle(.white)
            Text("重新登录后继续查看车辆状态")
                .font(.caption)
                .foregroundStyle(BrandTheme.textSecondary)
            Button(action: onLogin) {
                Text("去登录")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(BrandTheme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(20)
        .background(BrandTheme.card.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrandTheme.warning.opacity(0.35), lineWidth: 1)
        )
    }
}

struct NoVehicleCard: View {
    let onBind: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "car.badge.gearshape")
                .font(.system(size: 44))
                .foregroundStyle(BrandTheme.green)
            Text("还没有绑定车辆")
                .font(.headline)
                .foregroundStyle(.white)
            Text("请先在官方 App 完成绑车与激活，再回来刷新")
                .font(.caption)
                .foregroundStyle(BrandTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button(action: onBind) {
                Text("去绑定车辆")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(BrandTheme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .brandCard(padding: 20)
    }
}

struct ErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(BrandTheme.warning)
            Text(message)
                .font(.footnote)
                .foregroundStyle(BrandTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("重试", action: onRetry)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BrandTheme.green)
        }
        .brandCard(padding: 20)
    }
}
