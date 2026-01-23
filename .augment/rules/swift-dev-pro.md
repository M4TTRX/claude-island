---
type: "agent_requested"
description: "Modern Swift Best Practices for macOS"
---

# Swift 6+ Modern Development Guidelines

**Swift 6.2 and latest Apple platforms deliver complete data-race safety, ownership semantics, and performance-oriented memory features that fundamentally change how Swift code should be written.** This guide covers bleeding-edge patterns for greenfield development targeting macOS 26+, iOS 26+, watchOS 12+, tvOS 26+, and visionOS 3+—no legacy compatibility concerns.

The Swift 6 era introduces **compile-time data-race prevention** as the default, **typed throws** for exhaustive error handling, **non-copyable types** for resource management, and **Span/InlineArray** for systems programming. Combined with SwiftUI's `@Observable` macro and the Swift Testing framework, modern Swift development looks dramatically different from even two years ago.

---

## Swift 6 version roadmap and language features

Swift 6's release cadence has delivered transformative features across three point releases, each unlocking capabilities previously impossible in the language.

### Version timeline and key features

| Version | Release | Headline Features |
|---------|---------|-------------------|
| Swift 6.0 | September 2024 | Complete data-race safety, typed throws, `Int128`/`UInt128`, non-copyable generics |
| Swift 6.1 | March 2025 | `nonisolated` extensions, TaskGroup inference, package traits, trailing commas everywhere |
| Swift 6.2 | September 2025 | Approachable concurrency, `@concurrent`, `Span`, `InlineArray`, strict memory safety mode |

### Enabling Swift 6 language mode

All new projects should use Swift 6 language mode, which enables complete concurrency checking by default:

```swift
// Package.swift
// swift-tools-version: 6.0
.target(
    name: "MyTarget",
    swiftSettings: [
        .swiftLanguageMode(.v6),
        .enableUpcomingFeature("StrictConcurrency")
    ]
)
```

**Xcode Build Settings**: Set "Swift Language Version" to 6 and "Strict Concurrency Checking" to Complete.

### Typed throws transforms error handling

Swift 6.0 introduces typed throws (SE-0413), enabling exhaustive error handling without type erasure:

```swift
enum NetworkError: Error {
    case offline, timeout, invalidResponse(Int)
}

func fetchUser(id: String) throws(NetworkError) -> User {
    guard isConnected else { throw .offline }
    // Compiler enforces NetworkError is the only throwable type
}

func handleUser() {
    do throws(NetworkError) {
        let user = try fetchUser(id: "123")
    } catch {
        switch error {  // Exhaustive—no default needed
        case .offline: showOfflineUI()
        case .timeout: showRetry()
        case .invalidResponse(let code): log("Error: \(code)")
        }
    }
}
```

Use **typed throws for internal APIs** where exhaustive handling is valuable. Retain untyped `throws` for public library APIs where error types may evolve.

---

## Non-copyable types and ownership model

Swift 6 fully realizes its ownership model with `~Copyable` types and explicit ownership modifiers—essential for resource management without reference counting overhead.

### Ownership modifiers for function parameters

| Modifier | Behavior | Use Case |
|----------|----------|----------|
| `borrowing` | Temporary read access | Reading without consuming |
| `consuming` | Takes ownership, invalidates caller's copy | Finalizing resources |
| `inout` | Temporary mutable access | In-place mutation |

```swift
struct FileHandle: ~Copyable {
    private var descriptor: Int32

    init(path: String) throws {
        descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { throw FileError.cannotOpen }
    }

    deinit { close(descriptor) }

    borrowing func read() -> Data { /* read without consuming */ }
    consuming func close() { /* takes ownership, file closed */ }
}

func processFile() {
    var handle = try! FileHandle(path: "/tmp/data")
    let data = handle.read()    // borrowing—can still use handle
    handle.close()              // consuming—handle now invalid
    // handle.read()            // Compile error: handle consumed
}
```

### InlineArray for stack-allocated fixed-size arrays (Swift 6.2+)

