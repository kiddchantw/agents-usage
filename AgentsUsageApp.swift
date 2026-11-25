import SwiftUI
import AppKit

private enum UsagePalette {
    static let claude = NSColor(srgbRed: 218.0 / 255, green: 119.0 / 255, blue: 86.0 / 255, alpha: 1)
    static let codex = Color(.sRGB, red: 16.0 / 255, green: 163.0 / 255, blue: 127.0 / 255)
}

// MARK: - Data types

struct UsageRow: Identifiable {
    let id: String
    let name: String
    let sub: String?
    let percent: Double
    let resetsAt: Date?
    let span: TimeInterval
}

private struct WindowSpec {
    let key: String
    let name: String
    let sub: String?
    let span: TimeInterval
}

private let windowSpecs: [WindowSpec] = [
    WindowSpec(key: "five_hour",        name: "Current session", sub: nil,        span: 5 * 3600),
    WindowSpec(key: "seven_day",        name: "Weekly",          sub: "All models", span: 7 * 86400),
    WindowSpec(key: "seven_day_opus",   name: "Weekly",          sub: "Opus",       span: 7 * 86400),
    WindowSpec(key: "seven_day_sonnet", name: "Weekly",          sub: "Sonnet",     span: 7 * 86400),
]

enum UsageError: Error {
    case noCredentials
    case expired
    case unauthorized(Int)
    case rateLimited
    case http(Int)
    case network(String)
    case badFormat

    var message: String {
        switch self {
        case .noCredentials:
            return "Claude Code credentials were not found. Run claude in Terminal, sign in, then refresh. If macOS prompts for Keychain access, choose Allow."
        case .expired:
            return "Claude Code credentials expired. Open Claude Code, then refresh."
        case .unauthorized(let code):
            return "Anthropic rejected the credentials (HTTP \(code)). Sign in to Claude Code again."
        case .rateLimited:
            return "Rate limited (HTTP 429). The app will retry automatically."
        case .http(let code):
            return "Anthropic returned HTTP \(code). Select {} to view the response."
        case .network(let detail):
            return "Could not reach Anthropic (\(detail))."
        case .badFormat:
            return "Unexpected response format. Select {} to view the response."
        }
    }
}

// MARK: - Service (credentials + request)

enum UsageService {
    struct Credentials {
        let token: String
        let expiresAt: Date?
    }

    /// Reads Claude Code's OAuth credentials: Keychain first, then ~/.claude/.credentials.json.
    static func readCredentials() async -> Credentials? {
        await Task.detached(priority: .utility) { () -> Credentials? in
            if let text = runSecurity(), let cred = parseCredentials(text) {
                return cred
            }
            let path = NSString(string: "~/.claude/.credentials.json").expandingTildeInPath
            if let data = FileManager.default.contents(atPath: path),
               let text = String(data: data, encoding: .utf8),
               let cred = parseCredentials(text) {
                return cred
            }
            return nil
        }.value
    }

    private static func runSecurity() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private static func parseCredentials(_ raw: String) -> Credentials? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.hasPrefix("{"), let decoded = decodeHex(text) { text = decoded }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let oauth = (object["claudeAiOauth"] as? [String: Any]) ?? object
        guard let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        var expiry: Date?
        if let ms = (oauth["expiresAt"] as? NSNumber)?.doubleValue {
            expiry = Date(timeIntervalSince1970: ms > 1e12 ? ms / 1000 : ms)
        }
        return Credentials(token: token, expiresAt: expiry)
    }

    private static func decodeHex(_ s: String) -> String? {
        guard !s.isEmpty, s.count % 2 == 0, s.allSatisfy({ $0.isHexDigit }) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(s.count / 2)
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            guard let byte = UInt8(s[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    static func request(token: String) async throws -> (status: Int, data: Data) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-usage-menubar/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UsageError.badFormat }
            return (http.statusCode, data)
        } catch let error as UsageError {
            throw error
        } catch {
            throw UsageError.network(error.localizedDescription)
        }
    }

    static func parseRows(_ data: Data) throws -> [UsageRow] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.badFormat
        }
        var rows = [UsageRow]()
        for spec in windowSpecs {
            guard let window = object[spec.key] as? [String: Any],
                  let utilization = (window["utilization"] as? NSNumber)?.doubleValue
            else { continue }
            let reset = (window["resets_at"] as? String).flatMap(parseDate)
            rows.append(UsageRow(id: spec.key, name: spec.name, sub: spec.sub,
                                 percent: utilization, resetsAt: reset, span: spec.span))
        }
        guard !rows.isEmpty else { throw UsageError.badFormat }
        return rows
    }

    private static func parseDate(_ s: String) -> Date? {
        // The API returns microseconds; drop the fraction so ISO8601DateFormatter always parses it.
        let stripped = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: stripped)
    }
}

