import Foundation

/// 跨进程共享的车况快照存储（App Group 容器内文件）。
///
/// 与 `UserDefaults(suiteName:)` 相比，文件方案可以：
/// - 用版本信封做向前/向后兼容；
/// - 限制最大体积，避免扩展读入超大数据；
/// - 显式区分「容器不可用」与「内容损坏」，让小组件给出不同引导。
public struct WidgetStore: Sendable {

    /// 主 App 与扩展必须配置同一 App Group。
    public static let defaultGroupIdentifier = "group.com.alanpfx.mgcontrol.shared"

    /// 允许 `project.yml` 通过 Info.plist 覆盖，避免代码里写死多个环境。
    public static var groupIdentifier: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "CarControlAppGroupIdentifier") as? String,
           !configured.trimmingCharacters(in: .whitespaces).isEmpty {
            return configured
        }
        return defaultGroupIdentifier
    }

    public static var live: WidgetStore {
        WidgetStore(directory: FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ))
    }

    public let directory: URL?

    public var isAvailable: Bool { directory != nil }

    public init(directory: URL?) {
        self.directory = directory
    }

    // MARK: 常量

    private static let filename = "vehicle-summary-v1.json"
    private static let schemaVersion = 1
    private static let maxBytes = 64 * 1024

    private struct Envelope: Codable {
        let version: Int
        let snapshot: WidgetSnapshot
    }

    public enum StoreFailure: Error, Equatable {
        /// App Group 未配置或不可访问（多见于签名丢失共享权限）。
        case unavailable
        /// 内容超限、无法解码或版本不匹配。
        case invalid
    }

    // MARK: 读写

    private func fileURL() throws -> URL {
        guard let directory else { throw StoreFailure.unavailable }
        return directory.appendingPathComponent(Self.filename)
    }

    public func write(_ snapshot: WidgetSnapshot) throws {
        let data = try JSONEncoder().encode(Envelope(version: Self.schemaVersion, snapshot: snapshot))
        guard data.count <= Self.maxBytes else { throw StoreFailure.invalid }
        let url = try fileURL()
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func read() throws -> WidgetSnapshot? {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: Self.maxBytes + 1) ?? Data()
        guard data.count <= Self.maxBytes else { throw StoreFailure.invalid }

        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == Self.schemaVersion else { throw StoreFailure.invalid }
        return envelope.snapshot
    }

    public func clear() throws {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

// MARK: - 加载状态

/// 小组件可能处于的五种状态，每种都要给出可执行的引导文案。
///
/// 状态划分参考了 MGControl-Public（自定义非商业协议）公开的小组件加载态设计，
/// 代码与文案按本项目的模型重写。
public enum WidgetLoadPhase: String, Codable, Sendable {
    case loading
    case ready
    case notSynced
    case unavailable
    case invalid

    public var title: String {
        switch self {
        case .loading: return "正在读取车况"
        case .ready: return "最近同步车况"
        case .notSynced: return "尚未同步车况"
        case .unavailable: return "无法访问共享车况"
        case .invalid: return "车况数据无法读取"
        }
    }

    public var help: String {
        switch self {
        case .loading:
            return "若长时间停留在此状态，请打开主 App 刷新车况后重新添加小组件。"
        case .ready:
            return "打开主 App 刷新车况即可更新。"
        case .notSynced:
            return "打开主 App，登录并进入车辆页完成一次刷新。"
        case .unavailable:
            return "主 App 与小组件需要保留同一 App Groups 共享权限，请检查签名配置。"
        case .invalid:
            return "共享数据已损坏或版本不兼容，请在主 App 重新刷新车况。"
        }
    }
}

public struct WidgetLoadState: Sendable {
    public let snapshot: WidgetSnapshot
    public let phase: WidgetLoadPhase

    public init(snapshot: WidgetSnapshot, phase: WidgetLoadPhase) {
        self.snapshot = snapshot
        self.phase = phase
    }

    public static var placeholder: WidgetLoadState {
        WidgetLoadState(snapshot: .preview(), phase: .loading)
    }

    public static func load(from store: WidgetStore) -> WidgetLoadState {
        do {
            guard let snapshot = try store.read() else {
                return WidgetLoadState(snapshot: .empty, phase: .notSynced)
            }
            return WidgetLoadState(snapshot: snapshot, phase: .ready)
        } catch WidgetStore.StoreFailure.unavailable {
            return WidgetLoadState(snapshot: .empty, phase: .unavailable)
        } catch {
            return WidgetLoadState(snapshot: .empty, phase: .invalid)
        }
    }
}

public extension WidgetSnapshot {
    /// 空态占位，所有字段缺省。
    static var empty: WidgetSnapshot {
        WidgetSnapshot(vehicleName: "我的车辆", updatedAt: .distantPast)
    }
}
