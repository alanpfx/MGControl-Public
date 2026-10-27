import Foundation

/// 主 App 与小组件共享的车况快照。
///
/// 设计约束：
/// - 只放展示字段，不放 token、账号、密码等任何凭据；
/// - 序列化为 JSON 后控制在 64 KB 以内（Widget 扩展内存上限约 30 MB）；
/// - 可选字段缺失时展示为空占位，不得伪造成实时值。
public struct WidgetSnapshot: Codable, Equatable, Sendable {

    // MARK: 车辆标识（仅展示用）

    public var vehicleName: String
    public var plateNo: String?
    public var powerType: PowerType
    public var online: Bool

    // MARK: 能量

    public var soc: Int?
    public var fuelPercent: Int?
    public var rangeKm: Int?
    public var fullRangeKm: Int?
    public var rangeAchievement: Double?

    // MARK: 状态

    public var locked: Bool
    public var doorsClosed: Bool
    public var windowsClosed: Bool
    public var charging: Bool

    // MARK: 数值

    public var cabinTempC: Double?
    public var exteriorTempC: Double?
    public var batteryVoltageV: Double?
    public var odometerKm: Int?

    // MARK: 胎压

    public var tireText: String?
    public var tireMinBar: Double?
    public var tireAbnormal: Bool

    // MARK: 位置与花费（隐私：只存区/路级别）

    public var parkingArea: String?
    public var totalCost: Double?
    public var totalEnergyKWh: Double?
    public var costPer100Km: Double?

    // MARK: 时间戳

    public var updatedAt: Date

    public init(
        vehicleName: String,
        plateNo: String? = nil,
        powerType: PowerType = .ev,
        online: Bool = false,
        soc: Int? = nil,
        fuelPercent: Int? = nil,
        rangeKm: Int? = nil,
        fullRangeKm: Int? = nil,
        rangeAchievement: Double? = nil,
        locked: Bool = false,
        doorsClosed: Bool = false,
        windowsClosed: Bool = false,
        charging: Bool = false,
        cabinTempC: Double? = nil,
        exteriorTempC: Double? = nil,
        batteryVoltageV: Double? = nil,
        odometerKm: Int? = nil,
        tireText: String? = nil,
        tireMinBar: Double? = nil,
        tireAbnormal: Bool = false,
        parkingArea: String? = nil,
        totalCost: Double? = nil,
        totalEnergyKWh: Double? = nil,
        costPer100Km: Double? = nil,
        updatedAt: Date = Date()
    ) {
        self.vehicleName = vehicleName
        self.plateNo = plateNo
        self.powerType = powerType
        self.online = online
        self.soc = soc
        self.fuelPercent = fuelPercent
        self.rangeKm = rangeKm
        self.fullRangeKm = fullRangeKm
        self.rangeAchievement = rangeAchievement
        self.locked = locked
        self.doorsClosed = doorsClosed
        self.windowsClosed = windowsClosed
        self.charging = charging
        self.cabinTempC = cabinTempC
        self.exteriorTempC = exteriorTempC
        self.batteryVoltageV = batteryVoltageV
        self.odometerKm = odometerKm
        self.tireText = tireText
        self.tireMinBar = tireMinBar
        self.tireAbnormal = tireAbnormal
        self.parkingArea = parkingArea
        self.totalCost = totalCost
        self.totalEnergyKWh = totalEnergyKWh
        self.costPer100Km = costPer100Km
        self.updatedAt = updatedAt
    }
}

// MARK: - 由业务模型构造

public extension WidgetSnapshot {

    /// 从主 App 的实时车况一次性烘焙成展示快照。
    init(vehicle: Vehicle, status: VehicleStatus, stats: ChargingStats? = nil) {
        let tires = status.tirePressure
        let readings = tires?.readings ?? []
        let values = readings.compactMap(\.value)
        let tireText = values.isEmpty
            ? nil
            : values.map { String(format: "%.1f", $0) }.joined(separator: "/")
        let tireMin = values.min()

        var tireAbnormal = false
        if let tires {
            tireAbnormal = readings.contains { reading in
                guard let value = reading.value else { return false }
                return tires.level(value) != .normal
            }
        }

        self.init(
            vehicleName: vehicle.model,
            plateNo: vehicle.plateNo,
            powerType: vehicle.powerType,
            online: status.online,
            soc: status.soc,
            fuelPercent: status.fuelPercent,
            rangeKm: status.rangeKm,
            fullRangeKm: status.fullRangeKm,
            rangeAchievement: status.rangeAchievement,
            locked: status.locked,
            doorsClosed: status.doorsClosed,
            windowsClosed: status.windowsClosed,
            charging: status.charging,
            cabinTempC: status.cabinTempC,
            exteriorTempC: status.exteriorTempC,
            batteryVoltageV: status.batteryVoltageV,
            odometerKm: status.odometerKm,
            tireText: tireText,
            tireMinBar: tireMin,
            tireAbnormal: tireAbnormal,
            parkingArea: status.parkingLocation.map { Self.districtOnly($0.address) },
            totalCost: stats?.totalCost,
            totalEnergyKWh: stats?.totalEnergyKWh,
            costPer100Km: stats.map { $0.costPer100Km },
            updatedAt: status.updatedAt
        )
    }