`InlineArray` provides fixed-size, stack-allocated arrays with **20-30% performance improvement** in tight loops:

```swift
// Shorthand syntax (preferred)
var pixels: [256 of UInt8] = .init(repeating: 0)
var rgb: [3 of Float] = [1.0, 0.5, 0.0]

// Initialization from closure
var indices: [10 of Int] = .init { index in index * 2 }

struct Particle {
    var position: [3 of Float]  // x, y, z—no heap allocation
    var velocity: [3 of Float]
}
```

### Span for safe buffer access (Swift 6.2+)

`Span<T>` provides a **non-owning, lifetime-safe view** into contiguous memory—the Swift equivalent of C++'s `std::span`:

```swift
func sum(of buffer: Span<Int>) -> Int {
    var total = 0
    for i in 0..<buffer.count {
        total += buffer[i]  // Bounds-checked
    }
    return total
}

var array = [1, 2, 3, 4, 5]
sum(of: array.span)  // Zero-copy, lifetime enforced at compile time
```

Span cannot escape its source's lifetime—the compiler prevents dangling pointer bugs entirely.

---

## Concurrency and parallelism

Swift 6 delivers **complete data-race safety at compile time**. The concurrency model now guarantees that concurrent code is free of data races before it ever runs.

### Approachable concurrency in Swift 6.2

Swift 6.2 introduces a **single-threaded-by-default** mode that makes concurrency opt-in rather than requiring escape hatches:

```swift
// With -default-isolation MainActor enabled (Xcode 26 default)
struct ImageCache {
    static var cache: [URL: Image] = [:]  // Protected by MainActor automatically

    static func load(from url: URL) async throws -> Image {
        if let cached = cache[url] { return cached }
        let image = try await fetchAndDecode(url)  // Runs on MainActor
        cache[url] = image
        return image
    }

    @concurrent  // Explicitly opt into background execution
    static func fetchAndDecode(_ url: URL) async throws -> Image {
        let (data, _) = try await URLSession.shared.data(from: url)
        return Image(data: data)!
    }
}
```

The `@concurrent` attribute explicitly marks functions that should run on the global concurrent executor rather than inheriting the caller's isolation.

### Actor isolation patterns

Actors provide mutual exclusion without manual locking:

```swift
actor DataStore {
    private var items: [Item] = []

    func add(_ item: Item) {
        items.append(item)  // Synchronous within actor
    }

    func getItems() -> [Item] { items }

    nonisolated var description: String { "DataStore" }  // No isolation needed
}

// External access always requires await
let store = DataStore()
await store.add(newItem)
let items = await store.getItems()
```

### Sendable conformance without escape hatches

Swift 6 enforces `Sendable` strictly. Proper patterns:

```swift
// Value types are implicitly Sendable when all properties are Sendable
struct UserData: Sendable {
    let id: UUID
    let name: String
}

// Reference types require final + immutable state
final class Configuration: Sendable {
    let apiKey: String
    let baseURL: URL
}

// For mutable state, use actors instead of @unchecked Sendable
actor Repository {
    private var cache: [String: Data] = [:]
    func get(_ key: String) -> Data? { cache[key] }
    func set(_ key: String, value: Data) { cache[key] = value }
}
```

### Synchronization module: Mutex and Atomic

The `Synchronization` module (iOS 18+/macOS 15+) provides low-level primitives when actors add unwanted overhead:

```swift
import Synchronization

final class ThreadSafeCounter: Sendable {
    private let value = Atomic<Int>(0)

    func increment() -> Int {
        value.add(1, ordering: .relaxed)
    }

    func load() -> Int {
        value.load(ordering: .relaxed)
    }
}

final class ThreadSafeCache: Sendable {
    private let storage = Mutex<[String: Data]>([:])

    subscript(key: String) -> Data? {
        get { storage.withLock { $0[key] } }
        set { storage.withLock { $0[key] = newValue } }
    }
}
```

**Decision guide**: Use actors for async state management, `Mutex` when synchronous access is required, and `Atomic` for simple counters/flags with minimal contention.

---

## SwiftUI with @Observable (2025/26)

