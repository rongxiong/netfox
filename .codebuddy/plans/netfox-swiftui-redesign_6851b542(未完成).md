---
name: netfox-swiftui-redesign
overview: 用 SwiftUI 全面重设计 netfox 的 iOS 与 macOS 调试 UI（请求列表、详情、Body、URL Query、设置、统计、信息），最低版本提升到 iOS 17 / macOS 14，新增 SwiftUI 入口同时保留 NFX.show() 等旧 API，视觉改为中性系统色风格。
design:
  styleKeywords:
    - Minimalism
    - System Native
    - Neutral Palette
    - Card Grouping
    - Dark Mode Adaptive
    - Subtle Motion
  fontSystem:
    fontFamily: Helvetica Neue
    heading:
      size: 28px
      weight: 700
    subheading:
      size: 17px
      weight: 600
    body:
      size: 15px
      weight: 400
  colorSystem:
    primary:
      - "#007AFF"
      - "#0A84FF"
      - "#5E5CE6"
    background:
      - "#F2F2F7"
      - "#FFFFFF"
      - "#1C1C1E"
      - "#2C2C2E"
    text:
      - "#1C1C1E"
      - "#6E6E73"
      - "#FFFFFF"
      - "#98989D"
    functional:
      - "#34C759"
      - "#FF453A"
      - "#FF9F0A"
      - "#8E8E93"
todos:
  - id: raise-platform-config
    content: 用 [subagent:code-explorer] 核查待删类与 xib 的全部引用，并提升 Package.swift、podspec、pbxproj 到 iOS 17 / macOS 14
    status: pending
  - id: extract-core-content
    content: 新增 Core/NFXContent.swift 与 NFXStore.swift，把详情/统计/信息逻辑抽为结构化纯数据层
    status: pending
    dependencies:
      - raise-platform-config
  - id: build-swiftui-foundation
    content: 新建 UI/ 目录：NFXTheme 中性主题、共享组件（状态胶囊、方法徽章、键值行、卡片）与分享/复制能力
    status: pending
    dependencies:
      - extract-core-content
  - id: implement-ios-pages
    content: 实现 iOS SwiftUI 页面：请求列表、详情、Body/图片、Query、设置、统计、信息
    status: pending
    dependencies:
      - build-swiftui-foundation
  - id: implement-macos-ui
    content: 实现 macOS SwiftUI：删除 AppKit 与 xib，用 NSHostingController 窗口承载 NavigationSplitView 页面
    status: pending
    dependencies:
      - build-swiftui-foundation
  - id: wire-entry-points
    content: 改造 NFX.swift 入口为 SwiftUI 宿主，新增 NetfoxView 与 netfoxPanel 修饰符，保留摇一摇与旧 API
    status: pending
    dependencies:
      - implement-ios-pages
      - implement-macos-ui
  - id: verify-and-docs
    content: 更新 demo 与 README 演示新入口，校验两平台编译与空态/过滤/分享/清空等冒烟路径
    status: pending
    dependencies:
      - wire-entry-points
---

## 产品概述
netfox 是一个一行代码接入的网络调试库，用于在 App 内查看所有被拦截的 HTTP 请求。本次需求是把它的调试面板全部用 SwiftUI 重写，打造现代化、系统级的观感，并把最低支持版本提升到 iOS 17 / macOS 14 以使用最新 SwiftUI 能力。

## 核心功能
- **请求列表**：可搜索的请求流，展示方法、状态码、URL、耗时、响应类型、MOCK 标记与未读指示；支持清空数据。
- **请求详情**：Info / Request / Response 分段切换，结构化展示请求头、响应头与 body，支持复制、查看超长 body、查看 URL Query 参数。
- **Body 与图片预览**：完整请求/响应 body 文本（等宽字体、可复制），图片响应直接预览。
- **设置**：日志开关、Mock Server 开关与服务器地址、响应类型过滤、分享会话日志、清空数据、版本与项目链接。
- **统计**：请求总数、成功/失败、请求与响应体积、平均/最快/最慢响应时间，卡片化呈现。
- **设备信息**：应用名/版本/build、系统版本、设备型号、分辨率、IP 地址。
- **入口兼容**：保留 `NFX.show()/hide()/toggle()` 与摇一摇入口，额外提供可直接嵌入或 sheet 呈现的 SwiftUI 入口。

