import AppKit
import Foundation
import SwiftUI

struct Rule: Codable {
    var browser: String
    var domains: [String]?
    var url_prefixes: [String]?
}

struct Config: Codable {
    var default_browser: String?
    var rules: [Rule]?
}

struct BrowserInfo: Identifiable, Hashable {
    let name: String
    let path: String
    var id: String { path }
}

enum RouterCore {
    static let defaultSafari = URL(fileURLWithPath: "/Applications/Safari.app")

    static func configFileURL() -> URL {
        let envPath = ProcessInfo.processInfo.environment["BROWSER_OPENING_ROUTER_CONFIG"]
        if let envPath, !envPath.isEmpty {
            return URL(fileURLWithPath: (envPath as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/browser-opening-router/config.json")
    }

    static func loadConfig() -> Config {
        guard let data = try? Data(contentsOf: configFileURL()),
              let decoded = try? JSONDecoder().decode(Config.self, from: data) else {
            return Config(default_browser: "Safari", rules: [])
        }
        return decoded
    }

    static func saveConfig(_ config: Config) {
        let url = configFileURL()
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(config),
           let text = String(data: data, encoding: .utf8) {
            try? (text + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func installedBrowsers() -> [BrowserInfo] {
        let selfID = Bundle.main.bundleIdentifier
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
        var seenPaths = Set<String>()
        var seenNames = Set<String>()
        var list: [BrowserInfo] = []

        for url in urls {
            let path = url.standardizedFileURL.path
            guard !seenPaths.contains(path) else { continue }
            if let selfID, Bundle(url: url)?.bundleIdentifier == selfID { continue }
            let name = url.deletingPathExtension().lastPathComponent
            guard !seenNames.contains(name) else { continue }
            seenPaths.insert(path)
            seenNames.insert(name)
            list.append(BrowserInfo(name: name, path: path))
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func isDefaultWebBrowser() -> Bool {
        guard let selfID = Bundle.main.bundleIdentifier,
              let handlerURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
              let handlerID = Bundle(url: handlerURL)?.bundleIdentifier else {
            return false
        }
        return handlerID == selfID
    }

    static func currentDefaultBrowserName() -> String {
        NSWorkspace.shared
            .urlForApplication(toOpen: URL(string: "https://example.com")!)?
            .deletingPathExtension()
            .lastPathComponent ?? "Unknown"
    }

    static func targetApp(for url: URL, config: Config) -> URL {
        let fallback = resolveApp(config.default_browser, fallback: defaultSafari)
        for rule in config.rules ?? [] where matches(url, rule: rule) {
            return resolveApp(rule.browser, fallback: fallback)
        }
        return fallback
    }

    static func matches(_ url: URL, rule: Rule) -> Bool {
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

    static func resolveApp(_ value: String?, fallback: URL) -> URL {
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
            return defaultSafari
        }
        return candidate
    }
}

struct EditableRule: Identifiable {
    let id = UUID()
    var browser: String
    var patterns: String

    init(browser: String, patterns: String) {
        self.browser = browser
        self.patterns = patterns
    }

    init(from rule: Rule) {
        let combined = (rule.domains ?? []) + (rule.url_prefixes ?? [])
        self.browser = rule.browser
        self.patterns = combined.joined(separator: ", ")
    }

    func toRule() -> Rule? {
        let items = patterns
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !items.isEmpty else { return nil }
        let prefixes = items.filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
        let domains = items.filter { !($0.hasPrefix("http://") || $0.hasPrefix("https://")) }
        return Rule(
            browser: browser,
            domains: domains.isEmpty ? nil : domains,
            url_prefixes: prefixes.isEmpty ? nil : prefixes
        )
    }
}

final class SettingsStore: ObservableObject {
    @Published var isDefault: Bool = false
    @Published var currentDefaultName: String = ""
    @Published var browsers: [BrowserInfo] = []
    @Published var defaultBrowser: String = "Safari"
    @Published var rules: [EditableRule] = []
    @Published var testURL: String = "https://chatgpt.com"

    init() {
        reload()
    }

    func reload() {
        browsers = RouterCore.installedBrowsers()
        refreshDefaultStatus()
        let cfg = RouterCore.loadConfig()
        defaultBrowser = cfg.default_browser ?? "Safari"
        rules = (cfg.rules ?? []).map(EditableRule.init(from:))
    }

    func refreshDefaultStatus() {
        isDefault = RouterCore.isDefaultWebBrowser()
        currentDefaultName = RouterCore.currentDefaultBrowserName()
    }

    func currentConfig() -> Config {
        Config(
            default_browser: defaultBrowser,
            rules: rules.compactMap { $0.toRule() }
        )
    }

    func save() {
        RouterCore.saveConfig(currentConfig())
    }

    func addRule() {
        let suggested = browsers.first(where: { $0.name != defaultBrowser })?.name ?? defaultBrowser
        rules.append(EditableRule(browser: suggested, patterns: ""))
        save()
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    func setAsDefaultBrowser() {
        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpenURLsWithScheme: "http"
        ) { _ in
            DispatchQueue.main.async {
                self.refreshDefaultStatus()
            }
        }
    }

    func openDefaultBrowserSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func predictedBrowserName() -> String? {
        let raw = testURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let normalized = raw.contains("://") ? raw : "https://\(raw)"
        guard let url = URL(string: normalized), url.host != nil else { return nil }
        return RouterCore.targetApp(for: url, config: currentConfig())
            .deletingPathExtension()
            .lastPathComponent
    }

    func testOpen() {
        let raw = testURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let normalized = raw.contains("://") ? raw : "https://\(raw)"
        guard let url = URL(string: normalized) else { return }
        let target = RouterCore.targetApp(for: url, config: currentConfig())
        NSWorkspace.shared.open([url], withApplicationAt: target, configuration: NSWorkspace.OpenConfiguration())
    }

    func openConfigFile() {
        save()
        NSWorkspace.shared.open(RouterCore.configFileURL())
    }

    func browserNames(including current: String) -> [String] {
        var names = browsers.map(\.name)
        if !current.isEmpty, !names.contains(current) {
            names.insert(current, at: 0)
        }
        return names
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    private let statusTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: store.isDefault ? "checkmark.circle.fill" : "safari.fill")
                        .font(.title2)
                        .foregroundStyle(store.isDefault ? .green : .accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.isDefault
                             ? "Browser Opening Router is Active"
                             : "Step 1: Set as Your Default Web Browser")
                            .font(.headline)
                        Text(store.isDefault
                             ? "Links from other apps are routed automatically."
                             : "Currently \(store.currentDefaultName). Click below, then confirm in the macOS prompt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if store.isDefault {
                    HStack {
                        Text("Need to switch back later?")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open System Settings") {
                            store.openDefaultBrowserSettings()
                        }
                        .controlSize(.small)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button("Set as Default Browser") {
                            store.setAsDefaultBrowser()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Open System Settings") {
                            store.openDefaultBrowserSettings()
                        }

                        Spacer()
                    }
                    Text("Or in System Settings → Desktop & Dock → Default web browser → Browser Opening Router")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.6)))
            .onReceive(statusTimer) { _ in
                store.refreshDefaultStatus()
            }

            HStack {
                Text("Default Browser")
                    .font(.headline)
                Spacer()
                Picker("", selection: $store.defaultBrowser) {
                    ForEach(store.browserNames(including: store.defaultBrowser), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: store.defaultBrowser) { _ in store.save() }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Routing Rules")
                        .font(.headline)
                    Text("(comma-separated domains or URL prefixes)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.addRule()
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                }

                if store.rules.isEmpty {
                    Text("No rules yet. Click “Add Rule” to route specific sites to another browser.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach($store.rules) { $rule in
                                HStack(spacing: 8) {
                                    TextField("e.g. claude.ai, claude.com", text: $rule.patterns)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: rule.patterns) { _ in store.save() }

                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.secondary)

                                    Picker("", selection: $rule.browser) {
                                        ForEach(store.browserNames(including: rule.browser), id: \.self) { name in
                                            Text(name).tag(name)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 150)
                                    .onChange(of: rule.browser) { _ in store.save() }

                                    Button {
                                        store.removeRule(id: rule.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 80, maxHeight: 180)
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Test URL (e.g. https://chatgpt.com)", text: $store.testURL)
                    .textFieldStyle(.roundedBorder)
                if let predicted = store.predictedBrowserName() {
                    Text("→ \(predicted)")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button("Test Open") {
                    store.testOpen()
                }
            }

            HStack {
                Button("Open JSON") {
                    store.openConfigFile()
                }
                Spacer()
                Text("Auto-saved • 0 MB RAM when closed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    store.save()
                    NSApp.terminate(nil)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

final class RouterDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var handledURLs = false
    private var pendingOpens = 0
    private var window: NSWindow?
    private var store: SettingsStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.handledURLs else { return }
            self.showSettingsWindow()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        store?.refreshDefaultStatus()
    }

    func windowWillClose(_ notification: Notification) {
        store?.save()
        NSApp.terminate(nil)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handledURLs = true
        let config = RouterCore.loadConfig()

        var grouped: [URL: [URL]] = [:]
        var order: [URL] = []

        for url in urls {
            let target = RouterCore.targetApp(for: url, config: config)
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

    private func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        let settingsStore = SettingsStore()
        self.store = settingsStore

        let hosting = NSHostingController(rootView: SettingsView(store: settingsStore))
        let win = NSWindow(contentViewController: hosting)
        win.title = "Browser Opening Router"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
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
}

let app = NSApplication.shared
let delegate = RouterDelegate()
app.delegate = delegate
app.run()
