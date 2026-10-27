import Foundation
import WidgetKit
import CoreKit

/// 主 App 把最新车况写入 App Group 容器，并请求小组件刷新。
///
/// 扩展本身不发网络请求（docs/05 §3.2），所有刷新都由主 App 驱动。
@MainActor
enum WidgetBridge {

    /// 车辆页（MG4DashboardView）刷新成功后调用。
    static func sync(_ data: MG4VehicleData) {
        write(WidgetSnapshot(mg4: data))
    }

    /// 控制页 / 车辆列表路径（AppState）刷新成功后调用。
    static func sync(vehicle: Vehicle?, status: VehicleStatus?, stats: ChargingStats? = nil) {
        guard let vehicle, let status else { return }
        write(WidgetSnapshot(vehicle: vehicle, status: status, stats: stats))
    }

    /// 退出登录时清空，避免桌面残留上一账号的车辆信息。
    static func clear() {
        try? WidgetStore.live.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func write(_ snapshot: WidgetSnapshot) {
        do {
            try WidgetStore.live.write(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // App Group 未配置时静默降级，不影响主流程。
            #if DEBUG
            print("[WidgetBridge] 写入共享快照失败：\(error)")
            #endif
        }
    }
}
