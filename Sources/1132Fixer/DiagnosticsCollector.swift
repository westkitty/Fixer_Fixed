import Foundation

enum DiagnosticsCollector {
    private struct RedactionRule {
        let regex: NSRegularExpression
        let replacement: String
    }

    private static let genericRedactionRules: [RedactionRule] = [
        .init(
            regex: try! NSRegularExpression(pattern: #"\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b"#, options: [.caseInsensitive]),
            replacement: "[redacted email]"
        ),
        .init(
            regex: try! NSRegularExpression(pattern: #"\b100\.(?:6[4-9]|[7-9]\d|1\d\d)\.\d{1,3}\.\d{1,3}\b"#),
            replacement: "[redacted ip]"
        ),
        .init(
            regex: try! NSRegularExpression(pattern: #"\b[a-zA-Z0-9-]+\.ts\.net\b"#, options: [.caseInsensitive]),
            replacement: "[redacted host]"
        ),
        .init(
            regex: try! NSRegularExpression(pattern: #"\b[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}\b"#),
            replacement: "[redacted mac]"
        ),
        .init(
            regex: try! NSRegularExpression(pattern: #"\b(?:ghp|gho|ghu|ghs|github_pat)_[A-Za-z0-9_]{8,}\b"#, options: [.caseInsensitive]),
            replacement: "[redacted token]"
        ),
    ]

    static func makeSnapshot() -> [String] {
        let processInfo = ProcessInfo.processInfo
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser.path
        let zoomAppPath = "/Applications/zoom.us.app"
        let zoomBundle = Bundle(path: zoomAppPath)

        var lines = [
            "--- Environment Snapshot ---",
            "OS build: \(run("/usr/bin/sw_vers", ["-buildVersion"]) ?? "unknown")",
            "Host architecture: \(ShellCommands.machineArchitecture())",
            "Processor count: \(processInfo.processorCount)",
            "Physical memory: \(formatBytes(processInfo.physicalMemory))",
            "System uptime: \(formatDuration(processInfo.systemUptime))",
            "Locale: \(Locale.current.identifier)",
            "Time zone: \(TimeZone.current.identifier)",
            "Sandbox launch required: yes",
            "sandbox-exec available: \(yesNo(fileManager.isExecutableFile(atPath: "/usr/bin/sandbox-exec")))",
            "Zoom app installed: \(yesNo(fileManager.fileExists(atPath: zoomAppPath)))",
            "Zoom binary executable: \(yesNo(fileManager.isExecutableFile(atPath: ShellCommands.zoomBinaryPath)))",
            "Zoom version: \(zoomBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")",
            "Zoom build: \(zoomBundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")",
            "Zoom process running: \(yesNo(processIsRunning("zoom.us")))",
            "Zoom capture helper running: \(processIsRunning("caphost") || processIsRunning("CptHost") ? "yes" : "no")",
            "MAC spoofing enabled by OS policy: \(yesNo(!ShellCommands.isMacSpoofingDisabledForCurrentOS()))",
        ]

        lines.append(contentsOf: networkSnapshot())
        lines.append(contentsOf: zoomStateSnapshot(homeDirectory: homeDirectory))
        return redacted(lines)
    }

    static func redacted(_ text: String) -> String {
        var result = text
        for rule in genericRedactionRules {
            result = apply(rule, to: result)
        }

        for value in runtimeIdentifiers() {
            guard !value.isEmpty else { continue }
            result = result.replacingOccurrences(of: value, with: "[redacted value]", options: [.caseInsensitive])
        }

        if let homePrefix = runtimeHomeDirectoryPrefix(), !homePrefix.isEmpty {
            result = result.replacingOccurrences(of: homePrefix, with: "~", options: [.caseInsensitive])
        }

        return result
    }

    static func redacted(_ lines: [String]) -> [String] {
        lines.map(redacted)
    }

    private static func apply(_ rule: RedactionRule, to text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return rule.regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: rule.replacement
        )
    }

    private static func runtimeIdentifiers() -> [String] {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let homeComponent = URL(fileURLWithPath: homeDirectory).lastPathComponent
        let hostName = Host.current().localizedName ?? ""
        let hostShortName = ProcessInfo.processInfo.hostName.split(separator: ".").first.map(String.init) ?? ""

        return [homeComponent, hostName, hostShortName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .removeDuplicatesCaseInsensitive()
    }

    private static func runtimeHomeDirectoryPrefix() -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser.path
        return path.isEmpty ? nil : path
    }

    private static func networkSnapshot() -> [String] {
        guard let route = run("/sbin/route", ["-n", "get", "default"]) else {
            return ["Default route: unavailable"]
        }

        do {
            let device = try ShellCommands.parseDefaultRouteInterface(from: route)
            let ports = run("/usr/sbin/networksetup", ["-listallhardwareports"]) ?? ""
            let portName = ShellCommands.parseHardwarePorts(from: ports)[device] ?? "Unknown"
            let kind = (try? ShellCommands.classifySupportedInterface(hardwarePortName: portName))?.rawValue ?? "Unsupported"
            return [
                "Default route interface: \(device)",
                "Default route hardware port: \(portName)",
                "Default route interface type: \(kind)",
            ]
        } catch {
            return ["Default route: \(error.localizedDescription)"]
        }
    }

    private static func zoomStateSnapshot(homeDirectory: String) -> [String] {
        let paths = [
            ("Application Support", "\(homeDirectory)/Library/Application Support/zoom.us"),
            ("Cache", "\(homeDirectory)/Library/Caches/us.zoom.xos"),
            ("Preferences", "\(homeDirectory)/Library/Preferences/us.zoom.xos.plist"),
            ("Saved State", "\(homeDirectory)/Library/Saved Application State/us.zoom.xos.savedState"),
            ("Log", "\(homeDirectory)/Library/Logs/zoom.us.log"),
        ]

        return paths.map { label, path in
            "Zoom \(label) exists: \(yesNo(FileManager.default.fileExists(atPath: path)))"
        }
    }

    private static func processIsRunning(_ name: String) -> Bool {
        run("/usr/bin/pgrep", ["-x", name]) != nil
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3_600
        let minutes = (Int(seconds) % 3_600) / 60
        return "\(hours)h \(minutes)m"
    }
}

private extension Array where Element == String {
    func removeDuplicatesCaseInsensitive() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.lowercased()).inserted }
    }
}
