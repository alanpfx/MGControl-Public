import SwiftUI
import CoreKit

@main
struct CarControlApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
        }
    }
}

// MARK: - 全局状态

@MainActor
final class AppState: ObservableObject {
    @Published var user: User?
    @Published var token: String?
    @Published var vehicles: [Vehicle] = []
    @Published var selectedVehicle: Vehicle?
    @Published var status: VehicleStatus?
    @Published var messages: [MessageItem] = []
    @Published var chargingRecords: [ChargingRecord] = []
    @Published var chargingStats: ChargingStats?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var commandMessage: String?
    /// 小组件深链解析出的导航目标（只做跳转，不携带指令执行能力）。
    @Published var pendingRoute: WidgetRoute?
    /// 当前 Tab，供深链切换。
    @Published var selectedTab = 0
    @Published var codeSent = false
    @Published var showOfficialLoginHint = false
    @Published var showCaptcha = false
    @Published var pendingPhone = ""
    @Published var showPinPrompt = false
    @Published var pinInput = ""
    /// 高危指令下发前是否要求 Face ID / Touch ID（默认开启，可在「我的」里关闭）
    @Published var biometricEnabled: Bool = (UserDefaults.standard.object(forKey: "mg.biometric") as? Bool) ?? true
    /// 指令执行中（避免连点重复下发）
    @Published var isRunningCommand = false
    private var pendingPINCommand: CommandType?

    let api: APIClient

    init(api: APIClient? = nil) {
        self.api = api ?? AppState.makeDefaultAPI()
    }

    /// 真实后端联调开关：注入 `API_BASE_URL` 时使用 RemoteAPIClient，否则回退 Mock。
    /// 模拟器用法（每次 launch 生效）：
    ///   SIMCTL_CHILD_API_BASE_URL=http://127.0.0.1:8787 \
    ///   xcrun simctl launch --terminate-running-process booted com.alanpfx.mgcontrol
    private static func makeDefaultAPI() -> APIClient {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["MG_MOCK"] == "1" {
            return MockAPIClient()
        }
        if let toc = env["MG_TOC_TOKEN"], let swap = env["MG_SWAP_TOKEN"] {
            let client = MGRealClient.shared
            client.install(toc: toc, swap: swap)
            return client
        }
        if let raw = env["API_BASE_URL"], let url = URL(string: raw) {
            return RemoteAPIClient(baseURL: url)
        }
        #endif
        return MGRealClient.shared
    }

    var isLoggedIn: Bool { token != nil }

    /// 是否 Mock 演示模式（真后端模式下不展示演示提示）
    var isMockMode: Bool { api is MockAPIClient }

    /// 控车安全码是否仍在有效期（pvCode 约 4 分钟）
    var pinVerified: Bool {
        (api as? MGRealClient)?.hasValidAuthCode ?? false
    }

    /// 调试日志（写入沙盒 Documents/mg_debug.log）
    static func writeDebug(_ text: String) {
        #if DEBUG
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mg_debug.log")
        let line = "[\(Date())] \(text)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
        #endif
    }

    /// 启动时恢复本地会话；DEBUG 下支持环境变量注入。
    func bootstrapFromEnvironment() async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if api is MockAPIClient, env["MG_AUTO_MOCK"] == "1" {
            user = User(id: "u_10001", phone: "130****4295", nickname: "演示")
            token = "mock-token-demo"
            await loadVehicles()
            await loadMessages()
            return
        }
        #endif

        guard let real = api as? MGRealClient else { return }

        if real.hasSession, let profile = real.savedProfile {
            user = User(id: profile.uid, phone: profile.phone,
                        nickname: profile.nick.isEmpty ? nil : profile.nick)
            token = real.tocToken
            // tocToken 约 30 分钟：先静默换一次 swapToken，失败就走登录页
            let restored = await real.restoreSession()
            await loadVehicles()
            if !restored, vehicles.isEmpty {
                Self.writeDebug("bootstrap: session restore failed")
            }
            await loadMessages()
            return
        }

