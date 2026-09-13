---
name: add-unit-and-ui-tests
overview: 为 netfox 仓库新增 iOS 单元测试（含 SwiftUI 快照测试）与 XCUITest UI 测试：在 netfox.xcodeproj 中新建 netfoxTests / netfoxUITests 两个 target，引入 swift-snapshot-testing 依赖，补充必要的 accessibilityIdentifier 与 UI 测试种子数据，并更新 xcscheme 便于命令行运行。
todos:
  - id: add-test-targets
    content: 用 [subagent:code-explorer] 核对 pbxproj 结构，新增 netfoxTests 与 netfoxUITests 两个 target 并更新 netfox_ios.xcscheme
    status: completed
  - id: add-accessibility-ids
    content: 新增 NFXAccessibility 常量并为 netfox 列表/详情/设置与 demo 悬浮按钮挂 accessibilityIdentifier
    status: completed
    dependencies:
      - add-test-targets
  - id: add-demo-seeder
    content: 在 demo 内新增 NFXDemoStubProtocol 与 NFXDemoSeeder，仅由 -nfxUITestSeed 触发种子数据
    status: completed
    dependencies:
      - add-test-targets
  - id: write-unit-tests
    content: 编写纯逻辑单元测试：MockServer、Helper、Model、Manager、Store、Content，含 NFXTestCase 复位基类
    status: completed
    dependencies:
      - add-test-targets
  - id: write-e2e-tests
    content: 实现 NFXLocalHTTPServer 并编写 NFXProtocol 端到端拦截与 mock 重定向测试
    status: completed
    dependencies:
      - write-unit-tests
  - id: add-snapshot-tests
    content: 接入 swift-snapshot-testing，编写关键视图快照测试并 record 生成基准图
    status: completed
    dependencies:
      - add-test-targets
  - id: write-ui-tests
    content: 编写 XCUITest：Page Object 与面板主流程（列表、搜索、详情、设置、关闭）
    status: completed
    dependencies:
      - add-accessibility-ids
      - add-demo-seeder
  - id: verify-and-docs
    content: 用 xcodebuild 跑通全部测试并修复失败，README 补充测试运行说明
    status: completed
    dependencies:
      - write-unit-tests
      - write-e2e-tests
      - add-snapshot-tests
      - write-ui-tests
---


## 产品概述
为 netfox（iOS/macOS 网络调试库）补齐自动化测试体系：一套可离线运行、可被命令行 `xcodebuild test` 驱动的单元测试，以及一套基于 XCUITest 的端到端 UI 测试，并引入 SwiftUI 快照测试守护 netfox 面板视觉回归。

## 核心功能
1. **测试工程搭建**：在 `netfox.xcodeproj` 中新增 `netfoxTests`（单元测试 bundle，依赖 `netfox_ios` framework）与 `netfoxUITests`（XCUITest bundle，host app 为 `netfox_ios_demo`）两个 target，并更新 xcscheme 的 `<Testables>` 与 BuildAction，使 `xcodebuild -scheme netfox_ios test` 可直接运行。
2. **单元测试（纯逻辑、离线）**：覆盖请求解析与格式化（`NFXHelper` 的 `URLRequest/URLResponse` 扩展、curl 生成、文件名安全化）、`NFXHTTPModel` 的请求/响应落库与日志格式化、`NFXHTTPModelManager` 的过滤与插入、`NFXStore` 的搜索防抖与筛选、`NFXMockServer` 的重定向与映射优先级、`NFXContent`/`NFXFormat` 的详情与统计计算。
3. **本地 mock 服务端到端拦截测试**：内置一个只监听 `127.0.0.1` 的轻量 HTTP server，验证 `NFXProtocol` 真实拦截后模型的落库、body 落盘、session log 写入，以及 mock server 重定向时 `X-Netfox-Original-URL/Host` 头与路径/查询保留。全程不访问外网。
4. **UI 测试（netfox 面板主流程）**：demo 悬浮按钮 → 打开面板 → 请求列表 → 搜索/过滤 → 详情三页签 → 设置页开关；数据由 demo 内 UI-test 专用种子入口（launch argument 触发 + 进程内 stub URLProtocol）提供，稳定且不依赖网络。
5. **快照测试**：引入 `swift-snapshot-testing`，对请求行、空态、详情页、设置页等关键视图做图像快照，基准图以 record 模式首次生成后入库。
6. **可访问性标识**：为 netfox UI 与 demo 悬浮按钮补充 `accessibilityIdentifier`（不改视觉），作为 UI 测试的稳定锚点。



