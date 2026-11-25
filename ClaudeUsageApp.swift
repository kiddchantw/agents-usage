import SwiftUI
import AppKit

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
    WindowSpec(key: "five_hour",        name: "目前工作階段", sub: nil,        span: 5 * 3600),
    WindowSpec(key: "seven_day",        name: "每週限制",     sub: "所有模型",  span: 7 * 86400),
    WindowSpec(key: "seven_day_opus",   name: "每週限制",     sub: "Opus",     span: 7 * 86400),
    WindowSpec(key: "seven_day_sonnet", name: "每週限制",     sub: "Sonnet",   span: 7 * 86400),
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
            return "找不到 Claude Code 的登入憑證。請先在終端機執行 claude 並登入,再按重新整理。macOS 若跳出鑰匙圈視窗,請選「允許」。"
        case .expired:
            return "Claude Code 的登入憑證已過期。開啟一次 Claude Code 讓它更新,再按重新整理。"
        case .unauthorized(let code):
            return "Anthropic 拒絕了這份憑證(HTTP \(code))。請重新登入 Claude Code 後再試。"
        case .rateLimited:
            return "查詢太頻繁(HTTP 429),稍後會自動重試。"
        case .http(let code):
            return "Anthropic 回應 HTTP \(code)。這個端點未公開,可能已經變更。按 {} 可以看原始回應。"
        case .network(let detail):
            return "連不上 Anthropic:\(detail)"
        case .badFormat:
            return "回應不是預期的格式。按 {} 可以看原始回應。"
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

@MainActor
final class UsageModel: ObservableObject {
    @Published var rows: [UsageRow] = []
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    @Published var isLoading = false
    @Published var raw = ""

    private var lastFetch = Date.distantPast
    private var timer: Timer?

    init() {
        refresh(manual: false)
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(manual: false) }
        }
    }

    var menuTitle: String {
        if rows.isEmpty { return errorMessage == nil ? "…" : "!" }
        return rows.prefix(2).map { "\(Int($0.percent.rounded()))%" }.joined(separator: " / ")
    }

    func refresh(manual: Bool) {
        guard !isLoading else { return }
        if manual, Date().timeIntervalSince(lastFetch) < 15 { return }
        isLoading = true
        Task {
            await load()
            lastFetch = Date()
            isLoading = false
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
            raw = Self.pretty(data)
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
            errorMessage = "讀取用量時出錯:\(error.localizedDescription)"
        }
    }

    private static func pretty(_ data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let formatted = try? JSONSerialization.data(withJSONObject: object,
                                                       options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: formatted, encoding: .utf8) {
            return text
        }
        return String(data: data.prefix(4000), encoding: .utf8) ?? ""
    }
}

// MARK: - Views

struct RowView: View {
    let row: UsageRow
    let now: Date

    private var pct: Double { min(100, max(0, row.percent)) }
    private var color: Color { pct >= 80 ? .red : (pct >= 50 ? .orange : .teal) }
    private var left: TimeInterval? { row.resetsAt.map { $0.timeIntervalSince(now) } }
    private var elapsed: Double? { left.map { min(1, max(0, 1 - $0 / row.span)) } }

    private var resetText: String {
        guard let date = row.resetsAt else { return "" }
        let weekly = row.span > 86400
        let style = weekly
            ? Date.FormatStyle().weekday(.abbreviated).hour().minute()
            : Date.FormatStyle().hour().minute()
        return "於 " + date.formatted(style.locale(Locale(identifier: "zh_TW"))) + " 重設"
    }

    private var leftText: String {
        guard let left else { return "" }
        if left <= 0 { return "即將重設" }
        let minutes = Int((left / 60).rounded())
        if minutes < 60 { return "剩 \(minutes) 分" }
        let hours = minutes / 60
        if hours < 24 { return "剩 \(hours) 小時 \(minutes % 60) 分" }
        return "剩 \(hours / 24) 天 \(hours % 24) 小時"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name).font(.system(size: 13, weight: .semibold))
                if let sub = row.sub {
                    Text(sub).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(row.percent.rounded()))")
                    .font(.system(size: 28, weight: .bold)).monospacedDigit()
                + Text("%")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(color).frame(width: max(6, geo.size.width * pct / 100))
                    if let elapsed {
                        Rectangle()
                            .fill(Color.primary.opacity(0.55))
                            .frame(width: 2, height: 14)
                            .offset(x: geo.size.width * elapsed - 1)
                    }
                }
            }
            .frame(height: 8)
            HStack {
                Text(resetText)
                Spacer()
                Text(leftText)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
    }
}

struct UsagePanel: View {
    @EnvironmentObject var model: UsageModel
    @State private var showRaw = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Claude 用量").font(.headline)
                Spacer()
                Button { showRaw.toggle() } label: { Image(systemName: "curlybraces") }
                    .help("原始回應")
                Button { model.refresh(manual: true) } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.isLoading)
                    .help("重新整理")
            }
            .buttonStyle(.borderless)

            if let message = model.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle().fill(Color.red).frame(width: 3)
                    Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
            }

            if showRaw {
                ScrollView {
                    Text(model.raw.isEmpty ? "尚無回應" : model.raw)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(model.rows) { RowView(row: $0, now: context.date) }
                    }
                }
                if model.rows.isEmpty && model.errorMessage == nil {
                    Text(model.isLoading ? "讀取中…" : "尚無資料").foregroundStyle(.secondary)
                }
            }

            HStack {
                if model.isLoading {
                    Text("更新中…")
                } else if let updated = model.lastUpdated {
                    Text("更新於 " + updated.formatted(date: .omitted, time: .shortened))
                }
                Spacer()
                if !model.rows.isEmpty && !showRaw {
                    Text("標線是時段已過的時間")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Divider()
            HStack {
                Button("開啟用量設定頁") {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
                }
                Spacer()
                Button("結束") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 300)
    }
}

// MARK: - App

@main
struct ClaudeUsageApp: App {
    @StateObject private var model = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePanel().environmentObject(model)
        } label: {
            Text(model.menuTitle).monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}