The `@Observable` macro is now the **only recommended approach** for observable state in SwiftUI. It replaces `ObservableObject`, `@Published`, `@StateObject`, and `@ObservedObject` entirely.

### State management hierarchy

| Property Wrapper | Purpose | When to Use |
|-----------------|---------|-------------|
| `@State` | View-owned source of truth | Local view state, including @Observable objects |
| `@Binding` | Two-way connection to parent's state | Child views that modify parent state |
| `@Environment` | App-wide shared state | Dependency injection, shared models |
| `@Bindable` | Create bindings from @Observable | When mutating @Environment objects |

### Modern observable pattern

```swift
import Observation
import SwiftUI

@Observable
final class UserViewModel {
    var users: [User] = []
    var isLoading = false
    var errorMessage: String?

    func loadUsers() async {
        isLoading = true
        defer { isLoading = false }
        do {
            users = try await UserService.fetchUsers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct UserListView: View {
    @State private var viewModel = UserViewModel()

    var body: some View {
        List(viewModel.users) { user in
            Text(user.name)
        }
        .overlay { if viewModel.isLoading { ProgressView() } }
        .task { await viewModel.loadUsers() }
    }
}
```

### @Bindable for environment mutations

When an `@Environment` object needs to be mutated (e.g., in a form), create a `@Bindable` inside the body:

```swift
struct BookEditor: View {
    @Environment(Book.self) private var book

    var body: some View {
        @Bindable var book = book  // Create bindable inside body
        TextField("Title", text: $book.title)
    }
}
```

### iOS 26/macOS 26 SwiftUI additions

- **Liquid Glass design system**: Automatic visual refresh with `.glassEffect()` modifier
- **Native WebView**: `WebView(page)` for embedded web content
- **Rich TextEditor**: `TextEditor(text: $attributedString)` supports `AttributedString`
- **Tab roles**: `Tab("Search", systemImage: "magnifyingglass", role: .search)`
- **3D Charts**: `Chart3D` with RealityKit integration

---

## Architecture patterns for Swift 6

### MVVM with @Observable

The simplest production-ready architecture for most SwiftUI apps:

```swift
@Observable
final class CounterViewModel {
    var count = 0

    func increment() { count += 1 }
    func decrement() { count -= 1 }
}

struct CounterView: View {
    @State private var viewModel = CounterViewModel()

    var body: some View {
        VStack {
            Text("\(viewModel.count)")
            HStack {
                Button("-") { viewModel.decrement() }
                Button("+") { viewModel.increment() }
            }
        }
    }
}
```

### The Composable Architecture (TCA) for complex apps

TCA 1.23+ fully embraces Swift 6 with `@Reducer` and `@ObservableState`:

```swift
import ComposableArchitecture

@Reducer
struct CounterFeature {
    @ObservableState
    struct State: Equatable {
        var count = 0
    }

    enum Action {
        case increment, decrement
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .increment: state.count += 1; return .none
            case .decrement: state.count -= 1; return .none
            }
        }
    }
}

struct CounterView: View {
    let store: StoreOf<CounterFeature>

    var body: some View {
        VStack {
            Text("\(store.count)")
            Button("-") { store.send(.decrement) }
            Button("+") { store.send(.increment) }
        }
    }
}
```

**Use MVVM** for small-to-medium apps with straightforward state. **Use TCA** for large apps requiring rigorous testing, complex state management, or team scalability.

---

## Swift Testing framework

Swift Testing (`@Test`, `@Suite`, `#expect`, `#require`) is the **primary testing framework** for all new Swift 6 code. It replaces XCTest for most use cases.

### Core testing patterns

```swift
import Testing

@Suite("User Management")
struct UserTests {
    @Test("Creating a user sets properties correctly")
    func userCreation() {
        let user = User(name: "Alice", age: 30)
        #expect(user.name == "Alice")
        #expect(user.age == 30)
    }

    @Test("Age validation rejects invalid values", arguments: [
        (age: 17, valid: false),
        (age: 18, valid: true),
        (age: 100, valid: true),
        (age: 101, valid: false)
    ])
    func ageValidation(age: Int, valid: Bool) {
        #expect(User.isValidAge(age) == valid)
    }
}
```