    /// 隐私裁剪：桌面可见，只保留到「区/县/路」级别。
    static func districtOnly(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        for mark in ["区", "县", "旗"] {
            if let range = trimmed.range(of: mark) {
                let head = String(trimmed[trimmed.startIndex...range.lowerBound])
                return String(head.prefix(14))
            }
        }
        return String(trimmed.prefix(10))
    }
}

// MARK: - 由 MG4 展示模型构造（Dashboard 数据源）

public extension WidgetSnapshot {

    /// `MG4VehicleData` 是车辆页真正刷新的数据源，优先用它烘焙快照。
    init(mg4 data: MG4VehicleData) {
        // 胎压为 0 视为缺失，不能当成「胎压为 0」展示。
        let raw = [data.tireFrontLeft, data.tireFrontRight, data.tireRearLeft, data.tireRearRight]
        let tires = raw.map { $0 > 0 ? $0 : nil }
        let present = tires.compactMap { $0 }
        let recommended = 2.5
        let abnormal = present.contains { $0 < recommended - 0.3 || $0 > recommended + 0.3 }

        self.init(
            vehicleName: data.modelName,
            plateNo: data.plateNo,
            powerType: .ev,
            online: true,
            soc: data.soc,
            fuelPercent: nil,
            rangeKm: data.rangeKm,
            fullRangeKm: data.fullRangeKm,
            rangeAchievement: data.rangeAchievement,
            locked: data.isLocked,
            doorsClosed: data.isWindowClosed,
            windowsClosed: data.isWindowClosed,
            charging: false,
            cabinTempC: data.cabinTempC,
            exteriorTempC: data.exteriorTempC,
            batteryVoltageV: data.batteryVoltageV,
            odometerKm: data.odometerKm,
            tireText: present.isEmpty
                ? nil
                : present.map { String(format: "%.1f", $0) }.joined(separator: "/"),
            tireMinBar: present.min(),
            tireAbnormal: abnormal,
            parkingArea: Self.districtOnly(data.address),
            totalCost: nil,
            totalEnergyKWh: nil,
            costPer100Km: nil,
            updatedAt: data.updatedAt
        )
    }
}

// MARK: - 展示辅助

public extension WidgetSnapshot {

    /// 超过 30 分钟的快照视为陈旧（docs/05 §3.3）。
    static let staleInterval: TimeInterval = 30 * 60

    func isStale(at date: Date) -> Bool {
        let delta = date.timeIntervalSince(updatedAt)
        return delta > Self.staleInterval || delta < -60
    }

    var isStale: Bool { isStale(at: Date()) }

    /// 电量只在 0...100 之间才认为可信。
    var validSOC: Int? {
        guard let soc, (0...100).contains(soc) else { return nil }
        return soc
    }

    var socText: String { validSOC.map { "\($0)%" } ?? "—" }

    var rangeText: String { Self.text(rangeKm.map(Double.init), unit: " km") }

    var achievementText: String {
        guard let rangeAchievement, rangeAchievement > 0 else { return "—" }
        return "\(Int((rangeAchievement * 100).rounded()))%"
    }

    var lockText: String { locked ? "已锁车" : "未锁车" }

    var windowText: String {
        if doorsClosed && windowsClosed { return "门窗已关" }
        if !doorsClosed { return "车门未关" }
        return "车窗未关"
    }

    static func text(_ value: Double?, decimals: Int = 0, unit: String = "", minimum: Double = 0) -> String {
        guard let value, value.isFinite, value >= minimum else { return "—" }
        return String(format: "%.*f", decimals, value) + unit
    }

    /// 预览与 Widget Gallery 使用的示例数据。
    static func preview(name: String = "MG4 EV", stale: Bool = false) -> WidgetSnapshot {
        WidgetSnapshot(
            vehicleName: name,
            plateNo: "沪A·12345",
            powerType: .ev,
            online: true,
            soc: 76,
            rangeKm: 412,
            fullRangeKm: 520,
            rangeAchievement: 0.92,
            locked: true,
            doorsClosed: true,
            windowsClosed: true,
            charging: false,
            cabinTempC: 24.5,
            exteriorTempC: 18,
            batteryVoltageV: 12.4,
            odometerKm: 12680,
            tireText: "2.5/2.4/2.6/2.5",
            tireMinBar: 2.4,
            tireAbnormal: false,
            parkingArea: "上海市黄浦区",
            totalCost: 161.1,
            totalEnergyKWh: 125.8,
            costPer100Km: 12.6,
            updatedAt: stale ? Date().addingTimeInterval(-3600) : Date()
        )
    }
}
