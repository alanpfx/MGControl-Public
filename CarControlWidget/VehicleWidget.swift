import SwiftUI
import WidgetKit
import CoreKit

// MARK: - 时间线条目

struct VehicleEntry: TimelineEntry {
    let date: Date
    let state: WidgetLoadState

    var snapshot: WidgetSnapshot { state.snapshot }
    var phase: WidgetLoadPhase { state.phase }
}

struct VehicleProvider: TimelineProvider {

    func placeholder(in context: Context) -> VehicleEntry {
        VehicleEntry(date: .now, state: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (VehicleEntry) -> Void) {
        completion(VehicleEntry(date: .now, state: .load(from: .live)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VehicleEntry>) -> Void) {
        let entry = VehicleEntry(date: .now, state: .load(from: .live))
        // 扩展不发网络请求，只读快照；15 分钟后重建时间线让「已过期」提示及时生效。
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget 声明

struct VehicleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CarControl.Vehicle", provider: VehicleProvider()) { entry in
            VehicleWidgetView(entry: entry)
                .widgetURL(WidgetRoute(destination: .home).url)
                .widgetBackground()
        }
        .configurationDisplayName("车辆状态")
        .description("显示最近一次同步的电量、续航、车锁与胎压。点击入口回到 App 确认操作。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - 尺寸分发

struct VehicleWidgetView: View {
    let entry: VehicleEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = WidgetTheme.resolve(scheme)

        if entry.phase == .ready {
            switch family {
            case .systemSmall:
                SmallVehicleView(entry: entry, theme: theme)
            case .systemMedium:
                MediumVehicleView(entry: entry, theme: theme)
            default:
                LargeVehicleView(entry: entry, theme: theme)
            }
        } else {
            WidgetEmptyView(phase: entry.phase, theme: theme)
        }
    }
}

// MARK: - 小尺寸

private struct SmallVehicleView: View {
    let entry: VehicleEntry
    let theme: WidgetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(entry.snapshot.vehicleName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .privacySensitive()
                Spacer(minLength: 0)
                OnlineDot(online: entry.snapshot.online, theme: theme)
            }

            Spacer(minLength: 6)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(entry.snapshot.rangeKm.map { String($0) } ?? "—")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text("km")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondary)
            }

            ProgressBar(progress: entry.snapshot.socProgress, theme: theme)
                .padding(.top, 6)

            Spacer(minLength: 6)

            HStack(spacing: 5) {
                Image(systemName: entry.snapshot.locked ? "lock.fill" : "lock.open.fill")
                Text(entry.snapshot.lockText)
                Spacer(minLength: 0)
                UpdatedText(date: entry.date, snapshot: entry.snapshot, theme: theme)
            }
            .font(.system(size: 10))
            .foregroundStyle(theme.secondary)
        }
        .padding(14)
    }
}

// MARK: - 中尺寸

private struct MediumVehicleView: View {
    let entry: VehicleEntry
    let theme: WidgetTheme

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                Text(entry.snapshot.vehicleName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .privacySensitive()
                OnlineDot(online: entry.snapshot.online, theme: theme)
                Spacer(minLength: 0)
                UpdatedText(date: entry.date, snapshot: entry.snapshot, theme: theme)
                    .font(.system(size: 10))
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(entry.snapshot.rangeKm.map { String($0) } ?? "—")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.accent)
                            .lineLimit(1)
                        Text("km")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.secondary)
                    }

                    ProgressBar(progress: entry.snapshot.socProgress, theme: theme)
                        .frame(width: 96)

                    HStack(spacing: 6) {
                        Text("满电 \(entry.snapshot.fullRangeKm.map { String($0) } ?? "—")")
                        Text("达成 \(entry.snapshot.achievementText)")
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(theme.secondary)
                }

                Spacer(minLength: 0)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                    GridRow {
                        Metric(title: "锁车", value: entry.snapshot.lockText,
                               symbol: entry.snapshot.locked ? "lock.fill" : "lock.open.fill", theme: theme)
                        Metric(title: "车窗", value: entry.snapshot.windowsClosed ? "已关" : "未关",
                               symbol: "rectangle.portrait.and.arrow.right", theme: theme)
                    }
                    GridRow {
                        Metric(title: "车内",
                               value: WidgetSnapshot.text(entry.snapshot.cabinTempC, decimals: 1, unit: "℃", minimum: -40),
                               symbol: "thermometer.medium", theme: theme)
                        Metric(title: "胎压",
                               value: entry.snapshot.tireMinBar.map { String(format: "%.1f", $0) } ?? "—",
                               symbol: "speedometer",
                               theme: theme,
                               warning: entry.snapshot.tireAbnormal)
                    }
                }
            }

            ShortcutLinks(theme: theme)
        }
        .padding(14)
    }
}

// MARK: - 大尺寸

