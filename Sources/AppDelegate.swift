import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var checker = ConnectivityChecker()
    private var checkTimer: Timer?
    private var servers: [ServerEntry] = []
    private var serverStatuses: [ServerEntry: ServerStatus] = [:]
    private var isOnline = true
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var dirFileDescriptor: Int32 = -1

    private var configDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UptimeBar")
    }

    private var configFileURL: URL {
        configDirectory.appendingPathComponent("servers.txt")
    }

    private var checkInterval: TimeInterval {
        get {
            let minutes = UserDefaults.standard.integer(forKey: "checkIntervalMinutes")
            return TimeInterval(minutes > 0 ? minutes : 5) * 60
        }
        set {
            UserDefaults.standard.set(Int(newValue / 60), forKey: "checkIntervalMinutes")
        }
    }

    private var checkIntervalMinutes: Int {
        let m = UserDefaults.standard.integer(forKey: "checkIntervalMinutes")
        return m > 0 ? m : 5
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(color: .gray)

        ensureConfigFile()
        loadServers()
        buildMenu()
        startFileWatcher()
        startTimer()
        performCheck()
    }

    // MARK: - Icon

    private func createIcon(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            // Upward chevron/arrow
            let centerX = rect.midX
            let margin: CGFloat = 3
            let topY = rect.maxY - margin
            let midY = rect.midY
            let bottomY = rect.minY + margin

            // Arrow shaft
            path.move(to: NSPoint(x: centerX, y: bottomY))
            path.line(to: NSPoint(x: centerX, y: topY))

            // Arrow head
            path.move(to: NSPoint(x: centerX - 4, y: midY + 1))
            path.line(to: NSPoint(x: centerX, y: topY))
            path.line(to: NSPoint(x: centerX + 4, y: midY + 1))

            color.setStroke()
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func updateIcon(color: NSColor) {
        statusItem.button?.image = createIcon(color: color)
    }

    private func updateIconFromStatuses() {
        if !isOnline {
            updateIcon(color: .gray)
        } else if servers.isEmpty {
            updateIcon(color: .gray)
        } else if serverStatuses.values.contains(.offline) {
            updateIcon(color: .systemRed)
        } else if serverStatuses.values.allSatisfy({ $0 == .online }) {
            updateIcon(color: .systemGreen)
        } else {
            updateIcon(color: .gray)
        }
    }

    // MARK: - Config

    private func ensureConfigFile() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDirectory.path) {
            try? fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: configFileURL.path) {
            let defaultContent = "# Add servers to monitor, one per line\n# Format: hostname:port (port defaults to 22)\n# Example:\n# myserver.com:443\n# 192.168.1.1\n"
            try? defaultContent.write(to: configFileURL, atomically: true, encoding: .utf8)
        }
    }

    private func loadServers() {
        guard let content = try? String(contentsOf: configFileURL, encoding: .utf8) else { return }
        var parsed: [ServerEntry] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            let host = String(parts[0])
            let port: UInt16
            if parts.count > 1, let p = UInt16(parts[1]) {
                port = p
            } else {
                port = 22
            }
            parsed.append(ServerEntry(host: host, port: port))
        }
        servers = parsed
        // Clean up statuses for removed servers
        serverStatuses = serverStatuses.filter { servers.contains($0.key) }
    }

    // MARK: - File Watcher

    private func startFileWatcher() {
        let path = configDirectory.path
        dirFileDescriptor = open(path, O_EVTONLY)
        guard dirFileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFileDescriptor,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.loadServers()
            self?.buildMenu()
            self?.performCheck()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.dirFileDescriptor, fd >= 0 {
                close(fd)
                self?.dirFileDescriptor = -1
            }
        }
        source.resume()
        fileWatchSource = source
    }

    // MARK: - Timer

    private func startTimer() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(
            timeInterval: checkInterval,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func timerFired() {
        performCheck()
    }

    // MARK: - Check

    private func performCheck() {
        for server in servers {
            if serverStatuses[server] == nil {
                serverStatuses[server] = .checking
            }
        }
        buildMenu()

        checker.checkAll(servers: servers) { [weak self] online, results in
            guard let self else { return }
            self.isOnline = online
            self.serverStatuses = results
            self.updateIconFromStatuses()
            self.buildMenu()
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        if !isOnline && !servers.isEmpty {
            let offlineItem = NSMenuItem(title: "Computer is offline", action: nil, keyEquivalent: "")
            offlineItem.isEnabled = false
            menu.addItem(offlineItem)
            menu.addItem(.separator())
        }

        for server in servers {
            let status = serverStatuses[server] ?? .unknown
            let statusIcon: String
            switch status {
            case .online: statusIcon = "\u{1F7E2}"  // green circle
            case .offline: statusIcon = "\u{1F534}"  // red circle
            case .checking: statusIcon = "\u{1F7E1}"  // yellow circle
            case .unknown: statusIcon = "\u{26AA}"   // white circle
            }
            let item = NSMenuItem(
                title: "\(statusIcon)  \(server.displayName)",
                action: #selector(copyServerHost(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = server.host
            menu.addItem(item)
        }

        if !servers.isEmpty {
            menu.addItem(.separator())
        }

        let editItem = NSMenuItem(title: "Edit Configuration...", action: #selector(editConfig), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        let loginItem = NSMenuItem(title: "Open on Startup", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = UserDefaults.standard.bool(forKey: "loginItemEnabled") ? .on : .off
        menu.addItem(loginItem)

        let freqItem = NSMenuItem(title: "Check Frequency", action: nil, keyEquivalent: "")
        let freqSubmenu = NSMenu()
        for minutes in [1, 5, 15, 30] {
            let label = "\(minutes) min"
            let subItem = NSMenuItem(title: label, action: #selector(setFrequency(_:)), keyEquivalent: "")
            subItem.target = self
            subItem.tag = minutes
            if minutes == checkIntervalMinutes {
                subItem.state = .on
            }
            freqSubmenu.addItem(subItem)
        }
        freqItem.submenu = freqSubmenu
        menu.addItem(freqItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func copyServerHost(_ sender: NSMenuItem) {
        guard let host = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(host, forType: .string)
    }

    @objc private func editConfig() {
        NSWorkspace.shared.open(configFileURL)
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        let isCurrentlyEnabled = UserDefaults.standard.bool(forKey: "loginItemEnabled")
        let shouldEnable = !isCurrentlyEnabled
        do {
            if shouldEnable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(shouldEnable, forKey: "loginItemEnabled")
        } catch {
            // Still toggle the state — SMAppService may error on unsigned builds
            // but still work via System Settings
            UserDefaults.standard.set(shouldEnable, forKey: "loginItemEnabled")
        }
        buildMenu()
    }

    @objc private func setFrequency(_ sender: NSMenuItem) {
        let minutes = sender.tag
        checkInterval = TimeInterval(minutes) * 60
        startTimer()
        buildMenu()
    }

    @objc private func quit() {
        fileWatchSource?.cancel()
        NSApp.terminate(nil)
    }
}
