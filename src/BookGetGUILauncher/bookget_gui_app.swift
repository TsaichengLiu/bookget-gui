import SwiftUI
import AppKit

private enum BookGetHelpContent {
    static func loadMarkdown() -> String {
        if let url = Bundle.main.url(forResource: "BookGetGUIHelp", withExtension: "md"),
           let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        // Fallback if the help file is missing from the bundle.
        return """
        BookGet GUI 帮助文件缺失。

        请确认应用包内存在 Resources/BookGetGUIHelp.md。
        """
    }

    static var appVersionLine: String {
        let name = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "BookGet GUI"
        let ver = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
        return "\(name) v\(ver) (\(build))"
    }
}

private struct BookGetHelpView: View {
    @State private var markdown: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(BookGetHelpContent.appVersionLine)
                .font(.system(size: 16, weight: .semibold))
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let attr = try? AttributedString(markdown: markdown) {
                        Text(attr)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(markdown)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 720)
        .onAppear {
            if markdown.isEmpty {
                markdown = BookGetHelpContent.loadMarkdown()
            }
        }
    }
}

private final class BookGetHelpWindowController: NSObject, NSWindowDelegate {
    static let shared = BookGetHelpWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let root = BookGetHelpView()
            let hosting = NSHostingView(rootView: root)

            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 760),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            w.title = "帮助"
            w.center()
            w.contentView = hosting
            w.isReleasedWhenClosed = false
            w.delegate = self
            self.window = w
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Keep window instance for fast reopen.
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case obsidian = "obsidian"
    case ocean = "ocean"
    case graphite = "graphite"
    case dusk = "dusk"
    case vaporwave = "vaporwave"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "系统"
        case .obsidian: return "黑曜石"
        case .ocean: return "海蓝"
        case .graphite: return "石墨"
        case .dusk: return "黄昏"
        case .vaporwave: return "蒸汽波"
        }
    }
}

enum CardVisualStyle: String, CaseIterable, Identifiable {
    case outline = "outline"
    case frosted = "frosted"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outline: return "毛玻璃"
        case .frosted: return "金属"
        }
    }
}

struct SupportedSite: Identifiable {
    let id = UUID()
    let name: String
    let url: String
    let note: String

    private struct Entry: Decodable {
        let name: String
        let url: String
        let note: String?
    }

    private struct Registry: Decodable {
        let sites: [Entry]
    }

    /// Loaded from Contents/Resources/sites.json, shared with the wrapper and login helper.
    static func loadBundled() -> [SupportedSite] {
        guard let url = Bundle.main.url(forResource: "sites", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let registry = try? JSONDecoder().decode(Registry.self, from: data) else {
            return []
        }
        return registry.sites.map {
            SupportedSite(name: $0.name, url: $0.url, note: $0.note ?? "源码路由：\($0.name)")
        }
    }
}

enum UserAgentPreset: String, CaseIterable, Identifiable {
    case coreDefault = "__default__"
    case chrome = "chrome"
    case safari = "safari"
    case firefox = "firefox"
    case edge = "edge"
    case custom = "custom"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coreDefault: return "默认（内核）"
        case .chrome: return "Chrome"
        case .safari: return "Safari"
        case .firefox: return "Firefox"
        case .edge: return "Edge"
        case .custom: return "自定义"
        }
    }

    var userAgent: String {
        switch self {
        case .coreDefault, .custom:
            return ""
        case .chrome:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36"
        case .safari:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        case .firefox:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:133.0) Gecko/20100101 Firefox/133.0"
        case .edge:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 Edg/132.0.0.0"
        }
    }
}

enum DownloadTaskState: String {
    case idle
    case running
    case retrying
    case paused
    case stopped
    case completed
    case failed
}

enum QueueTaskState: String {
    case waiting
    case running
    case retrying
    case paused
    case stopped
    case succeeded
    case failed

    var title: String {
        switch self {
        case .waiting: return "等待"
        case .running: return "下载中"
        case .retrying: return "重试中"
        case .paused: return "已暂停"
        case .stopped: return "已终止"
        case .succeeded: return "成功"
        case .failed: return "失败"
        }
    }
}

struct QueueTaskItem: Identifiable {
    let id = UUID()
    let url: String
    var state: QueueTaskState
    var note: String = ""
}

struct QueueRun: Identifiable {
    let id = UUID()
    let startedAtText: String
    var items: [QueueTaskItem]
}

struct LogEntry: Identifiable {
    let id: Int
    let text: String
}

extension View {
    func restoreArrowCursorOnExit() -> some View {
        self.onHover { inside in
            if !inside {
                NSCursor.arrow.set()
            }
        }
    }

    @ViewBuilder
    func scrollClipDisabledIfAvailable() -> some View {
        if #available(macOS 14.0, *) {
            self.scrollClipDisabled()
        } else {
            self
        }
    }
}

struct DownloadCheckpoint {
    var index: Int
    var total: Int
    var currentURL: String
    var progressText: String
    var detectedTotalText: String
    var updatedAt: Date
}

struct DownloadOptions {
    let outputDirectory: String
    let needLogin: Bool
    let showAdvanced: Bool
    let appMode: String
    let concurrency: String
    let retries: String
    let seq: String
    let vol: String
    let captureInterval: String
    let fileExt: String
    let userAgent: String
    let cookieFilePath: String
    let localStorageFilePath: String

    func validate() throws {
        if !showAdvanced { return }
        let appModeTrimmed = appMode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !appModeTrimmed.isEmpty {
            guard let mode = Int(appModeTrimmed), (0...2).contains(mode) else {
                throw NSError(domain: "DownloadOptions", code: 1, userInfo: [NSLocalizedDescriptionKey: "自动识别模式 a 仅支持 0/1/2。"])
            }
        }
        if !concurrency.isEmpty && !CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: concurrency)) {
            throw NSError(domain: "DownloadOptions", code: 2, userInfo: [NSLocalizedDescriptionKey: "并发连接数 n 必须是整数。"])
        }
        if !retries.isEmpty && !CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: retries)) {
            throw NSError(domain: "DownloadOptions", code: 3, userInfo: [NSLocalizedDescriptionKey: "重试次数 r 必须是整数。"])
        }
        let volTrimmed = vol.trimmingCharacters(in: .whitespacesAndNewlines)
        if !volTrimmed.isEmpty {
            let pattern = #"^\d+(?::\d+)?$"#
            if volTrimmed.range(of: pattern, options: .regularExpression) == nil {
                throw NSError(domain: "DownloadOptions", code: 4, userInfo: [NSLocalizedDescriptionKey: "多册范围 vol 格式应为 N 或 N:M。"])
            }
        }
        if !captureInterval.isEmpty && !CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: captureInterval)) {
            throw NSError(domain: "DownloadOptions", code: 5, userInfo: [NSLocalizedDescriptionKey: "抓取间隔 interval 必须是整数秒。"])
        }
        let cookieTrimmed = cookieFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cookieTrimmed.isEmpty && !FileManager.default.fileExists(atPath: cookieTrimmed) {
            throw NSError(domain: "DownloadOptions", code: 6, userInfo: [NSLocalizedDescriptionKey: "Cookie 文件不存在：\(cookieTrimmed)"])
        }
        let storageTrimmed = localStorageFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !storageTrimmed.isEmpty && !FileManager.default.fileExists(atPath: storageTrimmed) {
            throw NSError(domain: "DownloadOptions", code: 7, userInfo: [NSLocalizedDescriptionKey: "localStorage 文件不存在：\(storageTrimmed)"])
        }
    }

    func baseArgs(withOutputDirectory dir: String? = nil) -> [String] {
        var args: [String] = ["-o", dir ?? outputDirectory]
        // The wrapper understands -login, but bookget-core doesn't. Always pass an explicit value so the
        // current task follows the UI toggle exactly.
        args += [needLogin ? "-login" : "-login=0"]
        if showAdvanced {
            let appModeTrimmed = appMode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !appModeTrimmed.isEmpty { args += ["-a", appModeTrimmed] }
            if !concurrency.isEmpty { args += ["-n", concurrency] }
            if !retries.isEmpty { args += ["-r", retries] }
            let seqTrimmed = seq.trimmingCharacters(in: .whitespacesAndNewlines)
            if !seqTrimmed.isEmpty { args += ["-seq", seqTrimmed] }
            let volTrimmed = vol.trimmingCharacters(in: .whitespacesAndNewlines)
            if !volTrimmed.isEmpty { args += ["-vol", volTrimmed] }
            if !captureInterval.isEmpty {
                // Use one interval setting for both wrapper logic (rbook/ndl) and core pacing.
                args += ["-interval", captureInterval, "-speed", captureInterval]
            }
            if fileExt != "_" {
                args += ["-ext", fileExt]
            }
            let uaTrimmed = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !uaTrimmed.isEmpty {
                args += ["-ua", uaTrimmed]
            }
            let cookieTrimmed = cookieFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cookieTrimmed.isEmpty {
                args += ["-c", cookieTrimmed]
            }
            let storageTrimmed = localStorageFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !storageTrimmed.isEmpty {
                args += ["-localStorage", storageTrimmed]
            }
        }
        return args
    }
}

final class DownloadEngine {
    var onState: ((DownloadTaskState, String) -> Void)?
    var onTaskStarted: ((Int, Int, String) -> Void)?
    var onTaskFinished: ((Int, Int, Int32) -> Void)?
    var onQueueUpdated: (([QueueTaskItem]) -> Void)?
    var onLogChunk: ((String) -> Void)?
    var onFinished: ((Int) -> Void)?

    private var process: Process?
    private var outputPipe: Pipe?
    private var currentBinDir: URL?
    private var executablePath: String = ""
    private var options: DownloadOptions?
    private var urls: [String] = []
    private var queueItems: [QueueTaskItem] = []
    private var currentIndex: Int = 0
    private var failCount: Int = 0
    private var isStopping = false
    private var isPauseRequested = false
    private var state: DownloadTaskState = .idle
    private var outputOverrideByIndex: [Int: String] = [:]
    private var conflictRetriedIndexes: Set<Int> = []
    private var appModeOverrideByIndex: [Int: String] = [:]
    private var appModeTriedByIndex: [Int: [String]] = [:]
    private var runLogBuffer: String = ""
    private let runLogLock = NSLock()

    private func markQueueItemsStopped(from startIndex: Int, note: String) {
        guard startIndex >= 0, startIndex < queueItems.count else { return }
        for idx in startIndex..<queueItems.count {
            switch queueItems[idx].state {
            case .succeeded, .failed, .stopped:
                continue
            default:
                queueItems[idx].state = .stopped
                queueItems[idx].note = note
            }
        }
    }

