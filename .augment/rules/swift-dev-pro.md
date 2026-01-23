---
type: "agent_requested"
description: "Modern Swift Best Practices for macOS"
---

# Swift 6+ Coding Guidelines and Best Practices (2025-2026)

Swift 6 fundamentally changes how developers approach concurrency by enforcing **complete data-race safety at compile time**. This comprehensive guide covers modern Swift idioms across all major development domains, combining official Apple guidance with community consensus. The most important shift for existing codebases is adopting strict concurrency checking—start with `SWIFT_STRICT_CONCURRENCY=targeted` immediately, then migrate incrementally to Swift 6 language mode.

---

## Swift 6 language features transform concurrency safety

Swift 6, released at WWDC 2024, prioritizes **data isolation enforcement** over flashy new features. The compiler now catches concurrent access issues at compile time rather than runtime, eliminating entire categories of data race bugs.

### Strict concurrency checking requires explicit safety

Global mutable state must now be explicitly protected. The compiler rejects patterns that were silently dangerous in Swift 5:

```swift
// ❌ Error in Swift 6: non-isolated global shared mutable state
var logger = Logger(subsystem: "app", category: "Main")

// ✅ Option 1: Make it immutable (preferred)
let logger = Logger(subsystem: "app", category: "Main")

// ✅ Option 2: Isolate to an actor
@MainActor var logger = Logger(subsystem: "app", category: "Main")

// ✅ Option 3: Unsafe opt-out (last resort)
nonisolated(unsafe) var logger = Logger(subsystem: "app", category: "Main")
```

### Typed throws enables exhaustive error handling

Swift 6 introduces typed throws (SE-0413), allowing functions to specify exact error types:

```swift
enum ValidationError: Error {
    case emptyName
    case nameTooShort(length: Int)
}

func validate(name: String) throws(ValidationError) {
    guard !name.isEmpty else { throw .emptyName }
    guard name.count > 2 else { throw .nameTooShort(length: name.count) }
}

do {
    try validate(name: "Jo")
} catch {
    // 'error' is inferred as ValidationError—no type casting needed
    switch error {
    case .emptyName: print("Name cannot be empty")
    case .nameTooShort(let len): print("Name too short: \(len)")
    }
}
```

**Use typed throws** for internal code requiring exhaustive handling. **Use untyped throws** for public APIs where error types may evolve—the Swift Evolution authors explicitly recommend untyped throws for most scenarios.

### Non-copyable types enforce unique ownership

The `~Copyable` syntax (SE-0390) creates types that cannot be duplicated, perfect for unique resources:

```swift
struct FileHandle: ~Copyable {
    private var fd: Int32

    init(path: String) throws {
        fd = open(path, O_RDONLY)
        guard fd >= 0 else { throw FileError.cannotOpen }
    }

    consuming func close() {
        close(fd)
        discard self  // Prevents deinit from running
    }

    deinit { close(fd) }  // Guaranteed cleanup
}

func useFile() {
    let file = try! FileHandle(path: "data.txt")
    processFile(file)  // Ownership transferred
    // file.read()     // ❌ Error: 'file' already consumed
}
```

### Migration strategy: incremental adoption

| Step | Action | Build Setting |
|------|--------|---------------|
| 1 | Enable upcoming features individually | `Swift Compiler > Upcoming Features` |
| 2 | Set strict concurrency to "Targeted" | `SWIFT_STRICT_CONCURRENCY=targeted` |
| 3 | Fix all warnings | — |
| 4 | Set strict concurrency to "Complete" | `SWIFT_STRICT_CONCURRENCY=complete` |
| 5 | Enable Swift 6 language mode | `SWIFT_VERSION=6` |

**Start with your UI layer** (often simpler with `@MainActor` inference), then progress to business logic. Swift 6 is opt-in per module—dependencies can use different Swift versions without compatibility issues.

---

## Concurrency patterns require understanding isolation boundaries

Swift 6.2 introduces "Approachable Concurrency" with **default main actor isolation** in new Xcode projects and `nonisolated(nonsending)` semantics for async functions. Understanding when to use actors, classes, and structs is critical.

### Actor selection follows four conditions

Use an actor only when all four conditions are met:
1. Non-Sendable mutable state exists
2. State needs reference from multiple places
3. Operations must be atomic
4. Operations cannot run on an existing actor (like MainActor)

