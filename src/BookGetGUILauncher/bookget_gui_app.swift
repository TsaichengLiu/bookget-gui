import SwiftUI
import AppKit
import UserNotifications

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

    var symbol: String {
        switch self {
        case .waiting: return "clock"
        case .running: return "arrow.down.circle"
        case .retrying: return "arrow.clockwise.circle"
        case .paused: return "pause.circle"
        case .stopped: return "stop.circle"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
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

/// The wrapper is a zsh script that runs bookget-core, curl and the login
/// helper as children; `Process.terminate()` only reaches the script itself,
/// so those children used to keep downloading after pause/stop.
enum ProcessTree {
    static func descendants(of root: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var pending: [pid_t] = [root]
        var buffer = [pid_t](repeating: 0, count: 512)
        while let pid = pending.popLast() {
            // With a buffer this returns the number of child pids written.
            let count = buffer.withUnsafeMutableBytes {
                proc_listchildpids(pid, $0.baseAddress, Int32($0.count))
            }
            guard count > 0 else { continue }
            let children = buffer.prefix(Int(count)).filter { $0 > 0 }
            result.append(contentsOf: children)
            pending.append(contentsOf: children)
        }
        return result
    }

    /// SIGTERM to the root and every descendant, then SIGCONT so a core the
    /// wrapper stopped in interval mode can act on it. Survivors get SIGKILL
    /// after `graceSeconds` (synchronously when `wait` is true, e.g. on quit).
    static func terminate(root: pid_t, graceSeconds: Double = 3, wait: Bool = false) {
        let pids = [root] + descendants(of: root)
        for pid in pids { kill(pid, SIGTERM) }
        for pid in pids { kill(pid, SIGCONT) }
        let killSurvivors = {
            for pid in pids where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
        if wait {
            usleep(useconds_t(graceSeconds * 1_000_000))
            killSurvivors()
        } else {
            DispatchQueue.global().asyncAfter(deadline: .now() + graceSeconds, execute: killSurvivors)
        }
    }
}

final class DownloadEngine {
    /// Lets the app delegate stop every running download on quit.
    static let live = NSHashTable<DownloadEngine>.weakObjects()

    init() {
        DownloadEngine.live.add(self)
    }

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
    private var pendingOutput = Data()
    private let outputLock = NSLock()
    /// Bumped on every runNext so a stale URL-preparation callback (e.g. from
    /// before a pause/resume) can never launch a second process.
    private var launchGeneration = 0

    var isBusy: Bool {
        state == .running || state == .retrying || state == .paused
    }

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
        if let proc = process, proc.isRunning {
            terminateProcessTree()
        } else {
            // Between tasks (URL preparation, retry hand-off) there is no
            // process to wait for: pause right away.
            launchGeneration += 1
            enterPausedState(index: currentIndex + 1, total: urls.count, status: nil)
        }
    }

    private func enterPausedState(index: Int, total: Int, status: Int32?) {
        state = .paused
        if currentIndex < queueItems.count {
            queueItems[currentIndex].state = .paused
            queueItems[currentIndex].note = "已暂停，可继续"
        }
        onQueueUpdated?(queueItems)
        onState?(.paused, "已暂停。继续时将从当前网址接着下载（已下载的页面会跳过）。")
        if let status {
            onTaskFinished?(index, total, status)
        }
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
            terminateProcessTree()
            return
        }

        state = .stopped
        onState?(.stopped, "任务已终止。")
        onFinished?(failCount)
    }

    private func terminateProcessTree() {
        guard let proc = process, proc.isRunning else { return }
        ProcessTree.terminate(root: proc.processIdentifier)
    }

    /// Called from applicationWillTerminate: nothing may outlive the app.
    func shutdownForAppExit() {
        isStopping = true
        guard let proc = process, proc.isRunning else { return }
        ProcessTree.terminate(root: proc.processIdentifier, graceSeconds: 0.5, wait: true)
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
        launchGeneration += 1
        let generation = launchGeneration
        prepareURLIfNeeded(for: url) { [weak self] preparedURL, preferredMode in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.currentIndex == taskArrayIndex, self.launchGeneration == generation else { return }
                guard !self.isStopping, !self.isPauseRequested else { return }
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

        outputLock.lock()
        pendingOutput.removeAll()
        outputLock.unlock()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF: stop being called in a loop.
                handle.readabilityHandler = nil
                return
            }
            self?.consumeOutput(data, flushAll: false)
        }

        proc.terminationHandler = { [weak self] p in
            guard let self else { return }
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = nil
            // The last lines are usually the error the retry logic looks for.
            self.consumeOutput(Self.readRemainingWithoutBlocking(handle), flushAll: true)
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
            if status == 0 {
                // The task finished just before the pause landed: keep it.
                queueItems[currentIndex].state = .succeeded
                queueItems[currentIndex].note = "完成"
                onTaskFinished?(index, total, status)
                currentIndex += 1
                if currentIndex >= urls.count {
                    isPauseRequested = false
                    state = .running
                    runNext()
                    return
                }
            }
            enterPausedState(index: index, total: total, status: status == 0 ? nil : status)
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
        if let reason = failureReasonFromLog() {
            queueItems[currentIndex].note = "失败：\(reason)"
        } else {
            queueItems[currentIndex].note = "失败（返回码 \(status)）"
        }
        onQueueUpdated?(queueItems)
        onTaskFinished?(index, total, status)
        currentIndex += 1
        state = .running
        runNext()
    }

    /// Emits only complete lines (up to the last \n or \r), so a multi-byte
    /// UTF-8 character or a line split across two reads is neither dropped
    /// nor broken in half.
    private func consumeOutput(_ data: Data, flushAll: Bool) {
        outputLock.lock()
        defer { outputLock.unlock() }
        pendingOutput.append(data)

        var emit = Data()
        if flushAll || pendingOutput.count > 64 * 1024 {
            emit = pendingOutput
            pendingOutput = Data()
        } else if let last = pendingOutput.lastIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            emit = Data(pendingOutput[pendingOutput.startIndex...last])
            pendingOutput = Data(pendingOutput[pendingOutput.index(after: last)...])
        }
        guard !emit.isEmpty else { return }

        let str = String(decoding: emit, as: UTF8.self)
        appendRunLog(str)
        onLogChunk?(str)
    }

    /// A grandchild that escaped termination may still hold the pipe open, so
    /// readDataToEndOfFile() could block forever; read what is there and stop.
    private static func readRemainingWithoutBlocking(_ handle: FileHandle) -> Data {
        let fd = handle.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            guard n > 0 else { break }
            result.append(contentsOf: buffer[0..<n])
        }
        return result
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

    /// Prefer the wrapper's explicit summary line, else the last error-looking line.
    private func failureReasonFromLog() -> String? {
        let lines = runLogSnapshot()
            .components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let marker = "失败原因："
        if let line = lines.last(where: { $0.contains(marker) }),
           let range = line.range(of: marker) {
            let reason = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !reason.isEmpty { return String(reason.prefix(80)) }
        }
        let keys = ["error", "failed", "panic", "失败", "错误", "无法"]
        if let line = lines.last(where: { l in
            let lower = l.lowercased()
            return keys.contains(where: { lower.contains($0) })
        }) {
            var text = line
            if text.hasPrefix("[bookget wrapper]") {
                text = String(text.dropFirst("[bookget wrapper]".count)).trimmingCharacters(in: .whitespaces)
            }
            return String(text.prefix(80))
        }
        return nil
    }

    private func shouldRetryForNameConflict(at index: Int) -> Bool {
        if conflictRetriedIndexes.contains(index) { return false }
        // "已存在"/"already exists" usually means the core skipped pages it
        // already has (e.g. after resume) — retrying into a new folder would
        // re-download the whole book. The wrapper handles real clashes itself,
        // so only an explicit name-clash message triggers this.
        let log = runLogSnapshot().lowercased()
        let skipped = ["跳过", "skip", "已下载"].contains(where: { log.contains($0) })
        return !skipped && ["同名冲突", "重名"].contains(where: { log.contains($0) })
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
        let stamp = DownloadViewModel.formatDate(Date(), format: "yyyyMMdd_HHmmss")
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
    private var pageProbeTask: Task<Void, Never>?

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
        startDownload(urls: urls)
    }

    /// Re-runs every item that failed in the most recent run.
    func retryFailedItems() {
        let failed = queueItems.filter { $0.state == .failed || $0.state == .stopped }.map(\.url)
        guard !failed.isEmpty else { return }
        startDownload(urls: failed)
    }

    func retry(url: String) {
        startDownload(urls: [url])
    }

    var canRetryFailed: Bool {
        !isRunning && taskState != .paused &&
            queueItems.contains { $0.state == .failed || $0.state == .stopped }
    }

    func clearQueueHistory() {
        guard !isRunning, taskState != .paused else { return }
        queueRuns = []
        queueItems = []
        activeQueueRunID = nil
        checkpointText = ""
    }

    func clearLogDisplay() {
        logEntries = []
    }

    func copyLogToPasteboard() {
        let text = logEntries.map(\.text).joined(separator: "\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        detail = "日志已复制到剪贴板。"
    }

    /// Number of distinct links currently in the input box.
    var inputURLCount: Int {
        parseInputURLs(urlText).filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }.count
    }

    func pasteURLsFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        appendURLs(Self.extractURLs(from: text))
    }

    /// Accepts .webloc (Safari/Finder), .url (Windows) and plain-text lists.
    func handleDroppedFiles(_ files: [URL]) {
        var found: [String] = []
        for file in files {
            switch file.pathExtension.lowercased() {
            case "webloc":
                if let data = try? Data(contentsOf: file),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let url = plist["URL"] as? String {
                    found.append(url)
                }
            default:
                if let text = try? String(contentsOf: file, encoding: .utf8) {
                    found += Self.extractURLs(from: text)
                }
            }
        }
        appendURLs(found)
    }

    private func appendURLs(_ urls: [String]) {
        guard !urls.isEmpty else {
            detail = "没有找到可用的网址。"
            return
        }
        let existing = Set(parseInputURLs(urlText))
        var seen = existing
        let fresh = urls.filter { seen.insert($0).inserted }
        guard !fresh.isEmpty else {
            detail = "这些网址已经在列表里了。"
            return
        }
        var text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { text += "\n" }
        urlText = text + fresh.joined(separator: "\n")
        detail = "已添加 \(fresh.count) 个网址。"
    }

    // A link ends at whitespace, quotes/brackets, or CJK punctuation that is
    // often typed right after it (见 https://…，以及 …).
    private static let urlRegex = try! NSRegularExpression(
        pattern: #"https?://[^\s<>"'，。、；：！？（）《》「」【】]+"#,
        options: [.caseInsensitive]
    )

    static func extractURLs(from text: String) -> [String] {
        let ns = text as NSString
        return urlRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)]"))
        }
    }

    func startDownload(urls: [String]) {
        guard !isRunning, taskState != .paused else { return }

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
        if queueRuns.count > 30 {
            queueRuns.removeFirst(queueRuns.count - 30)
        }
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
                // Keep the log open across pause so lines after resume are kept;
                // flush first so the final lines reach the file before it closes.
                if state == .stopped || state == .completed || state == .failed {
                    self.flushPendingLogNow()
                    self.sealTempLogFile()
                }
            }
        }

        engine.onQueueUpdated = { [weak self] items in
            guard let self else { return }
            DispatchQueue.main.async {
                self.queueItems = items
                self.updateDockBadge()
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

        engine.onFinished = { [weak self] failCount in
            guard let self else { return }
            DispatchQueue.main.async {
                self.flushPendingLogNow()
                NSApp.dockTile.badgeLabel = nil
                self.notifyFinished(failCount: failCount)
            }
        }
    }

    private func updateDockBadge() {
        let remaining = queueItems.filter { [.waiting, .running, .retrying].contains($0.state) }.count
        NSApp.dockTile.badgeLabel = remaining > 0 ? "\(remaining)" : nil
    }

    private func notifyFinished(failCount: Int) {
        let total = queueItems.count
        let succeeded = queueItems.filter { $0.state == .succeeded }.count
        let wasStopped = taskState == .stopped
        let title: String
        let body: String
        if wasStopped {
            title = "下载已终止"
            body = "已完成 \(succeeded) / \(total) 个网址。"
        } else if failCount == 0 {
            title = "下载完成"
            body = total > 1 ? "\(total) 个网址全部下载完成。" : "网址已下载完成。"
        } else {
            title = "下载结束，有 \(failCount) 个失败"
            body = "成功 \(succeeded) / \(total)。可在任务队列中点「重试失败项」。"
        }
        if !NSApp.isActive {
            NSApp.requestUserAttention(.informationalRequest)
        }
        // UNUserNotificationCenter traps without a bundle identifier.
        guard !wasStopped, Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
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

        // Callers are on the main thread; applying synchronously keeps the log
        // ahead of the "finished" state that is set right after a flush.
        let apply = {
            var lines = chunk.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.last == "" { lines.removeLast() }
            for line in lines {
                self.logEntryCounter += 1
                self.logEntries.append(LogEntry(id: self.logEntryCounter, text: line))
            }
            if self.logEntries.count > 1600 {
                self.logEntries = Array(self.logEntries.suffix(1600))
            }
            self.consumeLogChunk(chunk)
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
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

    /// One link per line (several per line separated by spaces also work);
    /// duplicates are dropped so a book is never downloaded twice in a run.
    private func parseInputURLs(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func discoverTotalPages(for sourceURL: String) {
        detectedTotalText = "正在探测总页数..."
        // A slow probe for the previous book must not set this book's total.
        pageProbeTask?.cancel()
        pageProbeTask = Task {
            let total = await Self.detectTotalPages(from: sourceURL)
            guard !Task.isCancelled else { return }
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

        var seen = Set<String>()
        let ordered = candidates.filter { seen.insert($0.absoluteString).inserted }

        for url in ordered {
            if let total = await fetchManifestTotal(from: url) {
                return total
            }
        }

        return nil
    }

    static func manifestPageCount(from obj: Any) -> Int? {
        if let dict = obj as? [String: Any] {
            // IIIF v2: the page list is sequences[0].canvases.
            if let seqs = dict["sequences"] as? [[String: Any]],
               let canvases = seqs.first?["canvases"] as? [Any], !canvases.isEmpty {
                return canvases.count
            }
            // IIIF v3: top-level items are the canvases; "structures" only
            // references them again, so it must not be counted.
            if let items = dict["items"] as? [[String: Any]], !items.isEmpty {
                let canvases = items.filter { ($0["type"] as? String)?.caseInsensitiveCompare("Canvas") == .orderedSame }
                return canvases.isEmpty ? items.count : canvases.count
            }
        }
        // Unknown layout: count distinct canvas ids anywhere in the document.
        var ids = Set<String>()
        var anonymous = 0
        collectCanvasIDs(in: obj, ids: &ids, anonymous: &anonymous)
        let total = ids.count + anonymous
        return total > 0 ? total : nil
    }

    private static func fetchManifestTotal(from manifestURL: URL) async -> Int? {
        guard let data = await fetchData(from: manifestURL, maxBytes: 4_000_000) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return manifestPageCount(from: obj)
    }

    private static func collectCanvasIDs(in obj: Any, ids: inout Set<String>, anonymous: inout Int) {
        if let dict = obj as? [String: Any] {
            let type = (dict["type"] as? String) ?? (dict["@type"] as? String) ?? ""
            if type.caseInsensitiveCompare("Canvas") == .orderedSame || type.caseInsensitiveCompare("sc:Canvas") == .orderedSame {
                if let id = (dict["id"] as? String) ?? (dict["@id"] as? String) {
                    ids.insert(id)
                } else {
                    anonymous += 1
                }
            }
            for (_, v) in dict {
                collectCanvasIDs(in: v, ids: &ids, anonymous: &anonymous)
            }
        } else if let arr = obj as? [Any] {
            for v in arr { collectCanvasIDs(in: v, ids: &ids, anonymous: &anonymous) }
        }
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

	// Restrict parsing to explicit progress-like lines to avoid false positives
	// from generic "x/y" text fragments. Compiled once, not per log line.
	private static let progressRegexes: [NSRegularExpression] = [
		"(?i)(?:^|\\s)get\\s*(\\d+)\\s*/\\s*(\\d+)(?:\\s|$)",
		"(?i)(?:^|\\s)saved\\s*(\\d+)\\s*/\\s*(\\d+)(?:\\s|$)",
		"第\\s*(\\d+)\\s*[\\/／]\\s*(\\d+)\\s*(?:页|張|张|項|项)"
	].compactMap { try? NSRegularExpression(pattern: $0) }

	private func extractPair(from line: String) -> (Int, Int)? {
        for regex in Self.progressRegexes {
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

    private static var formatters: [String: DateFormatter] = [:]
    private static let formattersLock = NSLock()

    static func formatDate(_ date: Date, format: String) -> String {
        formattersLock.lock()
        defer { formattersLock.unlock() }
        let formatter = formatters[format] ?? {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = format
            formatters[format] = f
            return f
        }()
        return formatter.string(from: date)
    }
}

struct Card<Content: View>: View {
    let title: String
    let subtitle: String?
    let style: CardVisualStyle
    let primaryText: Color
    let secondaryText: Color
    let accessory: AnyView?
    let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        style: CardVisualStyle = .frosted,
        primaryText: Color = .primary,
        secondaryText: Color = .secondary,
        accessory: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let accessory {
                    accessory
                        .controlSize(.small)
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

    // Constraints are applied once when the window attaches; re-applying on
    // every SwiftUI update (e.g. each log flush) only caused window churn.
    func updateNSView(_ nsView: NSView, context: Context) {}

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

/// NSTextView-backed input so that dropped .webloc/.txt files are read as
/// link lists instead of having their file paths pasted in as text.
final class URLDropTextView: NSTextView {
    var onFilesDropped: (([URL]) -> Void)?

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let files = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           !files.isEmpty {
            onFilesDropped?(files)
            return true
        }
        return super.performDragOperation(sender)
    }
}

struct URLInputEditor: NSViewRepresentable {
    @Binding var text: String
    let textColor: NSColor
    let onFilesDropped: ([URL]) -> Void

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: URLInputEditor
        init(_ parent: URLInputEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = URLDropTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.registerForDraggedTypes([.fileURL, .URL, .string])
        textView.onFilesDropped = onFilesDropped
        textView.string = text
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = nsView.documentView as? URLDropTextView else { return }
        tv.onFilesDropped = onFilesDropped
        tv.textColor = textColor
        tv.insertionPointColor = textColor
        if tv.string != text {
            tv.string = text
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
        // lastRenderedID == 0 means the placeholder is showing: replace it.
        if newestID < context.coordinator.lastRenderedID || context.coordinator.lastRenderedID == 0 {
            context.coordinator.lastRenderedID = 0
            textView.string = ""
        }

        let delta = entries.filter { $0.id > context.coordinator.lastRenderedID }
        guard !delta.isEmpty, let storage = textView.textStorage else { return }

        // Only follow the output when the user hasn't scrolled up to read.
        let clip = nsView.contentView
        let wasAtBottom = clip.bounds.maxY >= (textView.frame.height - 24)

        let chunk = NSMutableAttributedString()
        for entry in delta {
            chunk.append(NSAttributedString(string: entry.text + "\n", attributes: attributes(for: entry.text, base: attrs)))
        }
        storage.append(chunk)
        context.coordinator.lastRenderedID = newestID

        // NSTextStorage.length is O(1); String.count would walk the whole log.
        if storage.length > 140_000 {
            let cut = storage.length - 120_000
            let ns = storage.string as NSString
            let lineEnd = ns.range(of: "\n", options: [], range: NSRange(location: cut, length: ns.length - cut))
            let removeUpTo = lineEnd.location == NSNotFound ? cut : lineEnd.location + 1
            storage.deleteCharacters(in: NSRange(location: 0, length: removeUpTo))
        }
        if wasAtBottom {
            scrollToBottom(textView)
        }
    }

    private func attributes(for line: String, base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attrs = base
        let lower = line.lowercased()
        if lower.contains("失败") || lower.contains("error") || lower.contains("panic") || lower.contains("错误") {
            attrs[.foregroundColor] = NSColor.systemRed.blended(withFraction: 0.25, of: textColor) ?? NSColor.systemRed
        } else if line.hasPrefix("[bookget wrapper]") || line.hasPrefix("[bookget gui]") {
            attrs[.foregroundColor] = textColor.withAlphaComponent(0.62)
        }
        return attrs
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

    private var statusPillColor: Color {
        switch vm.taskState {
        case .running, .retrying: return .orange
        case .paused: return .yellow
        case .failed: return .red
        case .completed: return .green
        default: return vm.isRunning ? .orange : .green
        }
    }

    private var statusPillText: String {
        switch vm.taskState {
        case .running: return "下载中"
        case .retrying: return "重试中"
        case .paused: return "已暂停"
        case .failed: return "部分失败"
        case .completed: return "已完成"
        case .stopped: return "已终止"
        case .idle: return "空闲"
        }
    }

    private var isBusy: Bool { vm.isRunning || vm.taskState == .paused }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(cardSecondaryText)
            .gridColumnAlignment(.leading)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(headerPrimary)
                .frame(width: 36, height: 36)
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
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(headerPrimary)
                Text("典籍下载工作台")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(headerPrimary.opacity(0.72))
            }

            Spacer()

            Label(statusPillText, systemImage: "circle.fill")
                .labelStyle(StatusDotLabelStyle(color: statusPillColor))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(headerPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusPillColor.opacity(0.18), in: Capsule())

            Button {
                clearInputFocus()
                showSitesInfo = true
            } label: {
                Label("支持网站", systemImage: "globe")
            }
            .help("查看可下载的图书馆与网站")

            Menu {
                Picker("配色", selection: $themeRaw) {
                    ForEach(AppTheme.allCases) { t in
                        Text(t.title).tag(t.rawValue)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Picker("卡片样式", selection: $cardStyleRaw) {
                    ForEach(CardVisualStyle.allCases) { s in
                        Text(s.title).tag(s.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("外观", systemImage: "paintpalette")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("配色与卡片样式")

            Menu {
                Button("恢复上次设置") {
                    clearInputFocus()
                    vm.restoreLastUsed()
                }
                Button("清空最近记录") {
                    clearInputFocus()
                    vm.clearRecentHistory()
                }
                Divider()
                Button("恢复初始设置…") {
                    clearInputFocus()
                    showRestoreFactoryDefaultsConfirm = true
                }
                .disabled(isBusy)
                Divider()
                Button("BookGet GUI 帮助") {
                    BookGetHelpWindowController.shared.show()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(topBarBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(topBarBorder, lineWidth: 1)
        )
    }

    // MARK: Left column

    private var inputCard: some View {
        Card("下载内容", style: cardStyle, primaryText: cardPrimaryText, secondaryText: cardSecondaryText) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow(alignment: .top) {
                    fieldLabel("网址")
                        .padding(.top, 7)
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack(alignment: .topLeading) {
                            URLInputEditor(
                                text: $vm.urlText,
                                textColor: NSColor(cardPrimaryText),
                                onFilesDropped: { vm.handleDroppedFiles($0) }
                            )
                            if vm.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("每行一个网址，可一次粘贴多行\n也可以把网页链接、.webloc 或 .txt 文件拖到这里")
                                    .font(.system(size: 12))
                                    .foregroundStyle(cardSecondaryText.opacity(0.85))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(minHeight: 96, idealHeight: 120, maxHeight: 160)
                        .background(urlEditorBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(urlEditorBorder, lineWidth: 1)
                        )

                        HStack(spacing: 8) {
                            let count = vm.inputURLCount
                            Text(count == 0 ? "尚未输入网址" : "已识别 \(count) 个网址")
                                .font(.system(size: 11))
                                .foregroundStyle(cardSecondaryText)
                            Spacer(minLength: 0)
                            Button {
                                vm.pasteURLsFromClipboard()
                            } label: {
                                Label("粘贴", systemImage: "doc.on.clipboard")
                            }
                            Menu {
                                if vm.recentUrls.isEmpty {
                                    Text("暂无记录")
                                } else {
                                    ForEach(vm.recentUrls, id: \.self) { u in
                                        Button(u) { vm.applyRecentURL(u) }
                                    }
                                }
                            } label: {
                                Label("最近", systemImage: "clock.arrow.circlepath")
                            }
                            .fixedSize()
                            Button {
                                vm.urlText = ""
                            } label: {
                                Label("清空", systemImage: "xmark.circle")
                            }
                            .disabled(vm.urlText.isEmpty)
                        }
                        .controlSize(.small)
                        .disabled(isBusy)
                    }
                }

                GridRow {
                    fieldLabel("保存到")
                    HStack(spacing: 6) {
                        TextField("选择保存目录", text: $vm.saveDirectory)
                            .focused($focusedField, equals: .saveDirectory)
                            .textFieldStyle(.roundedBorder)
                            .restoreArrowCursorOnExit()
                        Button("选择…") {
                            clearInputFocus()
                            vm.chooseDirectory()
                        }
                        Menu {
                            if vm.recentDirectories.isEmpty {
                                Text("暂无记录")
                            } else {
                                ForEach(vm.recentDirectories, id: \.self) { d in
                                    Button(d) { vm.applyRecentDirectory(d) }
                                }
                            }
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("最近使用的目录")
                    }
                }

                GridRow {
                    fieldLabel("验证")
                    Toggle(isOn: Binding(
                        get: { vm.needLogin },
                        set: { vm.applyNeedLogin($0) }
                    )) {
                        Text("开启弹窗浏览器（需要登录或验证的网站）")
                            .foregroundStyle(cardPrimaryText)
                    }
                    .help("上海图书馆、台北国图等需要登录或点开阅读页的网站请保持开启")
                }
            }
        }
    }

    private func advancedField(_ label: String, hint: String, text: Binding<String>, focus: InputFocusField) -> some View {
        GridRow {
            fieldLabel(label)
            TextField(hint, text: text)
                .focused($focusedField, equals: focus)
                .textFieldStyle(.roundedBorder)
                .restoreArrowCursorOnExit()
        }
    }

    private var advancedCard: some View {
        Card(
            "高级参数",
            subtitle: vm.showAdvanced ? nil : "默认设置适合大多数网站",
            style: cardStyle,
            primaryText: cardPrimaryText,
            secondaryText: cardSecondaryText,
            accessory: AnyView(
                Toggle("启用", isOn: $vm.showAdvanced)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("启用后以下参数才会生效")
            )
        ) {
            if vm.showAdvanced {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        fieldLabel("识别模式")
                        Picker("", selection: $vm.appMode) {
                            Text("0 · 内置站点规则（默认）").tag("0")
                            Text("1 · 通用批量抓取").tag("1")
                            Text("2 · IIIF 自动识别").tag("2")
                        }
                        .labelsHidden()
                        .onChange(of: vm.appMode) { _, newValue in
                            vm.applyAppMode(newValue)
                        }
                    }
                    advancedField("并发线程", hint: "2（建议 2–6）", text: $vm.concurrency, focus: .concurrency)
                    advancedField("失败重试", hint: "3", text: $vm.retries, focus: .retries)
                    advancedField("抓取间隔", hint: "秒，留空为不限", text: $vm.captureInterval, focus: .captureInterval)
                    advancedField("页码范围", hint: "如 4:50", text: $vm.seq, focus: .seq)
                    advancedField("分册范围", hint: "如 3:6", text: $vm.vol, focus: .vol)
                    GridRow {
                        fieldLabel("输出格式")
                        Picker("", selection: $vm.fileExt) {
                            Text("默认").tag("_")
                            Text(".jpg").tag(".jpg")
                            Text(".png").tag(".png")
                            Text(".tif").tag(".tif")
                            Text(".pdf").tag(".pdf")
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    GridRow {
                        fieldLabel("浏览器标识")
                        HStack(spacing: 6) {
                            Picker("", selection: $vm.uaPreset) {
                                ForEach(UserAgentPreset.allCases) { preset in
                                    Text(preset.title).tag(preset.rawValue)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
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
                            }
                        }
                    }
                    GridRow {
                        fieldLabel("Cookie 文件")
                        HStack(spacing: 6) {
                            TextField("可选：cookie.txt", text: $vm.cookieFilePath)
                                .focused($focusedField, equals: .cookieFilePath)
                                .textFieldStyle(.roundedBorder)
                                .restoreArrowCursorOnExit()
                            Button("选择…") {
                                clearInputFocus()
                                vm.chooseCookieFile()
                            }
                            Button {
                                clearInputFocus()
                                vm.clearCookieFile()
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .help("清空")
                            .disabled(vm.cookieFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    GridRow {
                        fieldLabel("localStorage")
                        HStack(spacing: 6) {
                            TextField("可选：localStorage.txt", text: $vm.localStorageFilePath)
                                .focused($focusedField, equals: .localStorageFilePath)
                                .textFieldStyle(.roundedBorder)
                                .restoreArrowCursorOnExit()
                            Button("选择…") {
                                clearInputFocus()
                                vm.chooseLocalStorageFile()
                            }
                            Button {
                                clearInputFocus()
                                vm.clearLocalStorageFile()
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .help("清空")
                            .disabled(vm.localStorageFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .disabled(isBusy)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: vm.showAdvanced)
    }

    private var tipsCard: some View {
        Card("小提示", style: cardStyle, primaryText: cardPrimaryText, secondaryText: cardSecondaryText) {
            VStack(alignment: .leading, spacing: 7) {
                tip("square.stack.3d.down.right", "一次可粘贴多个网址，重复的会自动去掉。")
                tip("person.badge.key", "上海图书馆、台北国图等需要登录的网站，请勾选「开启弹窗浏览器」。")
                tip("pause.circle", "暂停或终止后再下载同一网址，已下好的页面会自动跳过。")
                tip("arrow.clockwise", "失败的网址可在任务队列里一键「重试失败项」，右键单项可复制或重下。")
            }
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(accentTint)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(cardSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Only the buttons that make sense right now, so none sit there disabled.
    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                switch vm.taskState {
                case .running, .retrying:
                    Button {
                        clearInputFocus()
                        vm.pauseDownload()
                    } label: {
                        Label("暂停", systemImage: "pause.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("p", modifiers: .command)
                    stopButton
                case .paused:
                    Button {
                        clearInputFocus()
                        vm.resumeDownload()
                    } label: {
                        Label("继续下载", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("p", modifiers: .command)
                    stopButton
                default:
                    Button {
                        clearInputFocus()
                        vm.startDownload()
                    } label: {
                        Label("开始下载", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(vm.inputURLCount == 0)
                }
            }
            .controlSize(.large)
            .onHover { inside in if inside { forceArrowCursor() } }

            Text(actionHint)
                .font(.system(size: 11))
                .foregroundStyle(cardSecondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .background(urlEditorBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(urlEditorBorder, lineWidth: 1)
        )
    }

    private var stopButton: some View {
        Button(role: .destructive) {
            clearInputFocus()
            vm.stopDownload()
        } label: {
            Label("终止", systemImage: "stop.fill").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .keyboardShortcut(".", modifiers: .command)
    }

    private var actionHint: String {
        switch vm.taskState {
        case .running, .retrying:
            return "⌘P 暂停 · ⌘. 终止 · 已下载的页面在继续时会自动跳过"
        case .paused:
            return "⌘P 继续 · ⌘. 终止"
        default:
            let count = vm.inputURLCount
            let dir = (vm.saveDirectory as NSString).abbreviatingWithTildeInPath
            return count == 0 ? "⌘↩ 开始下载" : "⌘↩ 下载 \(count) 个网址到 \(dir)"
        }
    }

    // MARK: Right column

    private var statusCard: some View {
        Card(
            "任务状态",
            style: cardStyle,
            primaryText: cardPrimaryText,
            secondaryText: cardSecondaryText,
            accessory: AnyView(
                HStack(spacing: 6) {
                    Button {
                        clearInputFocus()
                        vm.exportTaskLog()
                    } label: {
                        Label("导出日志", systemImage: "square.and.arrow.up")
                    }
                    .disabled(vm.isRunning || vm.logEntries.isEmpty)
                    Button {
                        clearInputFocus()
                        vm.openSaveDirectory()
                    } label: {
                        Label("打开目录", systemImage: "folder")
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(vm.status)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(cardPrimaryText)
                    Spacer(minLength: 8)
                    if vm.isRunning || vm.hasProgressEstimate {
                        Text(vm.progressText)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(cardSecondaryText)
                    }
                }

                if vm.hasProgressEstimate {
                    ProgressView(value: vm.progressValue)
                        .progressViewStyle(.linear)
                        .tint(accentTint)
                } else if vm.isRunning {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(accentTint)
                }

                Text(vm.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(cardSecondaryText)
                    .lineLimit(2)
                    .textSelection(.enabled)

                if !vm.detectedTotalText.isEmpty || !vm.checkpointText.isEmpty {
                    HStack(spacing: 10) {
                        if !vm.detectedTotalText.isEmpty {
                            Text(vm.detectedTotalText)
                        }
                        if !vm.checkpointText.isEmpty {
                            Text(vm.checkpointText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(cardSecondaryText)
                }

                if !vm.exportedLogPath.isEmpty {
                    Text(vm.exportedLogPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(cardSecondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func queueRow(index: Int, item: QueueTaskItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.state.symbol)
                .foregroundStyle(queueStateColor(item.state))
                .frame(width: 16)
            Text("\(index + 1).")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(cardSecondaryText)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(cardPrimaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.state == .failed || item.state == .retrying,
                   !item.note.isEmpty {
                    Text(item.note)
                        .font(.system(size: 10))
                        .foregroundStyle(queueStateColor(item.state).opacity(0.9))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(item.state.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(queueStateColor(item.state))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(queueStateColor(item.state).opacity(0.16), in: Capsule())
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .help(item.note.isEmpty ? item.url : "\(item.url)\n\(item.note)")
        .contextMenu {
            Button("复制网址") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url, forType: .string)
            }
            if let u = URL(string: item.url) {
                Button("在浏览器中打开") { NSWorkspace.shared.open(u) }
            }
            Divider()
            Button("重新下载这一项") { vm.retry(url: item.url) }
                .disabled(isBusy)
        }
    }

    private var queueCard: some View {
        Card(
            "任务队列",
            style: cardStyle,
            primaryText: cardPrimaryText,
            secondaryText: cardSecondaryText,
            accessory: AnyView(
                HStack(spacing: 6) {
                    Button {
                        vm.retryFailedItems()
                    } label: {
                        Label("重试失败项", systemImage: "arrow.clockwise")
                    }
                    .disabled(!vm.canRetryFailed)
                    Button {
                        vm.clearQueueHistory()
                    } label: {
                        Label("清空", systemImage: "trash")
                    }
                    .disabled(isBusy || vm.queueRuns.isEmpty)
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("共 \(queueSummary.total)")
                        .foregroundStyle(cardSecondaryText)
                    Text("完成 \(queueSummary.done)")
                        .foregroundStyle(Color.green.opacity(0.95))
                    Text("失败 \(queueSummary.failed)")
                        .foregroundStyle(Color.red.opacity(0.95))
                    Text("终止 \(queueSummary.stopped)")
                        .foregroundStyle(cardSecondaryText)
                    Spacer(minLength: 0)
                    if vm.queueRuns.count > 1 {
                        Text("历史 \(vm.queueRuns.count) 批")
                            .foregroundStyle(cardSecondaryText)
                    }
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if vm.queueRuns.isEmpty {
                                Text("还没有任务。输入网址后点「开始下载」。")
                                    .font(.system(size: 12))
                                    .foregroundStyle(cardSecondaryText)
                                    .padding(.vertical, 6)
                            } else {
                                ForEach(Array(vm.queueRuns.enumerated()), id: \.element.id) { runIdx, run in
                                    HStack {
                                        Text("第 \(runIdx + 1) 批")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(cardPrimaryText)
                                        Text(run.startedAtText)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(cardSecondaryText)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.top, runIdx == 0 ? 0 : 6)
                                    .id(run.id)

                                    ForEach(Array(run.items.enumerated()), id: \.element.id) { idx, item in
                                        queueRow(index: idx, item: item)
                                    }
                                }
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: vm.queueRuns.last?.id) { _, newID in
                        if let newID {
                            withAnimation { proxy.scrollTo(newID, anchor: .top) }
                        }
                    }
                }
                .frame(height: vm.queueRuns.isEmpty ? 64 : 168)
                .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var logCard: some View {
        Card(
            "实时日志",
            style: cardStyle,
            primaryText: cardPrimaryText,
            secondaryText: cardSecondaryText,
            accessory: AnyView(
                HStack(spacing: 6) {
                    Button {
                        vm.copyLogToPasteboard()
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .disabled(vm.logEntries.isEmpty)
                    Button {
                        vm.clearLogDisplay()
                    } label: {
                        Label("清屏", systemImage: "eraser")
                    }
                    .disabled(vm.logEntries.isEmpty)
                    .help("只清空显示，导出的日志仍然完整")
                }
            )
        ) {
            LogConsoleView(entries: vm.logEntries, textColor: logTextNSColor)
                .frame(minHeight: 220, maxHeight: .infinity)
                .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxHeight: .infinity)
    }

    var body: some View {
        ZStack {
            backgroundView.ignoresSafeArea()
            atmosphereOverlay.ignoresSafeArea()

            VStack(spacing: 10) {
                header

                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 10) {
                        ScrollView(.vertical) {
                            VStack(spacing: 10) {
                                inputCard
                                advancedCard
                                if !vm.showAdvanced {
                                    tipsCard
                                }
                            }
                            .padding(.vertical, 1)
                        }
                        .scrollClipDisabledIfAvailable()
                        .scrollIndicators(.never)

                        actionBar
                    }
                    .frame(width: 460)

                    VStack(spacing: 10) {
                        statusCard
                        queueCard
                        logCard
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(12)
            .tint(accentTint)
            // Every theme except "system" paints a dark background; light
            // system controls (white text fields, pale buttons) clash with it.
            .environment(\.colorScheme, theme == .system ? colorScheme : .dark)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                clearInputFocus()
            })
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
        .sheet(isPresented: $showSitesInfo) {
            SupportedSitesSheet(sites: vm.supportedSites)
        }
        .background(
            WindowSizeEnforcer(
                minWidth: 1040,
                minHeight: 760,
                idealWidth: 1180,
                idealHeight: 880
            )
            .frame(width: 0, height: 0)
        )
        .frame(minWidth: 1040, idealWidth: 1180, minHeight: 760, idealHeight: 880)
    }
}

struct StatusDotLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 7))
                .foregroundStyle(color)
            configuration.title
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard DownloadEngine.live.allObjects.contains(where: { $0.isBusy }) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "仍有下载任务未完成"
        alert.informativeText = "退出会终止当前下载。已下载的页面会保留，下次可从这个网址继续。"
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        for engine in DownloadEngine.live.allObjects {
            engine.shutdownForAppExit()
        }
    }
}

@main
struct BookGetGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
