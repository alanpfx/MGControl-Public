import Foundation

struct Theme: Codable, Equatable {
    static let roles=["lock","window","horn","trunk","power","fan","cool","heat","driverVent","passengerVent","driverHeat","passengerHeat","steering"]
    static let cards=["location","climate","details","sentinel"]
    struct Item: Codable, Equatable {
        var symbol:String
        var title:String
        var diameter:Double=56
        var iconSize:Double=24
        var fontSize:Double=12
        var gap:Double=7
    }
    var schemaVersion=1
    var name="MGControl 蓝白方案"
    var appearance="system"
    var accent="1677E8"
    var background="EAF1F8"
    var darkBackground="121823"
    var cardColor="FFFFFF"
    var darkCardColor="202A38"
    var padding:Double=16
    var spacing:Double=14
    var corner:Double=24
    var shadow:Double=8
    var titleSize:Double=30
    var heroHeight:Double=210
    var cardPadding:Double=16
    var cardOrder=Self.cards
    var vehicleAsset="MG4White"
    var items:[String:Item]=[:]
    static var initial:Self {
        var t=Self()
        let symbols=["lock","rectangle","speaker.wave.2","car","power","fan.fill","snowflake","sun.max.fill","fan.fill","fan.fill","flame.fill","flame.fill","steeringwheel"]
        let titles=["车锁","车窗","鸣笛寻车","后备箱","空调开关","远程通风","极速降温","极速升温","主驾通风","副驾通风","主驾加热","副驾加热","方向盘加热"]
        for i in roles.indices {t.items[roles[i]]=Item(symbol:symbols[i],title:titles[i])}
        return t
    }
    func validate() throws {
        func require(_ value:Bool) throws {if !value {throw ThemeError.invalid}}
        try require(schemaVersion==1 && !name.isEmpty && name.count <= 80)
        try require(["system","light","dark"].contains(appearance))
        for color in [accent,background,darkBackground,cardColor,darkCardColor] {
            try require(color.count==6 && color.utf8.allSatisfy{(48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)})
        }
        for (value,range) in [(padding,8.0...32),(spacing,4.0...32),(corner,0.0...40),(shadow,0.0...20),(titleSize,20.0...40),(heroHeight,160.0...300),(cardPadding,8.0...28)] {
            try require(value.isFinite && range.contains(value))
        }
        try require(cardOrder.count==Self.cards.count && Set(cardOrder)==Set(Self.cards))
        try require(["MG4White","MG4Grey","MG4Purple","MG4IceBlue","MG4Almond","MG4Jade"].contains(vehicleAsset))
        try require(Set(items.keys)==Set(Self.roles))
        for item in items.values {
            try require(!item.title.isEmpty && item.title.count<=24 && !item.symbol.isEmpty && item.symbol.count<=80)
            for (value,range) in [(item.diameter,36.0...88),(item.iconSize,12.0...44),(item.fontSize,10.0...22),(item.gap,2.0...20)] {try require(value.isFinite && range.contains(value))}
        }
    }
    static func decode(_ data:Data) throws -> Self {
        guard data.count<=512*1024 else {throw ThemeError.invalid}
        let value=try JSONDecoder().decode(Self.self,from:data);try value.validate();return value
    }
    func data() throws -> Data {
        try validate();let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];return try encoder.encode(self)
    }
}
enum ThemeError:LocalizedError {
    case invalid
    var errorDescription:String? {"设计文件格式或参数范围不受支持；请使用工作台导出的完整设计文件（格式版本1）。"}
}