    func start(urls: [String], options: DownloadOptions, binDir: URL, executablePath: String) {
        self.urls = urls
        self.options = options
        self.currentBinDir = binDir
        self.executablePath = executablePath
        self.queueItems = urls.map { QueueTaskItem(url: $0, state: .waiting, note: "等待中") }
        self.currentIndex = 0
        self.failCount = 0
        self.isStopping = false
        self.isPauseRequested = false
        self.outputOverrideByIndex = [:]
        self.conflictRetriedIndexes = []
        self.appModeOverrideByIndex = [:]
        self.appModeTriedByIndex = [:]
        self.state = .running
        onState?(.running, urls.count > 1 ? "任务已启动，准备批量下载 \(urls.count) 个网址..." : "任务已启动，正在下载...")
        onQueueUpdated?(queueItems)
        runNext()
    }

    func pause() {
        guard state == .running || state == .retrying else { return }
        isPauseRequested = true
        process?.terminate()
    }

    func resume(options: DownloadOptions? = nil) {
        guard state == .paused else { return }
        if let options {
            self.options = options
        }
        isPauseRequested = false
        state = .running
        onState?(.running, "已继续下载。")
        runNext()
    }

    func stop() {
        guard state == .running || state == .retrying || state == .paused else { return }
        isStopping = true
        isPauseRequested = false
        markQueueItemsStopped(from: currentIndex, note: "已终止")
        onQueueUpdated?(queueItems)

        let isProcRunning = process?.isRunning ?? false
        if isProcRunning {
            process?.terminate()
            return
        }

        state = .stopped
        onState?(.stopped, "任务已终止。")
        onFinished?(failCount)
    }

    private func runNext() {
        guard let binDir = currentBinDir, let options else { return }

        if isStopping {
            state = .stopped
            onState?(.stopped, "任务已终止。")
            onFinished?(failCount)
            return
        }

        if currentIndex >= urls.count {
            state = failCount > 0 ? .failed : .completed
            onState?(state, failCount > 0 ? "任务已完成，\(failCount) 个网址失败。" : "全部任务下载完成。")
            onFinished?(failCount)
            return
        }

        let idx = currentIndex + 1
        let total = urls.count
        let url = urls[currentIndex]
        queueItems[currentIndex].state = state == .retrying ? .retrying : .running
        queueItems[currentIndex].note = state == .retrying ? "重试中" : "下载中"
        onQueueUpdated?(queueItems)
        onTaskStarted?(idx, total, url)
        resetRunLog()

        let taskArrayIndex = currentIndex
        prepareURLIfNeeded(for: url) { [weak self] preparedURL, preferredMode in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.currentIndex == taskArrayIndex else { return }
                guard !self.isStopping else { return }
                if let preferredMode {
                    self.appModeOverrideByIndex[taskArrayIndex] = preferredMode
                    self.appModeTriedByIndex[taskArrayIndex, default: []].append(preferredMode)
                    self.queueItems[taskArrayIndex].note = "已适配链接，a=\(preferredMode)"
                    self.onQueueUpdated?(self.queueItems)
                    self.onLogChunk?("[bookget gui] 检测到 Harvard 页面结构，已提取 manifest 并使用 a=\(preferredMode)。\n")
                }
                self.launchProcess(
                    originalURL: url,
                    finalURL: preparedURL,
                    index: idx,
                    total: total,
                    options: options,
                    binDir: binDir
                )
            }
        }
    }

    private func launchProcess(
        originalURL: String,
        finalURL: String,
        index: Int,
        total: Int,
        options: DownloadOptions,
        binDir: URL
    ) {
        let outputDir = outputOverrideByIndex[currentIndex] ?? options.outputDirectory
        var args = options.baseArgs(withOutputDirectory: outputDir)
        if let overrideMode = appModeOverrideByIndex[currentIndex] {
            args += ["-a", overrideMode]
        }
        args += [finalURL]

        let proc = Process()
        let pipe = Pipe()
        process = proc
        outputPipe = pipe
        proc.currentDirectoryURL = binDir
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = args
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            guard let str = String(data: data, encoding: .utf8), !str.isEmpty else { return }
            self.appendRunLog(str)
            self.onLogChunk?(str)
        }

        proc.terminationHandler = { [weak self] p in
            guard let self else { return }
            self.outputPipe?.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                self.handleTermination(status: p.terminationStatus, url: originalURL, index: index, total: total)
            }
        }

        do {
            try proc.run()
        } catch {
            failCount += 1
            queueItems[currentIndex].state = .failed
            queueItems[currentIndex].note = "启动失败"
            onQueueUpdated?(queueItems)
            onTaskFinished?(index, total, 1)
            currentIndex += 1
            runNext()
        }
    }

    private func handleTermination(status: Int32, url: String, index: Int, total: Int) {
        if isStopping {
            state = .stopped
            markQueueItemsStopped(from: currentIndex, note: "已终止")
            onQueueUpdated?(queueItems)
            onState?(.stopped, "任务已终止。")
            onTaskFinished?(index, total, status)
            onFinished?(failCount)
            return
        }

        if status == 130 {
            // Wrapper reports 130 when the user cancels the verification/login window.
            state = .stopped
            markQueueItemsStopped(from: currentIndex, note: "已终止（取消验证）")
            onQueueUpdated?(queueItems)
            onState?(.stopped, "已取消验证，任务已终止。")
            onTaskFinished?(index, total, status)
            onFinished?(failCount)
            return
        }

        if isPauseRequested {
            state = .paused
            queueItems[currentIndex].state = .paused
            queueItems[currentIndex].note = "已暂停，可继续"
            onQueueUpdated?(queueItems)
            onState?(.paused, "已暂停。继续时将从当前网址重新开始。")
            onTaskFinished?(index, total, status)
            return
        }

        if shouldRetryForUnsupportedURL(), let nextMode = nextAppModeFallback(for: currentIndex) {
            appModeOverrideByIndex[currentIndex] = nextMode
            appModeTriedByIndex[currentIndex, default: []].append(nextMode)
            state = .retrying
            queueItems[currentIndex].state = .retrying
            queueItems[currentIndex].note = "URL 不兼容，切换模式 a=\(nextMode) 重试"
            onQueueUpdated?(queueItems)
            onState?(.retrying, "检测到 Unsupported URL，自动切换识别模式 a=\(nextMode) 重试。")
            runNext()
            return
        }
        if shouldRetryForUnsupportedURL() {
            failCount += 1
            queueItems[currentIndex].state = .failed
            queueItems[currentIndex].note = "不支持该网址"
            onQueueUpdated?(queueItems)
            onTaskFinished?(index, total, status == 0 ? 2 : status)
            currentIndex += 1
            state = .running
            runNext()
            return
        }

        if status == 0 {
            if shouldRetryForNameConflict(at: currentIndex) {
                let retryDir = makeRetryDirectory(for: url, index: index, baseDir: options?.outputDirectory ?? "")
                outputOverrideByIndex[currentIndex] = retryDir
                conflictRetriedIndexes.insert(currentIndex)
                state = .retrying
                queueItems[currentIndex].state = .retrying
                queueItems[currentIndex].note = "检测到重名，切换目录重试"
                onQueueUpdated?(queueItems)
                onState?(.retrying, "检测到同名冲突，已切换目录重试。")
                runNext()
                return
            }

            queueItems[currentIndex].state = .succeeded
            queueItems[currentIndex].note = "完成"
            onQueueUpdated?(queueItems)
            onTaskFinished?(index, total, status)
            currentIndex += 1
            state = .running
            runNext()
            return
        }

        failCount += 1
        queueItems[currentIndex].state = .failed
        queueItems[currentIndex].note = "失败（返回码 \(status)）"
        onQueueUpdated?(queueItems)
        onTaskFinished?(index, total, status)
        currentIndex += 1
        state = .running
        runNext()
    }

    private func resetRunLog() {
        runLogLock.lock()
        runLogBuffer = ""
        runLogLock.unlock()
    }

    private func appendRunLog(_ chunk: String) {
        runLogLock.lock()
        runLogBuffer.append(chunk)
        if runLogBuffer.count > 16_000 {
            runLogBuffer = String(runLogBuffer.suffix(16_000))
        }
        runLogLock.unlock()
    }

    private func runLogSnapshot() -> String {
        runLogLock.lock()
        let text = runLogBuffer
        runLogLock.unlock()
        return text
    }

    private func shouldRetryForNameConflict(at index: Int) -> Bool {
        if conflictRetriedIndexes.contains(index) { return false }
        let log = runLogSnapshot().lowercased()
        let keys = ["已存在", "already exists", "file exists", "同名", "重名"]
        if keys.contains(where: { log.contains($0) }) {
            return true
        }
        if log.contains("download complete"), !log.contains("saved"), !log.contains("下载成功"), !log.contains("/") {
            return true
        }
        return false
    }

    private func shouldRetryForUnsupportedURL() -> Bool {
        // When advanced options are hidden, the wrapper already tries a=0/1/2 automatically.
        // Avoid launching a second pass from the GUI which would also re-open the login window.
        if options?.showAdvanced != true {
            return false
        }
        let log = runLogSnapshot().lowercased()
        return log.contains("unsupported url") || log.contains("处理url失败")
    }

    private func nextAppModeFallback(for index: Int) -> String? {
        let tried = Set(appModeTriedByIndex[index] ?? [])
        let current = effectiveAppMode(for: index)
        for mode in ["1", "2"] where mode != current && !tried.contains(mode) {
            return mode
        }
        return nil
    }

    private func effectiveAppMode(for index: Int) -> String {
        if let override = appModeOverrideByIndex[index], ["0", "1", "2"].contains(override) {
            return override
        }
        guard let options else { return "0" }
        if options.showAdvanced {
            let trimmed = options.appMode.trimmingCharacters(in: .whitespacesAndNewlines)
            if ["0", "1", "2"].contains(trimmed) {
                return trimmed
            }
        }
        return "0"
    }

    private func prepareURLIfNeeded(for rawURL: String, completion: @escaping (String, String?) -> Void) {
        guard let url = URL(string: rawURL), shouldUseCuriosityPreprocess(url) else {
            completion(rawURL, nil)
            return
        }

        resolveCuriosityManifest(from: url) { manifestURL in
            guard let manifestURL else {
                completion(rawURL, nil)
                return
            }
            completion(manifestURL, "2")
        }
    }

    private func shouldUseCuriosityPreprocess(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host != "curiosity.lib.harvard.edu" {
            return false
        }
        let path = url.path.lowercased()
        return path.contains("/catalog/") || path.contains("/lists/")
    }

    private func resolveCuriosityManifest(from catalogURL: URL, completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: catalogURL)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else {
                completion(nil)
                return
            }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let data, let html = String(data: data, encoding: .utf8) else {
                completion(nil)
                return
            }
            completion(self.extractCuriosityManifestURL(from: html, baseURL: catalogURL))
        }.resume()
    }

    private func extractCuriosityManifestURL(from html: String, baseURL: URL) -> String? {
        let directURLPattern = #"https?://[^"'\\s]*manifest[^"'\\s]*\.json[^"'\\s]*"#
        if let directRegex = try? NSRegularExpression(pattern: directURLPattern) {
            let ns = html as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = directRegex.firstMatch(in: html, options: [], range: range), match.numberOfRanges >= 1 {
                let raw = ns.substring(with: match.range(at: 0))
                if let normalized = normalizeExtractedURL(raw, baseURL: baseURL) {
                    return normalized
                }
            }
        }

        let capturePatterns = [
            #""manifestUrl"\s*:\s*"([^"]+)""#,
            #""manifest"\s*:\s*"([^"]+)""#,
            #"manifest=(https?://[^"'\s]+)"#,
            #""iiifServiceUrl"\s*:\s*"([^"]+)""#
        ]

        for pattern in capturePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = html as NSString
            let range = NSRange(location: 0, length: ns.length)
            let matches = regex.matches(in: html, options: [], range: range)
            for match in matches where match.numberOfRanges >= 2 {
                let raw = ns.substring(with: match.range(at: 1))
                if let normalized = normalizeExtractedURL(raw, baseURL: baseURL) {
                    if normalized.lowercased().contains("manifest") {
                        return normalized
                    }
                    if normalized.hasSuffix("/full/full/0/default.jpg") {
                        // iiif image endpoint -> infer manifest sibling when possible.
                        let candidate = normalized.replacingOccurrences(of: "/full/full/0/default.jpg", with: "/manifest")
                        if let u = URL(string: candidate)?.absoluteString {
                            return u
                        }
                    }
                }
            }
        }
        return nil
    }

    private func normalizeExtractedURL(_ raw: String, baseURL: URL) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        value = value.replacingOccurrences(of: "\\/", with: "/")
        value = value.replacingOccurrences(of: "\\u002F", with: "/")
        value = value.replacingOccurrences(of: "&amp;", with: "&")
        value = value.replacingOccurrences(of: "\\\"", with: "\"")
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        if let absolute = URL(string: value), absolute.scheme != nil {
            return absolute.absoluteString
        }
        if let relative = URL(string: value, relativeTo: baseURL)?.absoluteURL {
            return relative.absoluteString
        }
        return nil
    }

    private func makeRetryDirectory(for url: String, index: Int, baseDir: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: Date())
        let host = (URL(string: url)?.host ?? "task").replacingOccurrences(of: ":", with: "_")
        let name = "bookget_retry_\(index)_\(host)_\(stamp)"
        let dir = URL(fileURLWithPath: baseDir).appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }
}