```swift
// ✅ Actor: protects mutable shared state
actor BankAccount {
    private var balance: Double = 0

    func deposit(amount: Double) { balance += amount }

    func withdraw(amount: Double) -> Bool {
        guard balance >= amount else { return false }
        balance -= amount
        return true
    }
}

// ❌ Don't use actors for stateless services
actor NetworkClient {  // Wrong: no mutable state to protect
    func fetch(url: URL) async throws -> Data { ... }
}

// ✅ Use struct instead
struct NetworkClient: Sendable {
    func fetch(url: URL) async throws -> Data { ... }
}
```

### Sendable conformance strategies determine thread safety

| Type | Sendable Conformance |
|------|---------------------|
| Structs with Sendable properties | Implicit |
| Enums with Sendable associated values | Implicit |
| `final class` with immutable properties | Explicit `Sendable` |
| Classes with internal synchronization | `@unchecked Sendable` (use cautiously) |
| Actors | Automatic |

```swift
// Swift 6+ with iOS 18: Use Mutex for true Sendable
import Synchronization

final class ThreadSafeCache: Sendable {
    private let cache = Mutex<[String: Sendable]>([:])

    func get(_ key: String) -> Sendable? {
        cache.withLock { $0[key] }
    }
}
```

**Never use `@unchecked Sendable`** just to silence warnings—only when you've implemented thread safety via locks, queues, or atomics.

### MainActor isolation patterns for UI code

```swift
// Entire class isolated (recommended for ViewModels)
@MainActor
class ProfileViewModel {
    var profile: Profile?

    func loadData() async {
        profile = await fetchProfile()  // Guaranteed main thread
    }
}

// Explicit switching when needed
func processData() async {
    let result = await heavyComputation()  // Background
    await MainActor.run {
        self.label.text = result.description  // Main thread
    }
}
```

### Task cancellation requires cooperative checking

Swift uses cooperative cancellation—tasks must explicitly check and respond:

```swift
func processItems(_ items: [Item]) async throws {
    for item in items {
        try Task.checkCancellation()  // Throws if cancelled
        await process(item)
    }
}

// For cleanup on cancellation
func fetchWithCancellation() async throws -> Data {
    var task: URLSessionDataTask?
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            task = URLSession.shared.dataTask(with: url) { data, _, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? URLError(.unknown)) }
            }
            task?.resume()
        }
    } onCancel: {
        task?.cancel()  // Propagate cancellation
    }
}
```

---

## Memory management leverages ownership modifiers

Swift 5.9+ introduced explicit ownership control with `borrowing`, `consuming`, and `inout` modifiers that eliminate unnecessary ARC operations.

### Ownership modifiers optimize performance

| Modifier | Semantics | Use Case |
|----------|-----------|----------|
| `borrowing` | Read-only access, caller retains ownership | Inspecting values |
| `consuming` | Transfers ownership, caller cannot reuse | Initializers, final operations |
| `inout` | Temporary write access | Mutation operations |

```swift
struct Message: ~Copyable {
    var content: String

    borrowing func peek() -> String { content }  // Read-only
    consuming func send() { print(content) }     // Takes ownership
}

// Eliminates defensive copies for large types
func process(_ data: borrowing LargeData) { /* no copy */ }
```

### Retain cycles require weak/unowned references

```swift
// Delegate pattern: always weak
protocol DataManagerDelegate: AnyObject { }
class DataManager {
    weak var delegate: DataManagerDelegate?
}

// Closure captures: use capture lists
class ViewController {
    var completionHandler: (() -> Void)?

    func setup() {
        completionHandler = { [weak self] in
            guard let self else { return }
            self.updateUI()
        }
    }
}

// Parent-child relationships: unowned when guaranteed valid
class CreditCard {
    unowned let customer: Customer  // Card can't exist without customer
}
```

### Copy-on-write for custom large types

```swift
struct CopyOnWriteBox<T> {
    private final class Ref<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private var ref: Ref<T>

    var value: T {
        get { ref.value }
        set {
            if !isKnownUniquelyReferenced(&ref) {
                ref = Ref(newValue)  // Copy on mutation
            } else {
                ref.value = newValue  // Mutate in place
            }
        }
    }
}
```

---

## SwiftUI embraces @Observable for precise invalidation

The `@Observable` macro (iOS 17+) replaces `ObservableObject` with property-level observation, dramatically improving performance.

### @Observable eliminates unnecessary redraws