### #expect vs #require

| Macro | Behavior | Use Case |
|-------|----------|----------|
| `#expect` | Records failure, **continues** test | Multiple assertions per test |
| `#require` | Throws on failure, **stops** test | Preconditions, unwrapping optionals |

```swift
@Test func unwrappingWithRequire() throws {
    let user = try #require(userStore.find(id: "123"))  // Stops if nil
    #expect(user.isActive)  // Only runs if user found
    #expect(user.permissions.contains(.admin))
}
```

### Testing async code and actors

```swift
@Test func asyncDataLoading() async throws {
    let viewModel = UserViewModel()
    await viewModel.loadUsers()
    #expect(!viewModel.users.isEmpty)
}

@Test @MainActor func mainActorTest() async {
    let controller = ViewController()
    await controller.refresh()
    #expect(controller.data != nil)
}
```

### Actor-based mocks for strict concurrency

```swift
actor MockUserService: UserServiceProtocol {
    var fetchCallCount = 0
    var usersToReturn: [User] = []

    func fetchUsers() async throws -> [User] {
        fetchCallCount += 1
        return usersToReturn
    }
}

@Test func viewModelCallsService() async {
    let mock = MockUserService()
    await mock.setUsers([User(name: "Test")])

    let viewModel = UserViewModel(service: mock)
    await viewModel.loadUsers()

    let count = await mock.fetchCallCount
    #expect(count == 1)
}
```

---

## Swift Package Manager

### Package.swift for Swift 6

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyPackage",
    platforms: [.macOS(.v26), .iOS(.v26), .watchOS(.v12), .tvOS(.v26), .visionOS(.v3)],
    products: [
        .library(name: "MyLibrary", targets: ["MyLibrary"])
    ],
    traits: [
        .default(enabledTraits: ["FullFeatures"]),
        .trait(name: "FullFeatures", description: "All features enabled"),
        .trait(name: "Minimal", description: "Core only")
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax", from: "509.0.0")
    ],
    targets: [
        .target(
            name: "MyLibrary",
            dependencies: [
                .target(name: "OptionalModule", condition: .when(traits: ["FullFeatures"]))
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .define("FULL_FEATURES", .when(traits: ["FullFeatures"]))
            ]
        ),
        .macro(
            name: "MyMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        )
    ]
)
```

### Package traits (Swift 6.1+)

Package traits enable conditional compilation without target proliferation:

```bash
swift build --traits FullFeatures
swift build --disable-default-traits
```

### The `package` access level

Share code between targets within a package without making it public:

```swift
// In Utilities target
package struct InternalHelper {
    package func process() { }
}

// In Main target (same package)—accessible
import Utilities
let helper = InternalHelper()

// Outside the package—not accessible
```

---

## API design for Swift 6

### Prefer `some` over `any`

Use opaque types (`some`) by default; use existentials (`any`) only when heterogeneity is required:

```swift
// ✅ some—single concrete type, better performance
func makeShape() -> some Shape {
    Circle(radius: 10)
}

// ✅ any—heterogeneous collection required
var shapes: [any Shape] = [Circle(), Square(), Triangle()]

// ✅ some with primary associated types
func loadItems() -> some Collection<Item> {
    [Item(), Item()]
}
```

### Primary associated types in protocol design

```swift
// Primary associated types enable constrained opaque/existential usage
protocol DataStore<Element> {
    associatedtype Element: Identifiable & Sendable
    func fetch() async throws -> [Element]
}

// Usage with some/any
func loadUsers(from store: some DataStore<User>) async throws -> [User] {
    try await store.fetch()
}
```

### Parameter packs for variadic generics

```swift
// Eliminates overload explosion
func process<each T>(_ items: repeat each T) {
    // Handle arbitrary number of heterogeneous arguments
}

// Real-world: multiple parallel requests
func query<each Payload>(
    _ requests: repeat Request<each Payload>
) async throws -> (repeat each Payload) {
    // Execute all, return tuple of results
}