        #if DEBUG
        let env2 = ProcessInfo.processInfo.environment
        if let toc = env2["MG_TOC_TOKEN"], env2["MG_SWAP_TOKEN"] != nil {
            user = User(id: env2["MG_USER_ID"] ?? "0",
                        phone: env2["MG_PHONE"] ?? "",
                        nickname: env2["MG_NICK"])
            token = toc
            await loadVehicles()
            await loadMessages()
            return
        }
        if let phone = env2["MG_SEND_CODE_PHONE"] {
            await sendCode(phone: phone)
            return
        }
        if let phone = env2["MG_LOGIN_PHONE"], let code = env2["MG_LOGIN_CODE"] {
            await login(phone: phone, code: code)
        }
        #endif
    }

    // MARK: 登录

    /// 发码入口：本地校验通过后，真后端先弹易盾验证，演示模式直接下发。
    func sendCode(phone: String) async {
        errorMessage = nil
        codeSent = false

        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 11, trimmed.allSatisfy(\.isNumber) else {
            errorMessage = "请输入正确的手机号"
            return
        }
        UserDefaults.standard.set(trimmed, forKey: "mg.lastPhone")

        if api is MGRealClient {
            // 真后端：先完成易盾图形验证，拿到 validate 后再发码
            pendingPhone = trimmed
            showCaptcha = true
            return
        }

        isLoading = true
        do {
            try await api.requestSMSCode(phone: trimmed, captchaValidate: "")
            codeSent = true
        } catch let err as APIError {
            errorMessage = err.message
        } catch {
            errorMessage = "网络异常，请稍后再试"
        }
        isLoading = false
    }

    /// 易盾验证通过后的回调，携带 validate 触发短信下发。
    func submitCaptcha(_ validate: String) async {
        showCaptcha = false
        guard !pendingPhone.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        do {
            try await api.requestSMSCode(phone: pendingPhone, captchaValidate: validate)
            codeSent = true
        } catch let err as APIError {
            errorMessage = err.message
            // 21102 表示 validate / captchaId 不被接受，退回官方 App 取码作为兜底
            if err.code == "21102" {
                showOfficialLoginHint = true
            }
        } catch {
            errorMessage = "验证码发送失败，请稍后再试"
        }
        isLoading = false
    }

    func login(phone: String, code: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await api.login(phone: phone, code: code)
            user = result.user
            token = result.token
            await loadVehicles()
            await loadMessages()
        } catch let err as APIError {
            errorMessage = err.message
            Self.writeDebug("login fail \(err.code) \(err.message)")
            if err.code == ControlErrorCode.sessionExpired {
                logout()
            }
        } catch {
            errorMessage = "登录失败，请稍后再试"
        }
        isLoading = false
    }

    func logout() {
        user = nil
        token = nil
        vehicles = []
        selectedVehicle = nil
        status = nil
        messages = []
        chargingRecords = []
        chargingStats = nil
        // 清掉安全码 / 指令相关的临时状态，避免换账号后残留上一次会话
        showPinPrompt = false
        pinInput = ""
        pendingPINCommand = nil
        commandMessage = nil
        if let real = api as? MGRealClient {
            real.clearSession()
        }
        // 清空共享快照，避免桌面残留上一账号的车辆信息
        WidgetBridge.clear()
    }

    // MARK: 小组件深链

    /// 处理 `mgcontrol://` 链接。
    /// 只负责切页与刷新，不在后台下发任何车控指令（docs/05 §4 安全边界）。
    func handle(_ url: URL) {
        guard let route = WidgetRoute.parse(url) else { return }
        pendingRoute = route

        switch route.destination {
        case .home, .charging, .parking:
            selectedTab = 0
        case .control:
            selectedTab = 1
        case .refresh:
            selectedTab = 0
            Task { await refreshStatus() }
        }
    }

    // MARK: 车辆

    func loadVehicles() async {
        guard let token else { return }
        isLoading = true
        do {
            let list = try await api.fetchVehicles(token: token)
            vehicles = list
            if selectedVehicle == nil || !list.contains(where: { $0.vin == selectedVehicle?.vin }) {
                selectedVehicle = list.first
            }
            if let vin = selectedVehicle?.vin {
                status = try await api.fetchStatus(token: token, vin: vin)
            }
            WidgetBridge.sync(vehicle: selectedVehicle, status: status)
        } catch let err as APIError {
            if err.code == ControlErrorCode.sessionExpired {
                logout()
                errorMessage = "登录已过期，请重新登录"
            } else {
                errorMessage = err.message
            }
        } catch {
            errorMessage = "车辆数据加载失败"
        }
        isLoading = false
    }

    func select(_ vehicle: Vehicle) async {
        selectedVehicle = vehicle
        status = nil
        chargingRecords = []
        chargingStats = nil
        guard let token else { return }
        do {
            status = try await api.fetchStatus(token: token, vin: vehicle.vin)
            WidgetBridge.sync(vehicle: vehicle, status: status)
        } catch {
            errorMessage = "车况刷新失败"
        }
    }

    func refreshStatus() async {
        guard let token, let vin = selectedVehicle?.vin else { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if let real = api as? MGRealClient {
                status = try await real.refreshVehicleStatus(token: token, vin: vin)
            } else {
                status = try await api.fetchStatus(token: token, vin: vin)
            }
            WidgetBridge.sync(vehicle: selectedVehicle, status: status, stats: chargingStats)
            commandMessage = "车辆信息已刷新"
        } catch let err as APIError {
            errorMessage = err.message
        } catch {
            errorMessage = "刷新失败，请稍后再试"
        }
    }

    // MARK: 车控

    /// 入口：先做本地校验 → 高危指令过生物识别 → 下发 → 用车辆状态反向确认。
    func run(_ command: CommandType) async {
        await execute(command, checkBiometrics: true)
    }

    private func execute(_ command: CommandType, checkBiometrics: Bool) async {
        guard let token, let vin = selectedVehicle?.vin else {
            Self.writeDebug("run skipped: no token/vehicle")
            errorMessage = "请先选择车辆"
            return
        }
        guard !isRunningCommand else { return }
        isRunningCommand = true
        defer { isRunningCommand = false }

        Self.audit("request \(command.rawValue) vin=\(vin.suffix(6))")

        if checkBiometrics, biometricEnabled, command.requiresConfirm {
            let passed = await BiometricGate.authenticate(
                reason: "验证身份后执行「\(command.title)」")
            guard passed else {
                commandMessage = "已取消：身份验证未通过"
                Self.audit("biometric rejected \(command.rawValue)")
                return
            }
        }

        commandMessage = "\(command.title)下发中…"
        do {
            let result = try await api.sendCommand(token: token, vin: vin, command: command)
            Self.audit("accepted \(command.rawValue) id=\(result.commandId)")
            if let real = api as? MGRealClient {
                commandMessage = "\(command.title)已下发，正在确认车辆状态…"
                let confirmed = await real.awaitCommandEffect(token: token, vin: vin, command: command)
                commandMessage = confirmed
                    ? "\(command.title)已完成"
                    : (result.message ?? "\(command.title)已下发，车辆状态尚未更新")
                Self.audit("effect \(command.rawValue) confirmed=\(confirmed)")
            } else {
                commandMessage = result.message ?? "指令已下发"
            }
            await refreshStatus()
        } catch let err as APIError {
            Self.audit("fail \(command.rawValue) code=\(err.code)")
            handleControlError(err, command: command)
        } catch {
            commandMessage = "指令执行失败"
        }
    }

    private func handleControlError(_ err: APIError, command: CommandType) {
        switch err.code {
        case ControlErrorCode.needPin, "14728", "14732", "14733":
            pendingPINCommand = command
            pinInput = ""
            showPinPrompt = true
            // 安全码弹窗本身就是提示，不再同时挂一条 toast
            commandMessage = nil
        case ControlErrorCode.sessionExpired:
            logout()
            errorMessage = "登录已过期，请重新登录"
        default:
            commandMessage = err.message
        }
    }

    /// 控车审计日志（Documents/control_audit.log），便于回溯指令与失败码。
    static func audit(_ text: String) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("control_audit.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(text)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    // MARK: 安全码

    /// 主动打开安全码输入，不依赖控车指令触发。
    func requestPINVerification() {
        guard let vin = selectedVehicle?.vin, !vin.isEmpty else {
            errorMessage = "请先选择车辆"
            return
        }
        guard api is MGRealClient else {
            errorMessage = "当前为演示模式，无需验证控车安全码"
            return
        }
        pendingPINCommand = nil
        pinInput = ""
        showPinPrompt = true
    }

    func submitPIN() async {
        guard let vin = selectedVehicle?.vin, let real = api as? MGRealClient else {
            showPinPrompt = false
            return
        }
        let pin = pinInput.trimmingCharacters(in: .whitespaces)
        guard pin.count >= 4 else { return }
        isLoading = true
        do {
            _ = try await real.verifyPIN(vin: vin, pin: pin)
            showPinPrompt = false
            pinInput = ""
            if let command = pendingPINCommand {
                pendingPINCommand = nil
                // 安全码已通过，同一次操作不再重复弹 Face ID
                await execute(command, checkBiometrics: false)
            } else {
                commandMessage = "安全码验证成功，4 分钟内可直接控车"
            }
        } catch let err as APIError {
            errorMessage = err.message
            if err.code == "14734" { showPinPrompt = false }
        } catch {
            errorMessage = "安全码校验失败，请重试"
        }
        isLoading = false
    }

    func setBiometric(_ enabled: Bool) {
        biometricEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "mg.biometric")
    }

    // MARK: 充电

    func loadChargingData() async {
        guard let token, let vin = selectedVehicle?.vin else { return }
        do {
            async let records = api.fetchChargingRecords(token: token, vin: vin)
            async let stats = api.fetchChargingStats(token: token, vin: vin)
            chargingRecords = try await records
            chargingStats = try await stats
            WidgetBridge.sync(vehicle: selectedVehicle, status: status, stats: chargingStats)
        } catch {
            // 充电数据失败不阻塞主页
        }
    }

    // MARK: 消息

    func loadMessages() async {
        guard let token else { return }
        do {
            messages = try await api.fetchMessages(token: token)
        } catch {
            // 消息失败不阻塞主流程
        }
    }
}

// MARK: - 根视图

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Group {
            if app.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.default, value: app.isLoggedIn)
        .task { await app.bootstrapFromEnvironment() }
        .onOpenURL { app.handle($0) }
        // 安全码弹窗挂在根视图：车辆页与控制页共用同一份状态，避免两个 Tab 同时呈现
        .sheet(isPresented: $app.showPinPrompt) {
            PinSheet(pin: $app.pinInput) {
                Task { await app.submitPIN() }
            } onCancel: {
                app.showPinPrompt = false
                app.pinInput = ""
            }
            .presentationDetents([.height(280)])
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView(selection: $app.selectedTab) {
            MG4DashboardView()
                .tabItem { Label("车辆", systemImage: "car.fill") }
                .tag(0)
            CarControlView()
                .tabItem { Label("控制", systemImage: "dot.radiowaves.left.and.right") }
                .tag(1)
            MessageView()
                .tabItem { Label("消息", systemImage: "bell.fill") }
                .tag(2)
            ProfileView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(3)
        }
        .tint(BrandTheme.green)
        .onAppear {
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["MG_START_TAB"],
               let value = Int(raw) {
                app.selectedTab = value
            }
            #endif
        }
    }
}
