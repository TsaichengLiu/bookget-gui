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

private enum InteractiveSiteAdapterKind: String {
    case generic
    case shanghaiLibrary
    case nclRBook

    static func detect(url: URL) -> InteractiveSiteAdapterKind {
        guard let raw = SiteRegistry.shared.match(url.absoluteString)?.site.loginAdapter else { return .generic }
        return InteractiveSiteAdapterKind(rawValue: raw) ?? .generic
    }
}

private func usage(_ msg: String? = nil) -> Never {
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
    exit(2)
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
            usage()
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
            return "invalid Shanghai reader URL: \(url)"
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
        let message = String(data: infoData, encoding: .utf8) ?? "HTTP \(infoResponse.statusCode)"
        throw ShanghaiDownloadError.infoRequestFailed(message)
    }

    let info = try JSONDecoder().decode(ShanghaiInfoResponse.self, from: infoData)
    guard info.state == 0, let payload = info.data, !payload.items.isEmpty else {
        throw ShanghaiDownloadError.infoRequestFailed(info.msg ?? "empty item list")
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

        func mergeCachedPages(into destinationURL: URL) throws -> Int {
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
                    let message = String(data: pageData, encoding: .utf8) ?? "HTTP \(pageResponse.statusCode)"
                    throw ShanghaiDownloadError.streamRequestFailed(message)
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
    private var popupBridgeWebView: WKWebView?
    private var urlField: NSTextField!
    private var isCompleting = false
    private var isScraping = false
    private var scrapeRetryCount = 0
    private var lastMeaningfulShanghaiLibraryReaderURL: String?

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

    private func loadRequestInMainWebView(_ request: URLRequest) {
        rememberMeaningfulShanghaiLibraryReaderURL(request.url)
        if let abs = request.url?.absoluteString, !abs.isEmpty {
            urlField.stringValue = abs
        }
        webView.load(request)
    }

    private func popupBridgeView(with configuration: WKWebViewConfiguration) -> WKWebView {
        if let existing = popupBridgeWebView {
            return existing
        }

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

    private func webViewRole(_ webView: WKWebView) -> String {
        if webView === self.webView {
            return "main"
        }
        if let popupBridgeWebView, webView === popupBridgeWebView {
            return "popup"
        }
        return "unknown"
    }

    private func logNavigationError(_ error: Error, role: String, stage: String, failingURL: URL?) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        let urlText = failingURL?.absoluteString ?? targetURL.absoluteString
        FileHandle.standardError.write(Data("[bookget-web-login] \(role) webview \(stage) failed: \(urlText) (\(nsError.localizedDescription))\n".utf8))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if targetHost.isEmpty {
            FileHandle.standardError.write(Data(("Invalid URL host: \(targetURL.absoluteString)\n").utf8))
            exit(2)
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
        window.title = (mode == .rbookScrape ? "國圖下載 (BookGet) - \(targetHost)" : "弹窗浏览器 (BookGet) - \(targetHost)")
        window.center()
        window.delegate = self

        rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = rootView

        let instructionText: String = {
            if mode == .rbookScrape {
                return "请在此窗口完成验证码/登录。点击“开始下载”后窗口会隐藏并开始保存图片到目标文件夹。"
            }
            if siteAdapter == .shanghaiLibrary {
                return "请在此弹窗浏览器中完成登录/验证码。若页面有“查看全文/阅读/在线阅读”等按钮，请先点击进入阅读页（新窗口会被自动接管到本窗口），再点击“完成”。"
            }
            return "请在此弹窗浏览器中完成登录/验证码。若页面有“阅读/在线阅读”等按钮，请先点击进入阅读页（新窗口会被自动接管到本窗口），再点击“完成”，窗口会关闭并继续下载。"
        }()
        let instruction = NSTextField(labelWithString: instructionText)
        instruction.translatesAutoresizingMaskIntoConstraints = false
        instruction.font = NSFont.systemFont(ofSize: 13)
        instruction.textColor = .secondaryLabelColor
        instruction.lineBreakMode = .byWordWrapping
        instruction.maximumNumberOfLines = 2

        let urlLabel = NSTextField(labelWithString: "网址")
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.font = NSFont.systemFont(ofSize: 12)
        urlLabel.textColor = .secondaryLabelColor

        urlField = NSTextField(string: targetURL.absoluteString)
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.font = NSFont.systemFont(ofSize: 12)
        urlField.placeholderString = "粘贴网址后回车"
        urlField.lineBreakMode = .byTruncatingMiddle
        urlField.usesSingleLineMode = true
        urlField.target = self
        urlField.action = #selector(onGoToURL)

        let go = NSButton(title: "前往", target: self, action: #selector(onGoToURL))
        go.translatesAutoresizingMaskIntoConstraints = false

        let backToStart = NSButton(title: "回到起始页", target: self, action: #selector(onBackToStart))
        backToStart.translatesAutoresizingMaskIntoConstraints = false

        let urlBar = NSStackView(views: [urlLabel, urlField, go, backToStart])
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

        let doneTitle = (mode == .rbookScrape ? "开始下载" : "完成")
        let done = NSButton(title: doneTitle, target: self, action: #selector(onDone))
        done.translatesAutoresizingMaskIntoConstraints = false
        done.keyEquivalent = "\r"

        let cancel = NSButton(title: "取消", target: self, action: #selector(onCancel))
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.keyEquivalent = "\u{1b}"

        let buttonRow = NSStackView(views: [cancel, done])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12
        buttonRow.alignment = .centerY

        rootView.addSubview(instruction)
        rootView.addSubview(urlBar)
        rootView.addSubview(webView)
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

            urlField.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),

            webView.topAnchor.constraint(equalTo: urlBar.bottomAnchor, constant: 10),
            webView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -10),
        ])

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.load(URLRequest(url: targetURL))
    }

    @objc private func onGoToURL() {
        let raw = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        var text = raw
        if !text.contains("://") {
            text = "https://" + text
        }
        guard let url = URL(string: text) else { return }
        webView.load(URLRequest(url: url))
    }

    @objc private func onBackToStart() {
        urlField.stringValue = targetURL.absoluteString
        webView.load(URLRequest(url: targetURL))
    }

    // Some sites open the reader in a new window/tab (target=_blank / window.open).
    // Keep the flow in the same temporary window so "完成" can capture the real reader URL.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let prepared = makeBrowserConfiguration(from: configuration)
        if let url = navigationAction.request.url {
            rememberMeaningfulShanghaiLibraryReaderURL(url)
            if !isBlankPopupURL(url) {
                let popup = popupBridgeView(with: prepared)
                return popup
            }
        }
        return popupBridgeView(with: prepared)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let popupBridgeWebView, webView === popupBridgeWebView {
            if let url = navigationAction.request.url, !isBlankPopupURL(url) {
                loadRequestInMainWebView(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
            return
        }

        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url, !isBlankPopupURL(url) {
                loadRequestInMainWebView(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let role = webViewRole(webView)
        rememberMeaningfulShanghaiLibraryReaderURL(webView.url)
        if role == "main", let u = webView.url?.absoluteString {
            urlField.stringValue = u
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
        FileHandle.standardError.write(Data("[bookget-web-login] \(webViewRole(webView)) webview content process terminated, reloading...\n".utf8))
        webView.reload()
    }

    func windowWillClose(_ notification: Notification) {
        exit(2)
    }

    @objc private func onCancel() {
        exit(2)
    }

    @objc private func onDone() {
        if isCompleting { return }
        isCompleting = true

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

            let header = """
            # Netscape HTTP Cookie File
            # Generated by bookget-web-login (WKWebView, non-persistent)

            """
            let body = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
            do {
                try FileManager.default.createDirectory(
                    at: self.cookieOutURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try (header + body).write(to: self.cookieOutURL, atomically: true, encoding: .utf8)
            } catch {
                FileHandle.standardError.write(Data(("登录状态写入失败：\(error)\n").utf8))
                exit(1)
            }

            if let urlOutURL = self.urlOutURL {
                do {
                    try FileManager.default.createDirectory(
                        at: urlOutURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try (finalURLString + "\n").write(to: urlOutURL, atomically: true, encoding: .utf8)
                } catch {
                    // Cookie capture is the primary signal; URL out is best-effort.
                    FileHandle.standardError.write(Data(("登录后网址写入失败：\(error)\n").utf8))
                }
            }

            if lines.isEmpty {
                FileHandle.standardError.write(Data(("已匹配到站点，但未获取到登录状态：\(self.targetHost)\n").utf8))
                exit(3)
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        attemptResolveAndProceed(attempt + 1, completion: completion)
                    }
                    return
                }

                if attempt < 2 && isShanghaiLibraryDetailPage(currentURLString, html: html) {
                    autoClickShanghaiLibraryFullTextIfPresent { clicked in
                        if clicked {
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
            if self.mode == .rbookScrape {
                self.window.orderOut(nil)
                self.isScraping = true
                captureLoginState(finalURLString: finalURLString) {
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

        FileHandle.standardError.write(Data("[bookget-web-login] rbook scrape started: \(outDir.path)\n".utf8))
        ensureRBookViewerReady(tries: 0)
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
          var src = img ? (img.currentSrc || img.src || '') : '';
          var dataUrl = '';
          if (img && w > 0 && h > 0) {
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
            }
          }
          return { pageNum: pageNum, totalPages: totalPages, width: w, height: h, dataUrl: dataUrl, src: src };
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

            if pageNum.isEmpty || totalPages.isEmpty || w <= 0 || h <= 0 || dataUrl.count < 200 {
                self.retryScrapeSoon(reason: "not ready (page=\(pageNum) total=\(totalPages) w=\(w) h=\(h) b64=\(dataUrl.count))")
                return
            }

            guard let outDir = self.outDir else { exit(1) }
            let fn = "第\(pageNum)頁.png"
            let outURL = outDir.appendingPathComponent(fn)
            guard let data = Data(base64Encoded: dataUrl, options: [.ignoreUnknownCharacters]) else {
                self.retryScrapeSoon(reason: "base64 decode failed")
                return
            }
            do {
                try data.write(to: outURL, options: [.atomic])
            } catch {
                FileHandle.standardError.write(Data("[bookget-web-login] write failed: \(outURL.path) (\(error))\n".utf8))
                exit(1)
            }

            self.scrapeRetryCount = 0
            FileHandle.standardError.write(Data("[bookget-web-login] saved \(pageNum)/\(totalPages): \(fn)\n".utf8))

            if pageNum == totalPages {
                FileHandle.standardError.write(Data("[bookget-web-login] rbook scrape complete\n".utf8))
                exit(0)
            }

            self.webView.evaluateJavaScript("var b=document.getElementById('AftT'); if (b) { b.click(); true } else { false }") { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + self.intervalSeconds) {
                    self.scrapeCurrentRBookPage()
                }
            }
        }
    }

    private func retryScrapeSoon(reason: String) {
        scrapeRetryCount += 1
        if scrapeRetryCount % 10 == 1 {
            FileHandle.standardError.write(Data("[bookget-web-login] waiting page render: \(reason)\n".utf8))
        }
        let delay = min(2.0, max(0.5, intervalSeconds / 2.0))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if self.isScraping {
                self.scrapeCurrentRBookPage()
            }
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