let (user, posts, settings) = try await query(
    Request<User>(),
    Request<[Post]>(),
    Request<Settings>()
)
```

---

## Swift macros

### Macro roles and when to use them

| Role | Syntax | Protocol | Purpose |
|------|--------|----------|---------|
| Freestanding Expression | `#macro()` | `ExpressionMacro` | Returns a value |
| Freestanding Declaration | `#macro` | `DeclarationMacro` | Creates declarations |
| Peer | `@Macro` | `PeerMacro` | Adds sibling declarations |
| Member | `@Macro` | `MemberMacro` | Adds members to types |
| Accessor | `@Macro` | `AccessorMacro` | Adds get/set/willSet/didSet |
| Extension | `@Macro` | `ExtensionMacro` | Adds protocol conformances |

### Built-in macros to use

- `@Observable` — SwiftUI observation (Observation framework)
- `@Model` — SwiftData persistence
- `@Test`, `@Suite`, `#expect`, `#require` — Swift Testing
- `@DebugDescription` — Custom LLDB summaries

### Recommended community macros

| Library | Purpose |
|---------|---------|
| **CasePaths** | `@CasePathable` for enum key paths |
| **MetaCodable** | Advanced Codable with custom keys, defaults |
| **Spyable** | Generate test spies from protocols |
| **MemberwiseInit** | Smart memberwise initializers |
| **Power Assert** | Rich assertion output |

---

## Security best practices

Swift 6's strict concurrency provides **thread safety by default**—the most significant security improvement in the language's history.

### Keychain with modern APIs

Use SwiftSecurity or similar wrappers for type-safe Keychain access:

```swift
import SwiftSecurity

let keychain = Keychain.default

// Store credentials
try keychain.store("api-key-value", query: .credential(for: "OpenAI"))

// Retrieve
let token: String? = try keychain.retrieve(.credential(for: "OpenAI"))

// Store CryptoKit keys
let privateKey = P256.KeyAgreement.PrivateKey()
try keychain.store(privateKey, query: .key(for: "UserKey"))

// Secure Enclave keys
let seKey = try SecureEnclave.P256.KeyAgreement.PrivateKey()
try keychain.store(seKey, query: .key(for: "SecureKey"))
```

### CryptoKit patterns

```swift
import CryptoKit

// Symmetric encryption with AES-GCM
let key = SymmetricKey(size: .bits256)
let sealed = try AES.GCM.seal(plaintext, using: key)
let decrypted = try AES.GCM.open(sealed, using: key)

// Key agreement with P256
let privateKey = P256.KeyAgreement.PrivateKey()
let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: otherPublicKey)
let derivedKey = sharedSecret.hkdfDerivedSymmetricKey(
    using: SHA256.self, salt: salt, sharedInfo: Data(), outputByteCount: 32
)

// Digital signatures
let signingKey = P256.Signing.PrivateKey()
let signature = try signingKey.signature(for: data)
let isValid = signingKey.publicKey.isValidSignature(signature, for: data)
```

### Type-safe input validation

```swift
struct ValidatedEmail {
    let value: String
    private init(_ email: String) { self.value = email }

    static func validate(_ input: String) -> ValidatedEmail? {
        let regex = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}/
        guard input.wholeMatch(of: regex) != nil else { return nil }
        return ValidatedEmail(input)
    }
}

// API requires validated types—invalid data cannot reach business logic
func createAccount(email: ValidatedEmail, password: ValidatedPassword) { }
```

---

## Cross-platform and server-side Swift

### Server frameworks for Swift 6

**Hummingbird 2.x** (shipping now) and **Vapor 5** (upcoming) both embrace full structured concurrency:

```swift
// Hummingbird 2
import Hummingbird

let router = Router()
router.get("hello") { _, _ in "Hello, Swift!" }

let app = Application(
    router: router,
    configuration: .init(address: .hostname("0.0.0.0", port: 8080))
)
try await app.runService()
```

### Platform conditional compilation