private struct LargeVehicleView: View {
    let entry: VehicleEntry
    let theme: WidgetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text(entry.snapshot.vehicleName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .privacySensitive()
                if let plate = entry.snapshot.plateNo, !plate.isEmpty {
                    Text(plate)
                        .font(.system(size: 9))
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                }
                OnlineDot(online: entry.snapshot.online, theme: theme)
                Spacer(minLength: 0)
                UpdatedText(date: entry.date, snapshot: entry.snapshot, theme: theme)
                    .font(.system(size: 10))
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry.snapshot.rangeKm.map { String($0) } ?? "—")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                Text("km 续航")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.secondary)
                Spacer(minLength: 0)
                Text("满电 \(entry.snapshot.fullRangeKm.map { String($0) } ?? "—") km · 达成 \(entry.snapshot.achievementText)")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
            }

            ProgressBar(progress: entry.snapshot.socProgress, theme: theme)

            Divider().overlay(theme.foreground.opacity(0.08))

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Metric(title: "锁车", value: entry.snapshot.lockText,
                           symbol: entry.snapshot.locked ? "lock.fill" : "lock.open.fill", theme: theme)
                    Metric(title: "门窗", value: entry.snapshot.windowText,
                           symbol: "rectangle.portrait.and.arrow.right", theme: theme)
                    Metric(title: "车内",
                           value: WidgetSnapshot.text(entry.snapshot.cabinTempC, decimals: 1, unit: "℃", minimum: -40),
                           symbol: "thermometer.medium", theme: theme)
                }
                GridRow {
                    Metric(title: "小电瓶",
                           value: WidgetSnapshot.text(entry.snapshot.batteryVoltageV, decimals: 1, unit: "V"),
                           symbol: "battery.100", theme: theme)
                    Metric(title: "充电", value: entry.snapshot.charging ? "充电中" : "未充电",
                           symbol: "bolt.car.fill", theme: theme)
                    Metric(title: "胎压", value: entry.snapshot.tireText ?? "—",
                           symbol: "speedometer", theme: theme, warning: entry.snapshot.tireAbnormal)
                }
            }

            Divider().overlay(theme.foreground.opacity(0.08))

            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                Text(parkingText)
                    .lineLimit(1)
                    .privacySensitive()
                Spacer(minLength: 8)
                if let cost = entry.snapshot.totalCost {
                    Text("累计 ¥\(String(format: "%.1f", cost))")
                        .lineLimit(1)
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(theme.secondary)

            ShortcutLinks(theme: theme)

            Text("点击入口后回到 App 确认操作")
                .font(.system(size: 8))
                .foregroundStyle(theme.tertiary)
        }
        .padding(14)
    }

    private var parkingText: String {
        guard let area = entry.snapshot.parkingArea, !area.isEmpty else { return "暂无停车位置" }
        return area
    }
}

// MARK: - 空态

private struct WidgetEmptyView: View {
    let phase: WidgetLoadPhase
    let theme: WidgetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: "car.fill")
                .font(.system(size: 18))
                .foregroundStyle(theme.accent)
            Text(phase.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.foreground)
            Text(phase.help)
                .font(.system(size: 10))
                .foregroundStyle(theme.secondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }
}

// MARK: - 原子组件

private struct OnlineDot: View {
    let online: Bool
    let theme: WidgetTheme

    var body: some View {
        Circle()
            .fill(online ? theme.accent : theme.tertiary)
            .frame(width: 6, height: 6)
            .accessibilityLabel(online ? "在线" : "离线")
    }
}

private struct ProgressBar: View {
    let progress: Double
    let theme: WidgetTheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.foreground.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(colors: [theme.accentDim, theme.accent],
                                         startPoint: .leading,
                                         endPoint: .trailing))
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("电量")
        .accessibilityValue("\(Int((max(0, min(1, progress)) * 100).rounded()))%")
    }
}

private struct Metric: View {
    let title: String
    let value: String
    let symbol: String
    let theme: WidgetTheme
    var warning: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 8))
                Text(title)
                    .font(.system(size: 8))
            }
            .foregroundStyle(theme.tertiary)

            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(warning ? theme.danger : theme.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct UpdatedText: View {
    let date: Date
    let snapshot: WidgetSnapshot
    let theme: WidgetTheme

    var body: some View {
        let stale = snapshot.isStale(at: date)
        HStack(spacing: 2) {
            if stale {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 8))
            }
            Text(date, format: .dateTime.hour().minute())
        }
        .foregroundStyle(stale ? theme.secondary : theme.tertiary)
        .accessibilityLabel(stale ? "数据可能已过期" : "更新时间")
    }
}

private struct ShortcutLinks: View {
    let theme: WidgetTheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(WidgetRoute.widgetShortcuts) { route in
                Link(destination: route.url) {
                    VStack(spacing: 1) {
                        Image(systemName: route.symbol)
                            .font(.system(size: 12))
                        Text(route.title)
                            .font(.system(size: 8))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(theme.foreground.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .accessibilityLabel("\(route.title)，打开 App 确认")
            }
        }
    }
}

private extension WidgetSnapshot {
    var socProgress: Double { Double(validSOC ?? 0) / 100 }
}