final class DownloadViewModel: ObservableObject {
    @Published var urlText: String = ""
    @Published var saveDirectory: String
    @Published var needLogin: Bool = false
    @Published var showAdvanced: Bool = false
    @Published var appMode: String = "0"
    @Published var concurrency: String = "2"
    @Published var retries: String = "3"
    @Published var seq: String = ""
    @Published var vol: String = ""
    @Published var captureInterval: String = ""
    @Published var fileExt: String = "_"
    @Published var uaPreset: String = UserAgentPreset.coreDefault.rawValue
    @Published var userAgent: String = ""
    @Published var cookieFilePath: String = ""
    @Published var localStorageFilePath: String = ""

    @Published var isRunning: Bool = false
    @Published var taskState: DownloadTaskState = .idle
    @Published var status: String = "就绪"
    @Published var detail: String = "请填写网址并选择保存目录。"
    @Published var logEntries: [LogEntry] = []
    @Published var exportedLogPath: String = ""
    @Published var queueItems: [QueueTaskItem] = []
    @Published var queueRuns: [QueueRun] = []
    @Published var checkpointText: String = ""

    @Published var hasProgressEstimate: Bool = false
    @Published var progressValue: Double = 0.0
    @Published var progressText: String = "等待开始"
    @Published var detectedTotalText: String = ""

    @Published var recentUrls: [String] = []
    @Published var recentDirectories: [String] = []

    let supportedSites: [SupportedSite] = SupportedSite.loadBundled()

    private let engine = DownloadEngine()

    private var downloadedCount: Int = 0
    private var totalCount: Int = 0
    private let pendingLock = NSLock()
    private var pendingLogBuffer: String = ""
    private var flushScheduled = false
    private var currentCheckpoint: DownloadCheckpoint?
    private var logEntryCounter: Int = 0
    private let logWriteQueue = DispatchQueue(label: "bookget.log.write.queue")
    private var tempLogURL: URL?
    private var tempLogHandle: FileHandle?
    private var activeQueueRunID: UUID?

    private let defaults = UserDefaults.standard
    private let kDir = "bookget.last.dir"
    private let kNeedLogin = "bookget.last.needLogin"
    private let kShowAdvanced = "bookget.last.showAdvanced"
    private let kAppMode = "bookget.last.appmode"
    private let kConcurrency = "bookget.last.concurrency"
    private let kRetries = "bookget.last.retries"
	    private let kSeq = "bookget.last.seq"
	    private let kVol = "bookget.last.vol"
	    private let kCaptureInterval = "bookget.last.interval"
	    private let kLegacySpeed = "bookget.last.speed"
	    private let kExt = "bookget.last.ext"
	    private let kExtDefaultMigrated = "bookget.last.ext.default_migrated"
	    private let kUAPreset = "bookget.last.ua.preset"
	    private let kUserAgent = "bookget.last.ua"
	    private let kCookiePath = "bookget.last.cookie.path"
    private let kLocalStoragePath = "bookget.last.localstorage.path"
    private let kRecentUrls = "bookget.recent.urls"
    private let kRecentDirs = "bookget.recent.dirs"

    init() {
        let defaultPath = NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first ?? NSHomeDirectory()
        self.saveDirectory = defaultPath
        loadLastUsed(defaultPath: defaultPath)
        self.showAdvanced = false
        bindEngine()
    }

    deinit {
        engine.stop()
        closeAndCleanupTempLog(deleteFile: true)
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "请选择下载保存位置"
        if panel.runModal() == .OK, let url = panel.url {
            saveDirectory = url.path
            status = "已更新"
            detail = "保存目录已更新。"
            saveLastUsed()
        }
    }

    func applyRecentURL(_ url: String) {
        urlText = url
        status = "已更新"
        detail = "已填入最近使用的网址。"
    }

    func applyRecentDirectory(_ dir: String) {
        saveDirectory = dir
        status = "已更新"
        detail = "已填入最近使用的目录。"
        saveLastUsed()
    }

