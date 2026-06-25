import Foundation
import Testing
@testable import _132Fixer

@Suite("DiagnosticsCollector")
struct DiagnosticsCollectorTests {
    @Test func redactsLocalAndSecretIdentifiers() {
        let homeComponent = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path).lastPathComponent
        let hostName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

        let input = """
        \(FileManager.default.homeDirectoryForCurrentUser.path)/Zoom_1132_Fixer_Fixed/build.log
        \(homeComponent) and \(hostName) with a@b.cd
        100.67.12.66 and host.ts.net
        ghp_abcdef0123456789token
        AA:BB:CC:DD:EE:FF
        """

        let redacted = DiagnosticsCollector.redacted(input)

        #expect(!redacted.contains(FileManager.default.homeDirectoryForCurrentUser.path))
        #expect(!redacted.contains(homeComponent))
        #expect(!redacted.contains(hostName))
        #expect(!redacted.contains("a@b.cd"))
        #expect(!redacted.contains("100.67.12.66"))
        #expect(!redacted.contains("host.ts.net"))
        #expect(!redacted.contains("AA:BB:CC:DD:EE:FF"))
        #expect(!redacted.contains("ghp_abcdef0123456789token"))
        #expect(redacted.contains("[redacted"))
    }
}
