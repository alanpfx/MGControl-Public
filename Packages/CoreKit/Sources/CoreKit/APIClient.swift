import Foundation

// MARK: - 协议

/// 所有业务调用都通过该协议，便于在 Mock / 真实后端之间切换。
public protocol APIClient: AnyObject {
    func requestSMSCode(phone: String, captchaValidate: String) async throws
    func login(phone: String, code: String) async throws -> LoginResult
    func fetchVehicles(token: String) async throws -> [Vehicle]
    func fetchStatus(token: String, vin: String) async throws -> VehicleStatus
    func sendCommand(token: String, vin: String, command: CommandType) async throws -> CommandResult
    func fetchMessages(token: String) async throws -> [MessageItem]
    func fetchChargingRecords(token: String, vin: String) async throws -> [ChargingRecord]
    func fetchChargingStats(token: String, vin: String) async throws -> ChargingStats
}

// MARK: - Mock 实现（默认，无需后端）

public final class MockAPIClient: APIClient {
    public static let demoCode = "123456"

    private let latency: UInt64
    private var commandSeq = 0

    public init(latencyNanoseconds: UInt64 = 250_000_000) {
        self.latency = latencyNanoseconds
    }

    private func delay() async {
        try? await Task.sleep(nanoseconds: latency)
    }

    public func requestSMSCode(phone: String, captchaValidate: String) async throws {
        try await delay()
        guard phone.count == 11, phone.allSatisfy(\.isNumber) else {
            throw APIError(code: "phone_invalid", message: "请输入正确的手机号")
        }
        // 演示模式不校验图形验证，任意 validate 均可
    }

    public func login(phone: String, code: String) async throws -> LoginResult {
        try await delay()
        guard phone.count == 11 else {
            throw APIError(code: "phone_invalid", message: "请输入正确的手机号")
        }
        guard code == Self.demoCode else {
            throw APIError(code: "14682", message: "验证码有误，请重试（演示码 123456）")
        }
        let user = User(id: "u_10001", phone: phone, nickname: "车主")
        return LoginResult(user: user, token: "mock-token-\(phone)")
    }

    public func fetchVehicles(token: String) async throws -> [Vehicle] {
        try await delay()
        return [
            Vehicle(vin: "LSJA0000000000001", model: "MG4 EV", plateNo: "沪A·D12345", powerType: .ev),
            Vehicle(vin: "LSJA0000000000002", model: "MG7", plateNo: "沪A·F67890", powerType: .fuel)
        ]
    }

    public func fetchStatus(token: String, vin: String) async throws -> VehicleStatus {
        try await delay()
        let isEV = vin.hasSuffix("1")
        return VehicleStatus(
            vin: vin,
            soc: isEV ? 76 : nil,
            fuelPercent: isEV ? nil : 58,
            rangeKm: isEV ? 412 : 486,
            odometerKm: isEV ? 12_680 : 8_420,
            locked: true,
            doorsClosed: true,
            windowsClosed: true,
            charging: false,
            online: true,
            updatedAt: Date(),
            cabinTempC: isEV ? 24.5 : 27.0,
            batteryVoltageV: isEV ? 12.4 : 12.1,
            fullRangeKm: isEV ? 520 : 620,
            rangeAchievement: isEV ? 0.92 : 0.88,
            tirePressure: TirePressure(frontLeft: 2.5, frontRight: 2.4, rearLeft: 2.6, rearRight: 2.5),
            parkingLocation: ParkingLocation(
                latitude: 31.2304,
                longitude: 121.4737,
                address: "上海市黄浦区人民大道 200 号",
                updatedAt: Date().addingTimeInterval(-900)
            )
        )
    }

    public func sendCommand(token: String, vin: String, command: CommandType) async throws -> CommandResult {
        try await delay()
        commandSeq += 1
        return CommandResult(
            commandId: "cmd_\(commandSeq)",
            accepted: true,
            message: "\(command.title)指令已下发"
        )
    }

    public func fetchMessages(token: String) async throws -> [MessageItem] {
        try await delay()
        return [
            MessageItem(id: "m1", title: "车门未锁提醒", body: "您的车辆主驾车门未锁，请及时锁车。", date: Date().addingTimeInterval(-600)),
            MessageItem(id: "m2", title: "车窗未关提醒", body: "检测到车窗未关闭，建议远程关窗。", date: Date().addingTimeInterval(-3600)),
            MessageItem(id: "m3", title: "系统消息", body: "欢迎使用「车控」，当前为 Mock 演示数据。", date: Date().addingTimeInterval(-86400))
        ]
    }

