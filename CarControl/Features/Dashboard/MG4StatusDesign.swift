import SwiftUI
import CoreKit

// MARK: - 配色（车况页，深色 + 蓝/绿强调）

enum StatusPalette {
    static let bg = Color(hex: 0x0A0A0B)
    static let card = Color(hex: 0x1C1C1E)
    static let blue = Color(hex: 0x0A84FF)
    static let green = Color(hex: 0x30D158)
    static let orange = Color(hex: 0xFF9F0A)
    static let red = Color(hex: 0xFF453A)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.32)
}

private struct StatusCardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(StatusPalette.card)
            )
    }
}

extension View {
    func statusCard(padding: CGFloat = 16) -> some View {
        modifier(StatusCardModifier(padding: padding))
    }
}

// MARK: - 车况页

struct MG4StatusPage: View {
    let data: MG4VehicleData
    let isRefreshing: Bool
    let onRefresh: () -> Void
    /// 车况页上的快捷车控入口；为 nil 时只读展示。
    var onControl: ((MG4ControlAction) -> Void)? = nil

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 14) {
            hero
            refreshButton
            statusRows
            metrics
            quickControls
            tires
            locationCard
            footer
        }
    }

    // MARK: 概览

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            SOCRing(soc: data.soc)

            VStack(alignment: .leading, spacing: 7) {
                Text(data.trimName.isEmpty ? data.modelName
                     : "\(data.modelName) · \(data.trimName)")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 8) {
                    Text(data.plateNo)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(StatusPalette.blue))

                    HStack(spacing: 4) {
                        Circle().fill(Color.white.opacity(0.6)).frame(width: 5, height: 5)
                        Text("纯电").font(.system(size: 12)).foregroundStyle(StatusPalette.secondary)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("剩余续航").font(.system(size: 12)).foregroundStyle(StatusPalette.secondary)
                    Text("\(data.rangeKm)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("km").font(.system(size: 12)).foregroundStyle(StatusPalette.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("总里程").font(.system(size: 12)).foregroundStyle(StatusPalette.secondary)
                    Text("\(data.odometerKm.formatted())")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("km").font(.system(size: 12)).foregroundStyle(StatusPalette.secondary)
                }

                Text("VIN \(data.vin.isEmpty ? "—" : data.vin)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(StatusPalette.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .statusCard(padding: 18)
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            HStack(spacing: 8) {
                if isRefreshing {
                    ProgressView().controlSize(.small).tint(StatusPalette.blue)
                    Text("正在请求车辆上报最新信息…")
                } else {
                    Image(systemName: "arrow.clockwise")
                    Text("手动刷新车辆信息")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(StatusPalette.blue)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(StatusPalette.blue.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
    }

    // MARK: 门锁 / 门窗

    private var statusRows: some View {
        VStack(spacing: 12) {
            StatusRow(icon: "lock.fill",
                      title: "门锁",
                      value: data.isLocked ? "车辆已锁" : "车辆未锁",
                      pill: data.isLocked ? "已锁好" : "未锁",
                      ok: data.isLocked)

            StatusRow(icon: "car.side.fill",
                      title: "门窗",
                      value: data.isWindowClosed ? "门窗已关" : "门窗未关",
                      pill: data.isWindowClosed ? "全部关闭" : "未关闭",
                      ok: data.isWindowClosed)
        }
    }

    // MARK: 指标网格

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)], spacing: 12) {
            MetricTile(icon: "car.fill", color: StatusPalette.blue,
                       value: "\(data.rangeKm) km", caption: "续航里程")
            MetricTile(icon: "speedometer", color: StatusPalette.orange,
                       value: "\(data.odometerKm.formatted()) km", caption: "总里程")
            MetricTile(icon: "thermometer.medium", color: StatusPalette.red,
                       value: String(format: "%.0f ℃", data.cabinTempC), caption: "车内温度")
            MetricTile(icon: "bolt.car.fill", color: StatusPalette.green,
                       value: String(format: "%.1f V", data.batteryVoltageV), caption: "小电瓶电压")
            MetricTile(icon: "bolt.fill", color: StatusPalette.green,
                       value: data.fullRangeKm.map { "\($0) km" } ?? "—", caption: "满电动态续航")
            MetricTile(icon: "chart.line.uptrend.xyaxis", color: StatusPalette.orange,
                       value: data.rangeAchievement.map { String(format: "%.1f%%", $0 * 100) } ?? "—",
                       caption: "续航达成率")
        }
    }

    // MARK: 胎压

    private var tires: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("胎压监测")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)], spacing: 14) {
                tireRow("前左", data.tireFrontLeft)
                tireRow("前右", data.tireFrontRight)
                tireRow("后左", data.tireRearLeft)
                tireRow("后右", data.tireRearRight)
            }
        }
        .statusCard()
    }

    private func tireRow(_ name: String, _ value: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(name).font(.system(size: 13)).foregroundStyle(StatusPalette.secondary)
            Text(String(format: "%.1f", value))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text("bar").font(.system(size: 11)).foregroundStyle(StatusPalette.tertiary)
            Spacer(minLength: 0)
        }
    }

    // MARK: 位置

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(StatusPalette.blue)

                Text(data.address.isEmpty ? "位置未知" : data.address)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Button(action: openMap) {
                    Text("导航")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(StatusPalette.blue))
                }
                .disabled(data.latitude == nil)
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(StatusPalette.tertiary)
                Text(updateText)
                    .font(.system(size: 12))
                    .foregroundStyle(StatusPalette.secondary)

                Spacer()

                Button(action: onRefresh) {
                    if isRefreshing {
                        ProgressView().controlSize(.mini).tint(StatusPalette.blue)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(StatusPalette.blue)
                    }
                }
            }

            if let lat = data.latitude, let lon = data.longitude {
                Text(String(format: "接口 %.6f,%.6f", lat, lon))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(StatusPalette.tertiary)
            }
        }
        .statusCard()
    }

    private var updateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: data.updatedAt)
        if Date().timeIntervalSince(data.updatedAt) > 15 * 60 {
            return "更新于 \(time)（数据已超过 15 分钟）"
        }
        return "更新于 \(time)"
    }

    // MARK: 快捷车控

    @ViewBuilder
    private var quickControls: some View {
        if let onControl {
            HStack(spacing: 10) {
                quickButton(data.isLocked ? "解锁" : "锁车",
                            icon: data.isLocked ? "lock.open.fill" : "lock.fill") {
                    onControl(data.isLocked ? .unlock : .lock)
                }
                quickButton(data.isWindowClosed ? "开窗通风" : "关闭车窗",
                            icon: "rectangle.split.2x1") {
                    onControl(data.isWindowClosed ? .openWindows : .closeWindows)
                }
            }
        }
    }

    private func quickButton(_ title: String, icon: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(StatusPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(StatusPalette.blue.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(StatusPalette.tertiary)
            Text("数据每 15 分钟自动刷新，以车辆最新上报为准")
                .font(.system(size: 11))
                .foregroundStyle(StatusPalette.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func openMap() {
        guard let lat = data.latitude, let lon = data.longitude,
              let url = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lon)") else { return }
        openURL(url)
    }
}

// MARK: - 组件

struct SOCRing: View {
    let soc: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 13)

            Circle()
                .trim(from: 0, to: min(1, max(0, Double(soc) / 100)))
                .stroke(
                    LinearGradient(colors: [StatusPalette.green.opacity(0.55), StatusPalette.green],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: -2) {
                Text("\(soc)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(StatusPalette.secondary)
            }
        }
        .frame(width: 118, height: 118)
    }
}

struct StatusRow: View {
    let icon: String
    let title: String
    let value: String
    let pill: String
    let ok: Bool

    private var accent: Color { ok ? StatusPalette.green : StatusPalette.orange }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .background(Circle().fill(accent.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12)).foregroundStyle(StatusPalette.secondary)
                Text(value).font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
            }

            Spacer(minLength: 8)

            Text(pill)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(accent.opacity(0.16)))
        }
        .statusCard(padding: 14)
    }
}

struct MetricTile: View {
    let icon: String
    let color: Color
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(StatusPalette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .statusCard(padding: 16)
    }
}