## 视觉效果
中性系统色 + 卡片化列表，弱化原有橙色品牌色；自动适配深色模式，圆角卡片、细分隔线、状态色语义（成功/失败/无响应）、SF Symbols 图标、等宽字体展示报文内容。


## 技术栈
- 语言：Swift 5.9+（Swift 5 mode）
- UI：SwiftUI（iOS 17+ / macOS 14+ 可用 `NavigationStack`、`NavigationSplitView`、`@Observable`、`ContentUnavailableView`、`.searchable`、`Table`、`scrollPosition`、`.contentTransition`）
- 宿主桥接：iOS `UIHostingController`；macOS `NSHostingController` + 代码创建 `NSWindow`
- 数据层：复用现有 `NFXHTTPModelManager` 的 `Publisher/Subscription`，新增 `@Observable` Store 做 UI 绑定
- 工程：Xcode 工程（`netfox.xcodeproj`）、SwiftPM（`Package.swift`）、CocoaPods（`netfox.podspec`）

## 实现思路
1. **先解耦再重写**：把散落在 `NFXDetailsController`/`NFXStatisticsController`/`NFXInfoController`/`NFXGenericController` 中的「NSAttributedString 拼装逻辑」抽成纯数据的结构化模型（分组 + key/value + body），SwiftUI 直接原生渲染；导出日志仍可复用纯文本生成路径（`shareLog` 使用 `.string`）。
2. **一套 SwiftUI 代码两平台**：新增 `netfox/UI/` 目录，iOS 与 macOS 同时编译；列表/详情/设置/统计/信息页面共享，仅导航容器与窗口宿主按平台分叉（iOS `NavigationStack`、macOS `NavigationSplitView`）。
3. **入口双向兼容**：`NFX.show()` 内部改为 present SwiftUI（`UIHostingController` / macOS `NSWindow`），公开 API 与摇一摇行为完全不变；新增 `NetfoxView`（公开 SwiftUI 根视图）与 `.netfoxPanel(isPresented:)` 修饰符作为 SwiftUI 入口。
4. **图标去资源化**：用 SF Symbols（`gearshape`、`xmark`、`info.circle`、`chart.bar`、`doc.on.doc`）替换 `NFXAssets` 的 base64 图片，减少体积并自动适配平台。

## 关键技术决策与权衡
- **iOS 17 / macOS 14 下限**：换取 `@Observable`（细粒度刷新、避免 `@Published` 全量重绘）、`ContentUnavailableView`（空态/无结果）、`NavigationStack`（可编程导航）。代价是放弃 iOS 13-16 用户 —— 已由用户确认。
- **删除 UIKit/AppKit UI 而非并存**：用户要求「重新设计所有 UI 页面」，双套 UI 会带来维护与行为不一致成本；故删除 `netfox/iOS/*`、`netfox/OSX/*` 与全部 xib，`NFXWindowController` 由新的 SwiftUI 窗口控制器取代。Core 中仅保留纯逻辑。
- **结构化详情 vs UIViewRepresentable(UITextView)**：直接用 Representable 渲染 `NSAttributedString` 在 macOS/iOS 双端表现不一致且无法利用 SwiftUI 的选择、复制、无障碍与动态字体；结构化渲染更可维护，且便于新增「复制到剪贴板」按钮（替代长按手势）。
- **性能**：请求量可达数千条。Store 只在 `NFXHTTPModelManager` 通知时增量赋值数组；列表使用 `List` 懒加载；搜索过滤在 Store 内单次 `filter`（O(n)），输入用 `.searchable` + 轻量 debounce（100ms）避免每次按键全量重算；body 文本按 1024 字节阈值内联，超长才进入独立页面读取文件，避免列表/详情一次性解码大报文。统计在模型集合变化时惰性计算（O(n)），不随视图重绘重复计算。

