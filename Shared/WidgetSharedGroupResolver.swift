import Foundation

/// Both processes inspect the same two installed bundles. Selection never
/// depends on which container happens to be accessible to the calling process.
struct WidgetSharedGroupSelection: Equatable {
    enum Mode: Equatable {case configured, adapted, unavailable}
    let identifier: String?
    let mode: Mode
    let message: String
}

enum WidgetSharedGroupResolver {
    static let defaultIdentifier="group.aa470567aa802a25.1"
    struct Signature {
        let team: String?
        let groups: [String]
        init(team: String?,groups: [String]) {self.team=team;self.groups=groups}
        init(_ ent: [String:Any]) {
            team=ent["com.apple.developer.team-identifier"] as? String
            groups=ent["com.apple.security.application-groups"] as? [String] ?? []
        }
    }
    static func valid(_ value: String) -> Bool {
        value.hasPrefix("group.") && value.utf8.count>6 && value.utf8.count<=255 &&
        value.split(separator:".",omittingEmptySubsequences:false).allSatisfy {!$0.isEmpty} &&
        value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46].contains($0) }
    }
    static func choose(mainConfigured: String,widgetConfigured: String,
                       main: Signature?,widget: Signature?) -> WidgetSharedGroupSelection {
        let configured=mainConfigured == widgetConfigured && valid(mainConfigured) ? mainConfigured : nil
        guard let main,let widget else {
            // Preserve the existing configured group for unsigned development or
            // DER-only signatures; never infer an adaptive group from one side.
            let known=[main,widget].compactMap {$0}
            let allowed=configured.flatMap {group in known.allSatisfy {$0.groups.contains(group)} ? group : nil}
            return .init(identifier:allowed,mode:allowed == nil ? .unavailable : .configured,
                         message:allowed == nil ? "双端签名未完整读取或原配置不匹配，停止共享" : "签名未完整读取，仅使用双端一致原配置；以运行时容器为准")
        }
        guard let team=main.team,!team.isEmpty,team == widget.team else {
            return .init(identifier:nil,mode:.unavailable,message:"双端签名团队缺失或不同，停止共享")
        }
        guard main.groups.count<=128,widget.groups.count<=128 else {
            return .init(identifier:nil,mode:.unavailable,message:"共享组声明数量异常，停止共享")
        }
        let common=Set(main.groups.filter(valid)).intersection(widget.groups.filter(valid)).sorted()
        if let configured,common.contains(configured) {
            return .init(identifier:configured,mode:.configured,message:"双端共同声明原共享组")
        }
        guard let selected=common.first else {
            return .init(identifier:nil,mode:.unavailable,message:"双端没有共同共享组，停止共享")
        }
        return .init(identifier:selected,mode:.adapted,
                     message:"重签名适配：双端共同组共\(common.count)个，按固定排序选择同一组；仍需系统授予运行时容器")
    }
    static func bundles(current: URL) -> (main: URL,widget: URL)? {
        if current.pathExtension == "app" {
            return (current,current.appendingPathComponent("PlugIns/MGControlWidget.appex"))
        }
        let plugins=current.deletingLastPathComponent()
        let parent=plugins.deletingLastPathComponent()
        guard current.lastPathComponent == "MGControlWidget.appex",plugins.lastPathComponent == "PlugIns",
              parent.pathExtension == "app" else {return nil}
        return (parent,current)
    }
    private static func configured(_ bundle: Bundle) -> String {
        (bundle.object(forInfoDictionaryKey:"MGControlAppGroupIdentifier") as? String) ?? defaultIdentifier
    }
    static let selection: WidgetSharedGroupSelection = {
        guard let urls=bundles(current:Bundle.main.bundleURL),let main=Bundle(url:urls.main),let widget=Bundle(url:urls.widget) else {
            let value=configured(.main)
            return .init(identifier:valid(value) ? value : nil,mode:valid(value) ? .configured : .unavailable,
                         message:"未能读取双端安装包，仅保留有效原配置；未自动切换共享组")
        }
        let mainSignature=WidgetSigningDiagnostics.bundleEntitlements(main).map {Signature($0)}
        let widgetSignature=WidgetSigningDiagnostics.bundleEntitlements(widget).map {Signature($0)}
        return choose(mainConfigured:configured(main),widgetConfigured:configured(widget),main:mainSignature,widget:widgetSignature)
    }()
}
