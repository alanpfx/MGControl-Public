import Foundation
import LocalAuthentication

/// 生物识别把关：解锁、开窗、开后备箱这类高危指令在下发前要求 Face ID / Touch ID。
///
/// 用 `.deviceOwnerAuthentication`（允许设备密码兜底），避免连续失败后锁死。
enum BiometricGate {
    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "设备密码"
        }
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// 返回 true 表示通过；系统不可用（模拟器、未设密码）时放行，交给安全码兜底。
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "使用设备密码"
        context.localizedCancelTitle = "取消"

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            return true
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