    func chooseCookieFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "请选择 cookie 文件"
        if panel.runModal() == .OK, let url = panel.url {
            cookieFilePath = url.path
            status = "已更新"
            detail = "Cookie 文件已设置。"
            saveLastUsed()
        }
    }

    func chooseLocalStorageFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "请选择 localStorage 文件"
        if panel.runModal() == .OK, let url = panel.url {
            localStorageFilePath = url.path
            status = "已更新"
            detail = "localStorage 文件已设置。"
            saveLastUsed()
        }
    }

    func clearCookieFile() {
        cookieFilePath = ""
        status = "已更新"
        detail = "已清空 Cookie 文件路径。"
        saveLastUsed()
    }

    func clearLocalStorageFile() {
        localStorageFilePath = ""
        status = "已更新"
        detail = "已清空 localStorage 文件路径。"
        saveLastUsed()
    }

    func applyAppMode(_ raw: String) {
        let next = ["0", "1", "2"].contains(raw) ? raw : "0"
        appMode = next
        saveLastUsed()
    }

    func applyNeedLogin(_ value: Bool) {
        needLogin = value
        saveLastUsed()
    }

    func applyUAPreset(_ raw: String) {
        guard let preset = UserAgentPreset(rawValue: raw) else { return }
        uaPreset = preset.rawValue
        if preset == .coreDefault {
            userAgent = ""
        } else if preset != .custom {
            userAgent = preset.userAgent
        }
        saveLastUsed()
    }

    func updateCustomUserAgent(_ value: String) {
        guard uaPreset == UserAgentPreset.custom.rawValue else { return }
        userAgent = value
        saveLastUsed()
    }

	func restoreLastUsed() {
		loadLastUsed(defaultPath: saveDirectory)
		status = "已恢复"
		detail = "已恢复上次使用设置。"
	}

		func restoreFactoryDefaults() {
		// Avoid resetting in the middle of a running task; stop first to keep state consistent.
		if isRunning || taskState == .paused {
			status = "无法恢复"
			detail = "请先终止或等待任务结束，再恢复初始设置。"
			return
		}

		let defaultPath = NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first ?? NSHomeDirectory()

		// Clear persisted "last used" keys so next launch is also clean.
				let keysToClear = [
					kDir, kNeedLogin, kShowAdvanced, kAppMode, kConcurrency, kRetries, kSeq, kVol, kCaptureInterval, kLegacySpeed, kExt,
				kExtDefaultMigrated, kUAPreset, kUserAgent, kCookiePath, kLocalStoragePath
			]
		for k in keysToClear { defaults.removeObject(forKey: k) }

		// Settings: restore to factory defaults.
		urlText = ""
		saveDirectory = defaultPath
		needLogin = false
		showAdvanced = false
		appMode = "0"
		concurrency = "2"
		retries = "3"
			seq = ""
			vol = ""
			captureInterval = ""
			fileExt = "_"
			uaPreset = UserAgentPreset.coreDefault.rawValue
			userAgent = ""
			cookieFilePath = ""
			localStorageFilePath = ""

		// Runtime/UI state: queue, progress, logs.
		isRunning = false
		taskState = .idle
		status = "就绪"
		detail = "请填写网址并选择保存目录。"

			queueItems = []
			queueRuns = []
			activeQueueRunID = nil
			currentCheckpoint = nil
			checkpointText = ""
		resetPendingLogBuffer()
		closeAndCleanupTempLog(deleteFile: true)
		logEntries = []
		logEntryCounter = 0
		exportedLogPath = ""

		downloadedCount = 0
		totalCount = 0
		hasProgressEstimate = false
		progressValue = 0
		progressText = "等待开始"
		detectedTotalText = ""
	}

	func clearRecentHistory() {
		defaults.removeObject(forKey: kRecentUrls)
		defaults.removeObject(forKey: kRecentDirs)
		recentUrls = []
        recentDirectories = []
        status = "已清空"
        detail = "最近记录已清空。"
    }

    func openSaveDirectory() {
        NSWorkspace.shared.open(URL(fileURLWithPath: saveDirectory))
    }

    func exportTaskLog() {
        flushPendingLogNow()
        logWriteQueue.sync { }

        guard let src = tempLogURL,
              FileManager.default.fileExists(atPath: src.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: src.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > 0 else {
            status = "无法导出"
            detail = "当前没有可导出的任务日志。"
            return
        }

        do {
            let stamp = Self.formatDate(Date(), format: "yyyyMMdd_HHmmss")
            let filename = "bookget_tasklog_\(stamp).txt"
            let outURL = URL(fileURLWithPath: saveDirectory).appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: outURL.path) {
                try FileManager.default.removeItem(at: outURL)
            }
            try FileManager.default.copyItem(at: src, to: outURL)
            exportedLogPath = outURL.path
            status = "已导出"
            detail = "任务日志已导出到：\(filename)"
            NSWorkspace.shared.open(URL(fileURLWithPath: saveDirectory))
        } catch {
            status = "导出失败"
            detail = "导出任务日志失败：\(error.localizedDescription)"
        }
    }

    func stopDownload() {
        guard isRunning || taskState == .paused else { return }
        engine.stop()
        status = "已请求终止"
        detail = "正在终止下载进程..."
    }

    func pauseDownload() {
        guard isRunning else { return }
        engine.pause()
        status = "暂停中"
        detail = "正在保存队列状态并暂停..."
    }

    func resumeDownload() {
        guard taskState == .paused else { return }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: saveDirectory, isDirectory: &isDir), isDir.boolValue else {
            status = "输入错误"
            detail = "保存目录不存在。"
            return
        }

	        let options = DownloadOptions(
	            outputDirectory: saveDirectory,
	            needLogin: needLogin,
	            showAdvanced: showAdvanced,
	            appMode: appMode,
	            concurrency: concurrency,
	            retries: retries,
	            seq: seq,
	            vol: vol,
	            captureInterval: captureInterval,
	            fileExt: fileExt,
	            userAgent: userAgent,
	            cookieFilePath: cookieFilePath,
	            localStorageFilePath: localStorageFilePath
	        )
        do {
            try options.validate()
        } catch {
            status = "输入错误"
            detail = error.localizedDescription
            return
        }

        engine.resume(options: options)
    }

    func startDownload() {
        guard !isRunning, taskState != .paused else { return }

        let urls = parseInputURLs(urlText)
        guard !urls.isEmpty else {
            status = "输入错误"
            detail = "请至少输入一个网址（可一行一个）。"
            return
        }
        if let invalid = urls.first(where: { !($0.hasPrefix("http://") || $0.hasPrefix("https://")) }) {
            status = "输入错误"
            detail = "网址格式不正确：\(invalid)"
            return
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: saveDirectory, isDirectory: &isDir), isDir.boolValue else {
            status = "输入错误"
            detail = "保存目录不存在。"
            return
        }

	        let options = DownloadOptions(
	            outputDirectory: saveDirectory,
	            needLogin: needLogin,
	            showAdvanced: showAdvanced,
	            appMode: appMode,
	            concurrency: concurrency,
	            retries: retries,
	            seq: seq,
	            vol: vol,
	            captureInterval: captureInterval,
	            fileExt: fileExt,
	            userAgent: userAgent,
	            cookieFilePath: cookieFilePath,
	            localStorageFilePath: localStorageFilePath
	        )
        do {
            try options.validate()
        } catch {
            status = "输入错误"
            detail = error.localizedDescription
            return
        }

        guard let binDir = Bundle.main.resourceURL?.appendingPathComponent("bin"),
              FileManager.default.fileExists(atPath: binDir.path) else {
            status = "启动失败"
            detail = "应用内缺少 bin 目录。"
            return
        }

        let bookgetPath = binDir.appendingPathComponent("bookget").path
        guard FileManager.default.isExecutableFile(atPath: bookgetPath) else {
            status = "启动失败"
            detail = "应用内未找到可执行文件 bookget。"
            return
        }

        logEntries = []
        logEntryCounter = 0
        exportedLogPath = ""

        // Accumulative queue history: append a new run section for this start.
        let run = QueueRun(
            startedAtText: Self.formatDate(Date(), format: "yyyy-MM-dd HH:mm:ss"),
            items: urls.map { QueueTaskItem(url: $0, state: .waiting, note: "等待中") }
        )
        queueRuns.append(run)
        activeQueueRunID = run.id
        queueItems = run.items
        checkpointText = ""
        resetPendingLogBuffer()
        closeAndCleanupTempLog(deleteFile: true)
        guard setupTempLog() else {
            status = "启动失败"
            detail = "无法创建临时日志文件。"
            return
        }

        resetProgress()
        saveLastUsed()
        pushRecent(url: urls[0], dir: saveDirectory)
        isRunning = true
        taskState = .running
        status = "下载中 (0/\(urls.count))"
        detail = urls.count > 1 ? "任务已启动，准备批量下载 \(urls.count) 个网址..." : "任务已启动，正在下载..."
        progressText = "准备中..."

        engine.start(urls: urls, options: options, binDir: binDir, executablePath: bookgetPath)
    }

    private func bindEngine() {
        engine.onState = { [weak self] state, detail in
            guard let self else { return }
            DispatchQueue.main.async {
                self.taskState = state
                self.detail = detail
                self.isRunning = (state == .running || state == .retrying)
                switch state {
                case .idle: self.status = "就绪"
                case .running: self.status = "下载中"
                case .retrying: self.status = "重试中"
                case .paused: self.status = "已暂停"
                case .stopped: self.status = "已终止"
                case .completed: self.status = "已完成"
                case .failed: self.status = "部分失败"
                }
                if state == .stopped {
                    self.progressText = "已终止"
                }
                if state == .paused || state == .stopped || state == .completed || state == .failed {
                    self.sealTempLogFile()
                }
            }
        }

        engine.onQueueUpdated = { [weak self] items in
            guard let self else { return }
            DispatchQueue.main.async {
                self.queueItems = items
                if let activeID = self.activeQueueRunID,
                   let idx = self.queueRuns.firstIndex(where: { $0.id == activeID }) {
                    self.queueRuns[idx].items = items
                }
            }
        }

        engine.onTaskStarted = { [weak self] idx, total, url in
            guard let self else { return }
            DispatchQueue.main.async {
                self.resetProgress()
                self.progressText = "预扫描页数中..."
                self.detectedTotalText = total > 1 ? "当前任务 \(idx)/\(total)" : "当前任务 \(idx)/\(total)"
                self.discoverTotalPages(for: url)
                self.updateCheckpoint(index: idx, total: total, url: url)
                self.status = "下载中 (\(idx)/\(total))"
                self.detail = "正在处理第 \(idx) 个网址。"
            }
        }

        engine.onTaskFinished = { [weak self] idx, total, statusCode in
            guard let self else { return }
            DispatchQueue.main.async {
                self.flushPendingLogNow()
                if statusCode == 0 {
                    if self.totalCount > 0 {
                        self.downloadedCount = max(self.downloadedCount, self.totalCount)
                        self.publishProgress()
                    } else {
                        // Unknown total: avoid forcing a fake 100%.
                        self.hasProgressEstimate = false
                        self.progressValue = 0
                        self.progressText = "已完成（总数未知）"
                    }
                } else if self.taskState == .stopped {
                    self.progressText = "已终止"
                } else if self.taskState != .paused && !self.hasProgressEstimate {
                    self.progressText = "失败"
                }
                self.updateCheckpoint(index: idx, total: total, url: self.currentCheckpoint?.currentURL ?? "")
            }
        }

        engine.onLogChunk = { [weak self] chunk in
            self?.enqueueLogChunkForUI(chunk)
        }

        engine.onFinished = { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.flushPendingLogNow()
            }
        }
    }

    private func updateCheckpoint(index: Int, total: Int, url: String) {
        let checkpoint = DownloadCheckpoint(
            index: index,
            total: total,
            currentURL: url,
            progressText: progressText,
            detectedTotalText: detectedTotalText,
            updatedAt: Date()
        )
        currentCheckpoint = checkpoint
        checkpointText = "断点：\(index)/\(total) \(url)"
    }

    private func resetPendingLogBuffer() {
        pendingLock.lock()
        pendingLogBuffer = ""
        flushScheduled = false
        pendingLock.unlock()
    }

    private func enqueueLogChunkForUI(_ chunk: String) {
        pendingLock.lock()
        pendingLogBuffer.append(chunk)
        let shouldSchedule = !flushScheduled
        if shouldSchedule {
            flushScheduled = true
        }
        pendingLock.unlock()

        if shouldSchedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.flushPendingLogNow()
            }
        }
    }

    private func flushPendingLogNow() {
        var chunk = ""
        pendingLock.lock()
        chunk = pendingLogBuffer
        pendingLogBuffer = ""
        flushScheduled = false
        pendingLock.unlock()

        guard !chunk.isEmpty else { return }

        appendChunkToTempLog(chunk)

        DispatchQueue.main.async {
            let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for line in lines {
                self.logEntryCounter += 1
                self.logEntries.append(LogEntry(id: self.logEntryCounter, text: line))
            }
            if self.logEntries.count > 1600 {
                self.logEntries = Array(self.logEntries.suffix(1600))
            }
            self.consumeLogChunk(chunk)
        }
    }

    private func setupTempLog() -> Bool {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let filename = "bookget_task_\(Self.formatDate(Date(), format: "yyyyMMdd_HHmmss")).log"
        let fileURL = tmpDir.appendingPathComponent(filename)

        do {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            tempLogHandle = try FileHandle(forWritingTo: fileURL)
            tempLogURL = fileURL
            return true
        } catch {
            tempLogHandle = nil
            tempLogURL = nil
            return false
        }
    }

    private func appendChunkToTempLog(_ chunk: String) {
        guard !chunk.isEmpty, let data = chunk.data(using: .utf8) else { return }
        logWriteQueue.async {
            self.tempLogHandle?.write(data)
        }
    }

    private func closeAndCleanupTempLog(deleteFile: Bool) {
        let oldURL = tempLogURL
        logWriteQueue.sync {
            try? tempLogHandle?.close()
            tempLogHandle = nil
        }
        tempLogURL = nil
        if deleteFile, let oldURL {
            try? FileManager.default.removeItem(at: oldURL)
        }
    }

    private func sealTempLogFile() {
        logWriteQueue.sync {
            try? tempLogHandle?.close()
            tempLogHandle = nil
        }
    }

    private func parseInputURLs(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func discoverTotalPages(for sourceURL: String) {
        detectedTotalText = "正在探测总页数..."
        Task {
            let total = await Self.detectTotalPages(from: sourceURL)
            await MainActor.run {
                if let total, total > 0 {
                    self.totalCount = max(self.totalCount, total)
                    self.hasProgressEstimate = true
                    self.detectedTotalText = "已探测总页数：\(total)"
                    self.publishProgress()
                } else {
                    self.detectedTotalText = "未探测到总页数（回退为估算）"
                    if self.totalCount == 0 && self.progressText.isEmpty {
                        self.progressText = "估算中"
                    }
                }
            }
        }
    }

    private static func detectTotalPages(from source: String) async -> Int? {
        guard let sourceURL = URL(string: source) else { return nil }

        if sourceURL.absoluteString.lowercased().contains("manifest") || sourceURL.path.lowercased().hasSuffix(".json") {
            if let total = await fetchManifestTotal(from: sourceURL) {
                return total
            }
        }

        guard let html = await fetchText(from: sourceURL, maxBytes: 2_000_000) else { return nil }

        var candidates: [URL] = []
        let patterns = [
            #""manifest"\s*:\s*"([^"]+)""#,
            #""@id"\s*:\s*"([^"]*manifest[^"]*)""#,
            #"href=["']([^"']*manifest[^"']*\.json[^"']*)["']"#
        ]

        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p) else { continue }
            let ns = html as NSString
            let all = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
            for m in all where m.numberOfRanges >= 2 {
                let raw = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.isEmpty { continue }
                if let u = URL(string: raw, relativeTo: sourceURL)?.absoluteURL {
                    candidates.append(u)
                }
            }
        }

        if candidates.isEmpty,
           let fallback = URL(string: "manifest.json", relativeTo: sourceURL)?.absoluteURL {
            candidates.append(fallback)
        }

        var dedup: [String: URL] = [:]
        for c in candidates { dedup[c.absoluteString] = c }

        for (_, url) in dedup {
            if let total = await fetchManifestTotal(from: url) {
                return total
            }
        }

        return nil
    }

    private static func fetchManifestTotal(from manifestURL: URL) async -> Int? {
        guard let data = await fetchData(from: manifestURL, maxBytes: 4_000_000) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }

        let total = countCanvasNodes(in: obj)
        if total > 0 { return total }

        if let dict = obj as? [String: Any] {
            if let seqs = dict["sequences"] as? [[String: Any]],
               let canvases = seqs.first?["canvases"] as? [Any], !canvases.isEmpty {
                return canvases.count
            }
            if let items = dict["items"] as? [Any], !items.isEmpty {
                return items.count
            }
        }

        return nil
    }

    private static func countCanvasNodes(in obj: Any) -> Int {
        if let dict = obj as? [String: Any] {
            var c = 0
            if let t = dict["type"] as? String, t.caseInsensitiveCompare("Canvas") == .orderedSame {
                c += 1
            }
            for (_, v) in dict {
                c += countCanvasNodes(in: v)
            }
            return c
        }
        if let arr = obj as? [Any] {
            return arr.reduce(0) { $0 + countCanvasNodes(in: $1) }
        }
        return 0
    }

    private static func fetchText(from url: URL, maxBytes: Int) async -> String? {
        guard let data = await fetchData(from: url, maxBytes: maxBytes) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func fetchData(from url: URL, maxBytes: Int) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            if data.count > maxBytes {
                return data.prefix(maxBytes)
            }
            return data
        } catch {
            return nil
        }
    }

    private func loadLastUsed(defaultPath: String) {
        let lastDir = defaults.string(forKey: kDir) ?? defaultPath
        let lastNeedLogin = defaults.object(forKey: kNeedLogin) as? Bool ?? false
        let lastShowAdvanced = defaults.object(forKey: kShowAdvanced) as? Bool ?? false

        let lastAppMode = defaults.string(forKey: kAppMode) ?? "0"
        let lastConcurrency = defaults.string(forKey: kConcurrency) ?? "2"
        let lastRetries = defaults.string(forKey: kRetries) ?? "3"
        let lastSeq = defaults.string(forKey: kSeq) ?? ""
	        let lastVol = defaults.string(forKey: kVol) ?? ""
	        let lastCaptureInterval = defaults.string(forKey: kCaptureInterval) ?? defaults.string(forKey: kLegacySpeed) ?? ""
	        let lastExt = defaults.string(forKey: kExt) ?? "_"
	        let migrated = defaults.object(forKey: kExtDefaultMigrated) as? Bool ?? false
	        let lastUAPreset = defaults.string(forKey: kUAPreset)
	        let lastUserAgent = defaults.string(forKey: kUserAgent) ?? ""
	        let lastCookiePath = defaults.string(forKey: kCookiePath) ?? ""
	        let lastLocalStoragePath = defaults.string(forKey: kLocalStoragePath) ?? ""

        self.urlText = ""
        self.saveDirectory = lastDir
        self.needLogin = lastNeedLogin
        self.showAdvanced = lastShowAdvanced
        self.appMode = ["0", "1", "2"].contains(lastAppMode) ? lastAppMode : "0"
        self.concurrency = lastConcurrency
        self.retries = lastRetries
	        self.seq = lastSeq
	        self.vol = lastVol
	        self.captureInterval = lastCaptureInterval
	        if let raw = lastUAPreset, let preset = UserAgentPreset(rawValue: raw) {
	            self.uaPreset = preset.rawValue
	            if preset == .coreDefault {
	                self.userAgent = ""
	            } else if preset == .custom {
                self.userAgent = lastUserAgent
            } else {
                self.userAgent = preset.userAgent
            }
        } else if lastUserAgent.isEmpty {
            self.uaPreset = UserAgentPreset.coreDefault.rawValue
            self.userAgent = ""
        } else if let matched = UserAgentPreset.allCases.first(where: { $0 != .coreDefault && $0 != .custom && $0.userAgent == lastUserAgent }) {
            self.uaPreset = matched.rawValue
            self.userAgent = matched.userAgent
        } else {
            self.uaPreset = UserAgentPreset.custom.rawValue
            self.userAgent = lastUserAgent
        }
        self.cookieFilePath = lastCookiePath
        self.localStorageFilePath = lastLocalStoragePath
        if !migrated && lastExt == ".jpg" {
            // Migrate old default (.jpg) to new default (_), without breaking future explicit choices.
            self.fileExt = "_"
            defaults.set(true, forKey: kExtDefaultMigrated)
            defaults.set("_", forKey: kExt)
        } else {
            self.fileExt = ["_", ".jpg", ".png", ".tif", ".pdf"].contains(lastExt) ? lastExt : "_"
        }

        self.recentUrls = defaults.stringArray(forKey: kRecentUrls) ?? []
        self.recentDirectories = defaults.stringArray(forKey: kRecentDirs) ?? []
    }

	    private func saveLastUsed() {
	        defaults.set(saveDirectory, forKey: kDir)
	        defaults.set(needLogin, forKey: kNeedLogin)
	        defaults.set(showAdvanced, forKey: kShowAdvanced)
	        defaults.set(appMode, forKey: kAppMode)
	        defaults.set(concurrency, forKey: kConcurrency)
	        defaults.set(retries, forKey: kRetries)
	        defaults.set(seq, forKey: kSeq)
	        defaults.set(vol, forKey: kVol)
	        defaults.set(captureInterval, forKey: kCaptureInterval)
	        // Keep writing legacy key for backward compatibility with older builds.
	        defaults.set(captureInterval, forKey: kLegacySpeed)
	        defaults.set(fileExt, forKey: kExt)
	        defaults.set(uaPreset, forKey: kUAPreset)
	        defaults.set(userAgent, forKey: kUserAgent)
	        defaults.set(cookieFilePath, forKey: kCookiePath)
	        defaults.set(localStorageFilePath, forKey: kLocalStoragePath)
	    }

    private func pushRecent(url: String, dir: String) {
        var urls = defaults.stringArray(forKey: kRecentUrls) ?? []
        urls.removeAll { $0 == url }
        urls.insert(url, at: 0)
        if urls.count > 8 { urls = Array(urls.prefix(8)) }
        defaults.set(urls, forKey: kRecentUrls)
        recentUrls = urls

        var dirs = defaults.stringArray(forKey: kRecentDirs) ?? []
        dirs.removeAll { $0 == dir }
        dirs.insert(dir, at: 0)
        if dirs.count > 8 { dirs = Array(dirs.prefix(8)) }
        defaults.set(dirs, forKey: kRecentDirs)
        recentDirectories = dirs
    }

    private func resetProgress() {
        downloadedCount = 0
        totalCount = 0
        hasProgressEstimate = false
        progressValue = 0
        progressText = "估算中"
        detectedTotalText = ""
    }

    private func consumeLogChunk(_ chunk: String) {
        let lines = chunk.split(separator: "\n", omittingEmptySubsequences: true)
        for lineSub in lines {
            let line = String(lineSub)
            updateProgressFromLine(line)
        }
    }

    private func updateProgressFromLine(_ line: String) {
        if let pair = extractPair(from: line) {
            let current = pair.0
            let total = pair.1
            if total > 0 {
                totalCount = max(totalCount, total)
                downloadedCount = max(downloadedCount, min(current, totalCount))
                hasProgressEstimate = true
                publishProgress()
            }
            return
        }

        let lower = line.lowercased()
        if lower.contains("saved") || lower.contains("success") || line.contains("下载成功") || line.contains("已完成") {
            downloadedCount += 1
            if totalCount > 0 {
                downloadedCount = min(downloadedCount, totalCount)
                publishProgress()
            } else {
                hasProgressEstimate = false
                progressText = "已下载 \(downloadedCount) 项（总数未知）"
            }
        }
    }

    private func publishProgress() {
        guard totalCount > 0 else { return }
        hasProgressEstimate = true
        let value = max(0.0, min(Double(downloadedCount) / Double(totalCount), 1.0))
        progressValue = value
        let percent = Int(value * 100)
        progressText = "\(percent)%（\(downloadedCount)/\(totalCount)）"
    }

	private func extractPair(from line: String) -> (Int, Int)? {
		// Restrict parsing to explicit progress-like lines to avoid false positives
		// from generic "x/y" text fragments.
		let patterns = [
			"(?i)(?:^|\\s)get\\s*(\\d+)\\s*/\\s*(\\d+)(?:\\s|$)",
			"(?i)(?:^|\\s)saved\\s*(\\d+)\\s*/\\s*(\\d+)(?:\\s|$)",
			"第\\s*(\\d+)\\s*[\\/／]\\s*(\\d+)\\s*(?:页|張|张|項|项)"
		]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: line, options: [], range: range), match.numberOfRanges >= 3 else { continue }
            let a = ns.substring(with: match.range(at: 1))
            let b = ns.substring(with: match.range(at: 2))
            if let current = Int(a), let total = Int(b), total > 0, current >= 0 {
                return (current, total)
            }
        }
        return nil
    }

    private static func formatDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

