import Foundation

/// 小组件 → 主 App 的导航入口。
///
/// 安全边界（对齐 docs/05 §4）：
/// - 链接只负责「打开哪个页面」，不携带身份、不携带指令参数以外的内容；
/// - 任何控车动作都必须回到 App 内完成二次确认与安全码校验；
/// - 解析失败一律返回 nil，不做宽松兜底。
public struct WidgetRoute: Equatable, Sendable, Identifiable {

    public enum Destination: String, Sendable, CaseIterable {
        case home
        case control
        case charging
        case parking
        case refresh
    }

    public let destination: Destination
    public let command: CommandType?

    public init(destination: Destination, command: CommandType? = nil) {
        self.destination = destination
        self.command = command
    }

    public var id: String {
        "\(destination.rawValue)\(command.map { ".\($0.rawValue)" } ?? "")"
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = destination.rawValue
        if let command {
            components.queryItems = [URLQueryItem(name: "cmd", value: command.rawValue)]
        }
        // Destination 与 CommandType 都是受控枚举，构造必然成功。
        return components.url ?? URL(string: "\(Self.scheme)://home")!
    }

    public static let scheme = "mgcontrol"

    // MARK: 展示信息

    public var title: String {
        switch destination {
        case .home: return "打开"
        case .control: return command?.title ?? "控制"
        case .charging: return "充电"
        case .parking: return "位置"
        case .refresh: return "刷新"
        }
    }

    public var symbol: String {
        switch destination {
        case .home: return "house.fill"
        case .control:
            switch command {
            case .findCar: return "speaker.wave.2.fill"
            case .lock: return "lock.fill"
            case .unlock: return "lock.open.fill"
            case .windowOpen, .windowClose: return "rectangle.portrait.and.arrow.right"
            case .acOn, .acOff: return "fan.fill"
            case .trunkOpen: return "car.rear.and.trianglebadge.exclamationmark"
            case .none: return "slider.horizontal.3"
            }
        case .charging: return "bolt.car.fill"
        case .parking: return "mappin.and.ellipse"
        case .refresh: return "arrow.clockwise"
        }
    }

    /// 小组件底部固定展示的四个入口。
    public static let widgetShortcuts: [WidgetRoute] = [
        WidgetRoute(destination: .home),
        WidgetRoute(destination: .control, command: .findCar),
        WidgetRoute(destination: .charging),
        WidgetRoute(destination: .parking)
    ]

    // MARK: 解析

    /// 严格解析，仅接受 `mgcontrol://<destination>` 与 `mgcontrol://control?cmd=<command>`。
    public static func parse(_ url: URL) -> WidgetRoute? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              let host = components.host?.lowercased(),
              let destination = Destination(rawValue: host)
        else { return nil }

        let items = components.queryItems ?? []
        if items.isEmpty {
            return WidgetRoute(destination: destination)
        }

        guard destination == .control,
              items.count == 1,
              items[0].name == "cmd",
              let raw = items[0].value,
              let command = CommandType(rawValue: raw)
        else { return nil }

        return WidgetRoute(destination: .control, command: command)
    }
}
