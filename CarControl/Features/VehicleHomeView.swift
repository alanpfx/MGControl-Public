import SwiftUI
import CoreKit

struct VehicleHomeView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let vehicle = app.selectedVehicle {
                        vehicleHeader(vehicle)
                        rangeSection
                        stateSection
                        if let pressure = app.status?.tirePressure {
                            TirePressureCard(pressure: pressure)
                        }
                        if let parking = app.status?.parkingLocation {
                            ParkingCard(parking: parking)
                        }
                        chargingSection
                        DigitalKeyCard()
                    } else if app.isLoading {
                        ProgressView("加载车辆…").padding(.top, 80)
                    } else {
                        emptyState
                    }
                }
                .padding(Theme.pagePadding)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("车辆")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await app.refreshStatus()
                            await app.loadChargingData()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(app.selectedVehicle == nil || app.isLoading)
                }
            }
            .task {
                if app.vehicles.isEmpty { await app.loadVehicles() }
                await app.loadChargingData()
            }
            .refreshable {
                await app.refreshStatus()
                await app.loadChargingData()
            }
        }
    }

    // MARK: - 头部

    private func vehicleHeader(_ vehicle: Vehicle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    ForEach(app.vehicles) { item in
                        Button {
                            Task {
                                await app.select(item)
                                await app.loadChargingData()
                            }
                        } label: {
                            if item.vin == vehicle.vin {
                                Label(item.model, systemImage: "checkmark")
                            } else {
                                Text(item.model)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(vehicle.model).font(.title2.bold())
                        Image(systemName: "chevron.down").font(.footnote)
                    }
                    .foregroundStyle(Theme.primary)
                }
                Spacer()
                onlineBadge
            }
            HStack(spacing: 8) {
                Text(vehicle.plateNo ?? vehicle.vin)
                Text("·")
                Text(powerText(vehicle.powerType))
                Spacer()
                Text(updateText)
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button {
                Task {
                    await app.refreshStatus()
                    await app.loadChargingData()
                }
            } label: {
                HStack(spacing: 6) {
                    if app.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(app.isLoading ? "正在请求车辆上报…" : "手动刷新车辆信息")
                }
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(app.selectedVehicle == nil || app.isLoading)
        }
        .card()
    }

    private var onlineBadge: some View {
        let online = app.status?.online ?? false
        return HStack(spacing: 4) {
            Circle().fill(online ? Theme.success : Color.secondary).frame(width: 6, height: 6)
            Text(online ? "在线" : "离线").font(.caption)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background((online ? Theme.success : Color.secondary).opacity(0.12))
        .clipShape(Capsule())
    }

    private var updateText: String {
        guard let date = app.status?.updatedAt else { return "暂无更新时间" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "更新于 \(f.string(from: date))"
    }

    private func powerText(_ type: PowerType) -> String {
        switch type {
        case .ev: return "纯电"
        case .fuel: return "燃油"
        case .hybrid: return "混动"
        }
    }

    // MARK: - 续航与能耗

    private var rangeSection: some View {
        let status = app.status
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle("续航与能耗")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCard("当前续航", status?.rangeKm.map { "\($0) km" } ?? "--", "bolt.fill")
                statCard("满电动态续航", status?.fullRangeKm.map { "\($0) km" } ?? "--", "battery.100")
                statCard("续航达成率", achievementText(status?.rangeAchievement), "chart.line.uptrend.xyaxis")
                statCard("总里程", status?.odometerKm.map { "\($0) km" } ?? "--", "gauge.with.dots.needle.33percent")
            }
        }
    }

    private func achievementText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f%%", value * 100)
    }

    // MARK: - 车辆状态

    private var stateSection: some View {
        let status = app.status
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle("车辆状态")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let soc = status?.soc {
                    statCard("电量", "\(soc)%", "battery.75")
                } else if let fuel = status?.fuelPercent {
                    statCard("油量", "\(fuel)%", "fuelpump.fill")
                } else {
                    statCard("电量", "--", "battery.75")
                }
                statCard("锁止", (status?.locked ?? false) ? "已锁" : "未锁", "lock.fill")
                statCard("门窗", (status?.doorsClosed ?? false) && (status?.windowsClosed ?? false) ? "已关" : "未关", "door.left.hand.closed")
                statCard("车内温度", status?.cabinTempC.map { String(format: "%.1f ℃", $0) } ?? "--", "thermometer.medium")
                statCard("小电瓶", status?.batteryVoltageV.map { String(format: "%.1f V", $0) } ?? "--", "minus.plus.batteryblock")
                statCard("充电", (status?.charging ?? false) ? "充电中" : "未充电", "ev.charger")
            }
        }
    }

    private func statCard(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon).foregroundStyle(Theme.accent)
                Spacer()
            }
            Text(value).font(.title3.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - 充电

    private var chargingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("充电与花费")
            VStack(alignment: .leading, spacing: 14) {
                if let stats = app.chargingStats {
                    HStack {
                        statColumn("总费用", String(format: "¥%.1f", stats.totalCost))
                        Divider().frame(height: 36)
                        statColumn("总电量", String(format: "%.1f kWh", stats.totalEnergyKWh))
                        Divider().frame(height: 36)
                        statColumn("百公里花费", String(format: "¥%.1f", stats.costPer100Km))
                    }
                    NavigationLink {
                        ChargingRecordsView()
                    } label: {
                        HStack {
                            Label("充电记录", systemImage: "bolt.car")
                            Spacer()
                            Text("\(app.chargingRecords.count) 条")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                } else {
                    HStack {
                        ProgressView()
                        Text("暂无充电数据").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func statColumn(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "car").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("暂无车辆").font(.headline)
            Text("请先在官方 App 完成绑车与激活，然后回到这里刷新。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("加载车辆") { Task { await app.loadVehicles() } }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
        }
        .padding(.top, 80)
    }
}

// MARK: - 胎压

struct TirePressureCard: View {
    let pressure: TirePressure

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("胎压监测", systemImage: "car.side")
                    .font(.headline)
                Spacer()
                if let recommended = pressure.recommended {
                    Text("推荐 \(String(format: "%.1f", recommended)) \(pressure.unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(pressure.readings) { item in
                    HStack {
                        Text(item.name).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(item.value.map { String(format: "%.1f", $0) } ?? "--")
                            .font(.headline)
                            .foregroundStyle(color(for: pressure.level(item.value)))
                        Text(pressure.unit).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func color(for level: TireLevel) -> Color {
        switch level {
        case .low: return Theme.warning
        case .high: return Theme.danger
        case .normal: return Theme.success
        case .unknown: return .secondary
        }
    }
}

// MARK: - 停车位置

struct ParkingCard: View {
    let parking: ParkingLocation
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("停车位置", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                Spacer()
                Button("导航") { openInMaps() }
                    .font(.footnote.weight(.semibold))
            }
            Text(parking.address)
                .font(.subheadline)
            Text("更新于 \(timeText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var timeText: String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: parking.updatedAt)
    }

    private func openInMaps() {
        var comps = URLComponents(string: "http://maps.apple.com/")
        comps?.queryItems = [
            URLQueryItem(name: "ll", value: "\(parking.latitude),\(parking.longitude)"),
            URLQueryItem(name: "q", value: parking.address)
        ]
        if let url = comps?.url { openURL(url) }
    }
}