## 技术栈
- 语言/框架：Swift 5，`XCTest`（单元测试 + XCUITest），`SwiftUI`（被测对象）
- 构建：Xcode target（`netfoxTests`、`netfoxUITests`）+ `xcodebuild -scheme netfox_ios -destination 'platform=iOS Simulator,name=iPhone 16' test`
- 依赖：`swift-snapshot-testing`（pointfreeco）通过 Xcode SPM 包引用**仅链接给 `netfoxTests`**，不污染 framework 与 CocoaPods 产物
- 本地 mock 服务：测试内自研 POSIX socket HTTP server（仅 `127.0.0.1`、随机端口），零第三方依赖

## 实现方案

### 总体策略
在不动现有架构的前提下新增两个测试 target；单元测试通过 `@testable import netfox_ios` 访问 internal 类型；通过"统一基类复位 + 注入式依赖"消除 netfox 全局单例副作用；UI 测试通过"launch argument + demo 进程内 stub"获得确定性数据。

### 关键技术决策
1. **测试载体选 Xcode target**：XCUITest 无法在 SwiftPM 中运行，用户已选定 Xcode 工程；单元测试同步放在 `netfoxTests`，避免同一套代码双份维护。
2. **UI 测试数据种子方案（重要取舍）**：
   - 备选 A：把 `NFXHTTPModelManager` 提升为 public 以便 demo 直接塞模型 —— 会扩大库公开 API 面，仅为测试改产品 API，不采纳。
   - **采纳 B**：在 demo target 内新增 `NFXDemoStubProtocol`（`URLProtocol` 子类）与 `NFXDemoSeeder`，仅当 launch argument 含 `-nfxUITestSeed` 时注册。**关键点**：`NFXProtocol.startLoading()` 内部会话使用 `URLSessionConfiguration.default`，其内部请求带 `nfxInternalKey` 会被 NFXProtocol 跳过，从而落到 stub 上返回固定 JSON/HTML/图片响应。因此请求会真实穿过 NFXProtocol 被记录，既零外网又端到端，且**不改动任何 netfox 源码 API**。注册时必须 insert 到 NFXProtocol **之后**（netfox 的 swizzle 已把它插在 index 0）。
3. **端到端拦截测试用本地 socket server 而非 stub URLProtocol**：真实走一遍 TCP/HTTP 栈，能验证重定向头、状态码、body 落盘与 gzip；stub 方式仅用于 demo 种子（那里只求数据确定性）。
4. **全局状态隔离**：`NFX` 的 `start()`、`URLSessionConfiguration.implementNetfox()` 均为一次性且有 swizzle，`NFXHTTPModelManager`/`NFXStore` 是单例。提供 `NFXTestCase` 基类在 `setUp/tearDown` 中：`NFXHTTPModelManager.shared.clear()`、恢复 `filters` 全 true、清空 `com.netfox.mockServer.enabled` / `.url` 两个 UserDefaults key、删除 `NSTemporaryDirectory()/NFX` 目录。`NFXMockServer` 测试使用 `UserDefaults(suiteName:)` 独立实例，避免污染 `standard`。
5. **`NFXHTTPModelManager.add` 是 `DispatchQueue.main.async`**：断言必须用 `XCTNSPredicateExpectation` / 主队列 drain 等待，不能用同步断言。同理 `NFXStore.searchText` 有 0.15s 防抖，测试用 `XCTWaiter` 等待 ≥ 0.3s。
6. **快照测试定位**：快照属于单元测试（render → 比对 PNG），放 `netfoxTests/Snapshot/`。首选 SwiftUI `.image` 策略；若当前版本对 SwiftUI 支持有限，降级为 `UIHostingController(rootView:).view` 渲染 UIView 后快照。用固定设备配置 + `perceptualPrecision` 降低模拟器字体差异导致的抖动。

