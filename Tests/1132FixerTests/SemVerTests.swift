import Testing
@testable import _132Fixer

@Suite("SemVer & UpdateChecker")
struct SemVerTests {

    @Test func parseFull() {
        let v = SemVer.parse("1.2.3")
        #expect(v == SemVer(major: 1, minor: 2, patch: 3))
    }

    @Test func parseVersion() {
        let v = SemVer.parse("1.3.6")
        #expect(v != nil)
        #expect(v?.major == 1)
        #expect(v?.minor == 3)
        #expect(v?.patch == 6)
    }

    @Test func parseWithSuffix() {
        let v = SemVer.parse("2.0.1-beta")
        #expect(v == SemVer(major: 2, minor: 0, patch: 1))
    }

    @Test func parseInvalid() {
        #expect(SemVer.parse("") == nil)
        #expect(SemVer.parse("abc") == nil)
    }

    @Test func comparison() {
        #expect(SemVer(major: 1, minor: 0, patch: 0) < SemVer(major: 2, minor: 0, patch: 0))
        #expect(SemVer(major: 1, minor: 2, patch: 0) < SemVer(major: 1, minor: 3, patch: 0))
        #expect(SemVer(major: 1, minor: 2, patch: 3) < SemVer(major: 1, minor: 2, patch: 4))
        #expect(!(SemVer(major: 2, minor: 0, patch: 0) < SemVer(major: 1, minor: 9, patch: 9)))
    }

    @Test func updateAvailable() {
        #expect(UpdateChecker.isUpdateAvailable(currentVersion: "1.3.5", latestVersion: "1.3.6"))
        #expect(!UpdateChecker.isUpdateAvailable(currentVersion: "1.3.6", latestVersion: "1.3.6"))
        #expect(!UpdateChecker.isUpdateAvailable(currentVersion: "2.0.0", latestVersion: "1.3.6"))
    }

    @Test func normalizeVersion() {
        #expect(UpdateChecker.normalizeVersion("v1.3.6") == "1.3.6")
        #expect(UpdateChecker.normalizeVersion("V2.0.0") == "2.0.0")
        #expect(UpdateChecker.normalizeVersion("1.0.0") == "1.0.0")
    }
}