// MARK: - Model

private enum CodexUsageService {
    private struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int
        let resetsAt: Double?
    }

    private struct Limits: Decodable {
        let primary: Window?
        let secondary: Window?
    }

    private struct Result: Decodable {
        let rateLimits: Limits
    }

    private struct Reply: Decodable {
        let result: Result
    }

    enum Failure: LocalizedError {
        case missingCLI, unavailable

        var errorDescription: String? {
            switch self {
            case .missingCLI: return "Codex CLI was not found."
            case .unavailable: return "Could not fetch Codex limits. Make sure Codex CLI is signed in to ChatGPT."
            }
        }
    }

    static func load() async throws -> [UsageRow] {
        try await Task.detached(priority: .utility) {
            try fetch()
        }.value
    }

    private static func fetch() throws -> [UsageRow] {
        let directories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin"]
        guard let executable = directories.filter({ $0.hasPrefix("/") })
            .map({ $0 + "/codex" })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw Failure.missingCLI
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 12, execute: timeout)
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            timeout.cancel()
        }

        var buffer = Data()
        func send(_ message: String) throws {
            try input.fileHandleForWriting.write(contentsOf: Data((message + "\n").utf8))
        }
        func receive(id: Int) throws -> Data {
            while true {
                if let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
                    if object?["id"] as? Int == id {
                        guard object?["result"] != nil else { throw Failure.unavailable }
                        return line
                    }
                } else {
                    let chunk = output.fileHandleForReading.availableData
                    guard !chunk.isEmpty else { throw Failure.unavailable }
                    buffer.append(chunk)
                }
            }
        }

        try send(#"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"agents-usage","version":"1.0"}}}"#)
        _ = try receive(id: 1)
        try send(#"{"method":"initialized"}"#)
        try send(#"{"id":2,"method":"account/rateLimits/read"}"#)
        let limits = try JSONDecoder().decode(Reply.self, from: receive(id: 2)).result.rateLimits
        return [limits.primary, limits.secondary].compactMap { $0 }.map { window in
            let name: String
            switch window.windowDurationMins {
            case 300: name = "5-hour limit"
            case 10080: name = "Weekly"
            default: name = "\(window.windowDurationMins)-minute limit"
            }
            return UsageRow(id: String(window.windowDurationMins), name: name, sub: nil,
                            percent: window.usedPercent,
                            resetsAt: window.resetsAt.map(Date.init(timeIntervalSince1970:)),
                            span: Double(window.windowDurationMins) * 60)
        }
    }
}

@MainActor
final class UsageModel: ObservableObject {
    @Published var rows: [UsageRow] = []
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    @Published var isLoading = false
    @Published var codexRows: [UsageRow] = []
    @Published var codexError: String?

    private var lastFetch = Date.distantPast
    private var timer: Timer?

    init() {
        refresh(manual: false)
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(manual: false) }
        }
    }

    var menuTitle: String {
        func summary(_ prefix: String, _ readings: [UsageRow]) -> String {
            func percent(for span: TimeInterval) -> String {
                guard let row = readings.first(where: { $0.span == span }) else { return "  –" }
                return String(format: "%3.0f", row.percent)
            }
            return "\(prefix) \(percent(for: 18000))/\(percent(for: 604800)) %"
        }
        return summary("A", rows) + "\n" + summary("O", codexRows)
    }

    var menuImage: NSImage {
        let title = menuTitle
        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        let lineHeight: CGFloat = 10
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let lines = title.components(separatedBy: "\n")
        let width = lines.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0
        let image = NSImage(size: NSSize(width: ceil(width), height: lineHeight * 2), flipped: true) { _ in
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: NSPoint(x: 0, y: CGFloat(index) * lineHeight - 1),
                                        withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    func refresh(manual: Bool) {
        guard !isLoading else { return }
        if manual, Date().timeIntervalSince(lastFetch) < 15 { return }
        isLoading = true
        Task {
            async let codex: Void = loadCodex()
            await load()
            await codex
            lastFetch = Date()
            isLoading = false
        }
    }

    private func loadCodex() async {
        do {
            codexRows = try await CodexUsageService.load()
            codexError = nil
        } catch {
            codexError = error.localizedDescription
        }
    }

    private func load() async {
        guard let credentials = await UsageService.readCredentials() else {
            errorMessage = UsageError.noCredentials.message
            return
        }
        if let expiry = credentials.expiresAt, expiry < Date() {
            errorMessage = UsageError.expired.message
            return
        }
        do {
            let (status, data) = try await UsageService.request(token: credentials.token)
            switch status {
            case 200..<300: break
            case 401, 403: throw UsageError.unauthorized(status)
            case 429: throw UsageError.rateLimited
            default: throw UsageError.http(status)
            }
            rows = try UsageService.parseRows(data)
            errorMessage = nil
            lastUpdated = Date()
        } catch let error as UsageError {
            errorMessage = error.message
        } catch {
            errorMessage = "Could not fetch usage (\(error.localizedDescription))."
        }
    }

}

// MARK: - Views

private enum UsageColumns {
    static let percent: CGFloat = 44
    static let reset: CGFloat = 70
    static let spacing: CGFloat = 8
}

struct RowView: View {
    let row: UsageRow
    let now: Date
    let barColor: Color

    private var pct: Double { min(100, max(0, row.percent)) }
    private var percentColor: Color { pct >= 80 ? .red : (pct >= 50 ? .orange : .primary) }
    private var left: TimeInterval? { row.resetsAt.map { $0.timeIntervalSince(now) } }
    private var elapsed: Double? { left.map { min(1, max(0, 1 - $0 / row.span)) } }
    private var percentText: String { String(format: "%.0f%%", row.percent) }

    private var resetText: String {
        guard let date = row.resetsAt else { return "—" }
        let locale = Locale(identifier: "en_GB")
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return "Today " + date.formatted(.dateTime.hour().minute().locale(locale))
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(locale))
    }

    private var leftText: String {
        guard let left else { return "Reset time unavailable" }
        if left <= 0 { return "Resets soon" }
        let minutes = Int((left / 60).rounded())
        if minutes < 60 { return "\(minutes)m left" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m left" }
        return "\(hours / 24)d \(hours % 24)h left"
    }

    var body: some View {
        let subtitle = Text(row.sub.map { " · \($0)" } ?? "").foregroundColor(.secondary)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: UsageColumns.spacing) {
                Text("\(row.name)\(subtitle)")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(percentText)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(percentColor)
                    .frame(width: UsageColumns.percent, alignment: .trailing)
                Text(resetText)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: UsageColumns.reset, alignment: .trailing)
                    .help(leftText)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(barColor).frame(width: geo.size.width * pct / 100)
                    if let elapsed {
                        Rectangle()
                            .fill(Color.primary.opacity(0.55))
                            .frame(width: 1, height: 7)
                            .offset(x: min(max(0, geo.size.width - 1), geo.size.width * elapsed))
                    }
                }
            }
            .frame(height: 7)
            .help(elapsed == nil ? "Usage in this window" : "The marker shows how much of this window has elapsed.")
            .accessibilityHidden(true)
        }
    }
}