## 执行要点（防回归）
- **pbxproj 手工编辑**：所有新增对象使用全新 24 位大写十六进制 UUID（已占用段 `B3BC02…`、`8229AD…`、`E20FD2…`、`7C000000000000000000000X` 系列均不可复用）；需补齐 `PBXGroup`、`PBXFileReference`、`PBXBuildFile`、`PBXSourcesBuildPhase`、`PBXFrameworksBuildPhase`、`PBXResourcesBuildPhase`、`XCConfigurationList` + Debug/Release `XCBuildConfiguration`、`PBXTargetDependency`、`PBXContainerItemProxy`；`netfoxUITests` 还需 `TargetAttributes` 中 `TestTargetID` 指向 demo。改完用 `xcodebuild -list` 与 `xcodebuild -showBuildSettings -target netfoxTests` 校验。
- **scheme**：`netfox_ios.xcscheme` 的 BuildAction 需加入 `netfox_ios_demo`（UI 测试的 host 必须可构建），`<Testables>` 加入两个测试 bundle。
- **性能**：测试总时长控制在秒级；本地 server 只启一次（`setUp` 中启动、`tearDown` 关闭并 `close` socket），避免每个用例重复 bind；快照用例控制在 6 张以内。
- **日志**：既有源码用 `print("[NFX]: …")` 输出，测试不对日志做断言；失败信息保持可定位（URL、状态码、期望/实际）。
- **影响面**：不改 netfox 运行时行为；`accessibilityIdentifier` 与 demo 种子代码（仅 launch argument 触发）对正式产物零影响。
- **依赖风险**：引入 SPM 包意味着首次打开工程需联网解析；README 中注明。

## 架构设计
```mermaid
graph TD
    A[xcodebuild test / Xcode Test] --> B[netfoxTests]
    A --> C[netfoxUITests]
    B --> D[@testable import netfox_ios]
    B --> E[NFXTestCase 全局复位基类]
    B --> F[NFXLocalHTTPServer 127.0.0.1]
    B --> G[swift-snapshot-testing]
    D --> H[Core: MockServer/Helper/Model/Manager/Store/Content]
    D --> I[UI: Row/Details/Settings/EmptyState 快照]
    F --> J[NFXProtocol 端到端拦截]
    C --> K[host: netfox_ios_demo]
    K --> L[NFSeeder + NFXDemoStubProtocol 仅 -nfxUITestSeed]
    K --> M[netfox 面板 NetfoxView]
    M --> N[accessibilityIdentifier 锚点]
```

## 目录结构

