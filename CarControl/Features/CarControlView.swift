import SwiftUI
import CoreKit

struct CarControlView: View {
    @EnvironmentObject private var app: AppState
    @State private var pendingCommand: CommandType?
    @State private var showConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let vehicle = app.selectedVehicle {
                        header(vehicle)
                        pinSection
                        commandGrid
                        safetyNote
                    } else {
                        Text("请先在「车辆」页选择车辆")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 80)
                    }
                }
                .padding(Theme.pagePadding)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("控制")
            .confirmationDialog("确认执行", isPresented: $showConfirm) {
                Button(pendingCommand?.title ?? "执行", role: .destructive) {
                    guard let command = pendingCommand else { return }
                    Task { await app.run(command) }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将向当前车辆下发「\(pendingCommand?.title ?? "")」指令")
            }
            .overlay(alignment: .bottom) {
                if let message = app.commandMessage {
                    Text(message)
                        .font(.footnote)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 96)
                        .onTapGesture { app.commandMessage = nil }
                }
            }
        }
    }

    private func header(_ vehicle: Vehicle) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(vehicle.model).font(.headline)
                Text(vehicle.plateNo ?? vehicle.vin).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let status = app.status {
                Text(status.online ? "在线" : "离线")
                    .font(.caption)
                    .foregroundStyle(status.online ? Theme.success : Color.secondary)
            }
        }
        .card()
    }

    private var commandGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(CommandType.allCases, id: \.self) { command in
                Button {
                    tap(command)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: icon(for: command))
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                        Text(command.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84)
                }
                .buttonStyle(.plain)
                .card()
            }
        }
    }

    private var pinSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: app.pinVerified ? "checkmark.shield.fill" : "lock.shield")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(app.pinVerified ? Theme.success : Theme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("控车安全码")
                        .font(.headline)
                    Text(app.pinVerified
                         ? "已验证，有效期内可直接下发控车指令"
                         : "解锁、开窗、空调等操作需要先验证安全码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button(app.pinVerified ? "重新验证" : "输入安全码") {
                    app.requestPINVerification()
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(app.pinVerified ? Theme.success : Theme.accent)
                .disabled(app.isLoading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var safetyNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("安全提示", systemImage: "exclamationmark.shield")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.warning)
            Text("解锁、开窗、开后备箱等指令需要二次确认；高危指令默认还要通过 \(BiometricGate.biometryName) / 设备密码，"
                 + "并由服务端安全码（pvCode）授权。指令下发后会用车辆状态反向确认是否生效。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func tap(_ command: CommandType) {
        if command.requiresConfirm {
            pendingCommand = command
            showConfirm = true
        } else {
            Task { await app.run(command) }
        }
    }

    private func icon(for command: CommandType) -> String {
        switch command {
        case .lock: return "lock.fill"
        case .unlock: return "lock.open.fill"
        case .windowClose: return "arrow.up.to.line"
        case .windowOpen: return "arrow.down.to.line"
        case .acOn: return "snowflake"
        case .acOff: return "wind"
        case .trunkOpen: return "shippingbox.fill"
        case .findCar: return "location.fill"
        }
    }
}


// MARK: - 安全码输入

struct PinSheet: View {
    @Binding var pin: String
    var onSubmit: () -> Void
    var onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 18) {
            Text("输入控车安全码")
                .font(.headline)
                .padding(.top, 8)

            SecureField("6 位安全码", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .onChange(of: pin) { value in
                    let digits = value.filter(\.isNumber)
                    pin = String(digits.prefix(6))
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 24)

            Text("开空调、解锁等操作需要安全码验证")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("确定", action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(pin.count < 6)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .onAppear { focused = true }
    }
}