```swift
#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS)
import UIKit
#elseif os(Linux)
import FoundationNetworking  // Required for URLSession on Linux
#endif

#if canImport(Combine)
import Combine
#endif
```

### Embedded Swift for microcontrollers

Swift 6 includes an experimental embedded mode for ARM/RISC-V targets with **kilobyte-sized binaries**:

```bash
swiftc -target armv6m-none-none-eabi \
       -enable-experimental-feature Embedded \
       -wmo input.swift -c -o output.o
```

---

## Foundation and standard library updates

### Key additions by version

| Feature | Swift Version | Deployment |
|---------|---------------|------------|
| `Int128`/`UInt128` | 6.0+ | All |
| `Atomic`, `Mutex` | 6.0+ | iOS 18+/macOS 15+ |
| Extended `nonisolated` | 6.1+ | All |
| Package traits | 6.1+ | All |
| `InlineArray` | 6.2+ | iOS 26+/macOS 26+ |
| `Span` | 6.2+ | iOS 26+/macOS 26+ |
| `@concurrent` | 6.2+ | iOS 26+/macOS 26+ |
| Foundation Models | — | iOS 26+/macOS 26+ |

### Modern date formatting

```swift
let date = Date.now

// Component-based (locale-aware)
date.formatted(.dateTime.day().month(.wide).year())  // "January 23, 2026"
date.formatted(date: .long, time: .shortened)         // "January 23, 2026 at 10:30 AM"

// SwiftUI integration
Text(Date.now, format: .dateTime.month().day().year())
```

### Swift Regex

```swift
import RegexBuilder

let pattern = Regex {
    "Price: "
    Capture { One(.localizedCurrency(code: "USD")) }
}

if let match = text.firstMatch(of: pattern) {
    print("Found price: \(match.1)")
}
```

---

## Interoperability

### C++ interop (Swift 5.9+)

Enable in Package.swift:

```swift
.target(
    name: "MyTarget",
    dependencies: ["CxxModule"],
    swiftSettings: [.interoperabilityMode(.Cxx)]
)
```

C++ classes import as Swift value types by default. Use `SWIFT_SHARED_REFERENCE` for reference-counted types:

```cpp
#include <swift/bridging>

class ManagedResource {
    // ...
} SWIFT_SHARED_REFERENCE(retainResource, releaseResource);
```

### Minimizing @objc

Use `@objc` **only** when Objective-C runtime features are required:

- `#selector` for target-action patterns
- `@objc dynamic` for KVO
- Protocol optional methods

For modern code, prefer Swift closures and protocols without `@objc`.

---

## Quick reference: modern vs legacy patterns

| Category | Legacy (Avoid) | Modern (Use) |
|----------|----------------|--------------|
| Observable state | `ObservableObject` + `@Published` | `@Observable` macro |
| View state | `@StateObject` | `@State` |
| Passed objects | `@ObservedObject` | Plain property or `@Bindable` |
| Environment | `@EnvironmentObject` | `@Environment(Type.self)` |
| Navigation | `NavigationView` | `NavigationStack` |
| Testing | XCTest | Swift Testing |
| Previews | `PreviewProvider` | `#Preview` macro |
| Error handling | Untyped `throws` | Typed `throws(ErrorType)` |
| Concurrency | `DispatchQueue`, callbacks | `async`/`await`, actors |
| Synchronization | `NSLock`, `DispatchSemaphore` | `Mutex`, `Atomic` |

---

## Conclusion

Swift 6+ represents a maturation of the language where **safety is the default, not an opt-in**. Complete data-race prevention at compile time, typed error handling, and ownership semantics eliminate entire categories of bugs before code ever runs.

For greenfield development on macOS 26+/iOS 26+, adopt these patterns immediately: use `@Observable` for all observable state, Swift Testing for all tests, typed throws for internal error handling, and actors for shared mutable state. The `Span` and `InlineArray` types unlock systems-programming performance while maintaining Swift's safety guarantees.

The result is code that is simultaneously **safer, faster, and more expressive** than what was possible in Swift 5—a rare combination that makes now an excellent time to start new Swift projects with these modern idioms.
