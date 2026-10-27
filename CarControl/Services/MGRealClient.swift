import Foundation
import CoreKit
import CryptoKit
import CoreLocation

/// 真实 MG Live 后端客户端（协议来自抓包复现，见 docs/06-真机接入与车控.md）。
///
/// 关键链路：
/// 1. 短信登录：易盾 H5 取 validate → `uais/1.1/graphicVerificationV2` 发码 →
///    `uais/1.0/quickLoginByVcodeV2` 换 tocToken；
/// 2. 会话：tocToken（capi 域）→ `getOutSideServiceToken` 换 swapToken（mp 域）；
/// 3. 车控：`user/1.2/checkPINCode` 换 pvCode（约 4 分钟）→ `vp/1.1/request*` 下发，
///    下发后用 `vp/1.2/getVehicleStatus` 反向确认锁 / 窗状态。
///
/// 令牌落 Keychain（`SessionStore`），不再明文写 UserDefaults。
final class MGRealClient: APIClient {
    /// 全局会话：登录后 token 由这里持有，仪表盘共用
    static let shared = MGRealClient()

    // MARK: - 常量

    private let capi = URL(string: "https://capi-pv.saicmotor.com")!
    private let mp = URL(string: "https://mp.ebanma.com")!

    /// 车辆 CLTC 额定续航（km）。默认 MG4 EV 437km 版本，可用环境变量 MG_RATED_RANGE 覆盖。
    static var ratedRangeKm: Double {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["MG_RATED_RANGE"], let v = Double(raw) { return v }
        #endif
        return 437
    }