struct UsagePanel: View {
    @EnvironmentObject var model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 10) {
                    section("Claude", rows: model.rows, error: model.errorMessage, now: context.date,
                            barColor: Color(nsColor: UsagePalette.claude),
                            showColumnHeaders: !model.rows.isEmpty || !model.codexRows.isEmpty)
                    Divider()
                    section("Codex", rows: model.codexRows, error: model.codexError, now: context.date,
                            barColor: UsagePalette.codex)
                }
            }

            Divider()
            HStack {
                Button { model.refresh(manual: true) } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.isLoading)
                    .help("Refresh")
                if model.isLoading {
                    Text("Refreshing…")
                } else if let updated = model.lastUpdated {
                    Text("Updated " + updated.formatted(.dateTime.hour().minute().locale(Locale(identifier: "en_GB"))))
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 269)
    }

    private func section(_ title: String, rows: [UsageRow], error: String?, now: Date,
                         barColor: Color, showColumnHeaders: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: UsageColumns.spacing) {
                Text(title).font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                if showColumnHeaders {
                    Spacer(minLength: 0)
                    Text("Used").frame(width: UsageColumns.percent, alignment: .trailing)
                    Text("Resets").frame(width: UsageColumns.reset, alignment: .trailing)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if rows.isEmpty {
                Text(model.isLoading ? "Loading…" : "No data yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { RowView(row: $0, now: now, barColor: barColor) }
        }
    }
}

// MARK: - App

@main
struct AgentsUsageApp: App {
    @StateObject private var model = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePanel().environmentObject(model)
        } label: {
            Image(nsImage: model.menuImage)
                .accessibilityLabel(model.menuTitle)
        }
        .menuBarExtraStyle(.window)
    }
}