```swift
// Old pattern (ObservableObject)
final class CounterViewModel: ObservableObject {
    @Published var count = 0
    @Published var unrelatedValue = 0  // Changes trigger ALL view updates
}

// New pattern (@Observable)
@Observable
final class CounterViewModel {
    var count = 0
    var unrelatedValue = 0  // Changes only affect views reading this property
}

struct CounterView: View {
    @State var viewModel = CounterViewModel()  // Note: @State, not @StateObject

    var body: some View {
        Text("\(viewModel.count)")  // Only redraws when count changes
    }
}
```

### State management property wrapper selection

| Wrapper | Use When | Owns Data? |
|---------|----------|------------|
| `@State` | View-local values OR `@Observable` ownership | Yes |
| `@Binding` | Child needs read/write access to parent's state | No |
| `@Environment` | System values or `@Observable` injection | No |
| `@Bindable` | Creating bindings from `@Observable` properties | No |

### NavigationStack with type-safe routes

```swift
enum Route: Hashable {
    case detail(id: Int)
    case settings
    case profile(userId: String)
}

struct ContentView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .detail(let id): DetailView(id: id)
                    case .settings: SettingsView()
                    case .profile(let userId): ProfileView(userId: userId)
                    }
                }
        }
    }
}
```

### Performance optimization techniques

- **Use `let` instead of `var`** for constants—SwiftUI knows they won't change
- **Extract subviews** to isolate redraws to specific components
- **Use `LazyVStack`/`LazyHStack`** for large scrolling content
- **Debug redraws** with `let _ = Self._printChanges()` in view body
- **Avoid `AnyView`**—it erases type information and hurts diffing

---

## Architecture patterns adapt to modern Swift

MVVM with `@Observable` has become the de facto standard, though alternatives like TCA serve specific needs.

### MVVM with @Observable

```swift
@Observable
class ProfileViewModel {
    var profile: Profile?
    var isLoading = false

    func loadProfile() async {
        isLoading = true
        defer { isLoading = false }
        profile = try? await ProfileService.fetch()
    }
}

struct ProfileView: View {
    @State var viewModel = ProfileViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let profile = viewModel.profile {
                ProfileContent(profile: profile)
            }
        }
        .task { await viewModel.loadProfile() }
    }
}
```

### Dependency injection without frameworks

SwiftLee's pattern mirrors SwiftUI's `@Environment`:

```swift
protocol InjectionKey {
    associatedtype Value
    static var currentValue: Self.Value { get set }
}

@propertyWrapper
struct Injected<T> {
    private let keyPath: WritableKeyPath<InjectedValues, T>
    var wrappedValue: T {
        get { InjectedValues[keyPath] }
        set { InjectedValues[keyPath] = newValue }
    }
    init(_ keyPath: WritableKeyPath<InjectedValues, T>) {
        self.keyPath = keyPath
    }
}

// Usage
struct DataController {
    @Injected(\.networkProvider) var networkProvider: NetworkProviding
}

// Testing
InjectedValues[\.networkProvider] = MockedNetworkProvider()
```

### The Composable Architecture considerations

TCA (Point-Free) excels for apps requiring **unidirectional data flow**, **strict architectural consistency**, and **exhaustive testing**. However, it has a steep learning curve and adds dependency on two maintainers. Consider TCA when you need cross-platform business logic (used by Arc browser) or complex state sharing across screens.

---

## Testing shifts to Swift Testing framework

The new Swift Testing framework (`@Test`, `#expect`, `#require`) offers cleaner syntax and better async support than XCTest.

### Swift Testing vs XCTest comparison

| Feature | XCTest | Swift Testing |
|---------|--------|---------------|
| Test declaration | `func test*()` | `@Test func name()` |
| Assertions | `XCTAssert*` (40+ functions) | `#expect` and `#require` |
| Parallelization | Multiple simulator processes | In-process via Swift Concurrency |
| Parameterized tests | Manual loops | Built-in `arguments:` parameter |

```swift
import Testing

@Test("Check video metadata", .tags(.metadata))
func videoMetadata() {
    let video = Video(fileName: "By the Lake.mov")
    #expect(video.metadata.duration == .seconds(90))
}

// Parameterized testing
@Test("Continents mentioned", arguments: ["A Beach", "By the Lake"])
func mentionedContinents(videoName: String) async throws {
    let video = try #require(await library.video(named: videoName))
    #expect(video.mentionedContinents.count <= 3)
}
```

