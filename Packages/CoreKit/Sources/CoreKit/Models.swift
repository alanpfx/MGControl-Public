import Foundation

// MARK: - 用户与登录

public struct User: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let phone: String
    public let nickname: String?

    public init(id: String, phone: String, nickname: String? = nil) {
        self.id = id
        self.phone = phone
        self.nickname = nickname
    }

    public var maskedPhone: String {
        guard phone.count == 11 else { return phone }
        let start = phone.prefix(3)
        let end = phone.suffix(4)
        return "\(start)****\(end)"
    }
}

public struct LoginResult: Codable, Sendable {
    public let user: User
    public let token: String

    public init(user: User, token: String) {
        self.user = user
        self.token = token
    }
}

// MARK: - 车辆

public struct Vehicle: Codable, Equatable, Identifiable, Sendable {
    public let vin: String
    public let model: String
    public let plateNo: String?
    public let powerType: PowerType

    public init(vin: String, model: String, plateNo: String? = nil, powerType: PowerType) {
        self.vin = vin
        self.model = model
        self.plateNo = plateNo
        self.powerType = powerType
    }

    public var id: String { vin }
}

public enum PowerType: String, Codable, Sendable {
    case fuel   // 燃油
    case ev     // 纯电
    case hybrid // 混动
}

public struct VehicleStatus: Codable, Equatable, Sendable {
    public let vin: String
    public let soc: Int?            // 电量 %
    public let fuelPercent: Int?    // 油量 %
    public let rangeKm: Int?        // 当前表显续航 km
    public let odometerKm: Int?     // 总里程
    public let locked: Bool
    public let doorsClosed: Bool
    public let windowsClosed: Bool
    public let charging: Bool
    public let online: Bool
    public let updatedAt: Date

    // 扩展字段（本次新增）
    public let cabinTempC: Double?          // 车内温度 ℃
    public let batteryVoltageV: Double?     // 小电瓶电压 V
    public let fullRangeKm: Int?            // 满电动态续航 km
    public let rangeAchievement: Double?    // 续航达成率 0~1.2
    public let tirePressure: TirePressure?  // 胎压
    public let parkingLocation: ParkingLocation? // 停车位置
    public let exteriorTempC: Double?       // 车外温度 ℃

    public init(vin: String, soc: Int?, fuelPercent: Int?, rangeKm: Int?, odometerKm: Int?,
                locked: Bool, doorsClosed: Bool, windowsClosed: Bool, charging: Bool,
                online: Bool, updatedAt: Date,
                cabinTempC: Double? = nil, batteryVoltageV: Double? = nil,
                fullRangeKm: Int? = nil, rangeAchievement: Double? = nil,
                tirePressure: TirePressure? = nil, parkingLocation: ParkingLocation? = nil,
                exteriorTempC: Double? = nil) {
        self.vin = vin
        self.soc = soc
        self.fuelPercent = fuelPercent
        self.rangeKm = rangeKm
        self.odometerKm = odometerKm
        self.locked = locked
        self.doorsClosed = doorsClosed
        self.windowsClosed = windowsClosed
        self.charging = charging
        self.online = online
        self.updatedAt = updatedAt
        self.cabinTempC = cabinTempC
        self.batteryVoltageV = batteryVoltageV
        self.fullRangeKm = fullRangeKm
        self.rangeAchievement = rangeAchievement
        self.tirePressure = tirePressure
        self.parkingLocation = parkingLocation
        self.exteriorTempC = exteriorTempC
    }
}

public struct TirePressure: Codable, Equatable, Sendable {
    public let frontLeft: Double?
    public let frontRight: Double?
    public let rearLeft: Double?
    public let rearRight: Double?
    public let unit: String
    public let recommended: Double?

    public init(frontLeft: Double?, frontRight: Double?, rearLeft: Double?, rearRight: Double?,
                unit: String = "bar", recommended: Double? = 2.5) {
        self.frontLeft = frontLeft
        self.frontRight = frontRight
        self.rearLeft = rearLeft
        self.rearRight = rearRight
        self.unit = unit
        self.recommended = recommended
    }

    public var readings: [TireReading] {
        [
            TireReading(id: "fl", name: "左前", value: frontLeft),
            TireReading(id: "fr", name: "右前", value: frontRight),
            TireReading(id: "rl", name: "左后", value: rearLeft),
            TireReading(id: "rr", name: "右后", value: rearRight)
        ]
    }

    /// 胎压状态：偏低 / 正常 / 偏高
    public func level(_ value: Double?) -> TireLevel {
        guard let value, let recommended else { return .unknown }
        if value < recommended - 0.3 { return .low }
        if value > recommended + 0.3 { return .high }
        return .normal
    }
}