    public func fetchChargingRecords(token: String, vin: String) async throws -> [ChargingRecord] {
        try await delay()
        let now = Date()
        return [
            ChargingRecord(id: "c1", startTime: now.addingTimeInterval(-86_400 * 2),
                           endTime: now.addingTimeInterval(-86_400 * 2 + 3_900),
                           energyKWh: 42.6, startSoc: 22, endSoc: 88, cost: 55.4,
                           stationName: "国网上海人民广场充电站", isFastCharge: true),
            ChargingRecord(id: "c2", startTime: now.addingTimeInterval(-86_400 * 5),
                           endTime: now.addingTimeInterval(-86_400 * 5 + 6_300),
                           energyKWh: 38.2, startSoc: 15, endSoc: 80, cost: 38.2,
                           stationName: "小区地下车库私桩", isFastCharge: false),
            ChargingRecord(id: "c3", startTime: now.addingTimeInterval(-86_400 * 9),
                           endTime: now.addingTimeInterval(-86_400 * 9 + 3_600),
                           energyKWh: 45.0, startSoc: 18, endSoc: 95, cost: 67.5,
                           stationName: "特来电充电站", isFastCharge: true)
        ]
    }

    public func fetchChargingStats(token: String, vin: String) async throws -> ChargingStats {
        try await delay()
        return ChargingStats(totalEnergyKWh: 186.5, totalCost: 205.2, totalDistanceKm: 1_280)
    }
}

// MARK: - 真实后端实现（接 TSP 时替换）

/// 说明：真实接口的签名/加密（时间戳、nonce、appSecret）需按后端文档实现，
/// 当前仅提供通用 JSON 调用骨架，签名逻辑留 TODO。
public final class RemoteAPIClient: APIClient {
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

    public func requestSMSCode(phone: String, captchaValidate: String) async throws {
        let _: EmptyResponse = try await request(path: "/api/auth/sms",
                                                method: "POST",
                                                body: ["phone": phone,
                                                       "captchaValidate": captchaValidate],
                                                token: nil)
    }

    public func login(phone: String, code: String) async throws -> LoginResult {
        try await request(path: "/api/auth/login", method: "POST", body: ["phone": phone, "code": code], token: nil)
    }

    public func fetchVehicles(token: String) async throws -> [Vehicle] {
        try await request(path: "/api/vehicles", method: "GET", body: nil, token: token)
    }

    public func fetchStatus(token: String, vin: String) async throws -> VehicleStatus {
        try await request(path: "/api/vehicles/\(vin)/status", method: "GET", body: nil, token: token)
    }

    public func sendCommand(token: String, vin: String, command: CommandType) async throws -> CommandResult {
        try await request(path: "/api/vehicles/\(vin)/commands",
                          method: "POST",
                          body: ["type": command.rawValue],
                          token: token)
    }

    public func fetchMessages(token: String) async throws -> [MessageItem] {
        try await request(path: "/api/messages", method: "GET", body: nil, token: token)
    }

    public func fetchChargingRecords(token: String, vin: String) async throws -> [ChargingRecord] {
        try await request(path: "/api/vehicles/\(vin)/charging/records", method: "GET", body: nil, token: token)
    }

    public func fetchChargingStats(token: String, vin: String) async throws -> ChargingStats {
        try await request(path: "/api/vehicles/\(vin)/charging/stats", method: "GET", body: nil, token: token)
    }

    // MARK: - 私有

    private func request<T: Decodable>(path: String,
                                       method: String,
                                       body: [String: String]?,
                                       token: String?) async throws -> T {
        var req = URLRequest(url: URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // TODO: 在此加入 X-Timestamp / X-Nonce / X-Sign 等签名头（按后端文档）
        if let body {
            req.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(code: "network", message: "网络异常")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let err = try? decoder.decode(ErrorEnvelope.self, from: data) {
                throw APIError(code: err.code, message: err.message)
            }
            throw APIError(code: "http_\(http.statusCode)", message: "服务异常（\(http.statusCode)）")
        }
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        return try decoder.decode(T.self, from: data)
    }
}

struct EmptyResponse: Decodable {}

struct ErrorEnvelope: Decodable {
    let code: String
    let message: String
}