```
netfox.xcodeproj/
├── project.pbxproj                    # [MODIFY] 新增 netfoxTests / netfoxUITests 两个 native target（全新 UUID）、
│                                      #          文件引用/构建阶段/配置列表/目标依赖，及 TargetAttributes.TestTargetID
└── xcshareddata/xcschemes/
    └── netfox_ios.xcscheme            # [MODIFY] TestAction 加入 <Testables>；BuildAction 加入 netfox_ios_demo

netfox/
├── UI/
│   ├── NFXAccessibility.swift         # [NEW] 统一 accessibilityIdentifier 常量枚举（nfx.list / nfx.row / nfx.search /
│   │                                  #       nfx.toolbar.settings / .statistics / .info / .clear / .close /
│   │                                  #       nfx.details.picker / nfx.settings.logging / .mockToggle / .mockURL …）
│   ├── NFXRequestListView.swift       # [MODIFY] 列表、搜索框、toolbar 按钮加 identifier
│   ├── NFXRequestRowView.swift        # [MODIFY] 行加 identifier（可按 randomHash 后缀，便于 UI 测试定位）
│   ├── NFXDetailsView.swift           # [MODIFY] 分段控件、标题、各页签加 identifier
│   └── NFXSettingsView.swift          # [MODIFY] 开关、URL 输入框、Clear Data 加 identifier
└── Core/
    └── （无改动；若种子方案需要再评估是否公开 NFXHTTPModelManager）

netfox_ios_demo/
├── NFXDemoStubProtocol.swift          # [NEW] demo 进程内 URLProtocol stub，返回固定 JSON/HTML/PNG 响应
├── NFXDemoSeeder.swift                # [NEW] 读取 launch argument -nfxUITestSeed，注册 stub 并触发 N 个确定性请求
├── AppDelegate.swift                  # [MODIFY] didFinishLaunching 中按需调用 seeder
└── DemoRootView.swift                 # [MODIFY] 悬浮按钮加 accessibilityIdentifier("demo.netfoxButton")

netfoxTests/
├── Info.plist                         # [NEW] 单元测试 bundle 配置
├── Supporting/
│   ├── NFXTestCase.swift              # [NEW] 基类：清 models、复位 filters、清 UserDefaults mock key、删临时 NFX 目录
│   ├── NFXLocalHTTPServer.swift       # [NEW] POSIX socket 本地 HTTP server（127.0.0.1 随机端口，/status/:code、/echo、/image）
│   └── NFXModelFactory.swift          # [NEW] 构造测试用 NFXHTTPModel / 请求，避免用例重复样板
├── NFXMockServerTests.swift           # [NEW] URL 归一化、非法输入、mappings 最长匹配、绝对 URL vs 路径、重定向头与路径保留
├── NFXHelperTests.swift               # [NEW] 短类型判定、URLRequest/URLResponse 扩展、curl、安全文件名、appendToFileURL
├── NFXHTTPModelTests.swift            # [NEW] saveRequest/saveResponse、isSuccessful、prettyPrint、日志文案、日志文件名
├── NFXHTTPModelManagerTests.swift     # [NEW] 异步插入顺序、filters/filteredModels、clear
├── NFXStoreTests.swift                # [NEW] 搜索防抖过滤、setFilter 同步、isUnread
├── NFXContentTests.swift              # [NEW] details/statistics/plainTextLog 与 NFXFormat 格式化
├── NFXProtocolInterceptionTests.swift # [NEW] 本地 server 上端到端拦截、body 落盘、session log、mock 重定向
└── Snapshot/
    ├── NFXSnapshotTests.swift         # [NEW] 请求行（success/error/mock/unread）、空态、详情页、设置页快照
    └── __Snapshots__/                 # [NEW] record 模式生成的基准 PNG

netfoxUITests/
├── Info.plist                         # [NEW] XCUITest bundle 配置
├── NFXUITestBase.swift                # [NEW] 启动封装：launchArguments += ["-nfxUITestSeed"]，等待种子数据就绪
├── Pages/
│   ├── DemoPage.swift                 # [NEW] 悬浮按钮打开面板
│   └── NetfoxPanelPage.swift          # [NEW] 列表/搜索/详情/设置的查询与操作封装（Page Object）
└── NFXNetfoxPanelUITests.swift        # [NEW] 主流程用例：打开面板→列表计数→搜索过滤→详情三页签→设置开关→关闭

README.md                              # [MODIFY] 补充测试运行方式与 SPM 依赖说明（可选但建议）
```

## 关键代码结构

```swift
// netfoxTests/Supporting/NFXLocalHTTPServer.swift
final class NFXLocalHTTPServer {
    /// 仅监听 127.0.0.1，端口由系统分配；返回 "http://127.0.0.1:<port>"
    func start() throws -> URL
    func stop()
    /// 注册固定应答：路径 -> (statusCode, headers, body)
    func register(path: String, status: Int, headers: [String: String], body: Data)
}
```

```swift
// netfox/UI/NFXAccessibility.swift
enum NFXAccessibility {
    static let requestList = "nfx.requestList"
    static let searchField = "nfx.searchField"
    static let rowPrefix   = "nfx.row."
    enum Toolbar { static let settings = "nfx.toolbar.settings"
                   static let statistics = "nfx.toolbar.statistics"
                   static let info = "nfx.toolbar.info"
                   static let clear = "nfx.toolbar.clear"
                   static let close = "nfx.toolbar.close" }
    enum Details { static let picker = "nfx.details.picker"
                   static let info = "nfx.details.info"
                   static let request = "nfx.details.request"
                   static let response = "nfx.details.response" }
    enum Settings { static let logging = "nfx.settings.logging"
                    static let mockToggle = "nfx.settings.mockServer"
                    static let mockURL = "nfx.settings.mockServerURL"
                    static let clearData = "nfx.settings.clearData" }
}
```


## Agent Extensions
### SubAgent
- **code-explorer**
  - Purpose：在动手改 `netfox.xcodeproj/project.pbxproj` 前，核对现有对象图（已用 UUID 段、`PBXGroup`/`PBXNativeTarget`/`XCConfigurationList` 结构、`netfox_ios` 与 `netfox_ios_demo` 的配置项差异），并确认 `netfox/UI` 与 `netfox_ios_demo` 中所有需要挂 `accessibilityIdentifier` 的具体位置。
  - Expected outcome：产出一份可执行的 pbxproj 新增对象清单（含未冲突的新 UUID 与需复制的 build settings）与 identifier 挂载点列表，避免手工编辑工程文件造成冲突或漏挂。
