import SwiftUI
import UniformTypeIdentifiers

struct ThemeDocument:FileDocument {
    static var readableContentTypes:[UTType] {[.json]}
    var data:Data
    init(data:Data=Data()) {self.data=data}
    init(configuration:ReadConfiguration) throws {data=configuration.file.regularFileContents ?? Data()}
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper {FileWrapper(regularFileWithContents:data)}
}

@main
struct WorkbenchApp:App {
    var body:some Scene {WindowGroup {WorkbenchView()}}
}

struct WorkbenchView:View {
    @State private var theme=Self.savedTheme()
    @State private var role="lock"
    @State private var page=0
    @State private var comfort=false
    @State private var longText=false
    @State private var missingData=false
    @State private var importOpen=false
    @State private var exportOpen=false
    @State private var document=ThemeDocument()
    @State private var notice:String?
    @State private var resetOpen=false
    @State private var previewWidth=390
    @State private var largeType=false
    private var scheme:ColorScheme? {theme.appearance=="dark" ? .dark : (theme.appearance=="light" ? .light : nil)}
    var body:some View {
        NavigationView {
            Group {
                if page==0 {
                    ScrollView(.horizontal) {
                        DesignRenderer(theme:theme,comfortPage:comfort,longText:longText,missingData:missingData)
                            .environment(\.dynamicTypeSize,largeType ? .accessibility1 : .large)
                            .frame(width:CGFloat(previewWidth))
                    }
                } else {editor}
            }
            .navigationTitle("MG UI 设计工作台").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.navigationBarLeading) {Button(page==0 ? "调整样式" : "查看预览") {page=page==0 ? 1 : 0}}
                ToolbarItem(placement:.navigationBarTrailing) {Menu {
                    Button("导出设计文件") {exportTheme()}
                    Button("导入设计文件") {importOpen=true}
                    Button("恢复默认方案",role:.destructive) {resetOpen=true}
                } label: {Image(systemName:"square.and.arrow.up")}}
            }
            .safeAreaInset(edge:.bottom) {
                HStack {Button(comfort ? "查看首页" : "查看舒适页") {comfort.toggle();page=0};Spacer();Text("仿真 · 不控车").font(.caption).foregroundStyle(.secondary)}.padding(12).background(.regularMaterial)
            }
        }.navigationViewStyle(.stack).preferredColorScheme(scheme)
            .onChange(of:theme) {value in if let data=try? value.data() {UserDefaults.standard.set(data,forKey:"design.theme.v1")}}
            .fileExporter(isPresented:$exportOpen,document:document,contentType:.json,defaultFilename:"MGControl-Design-v1") {result in
                if case .failure=result {notice="导出未完成，请重试并保存到文件。"}
            }
            .fileImporter(isPresented:$importOpen,allowedContentTypes:[.json],allowsMultipleSelection:false) {result in
                do {
                    guard let url=try result.get().first else {return}
                    let scoped=url.startAccessingSecurityScopedResource();defer {if scoped {url.stopAccessingSecurityScopedResource()}}
                    let size=(try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
                    guard size<=512*1024 else {throw ThemeError.invalid}
                    let value=try Theme.decode(Data(contentsOf:url));try validateSymbols(value)
                    theme=value;notice="设计文件已导入。";page=0
                } catch {notice="导入失败："+error.localizedDescription}
            }
            .alert("工作台",isPresented:Binding(get:{notice != nil},set:{if !$0 {notice=nil}})) {Button("好") {notice=nil}} message: {Text(notice ?? "")}
            .confirmationDialog("恢复默认方案？请先导出需要保留的设计。",isPresented:$resetOpen,titleVisibility:.visible) {Button("恢复默认",role:.destructive) {theme = .initial}}
    }
    private var editor:some View {
        Form {
            Section("方案与预览") {
                TextField("方案名称",text:$theme.name)
                Picker("外观",selection:$theme.appearance) {Text("跟随系统").tag("system");Text("浅色").tag("light");Text("深色").tag("dark")}
                Picker("画布宽度（pt）",selection:$previewWidth) {ForEach([320,375,390,430],id:\.self) {Text("\($0)").tag($0)}}
                Toggle("大字体压力测试",isOn:$largeType)
                Toggle("长车名与长地址",isOn:$longText)
                Toggle("缺失数据状态",isOn:$missingData)
                Text("预览宽度大于手机可用区域时可横向滚动。所有尺寸为pt；画布不是当前手机的物理像素。") .font(.caption)
            }
            Section("整体布局") {
                slider("页面左右边距",$theme.padding,8...32)
                slider("组件间距",$theme.spacing,4...32)
                slider("卡片内边距",$theme.cardPadding,8...28)
                slider("卡片圆角",$theme.corner,0...40)
                slider("阴影半径",$theme.shadow,0...20)
                slider("标题字号",$theme.titleSize,20...40)
                slider("车辆渲染高度",$theme.heroHeight,160...300)
            }
            Section("颜色（六位HEX，不含#）") {
                colorField("主题色",$theme.accent);colorField("浅色背景",$theme.background);colorField("浅色卡片",$theme.cardColor)
                colorField("深色背景",$theme.darkBackground);colorField("深色卡片",$theme.darkCardColor)
                Picker("车辆外观",selection:$theme.vehicleAsset) {
                    Text("月光白").tag("MG4White");Text("星野灰").tag("MG4Grey");Text("东来紫").tag("MG4Purple");Text("冰晶蓝").tag("MG4IceBlue");Text("杏仁米").tag("MG4Almond")
                }
            }
            Section("按钮与图标") {
                Picker("选择组件",selection:$role) {ForEach(Theme.roles,id:\.self) {Text(Theme.initial.items[$0]!.title).tag($0)}}
                TextField("按钮文字",text:itemBinding(\.title))
                TextField("SF Symbol 名称",text:itemBinding(\.symbol)).textInputAutocapitalization(.never).disableAutocorrection(true)
                Image(systemName:theme.items[role]?.symbol ?? "questionmark").font(.largeTitle).frame(maxWidth:.infinity)
                slider("圆形按钮直径",itemBinding(\.diameter),36...88)
                slider("图标大小",itemBinding(\.iconSize),12...44)
                slider("文字字号",itemBinding(\.fontSize),10...22)
                slider("图标文字间距",itemBinding(\.gap),2...20)
                Text("按钮点击区域至少44pt；后备箱保留禁用占位。首版使用系统图标，自定义图片及自由拖拽后续扩展。") .font(.caption)
            }
            Section("首页卡片排列") {
                ForEach(theme.cardOrder,id:\.self) {id in
                    HStack {Text(cardTitle(id));Spacer();Button("上移") {move(id,-1)}.buttonStyle(.borderless);Button("下移") {move(id,1)}.buttonStyle(.borderless)}
                }
            }
            Section {
                Button("保存并导出设计文件") {exportTheme()}
                Text("导出后发送完整JSON文件给开发者。配置包含格式版本、固定组件标识和样式参数；不包含账号、钥匙、定位或真实车辆数据。正式App尚未直接导入此格式，后续需接入共享渲染器后才能一致应用。") .font(.caption)
            }
        }
    }
    private func itemBinding<T>(_ key:WritableKeyPath<Theme.Item,T>)->Binding<T> {
        Binding(get:{(theme.items[role] ?? Theme.initial.items[role]!)[keyPath:key]},set:{value in var item=theme.items[role] ?? Theme.initial.items[role]!;item[keyPath:key]=value;theme.items[role]=item})
    }
    private func slider(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>)->some View {
        VStack(alignment:.leading) {HStack {Text(title);Spacer();Text("\(Int(value.wrappedValue)) pt").foregroundStyle(.secondary)};Slider(value:value,in:range,step:1)}
    }
    private func colorField(_ title:String,_ value:Binding<String>)->some View {
        HStack {Circle().fill(Color(designHex:value.wrappedValue)).frame(width:20,height:20);Text(title);TextField("HEX",text:value).multilineTextAlignment(.trailing).textInputAutocapitalization(.characters).disableAutocorrection(true)}
    }
    private func cardTitle(_ id:String)->String {["location":"车辆位置","climate":"空调","details":"完整车况","sentinel":"哨兵模式"][id] ?? id}
    private func move(_ id:String,_ offset:Int) {guard let index=theme.cardOrder.firstIndex(of:id),theme.cardOrder.indices.contains(index+offset) else {return};theme.cardOrder.swapAt(index,index+offset)}
    private func validateSymbols(_ value:Theme) throws {for item in value.items.values {guard UIImage(systemName:item.symbol) != nil else {throw ThemeError.invalid}}}
    private func exportTheme() {
        do {try validateSymbols(theme);document=ThemeDocument(data:try theme.data());exportOpen=true}
        catch {notice=error.localizedDescription}
    }
    private static func savedTheme()->Theme {
        guard let data=UserDefaults.standard.data(forKey:"design.theme.v1"),let value=try? Theme.decode(data) else {return .initial};return value
    }
}
