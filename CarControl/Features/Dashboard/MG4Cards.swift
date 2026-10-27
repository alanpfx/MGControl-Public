import SwiftUI
import CoreKit

// MARK: - 车辆占位图（无 3D 素材时使用；后续可替换为 Image("mg4_car")）

struct CarSilhouette: View {
    var scale: CGFloat = 1

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.02)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Image(systemName: "car.side.fill")
                .font(.system(size: 46 * scale, weight: .regular))
                .foregroundStyle(
                    LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: BrandTheme.green.opacity(0.25), radius: 12, y: 6)
        }
    }
}

// MARK: - 卡片 1：车辆概览（横向）

struct MG4OverviewCard: View {
    let data: MG4VehicleData

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(data.modelName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Text(data.plateNo)
                        .font(.caption)
                        .foregroundStyle(BrandTheme.textSecondary)
                }
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    Image(systemName: data.isLocked ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(BrandTheme.green)
                    Text("\(data.rangeKm) km")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 10) {
                    GreenProgressBar(progress: Double(data.soc) / 100)
                    Text("\(data.soc)%")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
            CarSilhouette()
                .frame(width: 118, height: 74)
        }
        .brandCard()
    }
}

// MARK: - 卡片 2：车辆详情（横版）

struct MG4DetailCard: View {
    let data: MG4VehicleData
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(data.modelName) \(data.trimName)")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(data.plateNo)
                        .font(.caption2)
                        .foregroundStyle(BrandTheme.textTertiary)
                }
                Spacer()
                Text("\(data.soc)%")
                    .font(.headline)
                    .foregroundStyle(BrandTheme.green)
                    .monospacedDigit()
            }

            GreenProgressBar(progress: Double(data.soc) / 100)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MG4Metric(title: "剩余续航", value: "\(data.rangeKm)", unit: "km")
                MG4Metric(title: "总里程", value: data.odometerKm.formatted(), unit: "km")
                MG4Metric(title: "车内温度", value: String(format: "%.0f", data.cabinTempC), unit: "°C")
                MG4Metric(title: "电瓶电压", value: String(format: "%.1f", data.batteryVoltageV), unit: "V")
            }

            HStack(spacing: 8) {
                MG4StatusBadge(title: data.isLocked ? "已锁" : "未锁门",
                               ok: data.isLocked,
                               icon: data.isLocked ? "lock.fill" : "lock.open.fill")
                MG4StatusBadge(title: data.isWindowClosed ? "门窗关" : "车窗未关",
                               ok: data.isWindowClosed,
                               icon: data.isWindowClosed ? "checkmark" : "exclamationmark.triangle.fill")
                Spacer()
            }

            HStack(spacing: 8) {
                MG4TireItem(name: "前左", value: data.tireFrontLeft)
                MG4TireItem(name: "前右", value: data.tireFrontRight)
                MG4TireItem(name: "后左", value: data.tireRearLeft)
                MG4TireItem(name: "后右", value: data.tireRearRight)
            }

            Divider().overlay(Color.white.opacity(0.06))

            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(BrandTheme.green)
                Text(data.address)
                    .font(.caption)
                    .foregroundStyle(BrandTheme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandTheme.green)
                }
                Text("更新于 \(timeText(data.updatedAt))")
                    .font(.caption2)
                    .foregroundStyle(BrandTheme.textTertiary)
            }
        }
        .brandCard()
    }
}

// MARK: - 卡片 3：车辆详情（竖版）

struct MG4VerticalCard: View {
    let data: MG4VehicleData
    let busyAction: MG4ControlAction?
    let onControl: (MG4ControlAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(data.modelName)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                    Text(data.trimName)
                        .font(.caption)
                        .foregroundStyle(BrandTheme.textSecondary)
                    Text(data.plateNo)
                        .font(.caption2)
                        .foregroundStyle(BrandTheme.textTertiary)
                }
                Spacer()
                CarSilhouette(scale: 0.8)
                    .frame(width: 96, height: 62)
                VStack(spacing: 2) {
                    Image(systemName: "battery.75")
                        .font(.system(size: 22))
                        .foregroundStyle(BrandTheme.green)
                    Text("\(data.soc)%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }

            GreenProgressBar(progress: Double(data.soc) / 100, height: 10)

            HStack(alignment: .bottom) {
                Text("\(data.rangeKm) km")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(BrandTheme.green)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Spacer()
                VStack(alignment: .trailing, spacing: 7) {
                    MG4MiniMetric(title: "总里程", value: "\(data.odometerKm.formatted()) km")
                    MG4MiniMetric(title: "车内温度", value: String(format: "%.0f °C", data.cabinTempC))
                    MG4MiniMetric(title: "电瓶电压", value: String(format: "%.1f V", data.batteryVoltageV))
                }
            }

            HStack(spacing: 10) {
                MG4ControlButton(
                    title: data.isLocked ? "车辆已锁" : "车辆未锁",
                    icon: data.isLocked ? "lock.fill" : "lock.open.fill",
                    isLoading: busyAction == .lock || busyAction == .unlock
                ) {
                    onControl(data.isLocked ? .unlock : .lock)
                }
                MG4ControlButton(
                    title: data.isWindowClosed ? "门窗已关" : "门窗未关",
                    icon: "rectangle.split.2x1",
                    isLoading: busyAction == .closeWindows
                ) {
                    onControl(.closeWindows)
                }
            }

            HStack(spacing: 8) {
                MG4TireItem(name: "前左", value: data.tireFrontLeft)
                MG4TireItem(name: "前右", value: data.tireFrontRight)
                MG4TireItem(name: "后左", value: data.tireRearLeft)
                MG4TireItem(name: "后右", value: data.tireRearRight)
            }

            Divider().overlay(Color.white.opacity(0.06))

            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(BrandTheme.green)
                Text(data.address)
                    .font(.caption)
                    .foregroundStyle(BrandTheme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text("更新于 \(timeText(data.updatedAt))")
                    .font(.caption2)
                    .foregroundStyle(BrandTheme.textTertiary)
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(BrandTheme.green)
            }
        }
        .brandCard()
    }
}

// MARK: - 小组件

struct MG4Metric: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(BrandTheme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(BrandTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MG4MiniMetric: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(BrandTheme.textTertiary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }
}

struct MG4StatusBadge: View {
    let title: String
    let ok: Bool
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2.weight(.bold))
            Text(title).font(.caption.weight(.semibold))
        }
        .foregroundStyle(ok ? BrandTheme.green : BrandTheme.danger)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((ok ? BrandTheme.greenDeep : BrandTheme.danger.opacity(0.14)))
        .clipShape(Capsule())
    }
}

struct MG4TireItem: View {
    let name: String
    let value: Double

    var body: some View {
        VStack(spacing: 3) {
            Text(name)
                .font(.caption2)
                .foregroundStyle(BrandTheme.textTertiary)
            Text(String(format: "%.1f", value))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text("bar")
                .font(.system(size: 9))
                .foregroundStyle(BrandTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct MG4ControlButton: View {
    let title: String
    let icon: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().tint(BrandTheme.green).scaleEffect(0.8)
                } else {
                    Image(systemName: icon).font(.footnote.weight(.bold))
                }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(BrandTheme.green)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(BrandTheme.greenDeep)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

private func timeText(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: date)
}
