import AppKit
import Foundation

struct Rule: Decodable {
    let browser: String
    let domains: [String]?
    let url_prefixes: [String]?
}

struct Config: Decodable {
    let default_browser: String?
    let rules: [Rule]?
}

final class RouterDelegate: NSObject, NSApplicationDelegate {
    private static let defaultSafari = URL(fileURLWithPath: "/Applications/Safari.app")
    private static let starterConfig = """
    {
      "default_browser": "Safari",
      "rules": [
        {
          "browser": "Firefox",
          "domains": [
            "claude.ai",
            "claude.com",
            "anthropic.com"
          ]
        }
      ]
    }
    """

    private var handledURLs = false
    private var pendingOpens = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.handledURLs else { return }
            self.showSetupAssistant()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handledURLs = true
        let config = loadConfig()
        let fallbackApp = resolveApp(config?.default_browser, fallback: Self.defaultSafari)
        let rules = config?.rules ?? []

        var grouped: [URL: [URL]] = [:]
        var order: [URL] = []

        for url in urls {
            let target = targetApp(for: url, rules: rules, fallback: fallbackApp)
            if grouped[target] == nil {
                order.append(target)
            }
            grouped[target, default: []].append(url)
        }

        for appURL in order {
            if let batch = grouped[appURL] {
                open(batch, with: appURL)
            }
        }

        if pendingOpens == 0 {
            NSApp.terminate(nil)
        }
    }

    private func showSetupAssistant() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        let isDefault = isDefaultWebBrowser()
        let currentDefault = NSWorkspace.shared
            .urlForApplication(toOpen: URL(string: "https://example.com")!)?
            .deletingPathExtension()
            .lastPathComponent ?? "Unknown"
        let configURL = configFileURL()
        let configExists = FileManager.default.fileExists(atPath: configURL.path)
        let config = loadConfig()

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Browser Opening Router"

        var lines: [String] = []
        if isDefault {
            lines.append("Default browser: Active (Browser Opening Router)")
        } else {
            lines.append("Default browser: \(currentDefault) (not active yet)")
        }

        if let config {
            let fallbackName = config.default_browser ?? "Safari"
            let count = config.rules?.count ?? 0
            lines.append("Fallback browser: \(fallbackName)")
            lines.append("Routing rules: \(count)")
        } else if configExists {
            lines.append("Config: invalid JSON at \(configURL.path)")
        } else {
            lines.append("Config: not created yet (using Safari as fallback)")
        }
        lines.append("Config file: \(configURL.path)")

        alert.informativeText = lines.joined(separator: "\n")

        if !isDefault {
            alert.addButton(withTitle: "Set as Default Browser")
        }
        alert.addButton(withTitle: configExists ? "Open Config" : "Create & Open Config")
        alert.addButton(withTitle: "Close")

        let response = alert.runModal()
        if !isDefault {
            switch response {
            case .alertFirstButtonReturn:
                setAsDefaultBrowser()
                return
            case .alertSecondButtonReturn:
                openOrCreateConfig(at: configURL)
            default:
                break
            }
        } else if response == .alertFirstButtonReturn {
            openOrCreateConfig(at: configURL)
        }

        NSApp.terminate(nil)
    }

    private func isDefaultWebBrowser() -> Bool {
        guard let selfID = Bundle.main.bundleIdentifier,
              let handlerURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
              let handlerID = Bundle(url: handlerURL)?.bundleIdentifier else {
            return false
        }
        return handlerID == selfID
    }

    private func setAsDefaultBrowser() {
        let appURL = Bundle.main.bundleURL
        let group = DispatchGroup()
        for scheme in ["http", "https"] {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) { _ in
                group.leave()
            }
        }
        group.notify(queue: .main) {
            NSApp.terminate(nil)
        }
    }

    private func openOrCreateConfig(at url: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? (Self.starterConfig + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    private func open(_ urls: [URL], with appURL: URL) {
        guard !urls.isEmpty else { return }
        pendingOpens += 1
        NSWorkspace.shared.open(
            urls,
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, _ in
            DispatchQueue.main.async {
                self.pendingOpens -= 1
                if self.pendingOpens == 0 {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func configFileURL() -> URL {
        let envPath = ProcessInfo.processInfo.environment["BROWSER_OPENING_ROUTER_CONFIG"]
        if let envPath, !envPath.isEmpty {
            return URL(fileURLWithPath: (envPath as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/browser-opening-router/config.json")
    }

    private func loadConfig() -> Config? {
        guard let data = try? Data(contentsOf: configFileURL()) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    private func targetApp(for url: URL, rules: [Rule], fallback: URL) -> URL {
        for rule in rules where matches(url, rule: rule) {
            return resolveApp(rule.browser, fallback: fallback)
        }
        return fallback
    }

    private func matches(_ url: URL, rule: Rule) -> Bool {
        if let prefixes = rule.url_prefixes {
            let full = url.absoluteString
            if prefixes.contains(where: { !$0.isEmpty && full.hasPrefix($0) }) {
                return true
            }
        }
        if let domains = rule.domains, let rawHost = url.host?.lowercased() {
            let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
            if domains.contains(where: { domain in
                let normalized = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return !normalized.isEmpty && (host == normalized || host.hasSuffix("." + normalized))
            }) {
                return true
            }
        }
        return false
    }

    private func resolveApp(_ value: String?, fallback: URL) -> URL {
        let candidate: URL
        if let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if raw.hasPrefix("/") {
                candidate = URL(fileURLWithPath: raw)
            } else if raw.contains("."), !raw.hasSuffix(".app"),
                      let byID = NSWorkspace.shared.urlForApplication(withBundleIdentifier: raw) {
                candidate = byID
            } else {
                let name = raw.hasSuffix(".app") ? raw : "\(raw).app"
                let locations = [
                    URL(fileURLWithPath: "/Applications").appendingPathComponent(name),
                    URL(fileURLWithPath: "/System/Applications").appendingPathComponent(name),
                    FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Applications")
                        .appendingPathComponent(name),
                ]
                candidate = locations.first { FileManager.default.fileExists(atPath: $0.path) } ?? fallback
            }
        } else {
            candidate = fallback
        }

        if let selfID = Bundle.main.bundleIdentifier,
           Bundle(url: candidate)?.bundleIdentifier == selfID {
            return Self.defaultSafari
        }
        return candidate
    }
}

let app = NSApplication.shared
let delegate = RouterDelegate()
app.delegate = delegate
app.run()