public enum TireLevel: String, Sendable {
    case low, normal, high, unknown
}

public struct TireReading: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let value: Double?

    public init(id: String, name: String, value: Double?) {
        self.id = id
        self.name = name
        self.value = value
    }
}

public struct ParkingLocation: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let address: String
    public let updatedAt: Date

    public init(latitude: Double, longitude: Double, address: String, updatedAt: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.updatedAt = updatedAt
    }
}

// MARK: - 充电记录

public struct ChargingRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let startTime: Date
    public let endTime: Date
    public let energyKWh: Double
    public let startSoc: Int
    public let endSoc: Int
    public let cost: Double
    public let stationName: String?
    public let isFastCharge: Bool

    public init(id: String, startTime: Date, endTime: Date, energyKWh: Double,
                startSoc: Int, endSoc: Int, cost: Double,
                stationName: String? = nil, isFastCharge: Bool = false) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.energyKWh = energyKWh
        self.startSoc = startSoc
        self.endSoc = endSoc
        self.cost = cost
        self.stationName = stationName
        self.isFastCharge = isFastCharge
    }

    public var durationMinutes: Int {
        max(0, Int(endTime.timeIntervalSince(startTime) / 60))
    }
}

public struct ChargingStats: Codable, Equatable, Sendable {
    public let totalEnergyKWh: Double
    public let totalCost: Double
    public let totalDistanceKm: Int

    public init(totalEnergyKWh: Double, totalCost: Double, totalDistanceKm: Int) {
        self.totalEnergyKWh = totalEnergyKWh
        self.totalCost = totalCost
        self.totalDistanceKm = totalDistanceKm
    }

    /// 百公里花费（元/100km）
    public var costPer100Km: Double {
        guard totalDistanceKm > 0 else { return 0 }
        return totalCost / Double(totalDistanceKm) * 100
    }

    /// 平均电价（元/kWh）
    public var averagePricePerKWh: Double {
        guard totalEnergyKWh > 0 else { return 0 }
        return totalCost / totalEnergyKWh
    }
}

// MARK: - 车控

public enum CommandType: String, Codable, CaseIterable, Sendable {
    case lock, unlock
    case windowClose, windowOpen
    case acOn, acOff
    case trunkOpen
    case findCar

    public var title: String {
        switch self {
        case .lock: return "锁车"
        case .unlock: return "解锁"
        case .windowClose: return "关窗"
        case .windowOpen: return "开窗"
        case .acOn: return "开空调"
        case .acOff: return "关空调"
        case .trunkOpen: return "开后备箱"
        case .findCar: return "寻车"
        }
    }

    /// 高危指令需要二次确认
    public var requiresConfirm: Bool {
        switch self {
        case .unlock, .trunkOpen, .windowOpen: return true
        default: return false
        }
    }
}

public extension CommandType {
    /// 所有控车指令都需要 pvCode（服务端 auth_type=2），未验证时由调用方先引导输入安全码。
    var requiresAuthCode: Bool { true }

    /// 能否用「车辆状态」反向确认指令生效（锁止 / 门窗类）。
    var isStateVerifiable: Bool {
        switch self {
        case .lock, .unlock, .windowClose, .windowOpen: return true
        case .acOn, .acOff, .trunkOpen, .findCar: return false
        }
    }

    /// 服务端受理后，车况是否已经体现该指令的效果。
    func isSatisfied(by status: VehicleStatus) -> Bool {
        switch self {
        case .lock: return status.locked
        case .unlock: return !status.locked
        case .windowClose: return status.windowsClosed
        case .windowOpen: return !status.windowsClosed
        case .acOn, .acOff, .trunkOpen, .findCar: return false
        }
    }
}

public struct CommandResult: Codable, Equatable, Sendable {
    public let commandId: String
    public let accepted: Bool
    public let message: String?

    public init(commandId: String, accepted: Bool, message: String? = nil) {
        self.commandId = commandId
        self.accepted = accepted
        self.message = message
    }
}

// MARK: - 消息

public struct MessageItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let date: Date
    public let read: Bool

    public init(id: String, title: String, body: String, date: Date, read: Bool = false) {
        self.id = id
        self.title = title
        self.body = body
        self.date = date
        self.read = read
    }
}

// MARK: - 错误

/// 客户端内部错误码（非服务端返回），用于驱动「去验证安全码 / 去重新登录」等交互。
public enum ControlErrorCode {
    /// 需要先验证控车安全码（pvCode 缺失或过期）
    public static let needPin = "need_pin"
    /// 登录态失效，需要重新登录
    public static let sessionExpired = "14101"
}

public struct APIError: Error, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}
