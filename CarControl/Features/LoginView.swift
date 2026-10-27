import SwiftUI
import Combine

struct LoginView: View {
    @EnvironmentObject private var app: AppState

    @State private var phone = ""
    @State private var code = ""
    @State private var sending = false
    /// 短信重发倒计时（秒），0 表示可发送
    @State private var cooldown = 0

    /// 倒计时用静态 publisher：struct 每次重建不会重新订阅，避免跳秒
    private static let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var canSendCode: Bool { phone.count == 11 && !sending && cooldown == 0 }
    private var canLogin: Bool { phone.count == 11 && code.count >= 4 && !app.isLoading }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                phoneSection
                codeSection
                sentHint
                loginButton
                demoHint
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            if phone.isEmpty, let saved = UserDefaults.standard.string(forKey: "mg.lastPhone") {
                phone = saved
            }
            #if DEBUG
            if phone.isEmpty,
               let prefill = ProcessInfo.processInfo.environment["MG_PREFILL_PHONE"] {
                phone = prefill
            }
            #endif
        }
        .onReceive(Self.ticker) { _ in
            if cooldown > 0 { cooldown -= 1 }
        }
        .onChange(of: app.codeSent) { sent in
            // 真正下发成功后才进入 60s 冷却；取消验证码不会白等
            if sent { cooldown = 60 }
        }
        .confirmationDialog("获取验证码", isPresented: $app.showOfficialLoginHint,
                            titleVisibility: .visible) {
            Button("打开 MG Live") {
                guard let url = URL(string: "mglive://") else { return }
                UIApplication.shared.open(url, options: [:]) { ok in
                    if !ok, let store = URL(string: "https://apps.apple.com/cn/app/id1441932656") {
                        UIApplication.shared.open(store)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("自动发码未通过安全验证，可临时改用官方 MG Live 获取验证码后回到本页输入。")
        }
        .sheet(isPresented: $app.showCaptcha) {
            CaptchaSheet(phone: app.pendingPhone,
                         onValidate: { validate in
                             Task { await app.submitCaptcha(validate) }
                         },
                         onCancel: { app.showCaptcha = false })
        }
        .alert("提示", isPresented: errorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { app.errorMessage != nil },
            set: { if !$0 { app.errorMessage = nil } }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MG 车控助手")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.primary)
            Text("车辆信息 · 远程控制")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("使用 MG Live 账号登录；蓝牙钥匙请先在官方 App 开通。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var phoneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("手机号").font(.footnote).foregroundStyle(.secondary)
            TextField("请输入手机号", text: $phone)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var codeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("验证码").font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                TextField("短信验证码", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onChange(of: code) { value in
                        let digits = value.filter(\.isNumber)
                        if digits != value || digits.count > 6 {
                            code = String(digits.prefix(6))
                        }
                    }

                Button {
                    Task {
                        sending = true
                        await app.sendCode(phone: phone)
                        sending = false
                    }
                } label: {
                    Text(sendButtonTitle)
                        .font(.footnote.weight(.semibold))
                        .frame(width: 104, height: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!canSendCode)
            }
        }
    }

    private var sendButtonTitle: String {
        if sending { return "发送中" }
        if cooldown > 0 { return "\(cooldown)s 后重发" }
        return "获取验证码"
    }

    private var loginButton: some View {
        Button {
            Task { await app.login(phone: phone, code: code) }
        } label: {
            HStack {
                if app.isLoading { ProgressView().tint(.white) }
                Text("登录").font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.primary)
        .disabled(!canLogin)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var sentHint: some View {
        if app.codeSent && !app.isMockMode {
            Text("验证码已发送，请查收短信")
                .font(.caption)
                .foregroundStyle(Theme.success)
        }
    }

    @ViewBuilder
    private var demoHint: some View {
        if app.isMockMode {
            Text("演示模式：验证码固定为 123456，无需真实短信。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("真机登录：点击「获取验证码」完成安全验证后自动下发短信。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
