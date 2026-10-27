import Foundation

// MARK: - MG4 车辆状态（需求文档字段）

public struct MG4VehicleData: Codable, Equatable, Sendable {
    public var modelName: String       // 名爵 MG4
    public var trimName: String        // 电掣风行
    public var plateNo: String         // 辽F·D00273
    public var rangeKm: Int            // 剩余续航
    public var soc: Int                // 剩余电量 %
    public var odometerKm: Int         // 总里程
    public var cabinTempC: Double      // 车内温度
    public var batteryVoltageV: Double // 电瓶电压
    public var isLocked: Bool
    public var isWindowClosed: Bool
    public var tireFrontLeft: Double
    public var tireFrontRight: Double
    public var tireRearLeft: Double
    public var tireRearRight: Double
    public var address: String
    public var updatedAt: Date
    public var vin: String            // 车架号
    public var exteriorTempC: Double? // 车外温度
    public var fullRangeKm: Int?      // 满电动态续航（按 SOC 折算）
    public var rangeAchievement: Double? // 续航达成率 = 满电动态 / CLTC 额定
    public var latitude: Double?      // 车端上报纬度
    public var longitude: Double?     // 车端上报经度

    public init(modelName: String = "名爵 MG4",
                trimName: String = "电掣风行",
                plateNo: String = "辽F·D00273",
                rangeKm: Int = 211,
                soc: Int = 55,
                odometerKm: Int = 1710,
                cabinTempC: Double = 23,
                batteryVoltageV: Double = 12.6,
                isLocked: Bool = true,
                isWindowClosed: Bool = true,
                tireFrontLeft: Double = 2.5,
                tireFrontRight: Double = 2.6,
                tireRearLeft: Double = 2.5,
                tireRearRight: Double = 2.5,
                address: String = "辽宁省大连市中山区人民路 15 号",
                updatedAt: Date = Date(),
                vin: String = "",
                exteriorTempC: Double? = nil,
                fullRangeKm: Int? = 384,
                rangeAchievement: Double? = 0.878,
                latitude: Double? = nil,
                longitude: Double? = nil) {
        self.modelName = modelName
        self.trimName = trimName
        self.plateNo = plateNo
        self.rangeKm = rangeKm
        self.soc = soc
        self.odometerKm = odometerKm
        self.cabinTempC = cabinTempC
        self.batteryVoltageV = batteryVoltageV
        self.isLocked = isLocked
        self.isWindowClosed = isWindowClosed
        self.tireFrontLeft = tireFrontLeft
        self.tireFrontRight = tireFrontRight
        self.tireRearLeft = tireRearLeft
        self.tireRearRight = tireRearRight
        self.address = address
        self.updatedAt = updatedAt
        self.vin = vin
        self.exteriorTempC = exteriorTempC
        self.fullRangeKm = fullRangeKm
        self.rangeAchievement = rangeAchievement
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum MG4ControlAction: String, Codable, Sendable {
    case lock, unlock, closeWindows, openWindows
}

public protocol MG4API: AnyObject {
    func fetchMG4Status(token: String) async throws -> MG4VehicleData
    func refreshMG4Status(token: String) async throws -> MG4VehicleData
    func controlMG4(token: String, action: MG4ControlAction) async throws
}

// MARK: - Mock（默认，无需后端）

public final class MockMG4API: MG4API {
    private var data: MG4VehicleData
    private let latency: UInt64

    public init(latencyNanoseconds: UInt64 = 600_000_000) {
        self.data = MG4VehicleData()
        self.latency = latencyNanoseconds
    }

    private func delay() async {
        try? await Task.sleep(nanoseconds: latency)
    }

    public func fetchMG4Status(token: String) async throws -> MG4VehicleData {
        try await delay()
        if token.isEmpty {
            throw APIError(code: "14101", message: "登录已过期，请重新登录")
        }
        if token.contains("expired") {
            throw APIError(code: "14101", message: "登录已过期，请重新登录")
        }
        if token.contains("no-vehicle") {
            throw APIError(code: "10500702", message: "账户未绑定车辆")
        }
        data.updatedAt = Date()
        return data
    }

    public func refreshMG4Status(token: String) async throws -> MG4VehicleData {
        try await delay()
        guard !token.isEmpty, !token.contains("expired") else {
            throw APIError(code: "14101", message: "登录已过期，请重新登录")
        }
        data.updatedAt = Date()
        return data
    }

    public func controlMG4(token: String, action: MG4ControlAction) async throws {
        try await delay()
        guard !token.isEmpty, !token.contains("expired") else {
            throw APIError(code: "14101", message: "登录已过期，请重新登录")
        }
        switch action {
        case .lock: data.isLocked = true
        case .unlock: data.isLocked = false
        case .closeWindows: data.isWindowClosed = true
        case .openWindows: data.isWindowClosed = false
        }
        data.updatedAt = Date()
    }
}

// MARK: - 真实后端骨架

public final class RemoteMG4API: MG4API {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        self.decoder = d
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        self.encoder = e
    }

    public func fetchMG4Status(token: String) async throws -> MG4VehicleData {
        try await request(path: "/api/vehicle/status", method: "GET", body: nil, token: token)
    }

    public func refreshMG4Status(token: String) async throws -> MG4VehicleData {
        try await request(path: "/api/vehicle/refresh", method: "POST", body: nil, token: token)
    }

    public func controlMG4(token: String, action: MG4ControlAction) async throws {
        let _: EmptyResponse = try await request(path: "/api/vehicle/control",
                                                method: "POST",
                                                body: ["action": action.rawValue],
                                                token: token)
    }

    private func request<T: Decodable>(path: String, method: String,
                                       body: [String: String]?, token: String) async throws -> T {
        var req = URLRequest(url: URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body { req.httpBody = try encoder.encode(body) }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(code: "network", message: "网络异常")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let err = try? decoder.decode(ErrorEnvelope.self, from: data) {
                throw APIError(code: err.code, message: err.message)
            }
            throw APIError(code: "http_\(http.statusCode)", message: "服务异常")
        }
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        return try decoder.decode(T.self, from: data)
    }
}
