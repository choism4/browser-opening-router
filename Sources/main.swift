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

    private var handledURLs = false
    private var pendingOpens = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, !self.handledURLs else { return }
            NSApp.terminate(nil)
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

    private func loadConfig() -> Config? {
        let envPath = ProcessInfo.processInfo.environment["BROWSER_OPENING_ROUTER_CONFIG"]
        let path: URL
        if let envPath, !envPath.isEmpty {
            path = URL(fileURLWithPath: (envPath as NSString).expandingTildeInPath)
        } else {
            path = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/browser-opening-router/config.json")
        }
        guard let data = try? Data(contentsOf: path) else { return nil }
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
