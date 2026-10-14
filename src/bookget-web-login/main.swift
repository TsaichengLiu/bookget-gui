import AppKit
import Foundation
import PDFKit
import WebKit

struct Args {
    enum Mode {
        case login
        case rbookScrape
        case shanghaiPDFDownload
    }

    var url: URL
    var cookieOut: URL
    var urlOut: URL?
    var userAgent: String
    var mode: Mode = .login
    var outDir: URL? = nil
    var intervalSeconds: Double = 5.0
}

// MARK: - Site registry (sites.json)

/// Site knowledge shared with the GUI and the wrapper. The app bundle ships it
/// as Contents/Resources/sites.json; this helper lives in Resources/bin.
struct SiteRegistry: Decodable {
    struct ReaderURLPatterns: Decodable {
        var contains: [String] = []
        var excludes: [String] = []
    }

    /// One special entry page of a site, e.g. a detail page that needs a rewrite.
    struct Entry: Decodable {
        let adapter: String
        let host: String
        var pathPrefixes: [String]?
        var queryPrefixes: [String]?
        var requiresQuery: Bool?
        var requiresPopup: Bool?
        var entryRewrite: String?
        var downloader: String?
    }

    struct Site: Decodable {
        var id: String?
        let name: String
        var hosts: [String]?
        var pathMarkers: [String]?
        var loginAdapter: String?
        var readerUrlPatterns: ReaderURLPatterns?
        var entries: [Entry]?
    }

    struct Match {
        let site: Site
        let entry: Entry?
    }

    let sites: [Site]

    static let shared: SiteRegistry = load()

    private static func candidatePaths() -> [URL] {
        var result: [URL] = []
        if let env = ProcessInfo.processInfo.environment["BOOKGET_SITES_JSON"], !env.isEmpty {
            result.append(URL(fileURLWithPath: env))
        }
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            let dir = exe.deletingLastPathComponent()
            result.append(dir.deletingLastPathComponent().appendingPathComponent("sites.json"))
            result.append(dir.appendingPathComponent("sites.json"))
        }
        return result
    }

    static func load() -> SiteRegistry {
        for path in candidatePaths() {
            guard let data = try? Data(contentsOf: path) else { continue }
            do {
                return try JSONDecoder().decode(SiteRegistry.self, from: data)
            } catch {
                FileHandle.standardError.write(Data("[bookget-web-login] invalid \(path.path): \(error)\n".utf8))
            }
        }
        return SiteRegistry(sites: [])
    }

    var isEmpty: Bool { sites.isEmpty }

    private static func parse(_ urlString: String) -> URLComponents? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let c = URLComponents(string: trimmed), c.host != nil { return c }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(["#", "%"])) ?? trimmed
        return URLComponents(string: encoded)
    }

    /// Host suffix match: "rbook.ncl.edu.tw" matches itself and "*.rbook.ncl.edu.tw".
    static func hostMatches(_ host: String, _ pattern: String) -> Bool {
        let p = pattern.lowercased()
        return host == p || host.hasSuffix("." + p)
    }

    private static func entryMatches(_ entry: Entry, raw: String, host: String, comps: URLComponents) -> Bool {
        guard hostMatches(host, entry.host) else { return false }
        if entry.requiresQuery == true, !raw.contains("?") { return false }
        if let prefixes = entry.pathPrefixes, !prefixes.isEmpty {
            let path = comps.percentEncodedPath.lowercased()
            guard prefixes.contains(where: { path.hasPrefix($0.lowercased()) }) else { return false }
        }
        if let prefixes = entry.queryPrefixes, !prefixes.isEmpty {
            // Sites like qingarchives percent-encode the "/" inside act=display/...
            let query = (comps.percentEncodedQuery ?? "").lowercased().replacingOccurrences(of: "%2f", with: "/")
            guard prefixes.contains(where: { query.hasPrefix($0.lowercased()) }) else { return false }
        }
        return true
    }

    func match(_ urlString: String) -> Match? {
        guard let comps = Self.parse(urlString), let host = comps.host?.lowercased(), !host.isEmpty else { return nil }
        let path = comps.percentEncodedPath.lowercased()
        var siteOnly: Site?
        for site in sites {
            let hostHit = (site.hosts ?? []).contains { Self.hostMatches(host, $0) }
            let markerHit = (site.pathMarkers ?? []).contains { path.contains($0.lowercased()) }
            guard hostHit || markerHit else { continue }
            if let entry = (site.entries ?? []).first(where: { Self.entryMatches($0, raw: urlString, host: host, comps: comps) }) {
                return Match(site: site, entry: entry)
            }
            if siteOnly == nil { siteOnly = site }
        }
        return siteOnly.map { Match(site: $0, entry: nil) }
    }

    func site(id: String) -> Site? {
        sites.first { $0.id == id }
    }

    /// Key=value lines for the zsh wrapper (`--detect-site`).
    func detectReport(_ urlString: String) -> String {
        let m = match(urlString)
        let e = m?.entry
        return [
            "site=\(m?.site.id ?? "")",
            "adapter=\(e?.adapter ?? "")",
            "requires_popup=\(e?.requiresPopup == true ? 1 : 0)",
            "entry_rewrite=\(e?.entryRewrite ?? "")",
            "downloader=\(e?.downloader ?? "")",
            "login_adapter=\(m?.site.loginAdapter ?? "")",
        ].joined(separator: "\n")
    }
}

// MARK: - Logging / file helpers

private func logError(_ message: String) {
    FileHandle.standardError.write(Data("[bookget-web-login] \(message)\n".utf8))
}

/// URL for logs: query strings and fragments often carry tokens (token=..., ticket=...).
private func redactedURLString(_ url: URL?) -> String {
    guard let url else { return "" }
    guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return url.absoluteString.components(separatedBy: "?").first ?? ""
    }
    let hadQuery = comps.percentEncodedQuery != nil || comps.percentEncodedFragment != nil
    comps.percentEncodedQuery = nil
    comps.percentEncodedFragment = nil
    comps.user = nil
    comps.password = nil
    let base = comps.string ?? ""
    return hadQuery ? base + "?…" : base
}

private func redactedURLString(_ raw: String) -> String {
    if let url = URL(string: raw) { return redactedURLString(url) }
    return raw.components(separatedBy: "?").first ?? ""
}

/// Response bodies for logs: may echo tokens or be huge HTML pages.
private func truncatedForLog(_ data: Data, limit: Int = 200) -> String {
    let text = String(decoding: data.prefix(limit * 4), as: UTF8.self)
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
    return text.count > limit ? String(text.prefix(limit)) + "…" : text
}

/// Writes `data` to `url` with POSIX mode 0600: written to a private temp file in the
/// same directory, then renamed over the destination (replacing e.g. a 0644 mktemp file).
private func writePrivateFile(_ data: Data, to url: URL) throws {
    let fm = FileManager.default
    let dir = url.deletingLastPathComponent()
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
    guard fm.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: tmp.path])
    }
    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
    if rename(tmp.path, url.path) != 0 {
        let err = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        try? fm.removeItem(at: tmp)
        throw err
    }
}