## 实现注意事项
- 保留未提交的 Mock Server 能力（`NFXMockServer`、`setMockServerURL/Mappings` 等），设置页必须完整承载对应交互。
- 保留 `UIScreen.nfx_main`、`UIWindow.keyWindow`（iOS 26 兼容）、`nfxSafeFileName` 等近期修复，勿回退。
- `NFXConstants.swift` 的 `NFXViewController/NSViewController` typealias 随控制器删除一并清理；`NFXColor/NFXFont` 若仍有 Core 使用则保留，UI 层改用 SwiftUI `Color/Font`。
- SwiftPM 目标原本 `exclude: ["OSX"]`，删除 OSX 目录后需移除该 exclude；podspec 的 `source_files` 需覆盖新的 `netfox/UI/**`。
- 自定义 `Publisher` 非 Combine、无背压，回调已在主线程；Store 更新必须在主线程赋值，避免 `#Preview`/后台触发的崩溃。
- 分享链路：`UIActivityViewController`（simple/full log、curl）用 `UIViewControllerRepresentable`；macOS 用 `NSSharingServicePicker` 或写入临时文件后 `NSWorkspace` 打开；邮件分享在 macOS 改为分享面板，避免 `MFMailComposeViewController` 平台限制。

## 架构设计
```mermaid
graph TD
    A[NFX 公开 API / 摇一摇] --> B[iOS: UIHostingController]
    A --> C[macOS: NSHostingController + NSWindow]
    B --> D[NetfoxView 公开 SwiftUI 根视图]
    C --> D
    D --> E[NavigationStack / NavigationSplitView]
    E --> F[RequestListView]
    E --> G[SettingsView / StatisticsView / InfoView]
    F --> H[DetailsView: Info/Request/Response]
    H --> I[BodyView / ImagePreview / QueryItemsView]
    J[NFXStore @Observable] --> F
    J --> G
    K[NFXHTTPModelManager + Publisher] --> J
    L[NFXContentBuilder 结构化详情/统计/信息] --> H
    L --> G
    M[NFXHTTPModel 文件读写] --> L
```
- 数据流：`NFXProtocol` 拦截 → `NFXHTTPModelManager.add()` → `Publisher` 通知 → `NFXStore` 更新 → SwiftUI 重绘。
- 交互回流：设置/过滤/清空 → `NFX` 与 `NFXHTTPModelManager` 单例 → 再次通知 Store，保持单一数据源。

