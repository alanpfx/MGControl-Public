import SwiftUI
import UIKit
import CoreKit

// MARK: - 官方 App 桥接（方案 A 核心：钥匙由官方 App 管理）

enum OfficialAppBridge {
    /// 依次尝试官方 App 的深链，失败时退化为仅打开 App。
    /// 说明：`mglive://` 已在官方 iOS 包 Info.plist 中确认；数字钥匙页的具体路由需真机实测后替换。
    static let candidates = ["mglive://digitalkey", "mglive://"]

    static func openDigitalKey(_ openURL: OpenURLAction) {
        for string in candidates {
            if let url = URL(string: string) {
                openURL(url)
                return
            }
        }
    }
}

struct DigitalKeyCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "key.fill").foregroundStyle(Theme.accent)
                Text("数字钥匙").font(.headline)
                Spacer()
                Button("打开官方 App") {
                    OfficialAppBridge.openDigitalKey(openURL)
                }
                .font(.footnote.weight(.semibold))
            }
            Text("蓝牙钥匙的开通、分享与撤销由 MG Live 官方 App 负责；本 App 不存储钥匙密钥，仅提供入口。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - 消息

struct MessageView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack {
            List(app.messages) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.title).font(.headline)
                        Spacer()
                        Text(item.date, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("消息")
            .overlay {
                if app.messages.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bell.slash").font(.largeTitle).foregroundStyle(.secondary)
                        Text("暂无消息").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .task { if app.messages.isEmpty { await app.loadMessages() } }
            .refreshable { await app.loadMessages() }
        }
    }
}

// MARK: - 我的

struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openURL) private var openURL

    /// 直接读 bundle：project.yml 里 CFBundleShortVersionString = $(MARKETING_VERSION)
    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.user?.nickname ?? "车主").font(.headline)
                            Text(app.user?.maskedPhone ?? "").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("车辆与钥匙") {
                    Button {
                        OfficialAppBridge.openDigitalKey(openURL)
                    } label: {
                        Label("数字钥匙（官方 App）", systemImage: "key.fill")
                    }
                    Label("当前车辆：\(app.selectedVehicle?.model ?? "未选择")", systemImage: "car.fill")
                }

                Section("安全") {
                    Toggle(isOn: Binding(
                        get: { app.biometricEnabled },
                        set: { app.setBiometric($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("高危指令校验 \(BiometricGate.biometryName)")
                            Text("解锁、开窗、开后备箱前要求本机身份验证")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("控车安全码", value: app.pinVerified ? "已验证（4 分钟内有效）" : "未验证")
                }

                Section("关于") {
                    LabeledContent("版本", value: Self.appVersion)
                    LabeledContent("使用许可", value: "个人非商业")
                    Text("本 App 为独立开发的第三方客户端，与上汽/MG 无隶属关系；车控功能请仅在授权范围内使用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(role: .destructive) {
                        app.logout()
                    } label: {
                        Text("退出登录").frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("我的")
        }
    }
}