/// Atomically moves `source` over `destination` (same volume).
private func atomicReplace(_ destination: URL, with source: URL) throws {
    if rename(source.path, destination.path) != 0 {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private func fileStartsWithPDFMagic(_ url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    let head = (try? handle.read(upToCount: 4)) ?? Data()
    return head == Data("%PDF".utf8)
}

/// Filename-safe version of page text scraped from a web page (keeps CJK, drops path
/// separators / control characters, limits length).
private func sanitizedPageLabel(_ raw: String, fallback: String) -> String {
    let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
    let mapped = raw.unicodeScalars.map { forbidden.contains($0) ? "_" : String($0) }.joined()
    var trimmed = mapped.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
    if trimmed.count > 60 { trimmed = String(trimmed.prefix(60)) }
    return trimmed.isEmpty ? sanitizedFilenameComponent(fallback) : trimmed
}

private enum InteractiveSiteAdapterKind: String {
    case generic
    case shanghaiLibrary
    case nclRBook

    static func detect(url: URL) -> InteractiveSiteAdapterKind {
        guard let raw = SiteRegistry.shared.match(url.absoluteString)?.site.loginAdapter else { return .generic }
        return InteractiveSiteAdapterKind(rawValue: raw) ?? .generic
    }
}

/// Exit codes: 0 ok, 1 failure, 2 user cancelled (wrapper maps to 130),
/// 3 no login state captured, 64 bad command-line arguments (EX_USAGE).
private let exitBadArguments: Int32 = 64

private func usage(_ msg: String? = nil, code: Int32 = exitBadArguments) -> Never {
    if let msg {
        FileHandle.standardError.write(Data((msg + "\n").utf8))
    }
    let text = """
    Usage:
      bookget-web-login --url <https://...> [--cookie-out <path>] [--url-out <path>] [--ua <user agent>]

      RBook (NCL Taipei) fallback:
      bookget-web-login --rbook-scrape --url <https://rbook.ncl.edu.tw/...SearchDetail...> --out-dir <dir> [--interval <seconds>]

      Shanghai Library pdfview fallback:
      bookget-web-login --shl-download --url <https://dhapi.library.sh.cn/pdfview/?...> --out-dir <dir>

      Site detection from sites.json (key=value lines, used by the bookget wrapper):
      bookget-web-login --detect-site <url>
    """
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(code)
}

private func parseArgs() -> Args {
    var urlString: String?
    var cookieOutPath: String?
    var urlOutPath: String?
    var userAgent: String?
    var mode: Args.Mode = .login
    var outDirPath: String?
    var intervalSeconds: Double = 5.0

    let argv = CommandLine.arguments
    var i = 1
    while i < argv.count {
        let a = argv[i]
        if a == "--help" || a == "-h" {
            usage(code: 0)
        }

        func takeValue() -> String {
            i += 1
            if i >= argv.count { usage("Missing value for \(a)") }
            return argv[i]
        }

        if a == "--url" {
            urlString = takeValue()
        } else if a.hasPrefix("--url=") {
            urlString = String(a.dropFirst("--url=".count))
        } else if a == "--rbook-scrape" || a == "--rbook" {
            mode = .rbookScrape
        } else if a == "--shl-download" || a == "--shanghai-download" {
            mode = .shanghaiPDFDownload
        } else if a == "--out-dir" {
            outDirPath = takeValue()
        } else if a.hasPrefix("--out-dir=") {
            outDirPath = String(a.dropFirst("--out-dir=".count))
        } else if a == "--interval" {
            let raw = takeValue()
            intervalSeconds = Double(raw) ?? intervalSeconds
        } else if a.hasPrefix("--interval=") {
            let raw = String(a.dropFirst("--interval=".count))
            intervalSeconds = Double(raw) ?? intervalSeconds
        } else if a == "--cookie-out" {
            cookieOutPath = takeValue()
        } else if a.hasPrefix("--cookie-out=") {
            cookieOutPath = String(a.dropFirst("--cookie-out=".count))
        } else if a == "--url-out" {
            urlOutPath = takeValue()
        } else if a.hasPrefix("--url-out=") {
            urlOutPath = String(a.dropFirst("--url-out=".count))
        } else if a == "--ua" {
            userAgent = takeValue()
        } else if a.hasPrefix("--ua=") {
            userAgent = String(a.dropFirst("--ua=".count))
        } else {
            usage("Unknown arg: \(a)")
        }
        i += 1
    }

    guard let urlString, let url = URL(string: urlString) else {
        usage("Invalid or missing --url")
    }
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
          let host = url.host, !host.isEmpty else {
        usage("Invalid URL host: \(redactedURLString(url))")
    }

    let cookieOutURL: URL
    if let cookieOutPath, !cookieOutPath.isEmpty {
        cookieOutURL = URL(fileURLWithPath: cookieOutPath)
    } else {
        let fn = "bookget_auto_cookie_wk_\(UUID().uuidString).txt"
        cookieOutURL = FileManager.default.temporaryDirectory.appendingPathComponent(fn)
    }

    let urlOutURL: URL?
    if let urlOutPath, !urlOutPath.isEmpty {
        urlOutURL = URL(fileURLWithPath: urlOutPath)
    } else {
        urlOutURL = nil
    }

    let ua = userAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalUA = (ua?.isEmpty == false)
        ? ua!
        : "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36"

    let outDirURL: URL? = {
        guard let outDirPath, !outDirPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return URL(fileURLWithPath: outDirPath)
    }()

    return Args(
        url: url,
        cookieOut: cookieOutURL,
        urlOut: urlOutURL,
        userAgent: finalUA,
        mode: mode,
        outDir: outDirURL,
        intervalSeconds: max(0.5, intervalSeconds)
    )
}

private struct ShanghaiPDFViewContext {
    let dbname: String
    let doi: String?
    let type: String?
    let idvalue: String?
    let innerflag: String?
    let token: String
}

private struct ShanghaiInfoResponse: Decodable {
    struct Payload: Decodable {
        struct Item: Decodable {
            let value: String
            let name: String?
            let pageCount: Int
        }

        let items: [Item]
    }

    let state: Int
    let msg: String?
    let data: Payload?
}

private struct ShanghaiInfoRequestByIDValue: Encodable {
    let dbname: String
    let type: String
    let idvalue: String
}

private struct ShanghaiInfoRequestByDOI: Encodable {
    let dbname: String
    let doi: String
}

private struct ShanghaiStreamRequest: Encodable {
    let dbname: String
    let innerflag: String?
    let itemId: String
    let pageNo: Int
}

private enum ShanghaiDownloadError: LocalizedError {
    case invalidReaderURL(String)
    case missingOutDir
    case missingInfoParameters
    case infoRequestFailed(String)
    case streamRequestFailed(String)
    case invalidPagePDF(Int)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidReaderURL(let url):
            return "invalid Shanghai reader URL: \(redactedURLString(url))"
        case .missingOutDir:
            return "missing --out-dir for Shanghai Library download"
        case .missingInfoParameters:
            return "missing Shanghai Library info parameters"
        case .infoRequestFailed(let message):
            return "Shanghai Library info request failed: \(message)"
        case .streamRequestFailed(let message):
            return "Shanghai Library stream request failed: \(message)"
        case .invalidPagePDF(let page):
            return "Shanghai Library returned an invalid PDF for page \(page)"
        case .writeFailed(let path):
            return "failed to write Shanghai Library output: \(path)"
        }
    }
}

private func parseShanghaiPDFViewContext(from url: URL) -> ShanghaiPDFViewContext? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          (components.host ?? "").lowercased().contains("dhapi.library.sh.cn"),
          components.path.lowercased().contains("/pdfview") else {
        return nil
    }

    let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    guard let dbname = items["dbname"], !dbname.isEmpty,
          let token = items["token"], !token.isEmpty else {
        return nil
    }

    let doi = items["doi"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    let type = items["type"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    let idvalue = items["idvalue"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    let innerflag = items["innerflag"]?.trimmingCharacters(in: .whitespacesAndNewlines)

    return ShanghaiPDFViewContext(
        dbname: dbname,
        doi: doi?.isEmpty == false ? doi : nil,
        type: type?.isEmpty == false ? type : nil,
        idvalue: idvalue?.isEmpty == false ? idvalue : nil,
        innerflag: innerflag?.isEmpty == false ? innerflag : nil,
        token: token
    )
}

private func sanitizedFilenameComponent(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "item" }

    let mapped = trimmed.map { ch -> Character in
        switch ch {
        case "a"..."z", "A"..."Z", "0"..."9", "-", "_", ".":
            return ch
        default:
            return "_"
        }
    }
    let collapsed = String(mapped).replacingOccurrences(of: "_{2,}", with: "_", options: .regularExpression)
    let final = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
    return final.isEmpty ? "item" : final
}

private func makeShanghaiAPIRequest(
    url: URL,
    token: String,
    userAgent: String,
    queryItems: [URLQueryItem] = [],
    jsonBody: Data
) throws -> (Data, HTTPURLResponse) {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    if !queryItems.isEmpty {
        components?.queryItems = queryItems
    }
    guard let finalURL = components?.url else {
        throw ShanghaiDownloadError.invalidReaderURL(url.absoluteString)
    }

    var request = URLRequest(url: finalURL)
    request.httpMethod = "POST"
    request.httpBody = jsonBody
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: "token")
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 60

    let maxRetries = 3
    var retry = 0
    while true {
        do {
            let (data, response) = try performSynchronousRequest(request)
            let status = response.statusCode
            if (status == 429 || (500...599).contains(status)) && retry < maxRetries {
                retry += 1
                let delay = shanghaiRetryDelay(retry: retry, response: response)
                logError("shl HTTP \(status) from \(redactedURLString(finalURL)), retry \(retry)/\(maxRetries) in \(Int(delay))s")
                Thread.sleep(forTimeInterval: delay)
                continue
            }
            return (data, response)
        } catch {
            if retry < maxRetries && isRetryableNetworkError(error) {
                retry += 1
                let delay = shanghaiRetryDelay(retry: retry, response: nil)
                logError("shl network error (\((error as NSError).localizedDescription)), retry \(retry)/\(maxRetries) in \(Int(delay))s")
                Thread.sleep(forTimeInterval: delay)
                continue
            }
            throw error
        }
    }
}

private func performSynchronousRequest(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
    let semaphore = DispatchSemaphore(value: 0)
    var responseData = Data()
    var responseError: Error?
    var httpResponse: HTTPURLResponse?

    URLSession.shared.dataTask(with: request) { data, response, error in
        responseData = data ?? Data()
        responseError = error
        httpResponse = response as? HTTPURLResponse
        semaphore.signal()
    }.resume()

    semaphore.wait()

    if let responseError {
        throw responseError
    }
    guard let httpResponse else {
        throw ShanghaiDownloadError.streamRequestFailed("missing HTTP response")
    }
    return (responseData, httpResponse)
}

private func isRetryableNetworkError(_ error: Error) -> Bool {
    let nsError = error as NSError
    guard nsError.domain == NSURLErrorDomain else { return false }
    switch nsError.code {
    case NSURLErrorCancelled, NSURLErrorBadURL, NSURLErrorUnsupportedURL,
         NSURLErrorUserAuthenticationRequired, NSURLErrorUserCancelledAuthentication:
        return false
    default:
        return true
    }
}

/// Exponential backoff (2s, 4s, 8s); honours a short Retry-After header.
private func shanghaiRetryDelay(retry: Int, response: HTTPURLResponse?) -> TimeInterval {
    if let raw = response?.value(forHTTPHeaderField: "Retry-After"),
       let seconds = Double(raw.trimmingCharacters(in: .whitespaces)), seconds > 0 {
        return min(seconds, 30)
    }
    return pow(2.0, Double(retry))
}