struct Card<Content: View>: View {
    let title: String
    let subtitle: String?
    let style: CardVisualStyle
    let primaryText: Color
    let secondaryText: Color
    let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        style: CardVisualStyle = .frosted,
        primaryText: Color = .primary,
        secondaryText: Color = .secondary,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(secondaryText)
            }
            content
        }
        .padding(12)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    cardBorder,
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(style == .outline ? 0.03 : 0.08), radius: style == .outline ? 8 : 14, x: 0, y: 6)
    }

    private var cardBackground: some View {
        Group {
            switch style {
            case .frosted:
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.28), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            case .outline:
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.14))
            }
        }
    }

    private var cardBorder: LinearGradient {
        switch style {
        case .frosted:
            return LinearGradient(
                colors: [Color.white.opacity(0.45), Color.white.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .outline:
            return LinearGradient(
                colors: [Color.white.opacity(0.68), Color.white.opacity(0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct SupportedSitesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sites: [SupportedSite]
    @State private var keyword: String = ""

    private var filtered: [SupportedSite] {
        let k = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if k.isEmpty { return sites }
        return sites.filter { s in
            s.name.lowercased().contains(k) ||
            s.url.lowercased().contains(k) ||
            s.note.lowercased().contains(k)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("支持网站信息")
                .font(.system(size: 20, weight: .bold))
            Text("以下列表主要来自源码路由（router/interface.go），并包含 GUI/wrapper 专用补充站点，共 \(sites.count) 项。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("另有通用模式：`bookget`（通用批量）、`iiif.io`（IIIF 自动检测）、`dzicnlib`（DZI 专用）。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if sites.isEmpty {
                Text("未能读取应用包内的 Resources/sites.json，请重新构建应用。")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            TextField("搜索站点名或域名", text: $keyword)
                .textFieldStyle(.roundedBorder)
                .restoreArrowCursorOnExit()

            HStack {
                Spacer()
                Text("共 \(filtered.count) / \(sites.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            List(filtered) { site in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(site.name)
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        if let destination = URL(string: site.url) {
                            Link(site.url, destination: destination)
                                .font(.system(size: 12))
                        }
                    }
                    Text(site.note)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            HStack {
                Spacer()
                Button("确定") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 560)
    }
}

struct WindowSizeEnforcer: NSViewRepresentable {
    let minWidth: CGFloat
    let minHeight: CGFloat
    let idealWidth: CGFloat
    let idealHeight: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = WindowHookView()
        view.onWindowAttached = { window in
            self.applyConstraints(to: window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.applyConstraints(to: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                applyConstraints(to: window)
            }
        }
    }

    private func applyConstraints(to window: NSWindow) {
        let minSize = NSSize(width: minWidth, height: minHeight)
        window.contentMinSize = minSize
        window.minSize = minSize
        let contentSize = window.contentLayoutRect.size
        if contentSize.width < minWidth || contentSize.height < minHeight {
            window.setContentSize(NSSize(width: max(idealWidth, minWidth), height: max(idealHeight, minHeight)))
        }
    }
}

final class WindowHookView: NSView {
    var onWindowAttached: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindowAttached?(window)
        }
    }
}

struct LogConsoleView: NSViewRepresentable {
    let entries: [LogEntry]
    let textColor: NSColor

    final class Coordinator {
        var lastRenderedID: Int = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = textColor

        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.textColor = textColor
        let attrs = textAttributes()

        if entries.isEmpty {
            context.coordinator.lastRenderedID = 0
            textView.textStorage?.setAttributedString(
                NSAttributedString(string: "等待任务开始...", attributes: attrs)
            )
            scrollToBottom(textView)
            return
        }

        let newestID = entries.last?.id ?? 0
        if newestID < context.coordinator.lastRenderedID {
            context.coordinator.lastRenderedID = 0
            textView.string = ""
        }

        let delta = entries.filter { $0.id > context.coordinator.lastRenderedID }
        if !delta.isEmpty {
            let chunk = delta.map(\.text).joined(separator: "\n") + "\n"
            textView.textStorage?.append(NSAttributedString(string: chunk, attributes: attrs))
            context.coordinator.lastRenderedID = newestID

            if textView.string.count > 140_000 {
                let trimmed = String(textView.string.suffix(120_000))
                textView.textStorage?.setAttributedString(
                    NSAttributedString(string: trimmed, attributes: attrs)
                )
            }
            scrollToBottom(textView)
        }
    }

    private func textAttributes() -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: textColor,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ]
    }

    private func scrollToBottom(_ textView: NSTextView) {
        textView.scrollToEndOfDocument(nil)
    }
}

struct ContentView: View {
	    private enum InputFocusField: Hashable {
	        case urlText
	        case saveDirectory
	        case concurrency
	        case retries
	        case vol
	        case captureInterval
	        case seq
	        case userAgent
	        case cookieFilePath
	        case localStorageFilePath
	    }

	@StateObject private var vm = DownloadViewModel()
	@AppStorage("bookget.theme") private var themeRaw: String = AppTheme.obsidian.rawValue
	@AppStorage("bookget.cardStyle") private var cardStyleRaw: String = CardVisualStyle.outline.rawValue
	@State private var showSitesInfo = false
	@State private var showRestoreFactoryDefaultsConfirm: Bool = false
	@FocusState private var focusedField: InputFocusField?
	@Environment(\.colorScheme) private var colorScheme

    private var theme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .obsidian
    }

    private var cardStyle: CardVisualStyle {
        CardVisualStyle(rawValue: cardStyleRaw) ?? .outline
    }

    private var headerPrimary: Color {
        switch theme {
        case .system:
            return .primary
        case .dusk:
            return Color(red: 0.99, green: 0.95, blue: 0.9)
        case .vaporwave:
            return Color(red: 0.97, green: 0.93, blue: 0.98)
        case .ocean:
            return Color.white.opacity(0.98)
        case .graphite, .obsidian:
            return Color.white.opacity(0.95)
        }
    }

    private var accentTint: Color {
        switch theme {
        case .system: return .accentColor
        case .obsidian: return Color(red: 0.84, green: 0.8, blue: 0.72)
        case .ocean: return Color(red: 0.45, green: 0.84, blue: 0.9)
        case .graphite: return Color(red: 0.76, green: 0.8, blue: 0.9)
        case .dusk: return Color(red: 0.94, green: 0.72, blue: 0.57)
        case .vaporwave: return Color(red: 0.93, green: 0.53, blue: 0.79)
        }
    }

    private var cardPrimaryText: Color {
        switch cardStyle {
        case .frosted:
            switch theme {
            case .system:
                return colorScheme == .dark ? Color.white.opacity(0.95) : Color.black.opacity(0.9)
            case .dusk:
                return Color(red: 1.0, green: 0.95, blue: 0.9)
            case .vaporwave:
                return Color(red: 0.98, green: 0.94, blue: 0.99)
            case .ocean:
                return Color.white.opacity(0.97)
            case .graphite, .obsidian:
                return Color.white.opacity(0.95)
            }
        case .outline:
            switch theme {
            case .system:
                return colorScheme == .dark ? Color.white.opacity(0.94) : Color.black.opacity(0.88)
            case .dusk:
                return Color(red: 1.0, green: 0.95, blue: 0.89)
            case .vaporwave:
                return Color(red: 0.97, green: 0.92, blue: 0.99)
            case .ocean:
                return Color.white.opacity(0.98)
            case .graphite, .obsidian:
                return Color.white.opacity(0.96)
            }
        }
    }

    private var cardSecondaryText: Color {
        switch cardStyle {
        case .frosted:
            switch theme {
            case .system:
                return colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.6)
            case .dusk:
                return Color(red: 0.95, green: 0.85, blue: 0.78)
            case .vaporwave:
                return Color(red: 0.92, green: 0.82, blue: 0.91)
            case .ocean:
                return Color.white.opacity(0.82)
            case .graphite, .obsidian:
                return Color.white.opacity(0.75)
            }
        case .outline:
            switch theme {
            case .system:
                return colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.58)
            case .dusk:
                return Color(red: 0.92, green: 0.8, blue: 0.72)
            case .vaporwave:
                return Color(red: 0.88, green: 0.76, blue: 0.88)
            case .ocean:
                return Color.white.opacity(0.8)
            case .graphite, .obsidian:
                return Color.white.opacity(0.74)
            }
        }
    }

    private var logTextNSColor: NSColor {
        switch theme {
        case .system:
            return .labelColor
        case .dusk:
            return NSColor(calibratedRed: 0.98, green: 0.91, blue: 0.84, alpha: 1.0)
        case .vaporwave:
            return NSColor(calibratedRed: 0.97, green: 0.9, blue: 0.97, alpha: 1.0)
        case .ocean:
            return NSColor(calibratedRed: 0.9, green: 0.96, blue: 0.98, alpha: 1.0)
        case .graphite, .obsidian:
            return NSColor(calibratedWhite: 0.93, alpha: 1.0)
        }
    }

    private var atmosphereOverlay: some View {
        ZStack {
            Circle()
                .fill(accentTint.opacity(0.22))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .offset(x: -300, y: -240)
            Circle()
                .fill(
                    (theme == .obsidian || theme == .graphite ? Color.white : accentTint)
                        .opacity(theme == .obsidian || theme == .graphite ? 0.07 : 0.14)
                )
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 360, y: -280)
        }
        .allowsHitTesting(false)
    }

    private func queueStateColor(_ state: QueueTaskState) -> Color {
        switch state {
        case .waiting: return .gray
        case .running: return .blue
        case .retrying: return .orange
        case .paused: return .yellow
        case .stopped: return .secondary
        case .succeeded: return .green
        case .failed: return .red
        }
    }

    private var topBarBackground: some View {
        Group {
            switch cardStyle {
            case .outline:
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        Color.white.opacity(
                            theme == .obsidian || theme == .graphite ? 0.15 :
                            theme == .ocean ? 0.13 :
                            theme == .vaporwave ? 0.15 : 0.12
                        )
                    )
            case .frosted:
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.28), accentTint.opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
        }
    }

    private var topBarBorder: LinearGradient {
        switch cardStyle {
        case .outline:
            return LinearGradient(
                colors: [Color.white.opacity(0.66), Color.white.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .frosted:
            return LinearGradient(
                colors: [Color.white.opacity(0.44), accentTint.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var urlEditorBackground: some View {
        Group {
            switch cardStyle {
            case .outline:
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        Color.white.opacity(
                            theme == .obsidian || theme == .graphite ? 0.2 :
                            theme == .ocean ? 0.18 :
                            theme == .vaporwave ? 0.18 : 0.16
                        )
                    )
            case .frosted:
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.26), accentTint.opacity(0.11)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
        }
    }

    private var urlEditorBorder: LinearGradient {
        switch cardStyle {
        case .outline:
            return LinearGradient(
                colors: [Color.white.opacity(0.64), Color.white.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .frosted:
            return LinearGradient(
                colors: [Color.white.opacity(0.46), accentTint.opacity(0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var queueSummary: (total: Int, done: Int, stopped: Int, failed: Int) {
        let total = vm.queueItems.count
        let done = vm.queueItems.filter { $0.state == .succeeded }.count
        let stopped = vm.queueItems.filter { $0.state == .stopped }.count
        let failed = vm.queueItems.filter { $0.state == .failed }.count
        return (total, done, stopped, failed)
    }

    // Reduce the "dead space" on the far right of the window so cards align tighter.
    private let rightPanelNarrowInset: CGFloat = 0

    private func clearInputFocus() {
        focusedField = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func forceArrowCursor() {
        NSCursor.arrow.set()
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch theme {
        case .system:
            Color(nsColor: .windowBackgroundColor)
        case .obsidian:
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.06, blue: 0.08), Color(red: 0.02, green: 0.02, blue: 0.03), Color(red: 0.0, green: 0.0, blue: 0.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .ocean:
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.15, blue: 0.24), Color(red: 0.04, green: 0.36, blue: 0.49), Color(red: 0.08, green: 0.56, blue: 0.52)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .graphite:
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.1, blue: 0.12), Color(red: 0.14, green: 0.16, blue: 0.2), Color(red: 0.2, green: 0.21, blue: 0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dusk:
            LinearGradient(
                colors: [Color(red: 0.35, green: 0.2, blue: 0.17), Color(red: 0.31, green: 0.14, blue: 0.23), Color(red: 0.11, green: 0.1, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .vaporwave:
            LinearGradient(
                colors: [Color(red: 0.2, green: 0.1, blue: 0.28), Color(red: 0.56, green: 0.16, blue: 0.46), Color(red: 0.28, green: 0.24, blue: 0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        ZStack {
            backgroundView.ignoresSafeArea()
            atmosphereOverlay.ignoresSafeArea()

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(headerPrimary)
                        .frame(width: 38, height: 38)
                        .background(
                            LinearGradient(
                                colors: [accentTint.opacity(0.55), Color.white.opacity(0.22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text("BookGet GUI")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(headerPrimary)
                        Text("典籍下载工作台")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(headerPrimary.opacity(0.72))
                    }

                    Spacer()

                    Button("支持网站信息") {
                        clearInputFocus()
                        showSitesInfo = true
                    }

                    Picker("配色", selection: $themeRaw) {
                        ForEach(AppTheme.allCases) { t in
                            Text(t.title).tag(t.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 138)

                    Picker("卡片", selection: $cardStyleRaw) {
                        ForEach(CardVisualStyle.allCases) { s in
                            Text(s.title).tag(s.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 106)

                    Text(vm.isRunning ? "运行中" : (vm.taskState == .paused ? "已暂停" : "空闲"))
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background((vm.isRunning ? Color.orange : (vm.taskState == .paused ? Color.yellow : Color.green)).opacity(0.2), in: Capsule())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(topBarBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(topBarBorder, lineWidth: 1)
                )
                .padding(.trailing, rightPanelNarrowInset)

	                HStack(alignment: .top, spacing: 10) {
		                    ScrollView(.vertical) {
		                        VStack(spacing: 8) {
		                        Card("基础设置", style: cardStyle, primaryText: cardPrimaryText, secondaryText: cardSecondaryText) {
	                            VStack(spacing: 8) {
                                HStack(alignment: .top) {
                                    Text("网址")
                                        .frame(width: 52, alignment: .leading)
                                        .foregroundStyle(cardSecondaryText)
                                        .padding(.top, 6)
                                    ZStack(alignment: .topLeading) {
                                        if vm.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text("每行一个网址，例如：\nhttps://example-1.com\nhttps://example-2.com")
                                                .font(.system(size: 12))
                                                .foregroundStyle(cardSecondaryText)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 8)
                                        }
                                        TextEditor(text: $vm.urlText)
                                            .font(.system(size: 12))
                                            .focused($focusedField, equals: .urlText)
                                            .scrollContentBackground(.hidden)
                                            .background(Color.clear)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .restoreArrowCursorOnExit()
                                    }
                                    .frame(minHeight: 78, maxHeight: 96)
                                    .background(urlEditorBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .stroke(urlEditorBorder, lineWidth: 1)
                                    )
                                }
                                HStack {
                                    Text("保存到")
                                        .frame(width: 52, alignment: .leading)
                                        .foregroundStyle(cardSecondaryText)
                                    TextField("选择保存目录", text: $vm.saveDirectory)
                                        .focused($focusedField, equals: .saveDirectory)
                                        .textFieldStyle(.roundedBorder)
                                        .restoreArrowCursorOnExit()
                                    Button("选择") {
                                        clearInputFocus()
                                        vm.chooseDirectory()
                                    }
                                }
                                HStack {
                                    Text("验证")
                                        .frame(width: 52, alignment: .leading)
                                        .foregroundStyle(cardSecondaryText)
		                                    Toggle("开启弹窗浏览器（适用于需要登录或验证的网站）", isOn: Binding(
		                                        get: { vm.needLogin },
		                                        set: { vm.applyNeedLogin($0) }
		                                    ))
	                                }
                            }
                        }

	                        Card("最近使用", style: cardStyle, primaryText: cardPrimaryText, secondaryText: cardSecondaryText) {
	                            VStack(spacing: 6) {
	                                HStack(spacing: 8) {
	                                    Button("恢复上次设置") {
	                                        clearInputFocus()
	                                        vm.restoreLastUsed()
	                                    }
	                                    Button("恢复初始设置", role: .destructive) {
	                                        clearInputFocus()
	                                        showRestoreFactoryDefaultsConfirm = true
	                                    }
	                                    .disabled(vm.isRunning || vm.taskState == .paused)
	                                    Button("清空最近记录", role: .destructive) {
	                                        clearInputFocus()
	                                        vm.clearRecentHistory()
	                                    }
	                                    Spacer()
	                                }

                                HStack(spacing: 8) {
                                    Menu("最近网址") {
                                        if vm.recentUrls.isEmpty {
                                            Text("暂无记录")
                                        } else {
                                            ForEach(vm.recentUrls, id: \.self) { u in
                                                Button(u) { vm.applyRecentURL(u) }
                                            }
                                        }
                                    }
                                    Menu("最近目录") {
                                        if vm.recentDirectories.isEmpty {
                                            Text("暂无记录")
                                        } else {
                                            ForEach(vm.recentDirectories, id: \.self) { d in
                                                Button(d) { vm.applyRecentDirectory(d) }
                                            }
                                        }
                                    }
                                    Spacer()
                                }
	                            }
	                        }
	                        .alert("恢复初始设置？", isPresented: $showRestoreFactoryDefaultsConfirm) {
	                            Button("恢复初始", role: .destructive) {
	                                // Factory reset should also reset UI theme/card style to app defaults.
	                                themeRaw = AppTheme.obsidian.rawValue
	                                cardStyleRaw = CardVisualStyle.outline.rawValue
	                                vm.restoreFactoryDefaults()
	                            }
	                            Button("取消", role: .cancel) { }
	                        } message: {
	                            Text("这会将设置、任务队列、进度与日志恢复到最初始状态。")
	                        }
	
	                        Card("高级参数", style: cardStyle, primaryText: cardPrimaryText, secondaryText: cardSecondaryText) {
	                            VStack(spacing: 6) {
	                                Toggle("启用高级参数", isOn: $vm.showAdvanced)
	                                    .toggleStyle(.switch)
                                if vm.showAdvanced {
                                    HStack(spacing: 8) {
                                        Picker("a (识别模式)", selection: $vm.appMode) {
                                            Text("0（默认：内置站点规则）").tag("0")
                                            Text("1（通用批量抓取）").tag("1")
                                            Text("2（IIIF 自动识别）").tag("2")
                                        }
                                        .frame(width: 220)
                                        .onChange(of: vm.appMode) { _, newValue in
                                            vm.applyAppMode(newValue)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    HStack(spacing: 8) {
                                        HStack {
                                            Text("n (并发线程)")
                                                .frame(width: 80, alignment: .leading)
                                                .foregroundStyle(cardSecondaryText)
                                            TextField("2", text: $vm.concurrency)
                                                .focused($focusedField, equals: .concurrency)
                                                .textFieldStyle(.roundedBorder)
                                                .restoreArrowCursorOnExit()
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    HStack(spacing: 8) {
                                        HStack {
                                            Text("r (失败重试)")
                                                .frame(width: 80, alignment: .leading)
                                                .foregroundStyle(cardSecondaryText)
                                            TextField("3", text: $vm.retries)
                                                .focused($focusedField, equals: .retries)
                                                .textFieldStyle(.roundedBorder)
                                                .restoreArrowCursorOnExit()
                                        }
                                        Spacer(minLength: 0)
                                    }
	                                    HStack(spacing: 8) {
	                                        HStack {
	                                            Text("interval (抓取间隔秒)")
	                                                .frame(width: 90, alignment: .leading)
	                                                .foregroundStyle(cardSecondaryText)
	                                            TextField("", text: $vm.captureInterval)
	                                                .focused($focusedField, equals: .captureInterval)
	                                                .textFieldStyle(.roundedBorder)
	                                                .restoreArrowCursorOnExit()
	                                        }
	                                        HStack {
	                                            Text("seq (页码范围)")
	                                                .frame(width: 95, alignment: .leading)
	                                                .foregroundStyle(cardSecondaryText)
	                                            TextField("如 4:50", text: $vm.seq)
                                                .focused($focusedField, equals: .seq)
                                                .textFieldStyle(.roundedBorder)
                                                .restoreArrowCursorOnExit()
                                        }
                                    }
                                    HStack(spacing: 8) {
                                        HStack {
                                            Text("vol (分册范围)")
                                                .frame(width: 95, alignment: .leading)
                                                .foregroundStyle(cardSecondaryText)
                                            TextField("如 3:6", text: $vm.vol)
                                                .focused($focusedField, equals: .vol)
                                                .textFieldStyle(.roundedBorder)
                                                .restoreArrowCursorOnExit()
                                        }
                                        Picker("扩展名 (输出格式)", selection: $vm.fileExt) {
                                            Text("_（默认）").tag("_")
                                            Text(".jpg").tag(".jpg")
                                            Text(".png").tag(".png")
                                            Text(".tif").tag(".tif")
                                            Text(".pdf").tag(".pdf")
                                        }
                                        .frame(width: 190)
                                    }
                                    HStack(spacing: 8) {
                                        Text("ua (浏览器标识)")
                                            .frame(width: 115, alignment: .leading)
                                            .foregroundStyle(cardSecondaryText)
                                        Picker("", selection: $vm.uaPreset) {
                                            ForEach(UserAgentPreset.allCases) { preset in
                                                Text(preset.title).tag(preset.rawValue)
                                            }
                                        }
                                        .frame(width: 150)
                                        .onChange(of: vm.uaPreset) { _, newValue in
                                            vm.applyUAPreset(newValue)
                                        }
                                        if vm.uaPreset == UserAgentPreset.custom.rawValue {
                                            TextField("粘贴自定义 User-Agent", text: $vm.userAgent)
                                                .focused($focusedField, equals: .userAgent)
                                                .textFieldStyle(.roundedBorder)
                                                .restoreArrowCursorOnExit()
                                                .onChange(of: vm.userAgent) { _, newValue in
                                                    vm.updateCustomUserAgent(newValue)
                                                }
                                        } else {
                                            Text(vm.uaPreset == UserAgentPreset.coreDefault.rawValue ? "使用内核默认 UA" : "已选择预设 UA")
                                                .font(.system(size: 11))
                                                .foregroundStyle(cardSecondaryText)
                                                .lineLimit(1)
                                            Spacer(minLength: 0)
                                        }
                                    }

                                    HStack(spacing: 8) {
                                        Text("c (Cookie 文件)")
                                            .frame(width: 115, alignment: .leading)
                                            .foregroundStyle(cardSecondaryText)
                                        TextField("可选：选择 cookie.txt", text: $vm.cookieFilePath)
                                            .focused($focusedField, equals: .cookieFilePath)
                                            .textFieldStyle(.roundedBorder)
                                            .restoreArrowCursorOnExit()
                                        Button("选择") {
                                            clearInputFocus()
                                            vm.chooseCookieFile()
                                        }
                                        Button("清空") {
                                            clearInputFocus()
                                            vm.clearCookieFile()
                                        }
                                        .disabled(vm.cookieFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }

                                    HStack(spacing: 8) {
                                        Text("localStorage (登录态)")
                                            .frame(width: 115, alignment: .leading)
                                            .foregroundStyle(cardSecondaryText)
                                        TextField("可选：选择 localStorage.txt", text: $vm.localStorageFilePath)
                                            .focused($focusedField, equals: .localStorageFilePath)
                                            .textFieldStyle(.roundedBorder)
                                            .restoreArrowCursorOnExit()
                                        Button("选择") {
                                            clearInputFocus()
                                            vm.chooseLocalStorageFile()
                                        }
                                        Button("清空") {
                                            clearInputFocus()
                                            vm.clearLocalStorageFile()
                                        }
                                        .disabled(vm.localStorageFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }
                                }
                            }
                            .animation(.easeInOut(duration: 0.18), value: vm.showAdvanced)
                        }

		                        HStack(spacing: 8) {
		                            Button {
		                                clearInputFocus()
		                                vm.startDownload()
		                            } label: {
		                                Label("开始下载", systemImage: "arrow.down.circle.fill")
		                                    .frame(maxWidth: .infinity)
		                            }
		                            .frame(maxWidth: .infinity)
		                            .buttonStyle(.borderedProminent)
		                            .controlSize(.large)
		                            .disabled(vm.isRunning || vm.taskState == .paused)
		                            .onHover { inside in if inside { forceArrowCursor() } }

		                            Button {
		                                clearInputFocus()
		                                vm.pauseDownload()
		                            } label: {
		                                Label("暂停", systemImage: "pause.circle")
		                                    .frame(maxWidth: .infinity)
		                            }
		                            .frame(maxWidth: .infinity)
		                            .buttonStyle(.bordered)
		                            .controlSize(.large)
		                            .disabled(!vm.isRunning)
		                            .onHover { inside in if inside { forceArrowCursor() } }

		                            Button {
		                                clearInputFocus()
		                                vm.resumeDownload()
		                            } label: {
		                                Label("继续", systemImage: "play.circle")
		                                    .frame(maxWidth: .infinity)
		                            }
		                            .frame(maxWidth: .infinity)
		                            .buttonStyle(.bordered)
		                            .controlSize(.large)
		                            .disabled(vm.taskState != .paused)
		                            .onHover { inside in if inside { forceArrowCursor() } }

		                            Button {
		                                clearInputFocus()
		                                vm.stopDownload()
		                            } label: {
		                                Label("终止", systemImage: "stop.circle")
		                                    .frame(maxWidth: .infinity)
		                            }
		                            .frame(maxWidth: .infinity)
		                            .buttonStyle(.bordered)
		                            .controlSize(.large)
		                            .disabled(!(vm.isRunning || vm.taskState == .paused))
		                            .onHover { inside in if inside { forceArrowCursor() } }
		                        }
		                        .frame(maxWidth: .infinity)

		                        }
		                        .frame(maxWidth: .infinity, alignment: .top)
		                        .padding(.vertical, 1)
		                    }
		                    .scrollClipDisabledIfAvailable()
		                    .frame(maxWidth: 470)

		                    ScrollView(.vertical) {
		                        VStack(spacing: 8) {
		                            Card("任务状态", style: cardStyle, primaryText: cardPrimaryText, secondaryText: cardSecondaryText) {
		                                VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text("状态")
                                        .foregroundStyle(cardSecondaryText)
                                    Text(vm.status)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(cardPrimaryText)
                                    Spacer()
                                    Button("导出任务日志") {
                                        clearInputFocus()
                                        vm.exportTaskLog()
                                    }
                                        .disabled(vm.isRunning || vm.logEntries.isEmpty)
                                        .onHover { inside in if inside { forceArrowCursor() } }
                                    Button("打开目录") {
                                        clearInputFocus()
                                        vm.openSaveDirectory()
                                    }
                                    .onHover { inside in if inside { forceArrowCursor() } }
                                }

                                if vm.isRunning {
                                    if vm.hasProgressEstimate {
                                        ProgressView(value: vm.progressValue)
                                            .progressViewStyle(.linear)
                                    } else {
                                        ProgressView()
                                            .progressViewStyle(.linear)
                                    }
                                    Text(vm.progressText)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(cardSecondaryText)
                                } else if vm.hasProgressEstimate {
                                    ProgressView(value: vm.progressValue)
                                        .progressViewStyle(.linear)
                                    Text(vm.progressText)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(cardSecondaryText)
                                }

                                if !vm.detectedTotalText.isEmpty {
                                    Text(vm.detectedTotalText)
                                        .font(.system(size: 11))
                                        .foregroundStyle(cardSecondaryText)
                                }

                                Text(vm.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(cardSecondaryText)

                                if !vm.checkpointText.isEmpty {
                                    Text(vm.checkpointText)
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .foregroundStyle(cardSecondaryText)
                                        .lineLimit(1)
                                }

                                if !vm.exportedLogPath.isEmpty {
                                    Text(vm.exportedLogPath)
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .foregroundStyle(cardSecondaryText)
                                        .lineLimit(1)
                                        .textSelection(.enabled)
	                            }
	                        }
		                        .frame(maxWidth: .infinity, alignment: .top)
		                        .padding(.vertical, 1)
		                    }
		                    .scrollClipDisabledIfAvailable()
	                        }

		                        Card("任务队列", subtitle: "队列与历史记录（累积显示）", style: cardStyle, primaryText: cardPrimaryText, secondaryText: cardSecondaryText) {
		                            VStack(alignment: .leading, spacing: 8) {
		                                HStack(spacing: 10) {
		                                    Text("总 \(queueSummary.total)")
		                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
		                                        .foregroundStyle(cardSecondaryText)
		                                    Text("完成 \(queueSummary.done)")
		                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
		                                        .foregroundStyle(Color.green.opacity(0.95))
		                                    Text("终止 \(queueSummary.stopped)")
		                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
		                                        .foregroundStyle(cardSecondaryText)
		                                    Text("失败 \(queueSummary.failed)")
		                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
		                                        .foregroundStyle(Color.red.opacity(0.95))
		                                    Spacer(minLength: 0)
		                                    if !vm.queueRuns.isEmpty {
		                                        Text("历史 \(vm.queueRuns.count) 次")
		                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
		                                            .foregroundStyle(cardSecondaryText)
		                                    }
		                                }
		                                if vm.taskState == .paused {
		                                    Text("当前已暂停，可点击“继续”恢复。")
		                                        .font(.system(size: 11))
		                                        .foregroundStyle(cardSecondaryText)
		                                }

		                                ScrollView {
		                                    LazyVStack(alignment: .leading, spacing: 6) {
		                                        if vm.queueRuns.isEmpty {
		                                            Text("等待任务开始...")
		                                                .font(.system(size: 12))
		                                                .foregroundStyle(cardSecondaryText)
		                                        } else {
		                                            ForEach(Array(vm.queueRuns.enumerated()), id: \.element.id) { runIdx, run in
		                                                HStack {
		                                                    Text("任务 \(runIdx + 1)")
		                                                        .font(.system(size: 12, weight: .semibold))
		                                                        .foregroundStyle(cardPrimaryText)
		                                                    Text(run.startedAtText)
		                                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
		                                                        .foregroundStyle(cardSecondaryText)
		                                                    Spacer(minLength: 0)
		                                                }
		                                                .padding(.top, runIdx == 0 ? 0 : 6)

		                                                ForEach(Array(run.items.enumerated()), id: \.element.id) { idx, item in
		                                                    HStack(spacing: 8) {
		                                                        Text("\(idx + 1).")
		                                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
		                                                            .frame(width: 22, alignment: .leading)
		                                                        Text(item.url)
		                                                            .font(.system(size: 11, weight: .regular, design: .monospaced))
		                                                            .lineLimit(1)
		                                                        Spacer(minLength: 8)
		                                                        Text(item.state.title)
		                                                            .font(.system(size: 11, weight: .semibold))
		                                                            .foregroundStyle(queueStateColor(item.state))
		                                                            .padding(.horizontal, 8)
		                                                            .padding(.vertical, 3)
		                                                            .background(queueStateColor(item.state).opacity(0.16), in: Capsule())
		                                                    }
		                                                }
		                                            }
		                                        }
		                                    }
		                                    .padding(10)
		                                }
		                                .frame(minHeight: 108, maxHeight: 144)
		                                .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
		                            }
		                        }

                        Card("实时日志", subtitle: "单击「导出任务日志」可将日志导出到任务保存目录", style: cardStyle, primaryText: cardPrimaryText, secondaryText: cardSecondaryText) {
                            LogConsoleView(entries: vm.logEntries, textColor: logTextNSColor)
                            .frame(height: 320)
                            .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, rightPanelNarrowInset)
                }
            }
            .padding(10)
            .tint(accentTint)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                clearInputFocus()
            })
        }
        .sheet(isPresented: $showSitesInfo) {
            SupportedSitesSheet(sites: vm.supportedSites)
        }
        .background(
            WindowSizeEnforcer(
                minWidth: 1120,
                minHeight: 860,
                idealWidth: 1180,
                idealHeight: 880
            )
            .frame(width: 0, height: 0)
        )
        .frame(minWidth: 1120, idealWidth: 1180, maxWidth: 1400, minHeight: 860, idealHeight: 880, maxHeight: 1020)
    }
}

@main
struct BookGetGUIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1180, height: 880)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .help) {
                Button("BookGet GUI 帮助") {
                    BookGetHelpWindowController.shared.show()
                }
                .keyboardShortcut("?", modifiers: [.command, .shift])
            }
        }
    }
}
