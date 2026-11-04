import Combine

/// Stand-in for SwiftUI's `@State`, which is a macro in the macOS 27 SDK and needs a plugin
/// that ships only with Xcode. Use as `@StateObject private var x = LocalState(…)` and bind with `$x.value`.
final class LocalState<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
