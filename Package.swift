// swift-tools-version:5.9
import Foundation
import PackageDescription


let testSwiftSettings: [SwiftSetting] = {
    let cltPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
    let env = ProcessInfo.processInfo.environment
    let developerDir = env["DEVELOPER_DIR"]
        ?? (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"))
        ?? "/Library/Developer/CommandLineTools"
    guard developerDir.hasPrefix("/Library/Developer/CommandLineTools"),
          FileManager.default.fileExists(atPath: cltPlugins + "/libTestingMacros.dylib")
    else { return [] }
    return [.unsafeFlags(["-plugin-path", cltPlugins])]
}()


let package = Package(
    name: "QuickText",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "QuickText", targets: ["QuickText"])],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", "1.15.0"..<"1.16.0"),
    ],
    targets: [
        .executableTarget(name: "QuickText", dependencies: ["KeyboardShortcuts"], path: "Sources/QuickText"),
        .testTarget(name: "QuickTextTests", dependencies: ["QuickText"], path: "Tests/QuickTextTests",
                    swiftSettings: testSwiftSettings),
    ]
)
