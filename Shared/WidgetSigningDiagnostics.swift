import Foundation

/// Reads only this installed bundle's embedded signature. This is not a claim
/// that the running process has received an App Groups sandbox extension.
enum WidgetSigningDiagnostics {
    static var version: String {
        let info=Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }
    static func entitlements(_ data: Data) throws -> [String:Any] {
        let b=Array(data)
        func number(_ offset: Int, big: Bool=false) -> Int? {
            guard offset >= 0, offset <= b.count-4 else {return nil}
            let a=(0..<4).map {Int(b[offset+$0])}
            return big ? (a[0]<<24 | a[1]<<16 | a[2]<<8 | a[3]) : (a[3]<<24 | a[2]<<16 | a[1]<<8 | a[0])
        }
        guard b.count >= 32,b.count <= 32*1024*1024,number(0)==0xfeedfacf,
              let count=number(16),let commandBytes=number(20),count <= 4096,
              commandBytes <= b.count-32 else {throw InspectionFailure(text:"签名格式暂不可检查")}
        var offset=32
        for _ in 0..<count {
            guard offset <= 32+commandBytes-8,let cmd=number(offset),let size=number(offset+4),
                  size >= 8,size <= 32+commandBytes-offset else {throw InspectionFailure(text:"签名结构无效")}
            defer {offset += size}
            guard cmd==0x1d else {continue}
            guard size >= 16,let start=number(offset+8),let length=number(offset+12),
                  start >= 0,length >= 12,start <= b.count-length,
                  number(start,big:true)==0xfade0cc0,let total=number(start+4,big:true),
                  total >= 12,total <= length,let slots=number(start+8,big:true),
                  slots <= 64,12+8*slots <= total else {throw InspectionFailure(text:"签名结构无效")}
            for i in 0..<slots {
                let index=start+12+8*i
                guard number(index,big:true)==5 else {continue}
                guard let relative=number(index+4,big:true),relative >= 12+8*slots,
                      relative <= total-8,number(start+relative,big:true)==0xfade7171,
                      let bytes=number(start+relative+4,big:true),bytes >= 8,bytes <= 65536,
                      bytes <= total-relative else {throw InspectionFailure(text:"签名权限数据无效")}
                let raw=Data(b[(start+relative+8)..<(start+relative+bytes)])
                guard let ent=(try? PropertyListSerialization.propertyList(from:raw,format:nil)) as? [String:Any] else {throw InspectionFailure(text:"签名权限数据无效")}
                return ent
            }
            throw InspectionFailure(text:"包内缺少XML权限，可能仅有DER权限")
        }
        throw InspectionFailure(text:"包内未发现签名")
    }
    struct InspectionFailure: Error {let text: String}
    static func describe(_ data: Data, group: String, bundleID: String) -> String {
        do {
            let ent=try entitlements(data)
            let groups=ent["com.apple.security.application-groups"] as? [String] ?? []
            let appID=ent["application-identifier"] as? String ?? ""
            let identity=appID.hasSuffix(".*") ? "应用标识为通配" : (appID.hasSuffix("."+bundleID) ? "应用标识精确" : "应用标识缺失或不同")
            return (groups.contains(group) ? "包内共享组匹配" : "包内共享组缺失或不同")+"；"+identity
        } catch let error as InspectionFailure {return error.text}
        catch {return "签名权限数据无效"}
    }
    static func bundleEntitlements(_ bundle: Bundle) -> [String:Any]? {
        guard let url=bundle.executableURL,let size=try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize,
              size <= 32*1024*1024,let data=try? Data(contentsOf:url) else {return nil}
        return try? entitlements(data)
    }
    static func bundleReport(_ bundle: Bundle) -> String {
        guard let url=bundle.executableURL,let size=try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize,
              size <= 32*1024*1024,let data=try? Data(contentsOf:url) else {return "包内签名暂不可读取"}
        return describe(data,group:SharedVehicleStore.groupIdentifier,bundleID:bundle.bundleIdentifier ?? "")
    }
    static var installedReport: String {
        let own="主 App 包内签名："+bundleReport(.main)
        let url=Bundle.main.bundleURL.appendingPathComponent("PlugIns/MGControlWidget.appex")
        guard let widget=Bundle(url:url) else {return own+"\n小组件扩展：本包未包含或无法读取"}
        return own+"\n小组件包内签名："+bundleReport(widget)+"\n包内声明不代表运行时容器已授权"
    }
}