    /// 设备标识：首次启动生成并持久化（官方客户端也是每台设备唯一）
    private let deviceUUID: String = {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "mg.uuid") { return value }
        let value = UUID().uuidString
        defaults.set(value, forKey: "mg.uuid")
        return value
    }()

    private let deviceId: String = {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "mg.deviceId") { return value }
        let value = (0..<32).map { _ in String(format: "%x", Int.random(in: 0...15)) }.joined()
        defaults.set(value, forKey: "mg.deviceId")
        return value
    }()

    private(set) var tocToken: String = ""
    private(set) var swapToken: String = ""
    private(set) var sessionIssuedAt: Date = .distantPast

    /// pvCode（控车授权码），有效期约 4 分钟
    private var authCode: String?
    private var authCodeExpiry: Date = .distantPast

    private enum Keys {
        static let toc = "mg.toc"
        static let swap = "mg.swap"
        static let phone = "mg.phone"
        static let nick = "mg.nick"
        static let uid = "mg.uid"
        static let issuedAt = "mg.issuedAt"
    }

    init() {
        SessionStore.migrateLegacyTokens()
        tocToken = SessionStore.token(Keys.toc) ?? ""
        swapToken = SessionStore.token(Keys.swap) ?? ""
        sessionIssuedAt = UserDefaults.standard.object(forKey: Keys.issuedAt) as? Date ?? .distantPast
    }

    // MARK: - 会话状态

    var hasSession: Bool { !tocToken.isEmpty }

    var hasValidAuthCode: Bool {
        authCode != nil && Date() < authCodeExpiry
    }

    var savedProfile: (phone: String, nick: String, uid: String)? {
        let d = UserDefaults.standard
        guard let phone = d.string(forKey: Keys.phone), !phone.isEmpty else { return nil }
        return (phone, d.string(forKey: Keys.nick) ?? "", d.string(forKey: Keys.uid) ?? "")
    }

    private func persistTokens() {
        SessionStore.save(token: tocToken, key: Keys.toc)
        SessionStore.save(token: swapToken, key: Keys.swap)
        UserDefaults.standard.set(sessionIssuedAt, forKey: Keys.issuedAt)
    }

    func install(toc: String, swap: String) {
        tocToken = toc
        swapToken = swap
        sessionIssuedAt = Date()
        persistTokens()
    }

    func clearSession() {
        tocToken = ""
        swapToken = ""
        sessionIssuedAt = .distantPast
        authCode = nil
        authCodeExpiry = .distantPast
        SessionStore.clearTokens()
        UserDefaults.standard.removeObject(forKey: Keys.issuedAt)
    }

    func invalidateAuthCode() {
        authCode = nil
        authCodeExpiry = .distantPast
    }

    /// 启动时恢复会话：主动换一次 swapToken（它有独立生命周期，只在为空时换会一直用到过期）。
    func restoreSession() async -> Bool {
        guard hasSession else { return false }
        do {
            _ = try await refreshSwapToken()
            return true
        } catch {
            // 换失败但本地还有旧的 swapToken 时先放行，真正的 14101 会由业务请求暴露
            return !swapToken.isEmpty
        }
    }

    // MARK: - 请求封装

    private func send(_ method: String,
                      base: URL,
                      path: String,
                      data: [String: Any]?,
                      query: [String: String]) async throws -> [String: Any] {
        let timestamp = self.timestamp()
        let json = try data.map { try jsonString($0) }
        var request: URLRequest

        if method == "GET" {
            var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            if let json {
                items.append(URLQueryItem(name: "data", value: json))
            }
            let url = base.appendingPathComponent(path)
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            comps.queryItems = items
            request = URLRequest(url: comps.url ?? url)
            request.httpMethod = "GET"
        } else {
            request = URLRequest(url: base.appendingPathComponent(path))
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            if let json {
                let body = "data=" + (json.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? json)
                request.httpBody = body.data(using: .utf8)
            }
        }

        var headers = commonHeaders()
        headers["timestamp"] = timestamp
        headers["sign"] = Self.sign(path: path, timestamp: timestamp, data: json ?? "")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (raw, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(code: "network", message: "网络异常（HTTP）")
        }
        guard let object = try? JSONSerialization.jsonObject(with: raw),
              let dict = object as? [String: Any] else {
            throw APIError(code: "decode", message: "返回格式异常")
        }
        if let err = dict["err_resp"] as? [String: Any] {
            let code = err["code"] as? String ?? "unknown"
            let serverMessage = err["msg"] as? String
            let message = (serverMessage?.isEmpty == false ? serverMessage : nil)
                ?? Self.message(for: code)
            throw APIError(code: code, message: message)
        }
        return dict
    }

    /// 带一次会话自愈的调用：mp 域 token 失效能换就换，capi 域失效只能重新登录。
    private func call(_ method: String,
                      base: URL,
                      path: String,
                      data: [String: Any]? = nil,
                      query: [String: String] = [:],
                      retrySession: Bool = true) async throws -> [String: Any] {
        do {
            return try await send(method, base: base, path: path, data: data, query: query)
        } catch let err as APIError where retrySession && Self.isSessionError(err.code) {
            if base == mp, !swapToken.isEmpty {
                try? await refreshSwapToken()
                return try await send(method, base: base, path: path, data: data, query: query)
            }
            throw APIError(code: ControlErrorCode.sessionExpired, message: "登录已过期，请重新登录")
        }
    }

    private static func isSessionError(_ code: String) -> Bool {
        ["14101", "14102", "14103"].contains(code)
    }

    /// sign = Base64Url( HMAC-SHA256( MgSignKey, path + timestamp + appType + data ) )
    /// 与官方客户端 native 实现一致（key 从 libmg.so 中 XOR 还原，即 7348a8950be64ed280e88ce9）
    static func sign(path: String, timestamp: String, data: String) -> String {
        let key = SymmetricKey(data: Data("7348a8950be64ed280e88ce9".utf8))
        let message = path + timestamp + "mgapp" + data
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        let base64 = Data(mac).base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func commonHeaders() -> [String: String] {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(version.majorVersion).\(version.minorVersion)"
        return [
            "User-Agent": "MGProject_PD/2.2.6 (iPhone; iOS \(osVersion); Scale/3.00)",
            "app-type": "mgapp",
            "channelID": "MG",
            "Uuid": deviceUUID,
            "brandcode": "2",
            "versionCode": "2.2.6",
            "os": "iOS",
            "osVersion": osVersion,
            "Model": "ehs",
            "X-client-id": "App",
            "Accept": "*/*"
        ]
    }

    private func jsonString(_ dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func timestamp() -> String {
        String(Int(Date().timeIntervalSince1970 * 1000))
    }

    // MARK: - 登录

    /// 对齐 MGControl 0.57 的发码 DTO：图形验证凭据、品牌、手机号和 captchaId 缺一不可。
    /// 旧参考实现使用 phone 单字段，会在完成易盾后被服务端以 21102 拒绝。
    func requestSMSCode(phone: String, captchaValidate: String) async throws {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 11, trimmed.allSatisfy(\.isNumber) else {
            throw APIError(code: "phone_invalid", message: "请输入 11 位手机号")
        }
        guard !captchaValidate.isEmpty else {
            throw APIError(code: "captcha_required", message: "请先完成安全验证")
        }
        let dict = try await call("POST", base: capi,
                                  path: "/app-mp/uais/1.1/graphicVerificationV2",
                                  data: ["NECaptchaValidate": captchaValidate,
                                         "brandCode": 2,
                                         "mobilePhone": trimmed,
                                         "captchaId": CaptchaView.captchaId])
        let data = dict["data"] as? [String: Any]
        let sent = (data?["send"] as? String)?.lowercased() == "true" || (data?["send"] as? Bool) == true
        guard sent else {
            throw APIError(code: "sms_unconfirmed", message: "短信服务未确认发送，请重新完成验证")
        }
    }

    func login(phone: String, code: String) async throws -> LoginResult {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 11, trimmed.allSatisfy(\.isNumber) else {
            throw APIError(code: "phone_invalid", message: "请输入 11 位手机号")
        }
        guard code.count >= 4 else {
            throw APIError(code: "code_invalid", message: "请输入短信验证码")
        }

        let payload: [String: Any] = [
            "uuid": deviceUUID,
            "mobile_type": "iPhone15,2",
            "phone": trimmed,
            "mobile_brand": "iPhone15,2",
            "app_version": "7",
            "deviceId": deviceId,
            "phoneName": "iPhone",
            "vcode": code,
            "appType": "MG",
            "sid": "",
            "platformType": "ios",
            "brandCode": 2,
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString
        ]
        let dict = try await call("POST", base: capi,
                                  path: "/app-mp/uais/1.0/quickLoginByVcodeV2",
                                  data: payload)
        guard let body = dict["data"] as? [String: Any],
              let loginData = body["loginData"] as? [String: Any],
              let token = loginData["token"] as? String, !token.isEmpty else {
            throw APIError(code: "login", message: "登录返回数据异常")
        }

        tocToken = token
        swapToken = ""
        sessionIssuedAt = Date()
        authCode = nil
        authCodeExpiry = .distantPast

        let userId = String(describing: loginData["user_id"] ?? "")
        let mobile = loginData["mobile"] as? String ?? trimmed
        let nick = loginData["nick_name"] as? String
        let d = UserDefaults.standard
        d.set(mobile, forKey: Keys.phone)
        d.set(nick ?? "", forKey: Keys.nick)
        d.set(userId, forKey: Keys.uid)
        persistTokens()

        _ = try? await refreshSwapToken()
        try? await registerDevice()
        return LoginResult(user: User(id: userId, phone: mobile, nickname: nick), token: token)
    }

    @discardableResult
    func refreshSwapToken() async throws -> String {
        guard !tocToken.isEmpty else {
            throw APIError(code: ControlErrorCode.sessionExpired, message: "登录已过期，请重新登录")
        }
        let dict = try await call("GET", base: capi,
                                  path: "/app-mp/user/1.1/getOutSideServiceToken",
                                  query: ["deviceId": deviceId, "brandCode": "2",
                                          "types": "[1,2]", "token": tocToken],
                                  retrySession: false)
        guard let body = dict["data"] as? [String: Any],
              let swap = body["swapToken"] as? String, !swap.isEmpty else {
            throw APIError(code: "swap", message: "会话交换失败")
        }
        swapToken = swap
        persistTokens()
        return swap
    }

    /// 绑定设备（控车 / 校验安全码的前置条件）
    func registerDevice() async throws {
        let inner: [String: Any] = [
            "app_type": "MG",
            "timestamp": timestamp(),
            "device_id": deviceId,
            "platform_type": "ios",
            "brandCode": "2",
            "channel_type": "1"
        ]
        let innerJSON = try jsonString(inner)
        _ = try await call("POST", base: capi,
                           path: "/app-mp/user/1.0/registDeviceIdV2",
                           data: ["registerMobileDeviceDto": innerJSON, "token": tocToken])
    }

    // MARK: - 安全码

    /// 校验控车安全码，成功后拿到 pvCode（auth_code）。
    /// `14734` 表示设备未注册，补一次 registDeviceIdV2 后重试（docs/06 §6）。
    func verifyPIN(vin: String, pin: String) async throws -> String {
        let trimmed = pin.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 4 else {
            throw APIError(code: "pin_invalid", message: "安全码至少 4 位")
        }
        do {
            return try await checkPIN(vin: vin, pin: trimmed)
        } catch let err as APIError where err.code == "14734" {
            try await registerDevice()
            return try await checkPIN(vin: vin, pin: trimmed)
        }
    }

    private func checkPIN(vin: String, pin: String) async throws -> String {
        if swapToken.isEmpty { try await refreshSwapToken() }
        let dict = try await call("POST", base: mp,
                                  path: "/app-mp/user/1.2/checkPINCode",
                                  data: ["pin": Self.hashPIN(pin),
                                         "vin": vin,
                                         "nonce": Self.nonce(),
                                         "timestamp": timestamp(),
                                         "token": swapToken,
                                         "deviceId": deviceId])
        let data = dict["data"] as? [String: Any] ?? [:]
        if let errorCode = data["errorCode"] as? String, !errorCode.isEmpty {
            invalidateAuthCode()
            throw APIError(code: errorCode, message: Self.message(for: errorCode))
        }
        guard (data["isRight"] as? String) == "true", let code = data["pvCode"] as? String else {
            throw APIError(code: "pin_invalid", message: "安全码错误，请重试")
        }
        authCode = code
        authCodeExpiry = Date().addingTimeInterval(240)
        return code
    }

    /// 官方 `pinEncryption` 仍在逆向（libmg.so），这里保持 SHA1 近似；服务端若返回 14732，
    /// 说明需要用原厂算法，届时替换本函数即可，调用方无需改动。
    private static func hashPIN(_ pin: String) -> String {
        Insecure.SHA1.hash(data: Data(pin.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - 车辆

    func fetchVehicles(token: String) async throws -> [Vehicle] {
        if swapToken.isEmpty { try await refreshSwapToken() }
        let dict = try await call("GET", base: mp,
                                  path: "/app-mp/user/1.0/findSimpleBoundVehicleList",
                                  data: ["token": swapToken, "appId": "MG",
                                         "timestamp": timestamp()])
        guard let body = dict["data"] as? [String: Any],
              let list = body["list"] as? [[String: Any]] else {
            return []
        }
        return list.compactMap { item in
            guard let vin = item["vin"] as? String else { return nil }
            let model = item["model_name"] as? String ?? "MG"
            let plate = item["vehicle_no"] as? String
            let isEV = model.contains("MG4") || model.contains("EV") || model.contains("MULAN")
            return Vehicle(vin: vin, model: model, plateNo: plate,
                           powerType: isEV ? .ev : .fuel)
        }
    }

    func fetchStatus(token: String, vin: String) async throws -> VehicleStatus {
        if swapToken.isEmpty { try await refreshSwapToken() }
        let dict = try await call("GET", base: mp,
                                  path: "/app-mp/vp/1.2/getVehicleStatus",
                                  data: ["appId": "MG", "timestamp": timestamp(),
                                         "vin": vin, "token": swapToken])
        guard let data = dict["data"] as? [String: Any] else {
            throw APIError(code: "status", message: "车况返回为空")
        }
        return Self.mapStatus(vin: vin, data: data)
    }

    /// 主动请求车辆上报最新状态，再读取服务端车况；供手动刷新按钮调用。
    func refreshVehicleStatus(token: String, vin: String) async throws -> VehicleStatus {
        guard !vin.isEmpty else {
            throw APIError(code: "no_vehicle", message: "请先选择车辆")
        }
        if swapToken.isEmpty { try await refreshSwapToken() }
        _ = try await call("POST", base: mp,
                           path: "/app-mp/vp/1.2/requestVehicleStatus",
                           data: ["vin": vin, "nonce": Self.nonce(),
                                  "token": swapToken])
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        return try await fetchStatus(token: token, vin: vin)
    }

    // MARK: - 消息

    func fetchMessages(token: String) async throws -> [MessageItem] {
        let dict = try await call("POST", base: capi, path: "/app-mp/msg/1.0/queryAllMsgV2",
                                  data: ["token": tocToken.isEmpty ? token : tocToken,
                                         "brandCode": "2"])
        guard let list = dict["data"] as? [[String: Any]] else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "zh_CN")
        return list.compactMap { category in
            guard let latest = category["latestMessage"] as? [String: Any] else { return nil }
            let title = latest["msgTitle"] as? String ?? "消息"
            let body = latest["msgContent"] as? String ?? ""
            let timeText = latest["sendTime"] as? String ?? ""
            let date = formatter.date(from: timeText) ?? Date()
            let read = (latest["isRead"] as? Int ?? 2) == 1
            let id = "\(latest["topicCode"] as? String ?? "m")-\(timeText)"
            return MessageItem(id: id, title: title, body: body, date: date, read: read)
        }
    }

    // MARK: - 车控

    private static func commandPath(_ command: CommandType) -> String {
        switch command {
        case .lock: return "/app-mp/vp/1.1/requestLock"
        case .unlock: return "/app-mp/vp/1.1/requestUnlockVehicle"
        case .windowClose: return "/app-mp/vp/1.1/requestCloseWindow"
        case .windowOpen: return "/app-mp/vp/1.1/requestOpenWindow"
        case .acOn: return "/app-mp/vp/1.1/requestTurnOnAc"
        case .acOff: return "/app-mp/vp/1.1/requestTurnOffAc"
        case .trunkOpen: return "/app-mp/vp/1.1/requestUnlockBoot"
        case .findCar: return "/app-mp/vp/1.1/requestFindVehicle"
        }
    }

    func sendCommand(token: String, vin: String, command: CommandType) async throws -> CommandResult {
        guard !vin.isEmpty else {
            throw APIError(code: "no_vehicle", message: "请先选择车辆")
        }
        if swapToken.isEmpty { try await refreshSwapToken() }
        guard let code = authCode, Date() < authCodeExpiry else {
            throw APIError(code: ControlErrorCode.needPin,
                           message: "请先验证控车安全码")
        }

        let payload: [String: Any] = [
            "appId": "MG",
            "brandCode": "2",
            "vin": vin,
            "token": swapToken,
            "timestamp": timestamp(),
            "nonce": Self.nonce(),
            "auth_type": "2",
            "auth_code": code
        ]

        do {
            let dict = try await call("POST", base: mp,
                                      path: Self.commandPath(command),
                                      data: payload)
            let data = dict["data"] as? [String: Any] ?? [:]
            // 显式分支：`??` 链 + String.init 重载会让类型检查器爆炸（实测 Swift 5.9 报 type-check timeout）
            let rawId: Any? = data["command_id"] ?? data["commandId"]
            let commandId: String
            if let number = rawId as? Int {
                commandId = String(number)
            } else if let text = rawId as? String, !text.isEmpty {
                commandId = text
            } else {
                commandId = "—"
            }
            let accepted = commandId != "—"
            return CommandResult(commandId: commandId,
                                 accepted: accepted,
                                 message: accepted ? "\(command.title)指令已下发" : "\(command.title)未受理，请稍后重试")
        } catch let err as APIError where err.code == "14728" {
            invalidateAuthCode()
            throw APIError(code: ControlErrorCode.needPin,
                           message: "控车授权码已失效，请重新输入安全码")
        }
    }

    /// 下发后用车辆状态反向确认（服务端没有稳定的 command 查询接口）。
    /// 返回 true 表示车况已经体现该指令效果；不可用状态验证的指令返回 false。
    func awaitCommandEffect(token: String, vin: String, command: CommandType,
                            timeout: TimeInterval = 20) async -> Bool {
        guard command.isStateVerifiable else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Task.isCancelled { return false }
            if let status = try? await fetchStatus(token: token, vin: vin),
               command.isSatisfied(by: status) {
                return true
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return false
    }

    /// 32 位大写十六进制随机串
    private static func nonce() -> String {
        (0..<32).map { _ in String(format: "%X", Int.random(in: 0...15)) }.joined()
    }

    func fetchChargingRecords(token: String, vin: String) async throws -> [ChargingRecord] { [] }

    func fetchChargingStats(token: String, vin: String) async throws -> ChargingStats {
        ChargingStats(totalEnergyKWh: 0, totalCost: 0, totalDistanceKm: 0)
    }

    // MARK: - 错误码

    static func message(for code: String) -> String {
        switch code {
        case ControlErrorCode.sessionExpired, "14102": return "登录已过期，请重新登录"
        case "14728": return "控车授权码已失效，请重新验证安全码"
        case "14732": return "控车密码错误"
        case "14733": return "安全码错误次数过多，请稍后再试"
        case "14734": return "设备未注册，请重新登录后再试"
        case "14903": return "请求签名校验失败（14903）"
        case "21102": return "图形验证校验失败，请重试"
        case "50080": return "手机号与验证码不匹配"
        case "14682": return "验证码错误，请重新输入"
        case "10500702": return "账户未绑定车辆"
        default: return "操作失败（\(code)）"
        }
    }

    // MARK: - 字段映射

    private static func mapStatus(vin: String, data: [String: Any]) -> VehicleStatus {
        let value = data["vehicle_value"] as? [String: Any] ?? [:]
        let state = data["vehicle_state"] as? [String: Any] ?? [:]
        let position = data["vehicle_position"] as? [String: Any] ?? [:]

        func int(_ dict: [String: Any], _ key: String) -> Int? {
            if let n = dict[key] as? Int { return n }
            if let d = dict[key] as? Double { return Int(d) }
            if let s = dict[key] as? String { return Int(s) }
            return nil
        }
        func double(_ dict: [String: Any], _ key: String) -> Double? {
            if let d = dict[key] as? Double { return d }
            if let n = dict[key] as? Int { return Double(n) }
            if let s = dict[key] as? String { return Double(s) }
            return nil
        }
        func flag(_ key: String) -> Bool { state[key] as? Bool ?? false }

        let soc = int(value, "battery_pack_prc").map { $0 / 10 }
        let rangeKm = int(value, "battery_pack_range") ?? int(value, "driving_range")
        let fullRangeKm: Int? = {
            guard let soc, soc > 0, let rangeKm else { return nil }
            return Int((Double(rangeKm) / (Double(soc) / 100)).rounded())
        }()
        let achievement: Double? = fullRangeKm.map { Double($0) / MGRealClient.ratedRangeKm }
        let doorsClosed = !(flag("door") || flag("driver_door") || flag("passenger_door")
                            || flag("rear_left_door") || flag("rear_right_door")
                            || flag("boot") || flag("bonnet"))
        let windowsClosed = !(flag("window") || flag("driver_window") || flag("passenger_window")
                              || flag("rear_left_window") || flag("rear_right_window")
                              || flag("sunroof"))
        let updated = int(data, "update_time").map {
            Date(timeIntervalSince1970: Double($0) / 1000)
        } ?? Date()

        var location: ParkingLocation?
        if let lat = double(position, "latitude"), let lon = double(position, "longitude") {
            location = ParkingLocation(latitude: lat, longitude: lon,
                                       address: "", updatedAt: updated)
        }

        return VehicleStatus(
            vin: vin,
            soc: soc,
            fuelPercent: int(value, "fuel_level_prc"),
            rangeKm: rangeKm,
            odometerKm: int(value, "odometer"),
            locked: state["lock"] as? Bool ?? true,
            doorsClosed: doorsClosed,
            windowsClosed: windowsClosed,
            charging: flag("charge") || (int(value, "charge_status") ?? 0) == 1,
            online: true,
            updatedAt: updated,
            cabinTempC: double(value, "interior_temperature"),
            batteryVoltageV: double(value, "vehicle_battery").map { $0 / 100 },
            fullRangeKm: fullRangeKm,
            rangeAchievement: achievement,
            tirePressure: TirePressure(
                frontLeft: double(value, "front_left_tyre_pressure").map { $0 / 100 },
                frontRight: double(value, "front_right_tyre_pressure").map { $0 / 100 },
                rearLeft: double(value, "rear_left_tyre_pressure").map { $0 / 100 },
                rearRight: double(value, "rear_right_tyre_pressure").map { $0 / 100 }),
            parkingLocation: location,
            exteriorTempC: double(value, "exterior_temperature")
        )
    }
}

// MARK: - MG4 仪表盘的真后端实现

/// 把真实车况映射到仪表盘模型（`MG4VehicleData`），供 `MG4DashboardView` 使用。
final class RealMG4API: MG4API {
    private let client = MGRealClient.shared
    /// 最近一次拉取车况的 VIN：MG4API 协议没有 vin 参数，控车前由这里兜底。
    private var lastVin: String?

    func fetchMG4Status(token: String) async throws -> MG4VehicleData {
        if client.swapToken.isEmpty { try await client.refreshSwapToken() }
        let vehicles = try await client.fetchVehicles(token: token)
        guard let vehicle = vehicles.first else {
            throw APIError(code: "10500702", message: "账户未绑定车辆")
        }
        lastVin = vehicle.vin
        let status = try await client.fetchStatus(token: token, vin: vehicle.vin)
        var mapped = Self.map(vehicle: vehicle, status: status)
        if let loc = status.parkingLocation {
            mapped.address = await Self.reverseGeocode(loc)
            #if DEBUG
            print("MGADDRESS:", mapped.address)
            #endif
        }
        return mapped
    }

    func refreshMG4Status(token: String) async throws -> MG4VehicleData {
        if client.swapToken.isEmpty { try await client.refreshSwapToken() }
        let vehicles = try await client.fetchVehicles(token: token)
        guard let vehicle = vehicles.first else {
            throw APIError(code: "10500702", message: "账户未绑定车辆")
        }
        lastVin = vehicle.vin
        let status = try await client.refreshVehicleStatus(token: token, vin: vehicle.vin)
        var mapped = Self.map(vehicle: vehicle, status: status)
        if let loc = status.parkingLocation {
            mapped.address = await Self.reverseGeocode(loc)
        }
        return mapped
    }

    func controlMG4(token: String, action: MG4ControlAction) async throws {
        guard let vin = lastVin else {
            throw APIError(code: "no_vehicle", message: "请先刷新车辆状态")
        }
        let command: CommandType
        switch action {
        case .lock: command = .lock
        case .unlock: command = .unlock
        case .closeWindows: command = .windowClose
        case .openWindows: command = .windowOpen
        }
        _ = try await client.sendCommand(token: token, vin: vin, command: command)
        _ = await client.awaitCommandEffect(token: token, vin: vin, command: command)
    }

    private static func map(vehicle: Vehicle, status: VehicleStatus) -> MG4VehicleData {
        let plate = formatPlate(vehicle.plateNo ?? "")
        let address: String
        if let loc = status.parkingLocation {
            address = String(format: "%.4f, %.4f", loc.latitude, loc.longitude)
        } else {
            address = "位置未知"
        }
        return MG4VehicleData(
            modelName: vehicle.model.contains("MG4") ? "名爵 MG4" : vehicle.model,
            trimName: "",
            plateNo: plate,
            rangeKm: status.rangeKm ?? 0,
            soc: status.soc ?? 0,
            odometerKm: status.odometerKm ?? 0,
            cabinTempC: status.cabinTempC ?? 0,
            batteryVoltageV: status.batteryVoltageV ?? 0,
            isLocked: status.locked,
            isWindowClosed: status.windowsClosed,
            tireFrontLeft: status.tirePressure?.frontLeft ?? 0,
            tireFrontRight: status.tirePressure?.frontRight ?? 0,
            tireRearLeft: status.tirePressure?.rearLeft ?? 0,
            tireRearRight: status.tirePressure?.rearRight ?? 0,
            address: address,
            updatedAt: status.updatedAt,
            vin: vehicle.vin,
            exteriorTempC: status.exteriorTempC,
            fullRangeKm: status.fullRangeKm,
            rangeAchievement: status.rangeAchievement,
            latitude: status.parkingLocation?.latitude,
            longitude: status.parkingLocation?.longitude
        )
    }

    /// 逆地理编码：坐标 -> 中文地址（失败时回退坐标文本）
    private static func reverseGeocode(_ loc: ParkingLocation) async -> String {
        let geocoder = CLGeocoder()
        let placemarks = try? await geocoder.reverseGeocodeLocation(
            CLLocation(latitude: loc.latitude, longitude: loc.longitude))
        if let p = placemarks?.first {
            let parts = [p.administrativeArea, p.locality, p.subLocality, p.name]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined() }
        }
        return String(format: "%.6f, %.6f", loc.latitude, loc.longitude)
    }

    /// "辽FD00273" -> "辽F·D00273"
    private static func formatPlate(_ raw: String) -> String {
        guard raw.count > 3 else { return raw }
        let idx = raw.index(raw.startIndex, offsetBy: 2)
        return raw[..<idx] + "·" + raw[idx...]
    }
}

// MARK: - 依赖选择

enum MG4APIProvider {
    static func make() -> MG4API {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MG_MOCK"] == "1" {
            return MockMG4API()
        }
        #endif
        return RealMG4API()
    }
}