### Testing async code and actors

```swift
@Test func openURL() async {
    await confirmation { confirm in
        let viewModel = ViewModel(onOpenURL: { _ in confirm() })
        await viewModel.didTap(URL(string: "https://example.com")!)
    }
}
```

### Mocking without frameworks

Protocol-based mocking is the Swift-native approach:

```swift
protocol HTTPClientable {
    func get(_ path: String) -> Data
}

class MockHTTPClient: HTTPClientable {
    private(set) var lastPath: String?
    var dataToReturn: Data = Data()

    func get(_ path: String) -> Data {
        lastPath = path
        return dataToReturn
    }
}

@Test func fetchGame_buildsPath() {
    let client = MockHTTPClient()
    let service = BoardGameService(client: client)
    _ = service.fetchGame(id: 42)
    #expect(client.lastPath == "/games/42")
}
```

---

## API design follows official Swift guidelines

The Swift API Design Guidelines prioritize **clarity at the point of use** over brevity.

### Naming conventions enforce readability

```swift
// Include words to avoid ambiguity
employees.remove(at: x)        // ✅ Clear
employees.remove(x)            // ❌ Ambiguous

// Name by role, not type
var greeting = "Hello"         // ✅ Role-based
var string = "Hello"           // ❌ Type-based

// Mutating/non-mutating pairs
x.sort()                       // Mutating
z = x.sorted()                 // Non-mutating (-ed suffix)
y.formUnion(z)                 // Mutating (form- prefix)
x = y.union(z)                 // Non-mutating
```

### `some` vs `any` usage criteria

| Feature | `some` (Opaque) | `any` (Existential) |
|---------|-----------------|---------------------|
| Type preservation | Preserves concrete type | Type erasure |
| Performance | Static dispatch | Dynamic dispatch + boxing |
| Associated types | Full access | Limited |

```swift
// Use `some` for return types (better performance)
func makeView(for farm: Farm) -> some View { FarmView(farm) }

// Use `any` for heterogeneous collections
var animals: [any Animal] = [cow, chicken, pig]

// `some` as generic shorthand in parameters
func feed(_ animal: some Animal) { ... }  // Equivalent to <T: Animal>
```

### Access control starts restrictive

Start with `private`, open to `internal` as needed, use `public` only for external APIs, and reserve `open` for types designed for external subclassing.

---

## Security practices protect user data

### Keychain for sensitive storage

**Never use UserDefaults for secrets**—it stores unencrypted plists. Keychain provides hardware-backed encryption:

```swift
func saveToKeychain(key: String, data: Data) throws {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Bundle.main.bundleIdentifier!,
        kSecAttrAccount as String: key,
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    SecItemDelete(query as CFDictionary)
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError.saveFailed }
}
```

### CryptoKit for encryption

```swift
import CryptoKit

// Symmetric encryption (AES-GCM)
let key = SymmetricKey(size: .bits256)
let sealedBox = try AES.GCM.seal(data, using: key)
let decrypted = try AES.GCM.open(sealedBox, using: key)

// Hashing
let hash = SHA256.hash(data: data)
```

### Networking security essentials

- **Always use HTTPS**—keep App Transport Security enabled
- **Implement certificate pinning** for sensitive APIs
- **Validate all input**—use parameterized queries to prevent injection
- **Never hardcode secrets**—fetch from backend at runtime

---

## Swift Package Manager modernizes dependency management