private func downloadShanghaiLibraryPDFView(args: Args) throws {
    guard let outDir = args.outDir else {
        throw ShanghaiDownloadError.missingOutDir
    }
    let context = try parseShanghaiPDFViewContext(from: args.url)
        .unwrap(or: ShanghaiDownloadError.invalidReaderURL(args.url.absoluteString))

    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let infoURL = URL(string: "https://dhapi.library.sh.cn/service_pdf/pdf/info")!
    let infoBody: Data = {
        if let doi = context.doi {
            return try! JSONEncoder().encode(ShanghaiInfoRequestByDOI(dbname: context.dbname, doi: doi))
        }
        guard let type = context.type, !type.isEmpty,
              let idvalue = context.idvalue, !idvalue.isEmpty else {
            return Data()
        }
        return try! JSONEncoder().encode(ShanghaiInfoRequestByIDValue(dbname: context.dbname, type: type, idvalue: idvalue))
    }()
    if infoBody.isEmpty {
        throw ShanghaiDownloadError.missingInfoParameters
    }

    let (infoData, infoResponse) = try makeShanghaiAPIRequest(
        url: infoURL,
        token: context.token,
        userAgent: args.userAgent,
        queryItems: [URLQueryItem(name: "dbname", value: context.dbname)],
        jsonBody: infoBody
    )
    guard (200..<300).contains(infoResponse.statusCode) else {
        throw ShanghaiDownloadError.infoRequestFailed("HTTP \(infoResponse.statusCode): \(truncatedForLog(infoData))")
    }

    let info = try JSONDecoder().decode(ShanghaiInfoResponse.self, from: infoData)
    guard info.state == 0, let payload = info.data, !payload.items.isEmpty else {
        throw ShanghaiDownloadError.infoRequestFailed(info.msg.map { truncatedForLog(Data($0.utf8)) } ?? "empty item list")
    }

    FileHandle.standardError.write(Data("[bookget-web-login] shl info loaded: \(payload.items.count) item(s)\n".utf8))

    let streamURL = URL(string: "https://dhapi.library.sh.cn/service_pdf/pdf/stream")!
    let safeBase = sanitizedFilenameComponent(context.idvalue ?? context.doi ?? context.dbname)

    for (itemIndex, item) in payload.items.enumerated() {
        let safeItemName = sanitizedFilenameComponent(item.name ?? "item_\(itemIndex + 1)")
        let fileName = payload.items.count == 1
            ? "shl_\(safeBase).pdf"
            : "shl_\(safeBase)_\(safeItemName)_\(itemIndex + 1).pdf"
        let outURL = outDir.appendingPathComponent(fileName)
        let partialURL = outDir.appendingPathComponent(fileName.replacingOccurrences(of: ".pdf", with: ".partial.pdf"))
        let pagesDir = outDir.appendingPathComponent(fileName.replacingOccurrences(of: ".pdf", with: ".pages"), isDirectory: true)

        guard item.pageCount > 0 else {
            logError("shl item \(itemIndex + 1)/\(payload.items.count): \(safeItemName) reports 0 pages, skipped")
            continue
        }
        if fileStartsWithPDFMagic(outURL) {
            logError("shl item \(itemIndex + 1)/\(payload.items.count): \(outURL.lastPathComponent) already exists, skipped")
            continue
        }

        try FileManager.default.createDirectory(at: pagesDir, withIntermediateDirectories: true)

        func pageCacheURL(_ pageNo: Int) -> URL {
            pagesDir.appendingPathComponent(String(format: "%04d.pdf", pageNo))
        }

        func fileExistsAndNonEmpty(_ url: URL) -> Bool {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? NSNumber else {
                return false
            }
            return size.intValue > 0
        }

        /// Merges cached page PDFs into a temp file next to `finalURL`, then renames it
        /// into place so an interrupted merge never leaves a truncated PDF behind.
        func mergeCachedPages(into finalURL: URL) throws -> Int {
            let destinationURL = finalURL.deletingLastPathComponent()
                .appendingPathComponent(".\(finalURL.lastPathComponent).\(UUID().uuidString).tmp")
            defer { try? FileManager.default.removeItem(at: destinationURL) }
            var merged = PDFDocument()
            var appendedPages = 0

            func compactMergedDocumentIfNeeded(force: Bool = false) throws {
                guard merged.pageCount > 0 else { return }
                if !force && appendedPages % 25 != 0 && appendedPages != item.pageCount {
                    return
                }
                guard merged.write(to: destinationURL) else {
                    throw ShanghaiDownloadError.writeFailed(destinationURL.path)
                }
                if let reopened = PDFDocument(url: destinationURL) {
                    merged = reopened
                }
            }

            for pageNo in 1...item.pageCount {
                let cachedURL = pageCacheURL(pageNo)
                guard fileExistsAndNonEmpty(cachedURL) else { break }

                let addedFromCurrentFile: Int = try autoreleasepool {
                    guard let pageDocument = PDFDocument(url: cachedURL), pageDocument.pageCount > 0 else {
                        throw ShanghaiDownloadError.invalidPagePDF(pageNo)
                    }
                    let count = pageDocument.pageCount
                    for idx in 0..<count {
                        if let page = pageDocument.page(at: idx) {
                            merged.insert(page, at: merged.pageCount)
                        }
                    }
                    return count
                }

                appendedPages += addedFromCurrentFile
                try compactMergedDocumentIfNeeded()
            }

            try compactMergedDocumentIfNeeded(force: true)
            if appendedPages > 0 {
                try atomicReplace(finalURL, with: destinationURL)
            }
            return appendedPages
        }

        FileHandle.standardError.write(Data("[bookget-web-login] shl item \(itemIndex + 1)/\(payload.items.count): \(safeItemName) (\(item.pageCount) pages)\n".utf8))

        do {
            for pageNo in 1...item.pageCount {
                let cachedURL = pageCacheURL(pageNo)
                if fileExistsAndNonEmpty(cachedURL) {
                    FileHandle.standardError.write(Data("[bookget-web-login] shl reused \(pageNo)/\(item.pageCount)\n".utf8))
                    continue
                }

                let streamBody = try JSONEncoder().encode(ShanghaiStreamRequest(
                    dbname: context.dbname,
                    innerflag: context.innerflag,
                    itemId: item.value,
                    pageNo: pageNo
                ))
                let (pageData, pageResponse) = try makeShanghaiAPIRequest(
                    url: streamURL,
                    token: context.token,
                    userAgent: args.userAgent,
                    jsonBody: streamBody
                )
                guard (200..<300).contains(pageResponse.statusCode) else {
                    throw ShanghaiDownloadError.streamRequestFailed("HTTP \(pageResponse.statusCode): \(truncatedForLog(pageData))")
                }
                let isValidPage = try autoreleasepool { () throws -> Bool in
                    guard let pageDocument = PDFDocument(data: pageData), pageDocument.pageCount > 0 else {
                        throw ShanghaiDownloadError.invalidPagePDF(pageNo)
                    }
                    return true
                }
                guard isValidPage else {
                    throw ShanghaiDownloadError.invalidPagePDF(pageNo)
                }
                try pageData.write(to: cachedURL, options: [.atomic])
                FileHandle.standardError.write(Data("[bookget-web-login] shl saved \(pageNo)/\(item.pageCount)\n".utf8))
            }
        } catch {
            let partialPages = (try? mergeCachedPages(into: partialURL)) ?? 0
            if partialPages > 0 {
                FileHandle.standardError.write(Data("[bookget-web-login] shl partial output: \(partialURL.lastPathComponent) (\(partialPages) pages cached)\n".utf8))
            }
            throw error
        }

        _ = try mergeCachedPages(into: outURL)
        try? FileManager.default.removeItem(at: partialURL)
        try? FileManager.default.removeItem(at: pagesDir)
        FileHandle.standardError.write(Data("[bookget-web-login] shl output: \(outURL.lastPathComponent)\n".utf8))
    }
}

private extension Optional {
    func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
        guard let value = self else { throw error() }
        return value
    }
}

private func sanitizeCookieField(_ s: String) -> String {
    var out = s
    out = out.replacingOccurrences(of: "\t", with: " ")
    out = out.replacingOccurrences(of: "\r", with: " ")
    out = out.replacingOccurrences(of: "\n", with: " ")
    return out
}

private func cookieMatchesHost(cookie: HTTPCookie, host: String) -> Bool {
    let hostLC = host.lowercased()
    var domain = cookie.domain.lowercased()
    if domain.hasPrefix(".") {
        domain.removeFirst()
    }
    if domain.isEmpty { return false }
    return hostLC == domain || hostLC.hasSuffix("." + domain)
}

private func cookieMatchesParentDomain(cookie: HTTPCookie, parentDomain: String) -> Bool {
    let parentLC = parentDomain.lowercased()
    var domain = cookie.domain.lowercased()
    if domain.hasPrefix(".") {
        domain.removeFirst()
    }
    if domain.isEmpty { return false }
    return domain == parentLC || domain.hasSuffix("." + parentLC)
}

private func normalizeHTMLForURLScan(_ html: String) -> String {
    var out = html
    // Common JSON/HTML escaping patterns used inside script blocks and attributes.
    out = out.replacingOccurrences(of: "\\/", with: "/")
    out = out.replacingOccurrences(of: "\\u002F", with: "/")
    out = out.replacingOccurrences(of: "\\u002f", with: "/")
    out = out.replacingOccurrences(of: "\\u0026", with: "&")
    out = out.replacingOccurrences(of: "\\u003d", with: "=")
    out = out.replacingOccurrences(of: "&amp;", with: "&")
    return out
}

private func regexMatches(in text: String, pattern: String, options: NSRegularExpression.Options = [], limit: Int = 50) -> [String] {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    let matches = re.matches(in: text, options: [], range: range)
    if matches.isEmpty { return [] }
    var out: [String] = []
    out.reserveCapacity(min(matches.count, limit))
    for m in matches {
        if m.numberOfRanges < 1 { continue }
        let r = m.range(at: 0)
        guard r.location != NSNotFound, r.length > 0 else { continue }
        out.append(ns.substring(with: r))
        if out.count >= limit { break }
    }
    return out
}

private func normalizeCandidateURLString(_ raw: String, baseURL: URL) -> String? {
    var v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if v.isEmpty { return nil }
    v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    v = v.replacingOccurrences(of: "\\/", with: "/")
    v = v.replacingOccurrences(of: "\\u002F", with: "/")
    v = v.replacingOccurrences(of: "\\u002f", with: "/")
    v = v.replacingOccurrences(of: "\\u0026", with: "&")
    v = v.replacingOccurrences(of: "\\u003d", with: "=")
    v = v.replacingOccurrences(of: "&amp;", with: "&")

    if v.hasPrefix("http://") || v.hasPrefix("https://") {
        return v
    }
    if v.hasPrefix("//") {
        let scheme = baseURL.scheme ?? "https"
        return scheme + ":" + v
    }
    // Handle "book/book/view.do" (missing leading slash).
    if !v.hasPrefix("/") {
        v = "/" + v
    }
    guard let abs = URL(string: v, relativeTo: baseURL)?.absoluteURL else { return nil }
    return abs.absoluteString
}