## 目录结构
```
netfox/
├── Core/
│   ├── NFX.swift                     # [MODIFY] iOS 分支改为 present UIHostingController(NetfoxView)；macOS 分支改为 SwiftUI 窗口控制器；新增 SwiftUI 版 show 辅助；保留全部 @objc API
│   ├── NFXContent.swift              # [NEW] 纯数据层：NFXDetailsContent（分组/字段/body/是否截断）、NFXStatisticsSummary、NFXDeviceInfo（含异步 IP），替代原 Controller 里的字符串拼装，并提供导出用的纯文本
│   ├── NFXStore.swift                # [NEW] @Observable 状态容器：模型列表、搜索文本、过滤、选中模型；订阅 NFXHTTPModelManager.publisher
│   ├── NFXHTTPModelManager.swift     # [MODIFY] 视需要补充清空/过滤变更通知，保持线程约定
│   ├── NFXHelper.swift               # [MODIFY] 删除 UI 相关颜色/字体/图片扩展（或标记 deprecated），保留 HTTPModelShortType、NFXPath、Publisher/Subscription、UIScreen.nfx_main
│   ├── NFXConstants.swift            # [MODIFY] 移除 NFXViewController 等无用 typealias
│   ├── NFXWindowController.swift     # [DELETE] 由 UI/Mac/NFXMacWindowController.swift 取代
│   ├── NFXGenericController.swift    # [DELETE] 逻辑迁移至 NFXContent.swift
│   ├── NFXDetailsController.swift    # [DELETE]
│   ├── NFXListController.swift       # [DELETE]
│   ├── NFXSettingsController.swift   # [DELETE]
│   ├── NFXStatisticsController.swift # [DELETE]
│   ├── NFXInfoController.swift       # [DELETE]
│   ├── NFXImageBodyDetailsController.swift # [DELETE] 功能并入 UI/NFXBodyView.swift
│   └── NFXAssets.swift               # [DELETE] 改用 SF Symbols
├── UI/                               # [NEW] 共享 SwiftUI 层（iOS + macOS 同编译）
│   ├── NFXTheme.swift                # [NEW] 中性配色、字体、圆角/阴影、状态色、卡片与标签样式
│   ├── NetfoxView.swift              # [NEW] 公开根视图 + .netfoxPanel(isPresented:) 修饰符，平台自适应导航容器
│   ├── NFXStore+Env.swift            # [NEW] Environment 注入 Store 与关闭回调
│   ├── NFXRequestListView.swift      # [NEW] 请求列表：searchable、空态、清空、工具栏
│   ├── NFXRequestRowView.swift       # [NEW] 请求行卡片：状态色条、方法徽章、URL、耗时、类型、MOCK、未读点
│   ├── NFXDetailsView.swift          # [NEW] Info/Request/Response 分段（TabView + segmented），结构化字段与复制
│   ├── NFXBodyView.swift             # [NEW] 完整 body 文本/图片预览
│   ├── NFXQueryItemsView.swift       # [NEW] URL Query 参数列表
│   ├── NFXSettingsView.swift         # [NEW] 日志开关、Mock Server、类型过滤、分享日志、清空、版本信息
│   ├── NFXStatisticsView.swift       # [NEW] 统计卡片网格
│   ├── NFXInfoView.swift             # [NEW] 设备与应用信息
│   ├── Components/                   # [NEW] StatusPill、MethodBadge、KeyValueRow、CardContainer、CopyButton、TagView
│   ├── Sharing/                      # [NEW] ShareSheet(UIViewControllerRepresentable)、MacSharing、curl 导出
│   └── Mac/
│       ├── NFXMacWindowController.swift # [NEW] NSWindow + NSHostingController 承载 SwiftUI，替代 xib 窗口
│       └── NFXMacRootView.swift      # [NEW] NavigationSplitView 布局（列表 + 详情）
├── iOS/                              # [DELETE] 9 个 UIKit 文件全部移除
└── OSX/                              # [DELETE] 全部 AppKit 文件与 NetfoxWindow.xib、两个 cell xib
```
工程与配置文件：
```
Package.swift                # [MODIFY] platforms 改为 .iOS(.v17)/.macOS(.v14)；移除 exclude OSX；tools-version 提升
netfox.podspec               # [MODIFY] ios/osx deployment_target 提升；source_files 覆盖 netfox/UI/**
netfox.xcodeproj/project.pbxproj # [MODIFY] IPHONEOS_DEPLOYMENT_TARGET=17.0、MACOSX_DEPLOYMENT_TARGET=14.0（各 target Debug/Release）；增删文件引用、移除 xib 与资源
netfox_ios_demo/AppDelegate.swift、Info.plist、SceneDelegate.swift # [MODIFY] 部署目标与 SwiftUI 入口演示
README.md                    # [MODIFY] 更新最低版本、SwiftUI 入口用法与截图说明
```

## 关键接口（实现时需严格对齐）
```swift
// 结构化详情（取代 NSAttributedString 拼装）
struct NFXContentSection { let title: String?; let fields: [NFXContentField]; let body: NFXContentBody? }
struct NFXContentField { let key: String; let value: String; let isCopyable: Bool }
struct NFXContentBody { let text: String?; let isTruncated: Bool; let byteLength: Int }
struct NFXDetailsContent { let info: NFXContentSection; let request: NFXContentSection; let response: NFXContentSection?; let plainTextLog: String }

// UI 单一数据源
@available(iOS 17.0, macOS 14.0, *)
@Observable public final class NFXStore {
    var models: [NFXHTTPModel]
    var searchText: String
    var filters: [Bool]
    var displayedModels: [NFXHTTPModel] { get }
    func clear()
}

// 新的 SwiftUI 入口（旧入口保留）
@available(iOS 17.0, macOS 14.0, *)
public struct NetfoxView: View { public init() }
@available(iOS 17.0, macOS 14.0, *)
public extension View { func netfoxPanel(isPresented: Binding<Bool>) -> some View }
```