### Package.swift structure

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MyLibrary",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "MyLibrary", targets: ["MyLibrary"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "MyLibrary",
            dependencies: [.product(name: "Algorithms", package: "swift-algorithms")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
```

### Versioning best practices

- **Use `from:` for external dependencies**—allows automatic patch/minor updates
- **Never use `.exact()` for published packages**—causes dependency conflicts
- **Commit Package.resolved** for reproducible builds
- **Remove branch/revision dependencies before publishing**

### Package traits enable optional features (Swift 6.1+)

```swift
traits: [
    .default(enabledTraits: ["Logging"]),
    .trait(name: "Metrics", enabledTraits: ["Logging"]),
],
targets: [
    .target(
        name: "MyLib",
        dependencies: [
            .product(name: "Logging", package: "swift-log",
                    condition: .when(traits: ["Logging"]))
        ]
    )
]
```

---

## Cross-platform development expands Swift's reach

### Vapor vs Hummingbird for server-side Swift

| Aspect | Vapor | Hummingbird |
|--------|-------|-------------|
| Philosophy | Batteries-included | Minimal, modular |
| Best for | Full-stack apps | APIs, microservices |
| Ecosystem | Larger (Fluent ORM, Leaf) | Growing, integrates with Fluent |

Vapor 5 (coming with Swift 6) rebuilds on structured concurrency with native Swift Service Lifecycle integration. Hummingbird 2.0 is already built entirely on modern async/await.

### Platform conditionals

```swift
#if os(iOS)
    import UIKit
    typealias XColor = UIColor
#elseif os(macOS)
    import AppKit
    typealias XColor = NSColor
#elseif os(Linux)
    // Linux-specific implementation
#endif

#if canImport(UIKit)
    import UIKit
#endif
```

### Embedded Swift for microcontrollers

Embedded Swift (WWDC 2024) compiles Swift to standalone firmware for ARM Cortex-M and RISC-V microcontrollers. Apple uses it in the Secure Enclave Processor. It's a full-featured Swift subset without runtime reflection or existentials.

---

## Interoperability bridges Swift with C, C++, and Objective-C

### C++ interop (Swift 5.9+)

Enable in Package.swift: `.swiftSettings: [.interoperabilityMode(.Cxx)]`

```swift
import CxxLibrary

let vec = std.vector<Int32>()
vec.push_back(42)

// Extend C++ types with Swift protocols
extension std.vector: RandomAccessCollection {
    public var startIndex: Int { 0 }
    public var endIndex: Int { size() }
}
```

Supported: `std::string`, `std::vector`, `std::unique_ptr`, constructors, operators. Not yet supported: r-value references, `std::function`, catching C++ exceptions.

### Unsafe pointers require scope management

```swift
// ✅ Always use withUnsafe* closures
var value = 42
withUnsafePointer(to: &value) { ptr in
    print(ptr.pointee)  // Valid only in this scope
}

// ✅ Balance allocation/deallocation
let ptr = UnsafeMutablePointer<Int>.allocate(capacity: 10)
ptr.initialize(repeating: 0, count: 10)
defer {
    ptr.deinitialize(count: 10)
    ptr.deallocate()
}

// ❌ Never return pointers from closure scope
func bad() -> UnsafePointer<Int> {
    var x = 42
    return withUnsafePointer(to: &x) { $0 }  // UNDEFINED BEHAVIOR
}
```

---

## Macros generate code at compile time

Swift Macros (Swift 5.9) enable type-safe compile-time code generation via SwiftSyntax.

### Freestanding vs attached macros

| Type | Syntax | Purpose |
|------|--------|---------|
| Freestanding expression | `#macroName()` | Returns a value |
| Freestanding declaration | `#macroName` | Creates declarations |
| Attached | `@MacroName` | Modifies/augments declarations |

### @Observable is the most important macro

```swift
@Observable
class ViewModel {
    var count = 0           // Automatically tracked
    @ObservationIgnored
    var transient = ""      // Excluded from observation
}
```

### When to use macros vs alternatives

Consider macros only when: eliminating **significant** boilerplate (10+ repetitions), needing **compile-time validation** with custom errors, or generating **type-specific code** that can't be generalized with generics or protocol extensions.

**Prefer alternatives first**: functions, generics, protocol extensions, property wrappers, result builders, or derived conformances (`Codable`, `Equatable`).

---

## Quick reference: key decisions

### Type selection matrix

| Criteria | Struct | Class | Actor |
|----------|--------|-------|-------|
| Thread safety | Copy semantics | Manual sync | Built-in isolation |
| Identity needed | No | Yes | Yes |
| SwiftUI data | Simple values | `@Observable` | Not recommended |
| Shared mutable state | No | Possible | Preferred |

### Property wrapper selection (SwiftUI, iOS 17+)

| Scenario | Wrapper |
|----------|---------|
| Own `@Observable` instance | `@State` |
| Bind to parent's state | `@Binding` |
| Create bindings from `@Observable` | `@Bindable` |
| Access environment values | `@Environment` |

### Concurrency decision tree

```
Need shared mutable state?
├── No → Use struct (automatically Sendable if properties are)
└── Yes → Can isolate to MainActor?
    ├── Yes → Use @MainActor class (for ViewModels)
    └── No → Use actor (for background state management)
```