private func bestDownloadURLFromHTML(_ html: String, baseURL: URL) -> String? {
    let normalized = normalizeHTMLForURLScan(html)
    var rawCandidates: [String] = []
    rawCandidates.reserveCapacity(64)

    // Prefer viewer-style links first.
    rawCandidates.append(contentsOf: regexMatches(
        in: normalized,
        pattern: #"https?://[^"' \t\r\n<>]*view\.do[^"' \t\r\n<>]*"#,
        options: [.caseInsensitive],
        limit: 50
    ))
    rawCandidates.append(contentsOf: regexMatches(
        in: normalized,
        pattern: #"(?:/)?(?:zh-tw/)?book/book/view\.do[^"' \t\r\n<>]*"#,
        options: [.caseInsensitive],
        limit: 50
    ))

    // IIIF candidates (some sites embed manifests instead of view.do).
    rawCandidates.append(contentsOf: regexMatches(
        in: normalized,
        pattern: #"https?://[^"' \t\r\n<>]*(?:manifest\.json|/manifest\b|:manifest)[^"' \t\r\n<>]*"#,
        options: [.caseInsensitive],
        limit: 50
    ))
    rawCandidates.append(contentsOf: regexMatches(
        in: normalized,
        pattern: #"/[^"' \t\r\n<>]*(?:manifest\.json|/manifest\b)[^"' \t\r\n<>]*"#,
        options: [.caseInsensitive],
        limit: 50
    ))
    rawCandidates.append(contentsOf: regexMatches(
        in: normalized,
        pattern: #"https?://[^"' \t\r\n<>]*(?:stgj2021/(?:book_view|book_page)/[^"' \t\r\n<>]*|pdfview(?:[/?#][^"' \t\r\n<>]*)?)"#,
        options: [.caseInsensitive],
        limit: 50
    ))
    rawCandidates.append(contentsOf: regexMatches(
        in: normalized,
        pattern: #"/[^"' \t\r\n<>]*(?:stgj2021/(?:book_view|book_page)/[^"' \t\r\n<>]*|pdfview(?:[/?#][^"' \t\r\n<>]*)?)"#,
        options: [.caseInsensitive],
        limit: 50
    ))

    if rawCandidates.isEmpty { return nil }

    var absCandidates: [String] = []
    absCandidates.reserveCapacity(rawCandidates.count)
    var seen = Set<String>()
    for raw in rawCandidates {
        guard let abs = normalizeCandidateURLString(raw, baseURL: baseURL) else { continue }
        if abs.count > 4096 { continue }
        let lc = abs.lowercased()
        if lc.contains("/pdfview/assets/") || lc.hasSuffix(".js") || lc.hasSuffix(".css") || lc.hasSuffix(".map") {
            continue
        }
        if seen.contains(abs) { continue }
        seen.insert(abs)
        absCandidates.append(abs)
        if absCandidates.count >= 80 { break }
    }
    if absCandidates.isEmpty { return nil }

    func score(_ url: String) -> Int {
        let lc = url.lowercased()
        var s = 0
        if lc.contains("taiwanebook.ncl.edu.tw") { s += 50 }
        if lc.contains("library.sh.cn") { s += 40 }
        if lc.contains("ncl.edu.tw") { s += 20 }
        if lc.contains("/stgj2021/book_view/") { s += 28 }
        if lc.contains("/stgj2021/book_page/") { s += 24 }
        if lc.contains("pdfview") { s += 20 }
        if lc.contains("view.do") { s += 12 }
        if lc.contains("manifest") { s += 10 }
        if lc.contains("iiif") { s += 4 }
        if lc.contains("searchdetail") { s -= 30 }
        return s
    }

    return absCandidates.max { score($0) < score($1) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKUIDelegate, WKNavigationDelegate {
    private let targetURL: URL
    private let targetHost: String
    private let cookieOutURL: URL
    private let urlOutURL: URL?
    private let userAgent: String
    private let mode: Args.Mode
    private let siteAdapter: InteractiveSiteAdapterKind
    private let outDir: URL?
    private let intervalSeconds: Double

    private var window: NSWindow!
    private var rootView: NSView!
    private var webView: WKWebView!
    /// Hidden 1x1 view returned to WebKit for window.open()/target=_blank; its first real
    /// navigation is redirected into the main view.
    private var popupBridgeWebView: WKWebView?
    /// Real child windows for OAuth/QR-login popups that rely on window.opener.
    private var popupWindows: [(webView: WKWebView, window: NSWindow)] = []
    private var urlField: NSTextField!
    private var doneButton: NSButton!
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var loadingSpinner: NSProgressIndicator!
    private var statusSpinner: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var observations: [NSKeyValueObservation] = []
    private var contentProcessReloads: [ObjectIdentifier: Int] = [:]
    private static let maxContentProcessReloads = 3
    private var isCompleting = false
    private var isScraping = false
    private var lastMeaningfulShanghaiLibraryReaderURL: String?

    // rbook scrape state
    private static let maxScrapeNoProgress = 20
    private var scrapeNoProgressCount = 0
    private var lastSavedPageLabel: String?
    private var savedPageCount = 0
    private var progressPanel: NSPanel?
    private var progressLabel: NSTextField?
    private var progressBar: NSProgressIndicator?

    private static let captureMeaningfulURLScript = #"""
    (function() {
      function normalize(url, base) {
        try {
          return new URL(url || window.location.href, base || window.location.href).toString();
        } catch (e) {
          return "";
        }
      }
      function save(url) {
        var abs = normalize(url, window.location.href);
        if (!abs) return;
        try { window.__bookgetOriginalURL = window.__bookgetOriginalURL || abs; } catch (e) {}
        try { window.__bookgetLastMeaningfulURL = abs; } catch (e) {}
      }
      save(window.location.href);
      var origReplace = history.replaceState ? history.replaceState.bind(history) : null;
      if (origReplace) {
        history.replaceState = function(state, title, url) {
          try {
            if (window.location.search) {
              save(window.location.href);
            } else if (typeof url === "string" && url.indexOf("?") !== -1) {
              save(url);
            }
          } catch (e) {}
          return origReplace(state, title, url);
        };
      }
      var origPush = history.pushState ? history.pushState.bind(history) : null;
      if (origPush) {
        history.pushState = function(state, title, url) {
          try {
            if (typeof url === "string" && url.indexOf("?") !== -1) {
              save(url);
            } else {
              save(window.location.href);
            }
          } catch (e) {}
          return origPush(state, title, url);
        };
      }
      window.addEventListener("beforeunload", function() {
        try {
          if (window.location.search) save(window.location.href);
        } catch (e) {}
      }, true);
    })();
    """#

    init(args: Args) {
        self.targetURL = args.url
        self.targetHost = args.url.host ?? ""
        self.cookieOutURL = args.cookieOut
        self.urlOutURL = args.urlOut
        self.userAgent = args.userAgent
        self.mode = args.mode
        self.siteAdapter = InteractiveSiteAdapterKind.detect(url: args.url)
        self.outDir = args.outDir
        self.intervalSeconds = args.intervalSeconds
        super.init()
    }

    private var shanghaiLibraryReaderPatterns: SiteRegistry.ReaderURLPatterns {
        SiteRegistry.shared.site(id: "shanghai-library")?.readerUrlPatterns ?? SiteRegistry.ReaderURLPatterns()
    }

    private func isShanghaiLibraryReaderURL(_ urlString: String) -> Bool {
        let lc = urlString.lowercased()
        if lc.hasSuffix(".js") || lc.hasSuffix(".css") || lc.hasSuffix(".map") {
            return false
        }
        let patterns = shanghaiLibraryReaderPatterns
        if patterns.excludes.contains(where: { lc.contains($0.lowercased()) }) {
            return false
        }
        return patterns.contains.contains { lc.contains($0.lowercased()) }
    }

    private func rememberMeaningfulShanghaiLibraryReaderURL(_ url: URL?) {
        guard let url else { return }
        let abs = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !abs.isEmpty, isShanghaiLibraryReaderURL(abs), abs.contains("?") else { return }
        lastMeaningfulShanghaiLibraryReaderURL = abs
    }

    private func makeBrowserConfiguration(from provided: WKWebViewConfiguration? = nil) -> WKWebViewConfiguration {
        let config = provided ?? WKWebViewConfiguration()
        if provided == nil {
            config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        }
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(macOS 11.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        let hasCaptureScript = config.userContentController.userScripts.contains {
            $0.source == Self.captureMeaningfulURLScript
        }
        if !hasCaptureScript {
            let captureScript = WKUserScript(
                source: Self.captureMeaningfulURLScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(captureScript)
        }
        return config
    }

    private func isBlankPopupURL(_ url: URL?) -> Bool {
        guard let url else { return true }
        let value = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty { return true }
        return value == "about:blank" || value == "about:srcdoc" || value.hasPrefix("javascript:")
    }

    /// OAuth / QR-login popups usually talk back to window.opener, so they need a real
    /// child window instead of being redirected into the main view.
    private func isAuthPopupURL(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased(), !host.isEmpty else { return false }
        return ["login", "oauth", "sso", "passport", "auth"].contains { host.contains($0) }
    }

    private func loadRequestInMainWebView(_ request: URLRequest) {
        rememberMeaningfulShanghaiLibraryReaderURL(request.url)
        if let abs = request.url?.absoluteString, !abs.isEmpty {
            urlField.stringValue = abs
        }
        webView.load(request)
    }

    private func removePopupBridge() {
        guard let bridge = popupBridgeWebView else { return }
        bridge.stopLoading()
        bridge.uiDelegate = nil
        bridge.navigationDelegate = nil
        bridge.removeFromSuperview()
        popupBridgeWebView = nil
    }

    /// WebKit requires the returned view to be created with the configuration it passes,
    /// so a fresh bridge is built for every popup (the previous one is discarded).
    private func makePopupBridgeView(with configuration: WKWebViewConfiguration) -> WKWebView {
        removePopupBridge()

        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.customUserAgent = userAgent
        popup.uiDelegate = self
        popup.navigationDelegate = self
        popup.isHidden = true
        popup.alphaValue = 0
        popupBridgeWebView = popup
        rootView.addSubview(popup)
        NSLayoutConstraint.activate([
            popup.widthAnchor.constraint(equalToConstant: 1),
            popup.heightAnchor.constraint(equalToConstant: 1),
            popup.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            popup.topAnchor.constraint(equalTo: rootView.topAnchor),
        ])
        return popup
    }

    private func makePopupWindow(with configuration: WKWebViewConfiguration, windowFeatures: WKWindowFeatures?) -> WKWebView {
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.customUserAgent = userAgent
        popup.uiDelegate = self
        popup.navigationDelegate = self
        presentPopupWindow(for: popup, windowFeatures: windowFeatures)
        return popup
    }

    /// Shows `popup` in its own child window (used for new auth popups, and to promote a
    /// hidden bridge view whose first navigation turned out to be an auth host).
    private func presentPopupWindow(for popup: WKWebView, windowFeatures: WKWindowFeatures?) {
        if popup === popupBridgeWebView {
            popup.removeFromSuperview()
            popupBridgeWebView = nil
            popup.isHidden = false
            popup.alphaValue = 1
        }
        popup.translatesAutoresizingMaskIntoConstraints = true
        popup.autoresizingMask = [.width, .height]

        let width = CGFloat(windowFeatures?.width?.doubleValue ?? 520)
        let height = CGFloat(windowFeatures?.height?.doubleValue ?? 640)
        let child = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: max(320, width), height: max(320, height)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        child.title = "登录窗口 (BookGet)"
        child.isReleasedWhenClosed = false
        child.delegate = self
        popup.frame = child.contentLayoutRect
        child.contentView = popup
        if let parent = window {
            let pf = parent.frame
            child.setFrameOrigin(NSPoint(x: pf.midX - child.frame.width / 2, y: pf.midY - child.frame.height / 2))
        } else {
            child.center()
        }
        popupWindows.append((webView: popup, window: child))
        child.makeKeyAndOrderFront(nil)
    }

    private func popupWindowEntry(for webView: WKWebView) -> (webView: WKWebView, window: NSWindow)? {
        popupWindows.first { $0.webView === webView }
    }

    private func webViewRole(_ webView: WKWebView) -> String {
        if webView === self.webView {
            return "main"
        }
        if let popupBridgeWebView, webView === popupBridgeWebView {
            return "popup"
        }
        if popupWindowEntry(for: webView) != nil {
            return "popup-window"
        }
        return "unknown"
    }

    private func logNavigationError(_ error: Error, role: String, stage: String, failingURL: URL?) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        let urlText = redactedURLString(failingURL ?? targetURL)
        FileHandle.standardError.write(Data("[bookget-web-login] \(role) webview \(stage) failed: \(urlText) (\(nsError.localizedDescription))\n".utf8))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if targetHost.isEmpty {
            FileHandle.standardError.write(Data(("Invalid URL host: \(redactedURLString(targetURL))\n").utf8))
            exit(exitBadArguments)
        }

        // Keep the temporary login/scrape helper out of the Dock.
        // It still shows its window, but behaves like an "agent" app.
        NSApp.setActivationPolicy(.accessory)

        let rect = NSRect(x: 0, y: 0, width: 1100, height: 720)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = (mode == .rbookScrape ? "国图下载 (BookGet) - \(targetHost)" : "弹窗浏览器 (BookGet) - \(targetHost)")
        window.subtitle = targetHost
        window.center()
        window.delegate = self

        rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = rootView

        let instructionText: String = {
            if mode == .rbookScrape {
                return "请在此窗口完成验证码/登录，然后点击“开始下载”（⌘↩）。下载期间请勿关闭本窗口，进度会显示在单独的小窗口中，可随时取消。"
            }
            if siteAdapter == .shanghaiLibrary {
                return "请在此弹窗浏览器中完成登录/验证码。若页面有“查看全文/阅读/在线阅读”等按钮，请先点击进入阅读页（新窗口会被自动接管到本窗口），再点击“完成”（⌘↩）。"
            }
            return "请在此弹窗浏览器中完成登录/验证码。若页面有“阅读/在线阅读”等按钮，请先点击进入阅读页（新窗口会被自动接管到本窗口），再点击“完成”（⌘↩），窗口会关闭并继续下载。"
        }()
        let instruction = NSTextField(wrappingLabelWithString: instructionText)
        instruction.translatesAutoresizingMaskIntoConstraints = false
        instruction.font = NSFont.systemFont(ofSize: 13)
        instruction.textColor = .secondaryLabelColor
        instruction.maximumNumberOfLines = 0
        instruction.setContentCompressionResistancePriority(.required, for: .vertical)
        instruction.setContentHuggingPriority(.defaultLow, for: .horizontal)

        func toolbarButton(_ symbol: String, _ fallback: String, _ tip: String, _ action: Selector) -> NSButton {
            let button: NSButton
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip) {
                button = NSButton(image: image, target: self, action: action)
            } else {
                button = NSButton(title: fallback, target: self, action: action)
            }
            button.translatesAutoresizingMaskIntoConstraints = false
            button.bezelStyle = .texturedRounded
            button.toolTip = tip
            return button
        }
        backButton = toolbarButton("chevron.left", "后退", "后退", #selector(onGoBack))
        forwardButton = toolbarButton("chevron.right", "前进", "前进", #selector(onGoForward))
        let reloadButton = toolbarButton("arrow.clockwise", "刷新", "刷新", #selector(onReload))
        backButton.isEnabled = false
        forwardButton.isEnabled = false

        urlField = NSTextField(string: targetURL.absoluteString)
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.font = NSFont.systemFont(ofSize: 12)
        urlField.placeholderString = "粘贴网址后回车"
        urlField.lineBreakMode = .byTruncatingMiddle
        urlField.usesSingleLineMode = true
        urlField.target = self
        urlField.action = #selector(onGoToURL)

        loadingSpinner = NSProgressIndicator()
        loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        loadingSpinner.style = .spinning
        loadingSpinner.controlSize = .small
        loadingSpinner.isDisplayedWhenStopped = false
        loadingSpinner.toolTip = "页面加载中"

        let go = NSButton(title: "前往", target: self, action: #selector(onGoToURL))
        go.translatesAutoresizingMaskIntoConstraints = false

        let backToStart = NSButton(title: "回到起始页", target: self, action: #selector(onBackToStart))
        backToStart.translatesAutoresizingMaskIntoConstraints = false

        let urlBar = NSStackView(views: [backButton, forwardButton, reloadButton, urlField, loadingSpinner, go, backToStart])
        urlBar.translatesAutoresizingMaskIntoConstraints = false
        urlBar.orientation = .horizontal
        urlBar.spacing = 8
        urlBar.alignment = .centerY

        let config = makeBrowserConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.customUserAgent = userAgent
        webView.uiDelegate = self
        webView.navigationDelegate = self
        observeMainWebView()

        let doneTitle = (mode == .rbookScrape ? "开始下载" : "完成")
        doneButton = NSButton(title: doneTitle, target: self, action: #selector(onDone))
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        // Plain Return would fire while typing into login forms; require ⌘↩.
        doneButton.keyEquivalent = "\r"
        doneButton.keyEquivalentModifierMask = [.command]
        doneButton.toolTip = "\(doneTitle)（⌘↩）"

        let cancel = NSButton(title: "取消", target: self, action: #selector(onCancel))
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.keyEquivalent = "\u{1b}"

        let buttonRow = NSStackView(views: [cancel, doneButton])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12
        buttonRow.alignment = .centerY

        statusSpinner = NSProgressIndicator()
        statusSpinner.translatesAutoresizingMaskIntoConstraints = false
        statusSpinner.style = .spinning
        statusSpinner.controlSize = .small
        statusSpinner.isDisplayedWhenStopped = false

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let statusRow = NSStackView(views: [statusSpinner, statusLabel])
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusRow.orientation = .horizontal
        statusRow.spacing = 6
        statusRow.alignment = .centerY

        rootView.addSubview(instruction)
        rootView.addSubview(urlBar)
        rootView.addSubview(webView)
        rootView.addSubview(statusRow)
        rootView.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            instruction.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 12),
            instruction.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 12),
            instruction.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -12),

            urlBar.topAnchor.constraint(equalTo: instruction.bottomAnchor, constant: 10),
            urlBar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 12),
            urlBar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -12),

            buttonRow.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -12),
            buttonRow.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -12),

            statusRow.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 12),
            statusRow.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            statusRow.trailingAnchor.constraint(lessThanOrEqualTo: buttonRow.leadingAnchor, constant: -12),

            urlField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),

            webView.topAnchor.constraint(equalTo: urlBar.bottomAnchor, constant: 10),
            webView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -10),
        ])

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.load(URLRequest(url: targetURL))
    }

    /// Keeps the address bar, title, navigation buttons and loading indicator in sync,
    /// including client-side (pushState) URL changes that never fire didFinish.
    private func observeMainWebView() {
        observations = [
            webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    guard let self, let url = webView.url else { return }
                    self.rememberMeaningfulShanghaiLibraryReaderURL(url)
                    // Don't clobber what the user is typing.
                    if self.urlField.currentEditor() == nil {
                        self.urlField.stringValue = url.absoluteString
                    }
                }
            },
            webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let title = (webView.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let prefix = (self.mode == .rbookScrape ? "国图下载 (BookGet)" : "弹窗浏览器 (BookGet)")
                    self.window.title = title.isEmpty ? "\(prefix) - \(self.targetHost)" : "\(title) — \(prefix)"
                    self.window.subtitle = webView.url?.host ?? self.targetHost
                }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if webView.isLoading {
                        self.loadingSpinner.startAnimation(nil)
                    } else {
                        self.loadingSpinner.stopAnimation(nil)
                    }
                }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
                DispatchQueue.main.async { self?.backButton.isEnabled = webView.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
                DispatchQueue.main.async { self?.forwardButton.isEnabled = webView.canGoForward }
            },
        ]
    }

    private func setStatus(_ text: String?, busy: Bool) {
        statusLabel.stringValue = text ?? ""
        if busy {
            statusSpinner.startAnimation(nil)
        } else {
            statusSpinner.stopAnimation(nil)
        }
    }

    @objc private func onGoBack() {
        webView.goBack()
    }

    @objc private func onGoForward() {
        webView.goForward()
    }

    @objc private func onReload() {
        contentProcessReloads[ObjectIdentifier(webView)] = 0
        webView.reload()
    }

    @objc private func onGoToURL() {
        let raw = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        var text = raw
        if !text.contains("://") {
            text = "https://" + text
        }
        guard let url = URL(string: text) else { return }
        window.makeFirstResponder(webView)
        webView.load(URLRequest(url: url))
    }

    @objc private func onBackToStart() {
        urlField.stringValue = targetURL.absoluteString
        webView.load(URLRequest(url: targetURL))
    }

    // Some sites open the reader in a new window/tab (target=_blank / window.open).
    // Keep the flow in the same temporary window so "完成" can capture the real reader URL,
    // except for OAuth/QR-login hosts, which get a real child window (they need window.opener).
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let prepared = makeBrowserConfiguration(from: configuration)
        let url = navigationAction.request.url
        rememberMeaningfulShanghaiLibraryReaderURL(url)
        if !isBlankPopupURL(url) && isAuthPopupURL(url) {
            return makePopupWindow(with: prepared, windowFeatures: windowFeatures)
        }
        return makePopupBridgeView(with: prepared)
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let entry = popupWindowEntry(for: webView) {
            entry.window.close()
            return
        }
        if let popupBridgeWebView, webView === popupBridgeWebView {
            removePopupBridge()
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        if let popupBridgeWebView, webView === popupBridgeWebView, !isBlankPopupURL(url) {
            if isAuthPopupURL(url) {
                // window.open('') followed by navigation to a login host: promote to a real window.
                presentPopupWindow(for: webView, windowFeatures: nil)
                decisionHandler(.allow)
                return
            }
            loadRequestInMainWebView(navigationAction.request)
            decisionHandler(.cancel)
            return
        }

        if webView === self.webView, navigationAction.targetFrame == nil, !isBlankPopupURL(url) {
            loadRequestInMainWebView(navigationAction.request)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let role = webViewRole(webView)
        rememberMeaningfulShanghaiLibraryReaderURL(webView.url)
        contentProcessReloads[ObjectIdentifier(webView)] = 0
        if role == "main", let u = webView.url?.absoluteString, urlField.currentEditor() == nil {
            urlField.stringValue = u
        } else if role == "popup-window", let entry = popupWindowEntry(for: webView) {
            let title = (webView.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            entry.window.title = title.isEmpty ? "登录窗口 (BookGet)" : title
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logNavigationError(error, role: webViewRole(webView), stage: "navigation", failingURL: webView.url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let failingURL = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? webView.url
        logNavigationError(error, role: webViewRole(webView), stage: "provisional navigation", failingURL: failingURL)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let key = ObjectIdentifier(webView)
        let count = (contentProcessReloads[key] ?? 0) + 1
        contentProcessReloads[key] = count
        let role = webViewRole(webView)
        guard count <= Self.maxContentProcessReloads else {
            logError("\(role) webview content process terminated \(count) times, not reloading again")
            if role == "main" {
                setStatus("页面进程多次崩溃，请点击“刷新”重试。", busy: false)
            }
            return
        }
        logError("\(role) webview content process terminated, reloading (\(count)/\(Self.maxContentProcessReloads))...")
        webView.reload()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === window {
            exit(2)
        }
        if let idx = popupWindows.firstIndex(where: { $0.window === closing }) {
            let popup = popupWindows.remove(at: idx).webView
            popup.stopLoading()
            popup.uiDelegate = nil
            popup.navigationDelegate = nil
            contentProcessReloads[ObjectIdentifier(popup)] = nil
        }
    }

    @objc private func onCancel() {
        exit(2)
    }

    @objc private func onDone() {
        if isCompleting { return }
        isCompleting = true
        doneButton.isEnabled = false
        setStatus("正在定位阅读页…", busy: true)

        func isShanghaiLibraryReaderURL(_ urlString: String) -> Bool {
            self.isShanghaiLibraryReaderURL(urlString)
        }

        func extractMeaningfulShanghaiLibraryURL(completion: @escaping (String?) -> Void) {
            if let remembered = self.lastMeaningfulShanghaiLibraryReaderURL,
               isShanghaiLibraryReaderURL(remembered),
               remembered.contains("?") {
                completion(remembered)
                return
            }
            let patterns = self.shanghaiLibraryReaderPatterns
            func jsArray(_ items: [String]) -> String {
                let data = (try? JSONSerialization.data(withJSONObject: items.map { $0.lowercased() })) ?? Data("[]".utf8)
                return String(data: data, encoding: .utf8) ?? "[]"
            }
            let js = #"""
            (function() {
              var readerContains = \#(jsArray(patterns.contains));
              var readerExcludes = \#(jsArray(patterns.excludes));
              function hasAny(lc, list) {
                for (var j = 0; j < list.length; j++) { if (lc.indexOf(list[j]) !== -1) return true; }
                return false;
              }
              function normalize(url, base) {
                try { return new URL(url || window.location.href, base || window.location.href).toString(); }
                catch (e) { return ""; }
              }
              var candidates = [];
              if (window.__bookgetLastMeaningfulURL) candidates.push(window.__bookgetLastMeaningfulURL);
              if (window.__bookgetOriginalURL) candidates.push(window.__bookgetOriginalURL);
              try {
                var nav = performance.getEntriesByType('navigation');
                if (nav && nav[0] && nav[0].name) candidates.push(nav[0].name);
              } catch (e) {}
              candidates.push(window.location.href);
              for (var i = 0; i < candidates.length; i++) {
                var abs = normalize(candidates[i], window.location.href);
                if (!abs) continue;
                var lc = abs.toLowerCase();
                if (hasAny(lc, readerExcludes)) continue;
                if (hasAny(lc, readerContains) && abs.indexOf('?') !== -1) {
                  return abs;
                }
              }
              return "";
            })();
            """#
            webView.evaluateJavaScript(js) { result, _ in
                let s = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                completion(s.isEmpty ? nil : s)
            }
        }

        func isShanghaiLibraryDetailPage(_ urlString: String, html: String?) -> Bool {
            if SiteRegistry.shared.match(urlString)?.entry?.adapter == "shanghai-library-detail" {
                return true
            }
            guard let html else { return false }
            return html.contains("点击查看全文") || html.contains("點擊查看全文")
        }

        func isShanghaiLibraryRedirectPage(_ urlString: String) -> Bool {
            urlString.lowercased().contains("gj.library.sh.cn/index/redirect")
        }

        func captureLoginState(finalURLString: String, completion: @escaping () -> Void) {
            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.getAllCookies { cookies in
            // Login flows sometimes bounce between sibling subdomains (e.g. rbook.* -> taiwanebook.*).
            // Capture cookies for the current host and its parent domain (when safe) to improve success rate.
            let parts = self.targetHost.split(separator: ".")
            let parentDomain: String? = {
                guard parts.count >= 3 else { return nil }
                let candidate = parts.dropFirst().joined(separator: ".")
                return candidate.contains(".") ? candidate : nil
            }()

            let filtered = cookies.filter {
                if cookieMatchesHost(cookie: $0, host: self.targetHost) { return true }
                if let parentDomain { return cookieMatchesParentDomain(cookie: $0, parentDomain: parentDomain) }
                return false
            }
            let sorted = filtered.sorted {
                ($0.domain, $0.path, $0.name) < ($1.domain, $1.path, $1.name)
            }

            var lines: [String] = []
            lines.reserveCapacity(sorted.count)

            for c in sorted {
                let domain = sanitizeCookieField(c.domain)
                let domainField = c.isHTTPOnly ? "#HttpOnly_\(domain)" : domain
                let includeSubdomains = c.domain.hasPrefix(".") ? "TRUE" : "FALSE"
                let path = sanitizeCookieField(c.path.isEmpty ? "/" : c.path)
                let secure = c.isSecure ? "TRUE" : "FALSE"
                let expires = c.expiresDate.map { Int($0.timeIntervalSince1970) } ?? 0
                let name = sanitizeCookieField(c.name)
                let value = sanitizeCookieField(c.value)
                lines.append("\(domainField)\t\(includeSubdomains)\t\(path)\t\(secure)\t\(expires)\t\(name)\t\(value)")
            }

            if let urlOutURL = self.urlOutURL {
                do {
                    try writePrivateFile(Data((finalURLString + "\n").utf8), to: urlOutURL)
                } catch {
                    // Cookie capture is the primary signal; URL out is best-effort.
                    FileHandle.standardError.write(Data(("登录后网址写入失败：\(error)\n").utf8))
                }
            }

            if lines.isEmpty {
                if self.mode == .rbookScrape {
                    // rbook pages are scraped inside this web view; cookies are optional.
                    logError("no cookies captured for \(self.targetHost); continuing rbook scrape")
                    completion()
                    return
                }
                FileHandle.standardError.write(Data(("已匹配到站点，但未获取到登录状态：\(self.targetHost)\n").utf8))
                exit(3)
            }

            let header = """
            # Netscape HTTP Cookie File
            # Generated by bookget-web-login (WKWebView, non-persistent)

            """
            let body = lines.joined(separator: "\n") + "\n"
            do {
                try writePrivateFile(Data((header + body).utf8), to: self.cookieOutURL)
            } catch {
                FileHandle.standardError.write(Data(("登录状态写入失败：\(error)\n").utf8))
                exit(1)
            }

            // Keep stdout output for wrapper debugging; wrapper currently discards stdout.
            FileHandle.standardOutput.write(Data((self.cookieOutURL.path + "\n").utf8))
            completion()
            }
        }

        func autoClickShanghaiLibraryFullTextIfPresent(completion: @escaping (Bool) -> Void) {
            let js = #"""
            (function(){
              function click(el){ try { el.click(); return true; } catch(e) { return false; } }
              function host(el){
                if (!el) return null;
                var tag = (el.tagName || '').toLowerCase();
                if (tag === 'img') return el.closest('a') || el;
                return el;
              }
              function textOf(el){
                if (!el) return '';
                var h = host(el) || el;
                return [
                  h.innerText || h.textContent || '',
                  h.getAttribute('title') || '',
                  h.getAttribute('aria-label') || '',
                  el.getAttribute && el.getAttribute('title') || ''
                ].join(' ').replace(/\s+/g, ' ').trim();
              }
              var direct = document.querySelector("a[onclick*='login'], a[onclick*='login('], a img[title*='全文']");
              var directHost = host(direct);
              if (directHost && click(directHost)) return textOf(directHost) || 'login()';
              var els = Array.prototype.slice.call(document.querySelectorAll('a,button,input[type="button"],input[type="submit"],img[title]'));
              for (var i=0;i<els.length;i++){
                var h = host(els[i]);
                if (!h) continue;
                var t = textOf(els[i]);
                var on = ((h.getAttribute('onclick') || '') + ' ' + (els[i].getAttribute && els[i].getAttribute('onclick') || '')).toLowerCase();
                if ((t.indexOf('点击查看全文') !== -1 || t.indexOf('點擊查看全文') !== -1 || t.indexOf('查看全文') !== -1) && click(h)) return t;
                if (on.indexOf('login') !== -1 && (t.indexOf('全文') !== -1 || t.indexOf('阅读') !== -1 || t.indexOf('閱讀') !== -1 || t.indexOf('阅览') !== -1 || t.indexOf('閱覽') !== -1)) {
                  if (click(h)) return t || 'login()';
                }
              }
              return '';
            })()
            """#
            webView.evaluateJavaScript(js) { result, _ in
                let s = (result as? String) ?? ""
                completion(!s.isEmpty)
            }
        }

        func autoClickRBookViewerIfPresent(completion: @escaping (Bool) -> Void) {
            let js = #"""
            (function(){
              function click(el){ try { el.click(); return true; } catch(e) { return false; } }
              var sel = '.btn.btn-default.bg-malachite-green.text-white.mr-5px';
              var b = document.querySelector(sel);
              if (b && click(b)) return 'selector';
              var els = Array.prototype.slice.call(document.querySelectorAll('a,button,input[type="button"],input[type="submit"]'));
              for (var i=0;i<els.length;i++){
                var t = (els[i].innerText || els[i].value || '').trim();
                if (!t) continue;
                if (t.indexOf('古籍')!=-1 && t.indexOf('影像')!=-1 && (t.indexOf('浏览')!=-1 || t.indexOf('瀏覽')!=-1)) { if (click(els[i])) return t; }
                if (t.indexOf('影像')!=-1 && (t.indexOf('浏览')!=-1 || t.indexOf('瀏覽')!=-1)) { if (click(els[i])) return t; }
                if (t.indexOf('在线阅读')!=-1 || t.indexOf('線上閱讀')!=-1 || t.indexOf('阅读')!=-1 || t.indexOf('閱讀')!=-1) { if (click(els[i])) return t; }
              }
              return '';
            })()
            """#
            webView.evaluateJavaScript(js) { result, _ in
                let s = (result as? String) ?? ""
                completion(!s.isEmpty)
            }
        }

        func attemptResolveAndProceed(_ attempt: Int, completion: @escaping (String) -> Void) {
            let currentURLString = webView.url?.absoluteString ?? targetURL.absoluteString
            let baseURL = webView.url ?? targetURL

            if isShanghaiLibraryReaderURL(currentURLString) && currentURLString.contains("?") {
                completion(currentURLString)
                return
            }

            if isShanghaiLibraryReaderURL(currentURLString) {
                extractMeaningfulShanghaiLibraryURL { meaningfulURL in
                    completion(meaningfulURL ?? currentURLString)
                }
                return
            }

            webView.evaluateJavaScript("document.documentElement.outerHTML") { result, _ in
                let html = result as? String
                let bestFromHTML = html.flatMap { bestDownloadURLFromHTML($0, baseURL: baseURL) }
                let best = (bestFromHTML?.isEmpty == false) ? bestFromHTML! : currentURLString

                let lc = best.lowercased()
                if lc.contains("view.do") || lc.contains("manifest") || lc.contains("iiif") || isShanghaiLibraryReaderURL(best) {
                    completion(best)
                    return
                }

                if attempt < 2 && isShanghaiLibraryRedirectPage(currentURLString) {
                    self.setStatus("等待跳转完成…（第 \(attempt + 1) 次重试）", busy: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        attemptResolveAndProceed(attempt + 1, completion: completion)
                    }
                    return
                }

                if attempt < 2 && isShanghaiLibraryDetailPage(currentURLString, html: html) {
                    autoClickShanghaiLibraryFullTextIfPresent { clicked in
                        if clicked {
                            self.setStatus("已自动点击“查看全文”，等待阅读页加载…（第 \(attempt + 1) 次）", busy: true)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                attemptResolveAndProceed(attempt + 1, completion: completion)
                            }
                            return
                        }
                        completion(best)
                    }
                    return
                }

                // NCL rbook: SearchDetail is an entry page. Try to auto-click into the viewer once.
                let isSearchDetail = currentURLString.lowercased().contains("searchdetail")
                if attempt == 0 && isSearchDetail {
                    autoClickRBookViewerIfPresent { clicked in
                        if clicked {
                            self.setStatus("已自动进入影像浏览页，等待加载…", busy: true)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                attemptResolveAndProceed(1, completion: completion)
                            }
                            return
                        }
                        completion(best)
                    }
                    return
                }

                completion(best)
            }
        }

        attemptResolveAndProceed(0) { finalURLString in
            self.setStatus("正在导出登录状态…", busy: true)
            if self.mode == .rbookScrape {
                captureLoginState(finalURLString: finalURLString) {
                    self.isScraping = true
                    self.startRBookScrape()
                }
                return
            }
            captureLoginState(finalURLString: finalURLString) {
                exit(0)
            }
        }
    }

    private func startRBookScrape() {
        guard let outDir else {
            FileHandle.standardError.write(Data("[bookget-web-login] missing --out-dir for rbook scrape\n".utf8))
            exit(1)
        }
        do {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("[bookget-web-login] cannot create out dir: \(outDir.path) (\(error))\n".utf8))
            exit(1)
        }

        // The web view must stay in a visible window to keep rendering pages, so the
        // browser window stays open (behind) and a small progress panel offers 取消.
        showScrapeProgressPanel()
        updateScrapeProgress(page: nil, total: nil, note: "正在打开影像浏览页…")
        setStatus("正在下载，请勿关闭本窗口…", busy: true)

        FileHandle.standardError.write(Data("[bookget-web-login] rbook scrape started: \(outDir.path)\n".utf8))
        ensureRBookViewerReady(tries: 0)
    }

    private func showScrapeProgressPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 110),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "国图下载进度"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let content = NSView()
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail

        let bar = NSProgressIndicator()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.style = .bar
        bar.isIndeterminate = true
        bar.minValue = 0
        bar.maxValue = 1
        bar.startAnimation(nil)

        let cancel = NSButton(title: "取消", target: self, action: #selector(onCancel))
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.keyEquivalent = "\u{1b}"

        content.addSubview(label)
        content.addSubview(bar)
        content.addSubview(cancel)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            bar.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            cancel.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 10),
            cancel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            cancel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        panel.contentView = content

        let wf = window.frame
        panel.setFrameTopLeftPoint(NSPoint(x: wf.maxX - 380, y: wf.maxY - 40))
        panel.orderFrontRegardless()

        progressPanel = panel
        progressLabel = label
        progressBar = bar
    }

    private func updateScrapeProgress(page: String?, total: String?, note: String? = nil) {
        let text: String
        if let note {
            text = note
        } else if let page, let total, !total.isEmpty {
            text = "正在抓取第 \(page) / \(total) 页"
        } else if let page {
            text = "正在抓取第 \(page) 页"
        } else {
            text = "正在抓取…"
        }
        progressLabel?.stringValue = text
        if let bar = progressBar, let totalCount = total.flatMap({ Int($0) }), totalCount > 0 {
            if bar.isIndeterminate {
                bar.stopAnimation(nil)
                bar.isIndeterminate = false
            }
            bar.maxValue = Double(totalCount)
            bar.doubleValue = Double(min(savedPageCount, totalCount))
        }
    }

    private func ensureRBookViewerReady(tries: Int) {
        if !isScraping { return }
        if tries >= 45 {
            FileHandle.standardError.write(Data("[bookget-web-login] rbook viewer not ready (timeout)\n".utf8))
            exit(1)
        }

        let jsReady = "document.querySelector('#ImageDisplay') != null && document.querySelector('#sel-content-no') != null"
        webView.evaluateJavaScript(jsReady) { result, _ in
            let ready = (result as? Bool) ?? false
            if ready {
                self.scrapeCurrentRBookPage()
                return
            }

            // Try to advance from SearchDetail into viewer again, then retry.
            self.webView.evaluateJavaScript(#"""
            (function(){
              function abs(u){ try { return new URL(u, document.baseURI).toString(); } catch(e) { return ''; } }
              function getUrl(el){
                if (!el) return '';
                var href = el.getAttribute('href') || '';
                if (href && href !== '#' && href.indexOf('javascript:') !== 0) return abs(href);
                var du = el.getAttribute('data-url') || el.getAttribute('data-href') || '';
                if (du) return abs(du);
                var on = el.getAttribute('onclick') || '';
                var m = on.match(/(?:window\.open|location\.href|location\.assign)\(['"]([^'"]+)['"]/);
                if (m && m[1]) return abs(m[1]);
                return '';
              }
              var sel = '.btn.btn-default.bg-malachite-green.text-white.mr-5px';
              var b = document.querySelector(sel);
              var u = getUrl(b);
              if (u) { location.href = u; return u; }
              if (b) { try { b.click(); return 'clicked'; } catch(e) {} }
              return '';
            })()
            """#) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.ensureRBookViewerReady(tries: tries + 1)
                }
            }
        }
    }

    private func clickNextRBookPage(then: @escaping () -> Void) {
        webView.evaluateJavaScript("var b=document.getElementById('AftT'); if (b) { b.click(); true } else { false }") { _, _ in
            then()
        }
    }

    private func scrapeCurrentRBookPage() {
        if !isScraping { return }

        let js = #"""
        (function() {
          var img = document.querySelector('#ImageDisplay');
          var sel = document.querySelector('#sel-content-no');
          var totalEl = document.querySelector('span.total-page');
          var pageNum = '';
          if (sel && sel.selectedOptions && sel.selectedOptions[0]) pageNum = (sel.selectedOptions[0].textContent || '').trim();
          var totalPages = '';
          if (totalEl) totalPages = (totalEl.textContent || '').trim().replace('/ ', '').replace('/', '');
          var w = img ? (img.naturalWidth || 0) : 0;
          var h = img ? (img.naturalHeight || 0) : 0;
          var complete = img ? !!img.complete : false;
          var src = img ? (img.currentSrc || img.src || '') : '';
          var dataUrl = '';
          var tainted = false;
          if (img && complete && w > 0 && h > 0) {
            try {
              var canvas = document.createElement('canvas');
              canvas.width = w;
              canvas.height = h;
              var ctx = canvas.getContext('2d');
              ctx.drawImage(img, 0, 0, w, h);
              dataUrl = canvas.toDataURL('image/png');
              if (dataUrl.indexOf('data:image/png;base64,') === 0) {
                dataUrl = dataUrl.substring('data:image/png;base64,'.length);
              } else {
                dataUrl = '';
              }
            } catch (e) {
              dataUrl = '';
              tainted = true;
            }
          }
          return { pageNum: pageNum, totalPages: totalPages, width: w, height: h, dataUrl: dataUrl, src: src, tainted: tainted };
        })();
        """#

        webView.evaluateJavaScript(js) { result, _ in
            guard let dict = result as? [String: Any] else {
                self.retryScrapeSoon(reason: "no result dict")
                return
            }
            let pageNum = (dict["pageNum"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let totalPages = (dict["totalPages"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let w = dict["width"] as? Int ?? 0
            let h = dict["height"] as? Int ?? 0
            let dataUrl = (dict["dataUrl"] as? String) ?? ""
            let src = (dict["src"] as? String) ?? ""

            if pageNum.isEmpty || totalPages.isEmpty || w <= 0 || h <= 0 {
                self.retryScrapeSoon(reason: "not ready (page=\(pageNum) total=\(totalPages) w=\(w) h=\(h))")
                return
            }

            if let last = self.lastSavedPageLabel, last == pageNum {
                // The viewer did not move on after clicking "next"; click again every few tries.
                let clickAgain = self.scrapeNoProgressCount % 5 == 4
                self.retryScrapeSoon(reason: "page \(pageNum) not advanced", clickNext: clickAgain)
                return
            }

            self.updateScrapeProgress(page: pageNum, total: totalPages)

            if dataUrl.count >= 200, let data = Data(base64Encoded: dataUrl, options: [.ignoreUnknownCharacters]) {
                self.saveRBookPage(data, pageNum: pageNum, totalPages: totalPages)
                return
            }

            // Cross-origin images taint the canvas (toDataURL throws): fetch the src
            // directly with this web view's cookies instead.
            guard !src.isEmpty, !src.lowercased().hasPrefix("blob:"), let srcURL = URL(string: src) else {
                self.retryScrapeSoon(reason: "canvas export failed and no fetchable src (page=\(pageNum))")
                return
            }
            self.fetchRBookImage(srcURL) { data in
                guard let data else {
                    self.retryScrapeSoon(reason: "image fetch failed: \(redactedURLString(srcURL))")
                    return
                }
                self.saveRBookPage(data, pageNum: pageNum, totalPages: totalPages)
            }
        }
    }

    /// Downloads `url` with the web view's cookies and converts it to PNG bytes
    /// (pages are always saved as 第N頁.png).
    private func fetchRBookImage(_ url: URL, completion: @escaping (Data?) -> Void) {
        func toPNG(_ data: Data) -> Data? {
            guard let rep = NSBitmapImageRep(data: data) else { return nil }
            return rep.representation(using: .png, properties: [:])
        }

        if url.scheme?.lowercased() == "data" {
            let raw = url.absoluteString
            guard let comma = raw.firstIndex(of: ","), raw[..<comma].contains(";base64"),
                  let data = Data(base64Encoded: String(raw[raw.index(after: comma)...]), options: [.ignoreUnknownCharacters]) else {
                completion(nil)
                return
            }
            completion(toPNG(data))
            return
        }

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let host = url.host ?? ""
            let matching = cookies.filter { cookieMatchesHost(cookie: $0, host: host) }
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            request.httpShouldHandleCookies = false
            request.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
            if let referer = self.webView.url?.absoluteString {
                request.setValue(referer, forHTTPHeaderField: "Referer")
            }
            for (k, v) in HTTPCookie.requestHeaderFields(with: matching) {
                request.setValue(v, forHTTPHeaderField: k)
            }
            let session = URLSession(configuration: .ephemeral)
            session.dataTask(with: request) { data, response, error in
                session.finishTasksAndInvalidate()
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                var png: Data?
                if error == nil, (200..<300).contains(status), let data, !data.isEmpty {
                    png = toPNG(data)
                } else {
                    logError("rbook image fetch HTTP \(status): \(redactedURLString(url))")
                }
                DispatchQueue.main.async { completion(png) }
            }.resume()
        }
    }

    private func saveRBookPage(_ data: Data, pageNum: String, totalPages: String) {
        if !isScraping { return }
        guard let outDir = self.outDir else { exit(1) }
        let label = sanitizedPageLabel(pageNum, fallback: "\(savedPageCount + 1)")
        let fn = "第\(label)頁.png"
        let outURL = outDir.appendingPathComponent(fn)
        do {
            try data.write(to: outURL, options: [.atomic])
        } catch {
            FileHandle.standardError.write(Data("[bookget-web-login] write failed: \(outURL.path) (\(error))\n".utf8))
            exit(1)
        }

        scrapeNoProgressCount = 0
        lastSavedPageLabel = pageNum
        savedPageCount += 1
        updateScrapeProgress(page: pageNum, total: totalPages)
        FileHandle.standardError.write(Data("[bookget-web-login] saved \(pageNum)/\(totalPages): \(fn)\n".utf8))

        let isLast: Bool = {
            if pageNum == totalPages { return true }
            if let p = Int(pageNum), let t = Int(totalPages), t > 0 { return p >= t }
            return false
        }()
        if isLast {
            FileHandle.standardError.write(Data("[bookget-web-login] rbook scrape complete\n".utf8))
            exit(0)
        }

        clickNextRBookPage {
            DispatchQueue.main.asyncAfter(deadline: .now() + self.intervalSeconds) {
                self.scrapeCurrentRBookPage()
            }
        }
    }

    private func retryScrapeSoon(reason: String, clickNext: Bool = false) {
        scrapeNoProgressCount += 1
        if scrapeNoProgressCount >= Self.maxScrapeNoProgress {
            logError("rbook scrape stalled after \(scrapeNoProgressCount) attempts without progress: \(reason)")
            exit(1)
        }
        if scrapeNoProgressCount % 5 == 1 {
            logError("waiting page render (\(scrapeNoProgressCount)/\(Self.maxScrapeNoProgress)): \(reason)")
        }
        let delay = min(2.0, max(0.5, intervalSeconds / 2.0))
        let next = {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if self.isScraping {
                    self.scrapeCurrentRBookPage()
                }
            }
        }
        if clickNext {
            clickNextRBookPage(then: next)
        } else {
            next()
        }
    }
}

if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "--detect-site" {
    guard CommandLine.arguments.count >= 3 else { usage("Missing value for --detect-site") }
    let registry = SiteRegistry.shared
    if registry.isEmpty {
        FileHandle.standardError.write(Data("[bookget-web-login] sites.json not found or empty\n".utf8))
        exit(3)
    }
    print(registry.detectReport(CommandLine.arguments[2]))
    exit(0)
}

let args = parseArgs()
if args.mode == .shanghaiPDFDownload {
    do {
        try downloadShanghaiLibraryPDFView(args: args)
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("[bookget-web-login] \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}
let app = NSApplication.shared
let delegate = AppDelegate(args: args)
app.delegate = delegate
app.run()
