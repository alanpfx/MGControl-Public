import SwiftUI

extension Color {
    init(designHex:String) {
        let n=UInt64(designHex,radix:16) ?? 0x1677E8
        self.init(.sRGB,red:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255,opacity:1)
    }
}

/// Pure presentation: no account, server, Bluetooth or vehicle-control dependency.
struct DesignRenderer:View {
    let theme:Theme
    var comfortPage=false
    var longText=false
    var missingData=false
    @State private var locked=true
    @State private var ac=false
    @State private var degrees=26
    @State private var enabled=Set<String>()
    @State private var feedback="所有数据和操作均为模拟"
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var type
    private var accent:Color {Color(designHex:theme.accent)}
    private var surface:Color {Color(designHex:scheme == .dark ? theme.darkCardColor : theme.cardColor)}
    private var background:Color {Color(designHex:scheme == .dark ? theme.darkBackground : theme.background)}
    var body:some View {
        ScrollView {
            VStack(spacing:theme.spacing) {
                HStack {Text(comfortPage ? "空调与舒适控制" : (longText ? "这是一个较长的自定义车辆名称" : "我的 MG4")).font(.system(size:theme.titleSize,weight:.bold));Spacer();Image(systemName:"gearshape")}
                if comfortPage {climate;seats} else {home}
                Text(feedback).font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity)
                HStack {tab("车控","car.side.fill");tab("蓝牙钥匙","key.radiowaves.forward");tab("设置","gearshape.fill")}
                    .padding(8).background(.regularMaterial,in:Capsule())
            }.padding(theme.padding)
        }.background(background.ignoresSafeArea()).tint(accent)
    }
    private var home:some View {
        VStack(spacing:theme.spacing) {
            Text("模拟车况 · 今天 15:22").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
            HStack {
                VStack(alignment:.leading) {
                    HStack(alignment:.firstTextBaseline) {Text(missingData ? "—" : "410").font(.system(size:50,weight:.semibold,design:.rounded));Text("km");Text(missingData ? "—" : "64%").font(.title2.bold()).foregroundStyle(accent)}
                    ProgressView(value:missingData ? 0 : 0.64).tint(accent)
                    Text(missingData ? "总里程 —" : "总里程 6888 km").font(.caption)
                }
                Spacer()
                Text(missingData ? "锁态未知" : (locked ? "已锁车" : "未锁车")).font(.caption.bold()).padding(10).background(accent.opacity(0.12),in:Capsule())
            }
            Image(theme.vehicleAsset).resizable().scaledToFit().frame(height:theme.heroHeight).shadow(color:.black.opacity(0.15),radius:theme.shadow,y:8)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:type.isAccessibilitySize ? 2 : 4),spacing:theme.spacing) {
                ForEach(["lock","window","horn","trunk"],id:\.self) {id in
                    Button {simulate(id)} label: {item(id)}.buttonStyle(.plain).disabled(id=="trunk").opacity(id=="trunk" ? 0.35 : 1)
                }
            }
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:theme.spacing),count:type.isAccessibilitySize ? 1 : 2),spacing:theme.spacing) {
                ForEach(theme.cardOrder,id:\.self) {id in homeCard(id)}
            }
        }
    }
    @ViewBuilder private func homeCard(_ id:String)->some View {
        if id=="location" {
            card {VStack(alignment:.leading,spacing:12) {Text("车辆位置").font(.headline);Text(missingData ? "暂无定位地址" : (longText ? "示例城市 · 很长的停车场名称 · 地下一层东侧入口" : "示例停车场 · 地下一层")).font(.caption);Image(systemName:"mappin.circle.fill").font(.system(size:46)).foregroundStyle(accent).frame(maxWidth:.infinity,minHeight:76);Text("停车照片 ›").font(.caption).foregroundStyle(accent)}.frame(minHeight:180)}
        } else if id=="climate" {
            card {VStack(spacing:12) {HStack {Text("空调").font(.headline);Spacer();Button {simulate("power")} label: {Image(systemName:"power").foregroundStyle(ac ? accent : .secondary).frame(width:44,height:44)}};Text("车内 26℃").font(.caption).foregroundStyle(.secondary);Text("\(degrees)℃").font(.system(size:38,weight:.light));Text("模拟设置 · 30分钟").font(.caption);HStack {Button("−") {degrees=max(25,degrees-1)};Spacer();Button("＋") {degrees=min(29,degrees+1)}}}.frame(minHeight:180)}
        } else {card {Button {feedback="模拟打开"+(id=="details" ? "完整车况" : "哨兵模式")} label: {HStack {Text(id=="details" ? "完整车况" : "哨兵模式").font(.headline);Spacer();Image(systemName:"chevron.right")}.frame(minHeight:35)}.buttonStyle(.plain)}}
    }
    private var climate:some View {
        card {VStack(spacing:theme.spacing) {
            HStack {Text("空调").font(.headline);Spacer();Button {simulate("power")} label: {item("power")}}
            Text("车内26℃ · 车外29℃").font(.caption).foregroundStyle(.secondary)
            HStack {Button("−") {degrees=max(25,degrees-1)};Spacer();Text("\(degrees)℃").font(.system(size:52,weight:.light));Spacer();Button("＋") {degrees=min(29,degrees+1)}}
            Slider(value:Binding(get:{Double(degrees)},set:{degrees=Int($0)}),in:25...29,step:1)
            Text("温控　｜　制冷　｜　制热").font(.subheadline)
            Text("运行时长　30分钟 ›").font(.caption)
            HStack {ForEach(["fan","cool","heat"],id:\.self) {id in Button {simulate(id)} label: {item(id)}.buttonStyle(.plain)}}
        }}
    }
    private var seats:some View {
        card {VStack(spacing:theme.spacing) {
            Text("座椅与方向盘").font(.headline).frame(maxWidth:.infinity,alignment:.leading)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:theme.spacing) {
                ForEach(["driverVent","passengerVent","driverHeat","passengerHeat"],id:\.self) {id in Button {simulate(id)} label: {item(id)}.buttonStyle(.plain)}
            }
            Button {simulate("steering")} label: {item("steering")}.buttonStyle(.plain)
        }}
    }
    private func item(_ id:String)->some View {
        let style=theme.items[id] ?? Theme.initial.items[id]!
        return VStack(spacing:style.gap) {
            Image(systemName:style.symbol).font(.system(size:style.iconSize)).frame(width:style.diameter,height:style.diameter)
                .foregroundStyle(enabled.contains(id) ? accent : .primary)
                .background(accent.opacity(enabled.contains(id) ? 0.18 : 0.06),in:Circle())
            Text(style.title).font(.system(size:style.fontSize)).multilineTextAlignment(.center)
        }.frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())
    }
    private func card<C:View>(@ViewBuilder _ content:()->C)->some View {
        content().padding(theme.cardPadding).frame(maxWidth:.infinity).background(surface,in:RoundedRectangle(cornerRadius:theme.corner))
            .shadow(color:.black.opacity(scheme == .dark ? 0.15 : 0.04),radius:theme.shadow,y:3)
    }
    private func tab(_ title:String,_ icon:String)->some View {
        VStack {Image(systemName:icon).font(.title2);Text(title).font(.caption2)}.frame(maxWidth:.infinity).padding(.vertical,6)
    }
    private func simulate(_ id:String) {
        if id=="lock" {locked.toggle()}
        if id=="power" {ac.toggle()}
        if enabled.contains(id) {enabled.remove(id)} else {
            let opposite=["driverVent":"driverHeat","driverHeat":"driverVent","passengerVent":"passengerHeat","passengerHeat":"passengerVent"]
            if let other=opposite[id] {enabled.remove(other)}
            enabled.insert(id)
        }
        feedback="模拟反馈："+(theme.items[id]?.title ?? id)+"，未操作车辆"
    }
}