## 应用类型
iOS 与 macOS 双平台的 App 内嵌调试面板（iOS 以 sheet/全屏呈现，macOS 以独立窗口呈现），采用系统原生观感。

## 设计风格
中性系统色 + 卡片化分组，接近系统「设置」的视觉语言：浅色为 #F2F2F7 底 + 纯白圆角卡片，深色为 #1C1C1E 底 + #2C2C2E 卡片；强调色使用系统蓝，状态色仅用于语义（成功/失败/无响应/MOCK）；SF Symbols 线性图标、16pt 圆角、1px 细分隔线、轻微按压反馈。

## 页面设计

### 1. 请求列表（iOS 主页面 / macOS 左栏）
- 顶部导航栏：标题「Requests」，左侧关闭，右侧清空与设置图标。
- 搜索栏：`.searchable` 常驻，实时过滤 URL / 方法 / 类型。
- 请求卡片列表：左侧状态色条（绿/红/灰），右侧方法徽章、URL（两行截断）、耗时、响应类型、MOCK 标签、未读圆点。
- 空态：无请求时展示 `ContentUnavailableView`（图标 + 说明 + 摇一摇提示）。

### 2. 请求详情
- 分段控件：Info / Request / Response 三选一，`TabView` 支持滑动切换并带选中态下划线动画。
- 概览卡：状态码胶囊、方法、时长、时间等核心指标置顶。
- 分组字段：Headers / Body 分区，key 次级灰、value 主色、右侧复制按钮；body 超 1024 字节显示「查看完整内容」。
- 右上角操作菜单：Simple log / Full log / Export as curl / 复制 URL。

### 3. Body 与图片预览
- 文本 body：等宽字体、可滚动、保留换行，支持一键复制与分享。
- 图片响应：自适应缩放预览，顶部显示尺寸与类型，支持分享。
- URL Query 页：参数名/值两列列表，单项可复制。

### 4. 设置
- 分组卡片：Logging（开关）、Mock Server（开关 + 地址输入 + 映射说明）、Response Types（勾选过滤）、Session（分享会话日志）、Data（清空，红色破坏性操作）。
- 底部：版本号与项目链接（中性灰小字）。
- macOS 以窗口工具栏入口呈现，iOS 由列表页工具栏 push。

### 5. 统计
- 指标卡片网格：总请求、成功/失败、请求/响应体积、平均/最快/最慢耗时，大数字 + 次级标签。
- 成功/失败占比用细进度条表达，随数据变化带数字滚动动画。
- 空数据时展示占位说明而非 0 值堆叠。

### 6. 设备信息
- 分组列表：应用（名称/版本/build/包名）、设备（型号/系统/分辨率）、网络（IP，异步加载带占位）。
- 每项支持复制，整体支持导出。

## 响应式与适配
iOS 支持 Dynamic Type 与横竖屏；macOS 使用 NavigationSplitView，窗口最小尺寸约束，列表列宽可拖拽；两平台均自动适配深色模式与系统强调色。

## Agent Extensions
### SubAgent
- **code-explorer**
  - 用途：在删除 UIKit/AppKit UI 前后，全仓检索所有对 `NFXListController_iOS`、`NFXListController_OSX`、`NFXWindowController`、`NFXGenericController`、`NFXAssets`、`NFXViewController` 及 xib 名称的引用（含 `project.pbxproj`、`Package.swift`、`netfox.podspec`、demo），确保无遗漏引用与构建断链。
  - 预期结果：输出一份完整的引用清单与受影响文件列表，作为删除与配置修改的依据。
