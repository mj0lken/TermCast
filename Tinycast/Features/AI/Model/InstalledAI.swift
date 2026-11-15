import Foundation

enum InstalledAIKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex
    case claude
    case antigravity
    case grok
    case openCode
    case cursor

    /// Every installed CLI except Codex, which talks through its app-server instead.
    static let managedCLIKinds: [InstalledAIKind] = [
        .claude, .antigravity, .grok, .openCode, .cursor
    ]

    var id: String { rawValue }

    /// OpenCode's JSON stream has no closing line, so a clean exit is its finish.
    var finishesAtExit: Bool { self == .openCode }

    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .antigravity: return "Antigravity"
        case .grok: return "Grok"
        case .openCode: return "OpenCode"
        case .cursor: return "Cursor"
        }
    }

    var command: String {
        switch self {
        case .codex: return "codex"
        case .claude: return "claude"
        case .antigravity: return "agy"
        case .grok: return "grok"
        case .openCode: return "opencode"
        case .cursor: return "agent"
        }
    }

    var installURL: URL {
        switch self {
        case .codex: return URL(string: "https://developers.openai.com/codex/cli")!
        case .claude: return URL(string: "https://code.claude.com/docs/en/setup")!
        case .antigravity: return URL(string: "https://antigravity.google/docs/cli/reference")!
        case .grok: return URL(string: "https://x.ai/cli")!
        case .openCode: return URL(string: "https://opencode.ai/v2/docs")!
        case .cursor: return URL(string: "https://cursor.com/docs/cli/overview")!
        }
    }

    /// Installs that put their command outside every shared `bin` the locator already walks.
    var extraExecutablePaths: [String] {
        switch self {
        case .claude: return [".claude/local/claude"]
        case .grok: return [".grok/bin/grok"]
        case .codex, .antigravity, .openCode, .cursor: return []
        }
    }

    var source: AIModelSource {
        switch self {
        case .codex: return .codex
        case .claude: return .claude
        case .antigravity: return .antigravity
        case .grok: return .grok
        case .openCode: return .openCode
        case .cursor: return .cursor
        }
    }

    /// What the Providers row says: Cursor keeps the reader's MCP; a managed policy owns Claude's.
    func isolationCaveat(hasManagedMCPPolicy: Bool) -> String? {
        switch self {
        case .cursor: return String(localized: "Ask mode · your Cursor MCP servers still apply")
        case .claude:
            return hasManagedMCPPolicy
                ? String(localized: "Claude’s MCP configuration is managed by your organization.") : nil
        case .codex, .antigravity, .grok, .openCode: return nil
        }
    }

    var signInCommand: String {
        switch self {
        case .codex: return "codex login"
        case .claude: return "claude auth login"
        case .antigravity: return "agy acp --login"
        case .grok: return "grok login"
        case .openCode: return "opencode auth login"
        case .cursor: return "agent login"
        }
    }
}

extension AIModelSource {
    /// The installed command behind this source, or `nil` for the two routes Tinycast reaches itself.
    var installedKind: InstalledAIKind? {
        switch self {
        case .codex: return .codex
        case .claude: return .claude
        case .antigravity: return .antigravity
        case .grok: return .grok
        case .openCode: return .openCode
        case .cursor: return .cursor
        case .appleIntelligence, .api: return nil
        }
    }
}

struct InstalledAIModel: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let efforts: [ChatGPTSubscription.Effort]
    let acceptsImages: Bool
    let supportsTools: Bool

    init(
        id: String, name: String, efforts: [ChatGPTSubscription.Effort] = [],
        acceptsImages: Bool = false, supportsTools: Bool = false
    ) {
        self.id = id
        self.name = name
        self.efforts = efforts
        self.acceptsImages = acceptsImages
        self.supportsTools = supportsTools
    }

    func resolvedEffort(_ preferred: String?) -> String? {
        guard !efforts.isEmpty else { return nil }
        if let preferred, efforts.contains(where: { $0.id == preferred }) { return preferred }
        if efforts.contains(where: { $0.id == "high" }) { return "high" }
        return efforts.first?.id
    }

    /// What Claude's `initialize` control request asks for; the answer is its own `/model` list.
    static let claudeInitializeRequest =
        #"{"type":"control_request","request_id":"tinycast-models","request":{"subtype":"initialize"}}"#
        + "\n"

    static let claudeTitleRequestID = "tinycast-title"

    /// Claude Code's own session namer, asked without persisting anything to its history.
    static func claudeTitleRequest(_ description: String) -> String? {
        let request: [String: Any] = [
            "type": "control_request", "request_id": claudeTitleRequestID,
            "request": [
                "subtype": "generate_session_title", "description": description,
                "persist": false
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: request),
            let line = String(bytes: data, encoding: .utf8)
        else { return nil }
        return line + "\n"
    }

    static func claudeTitle(_ output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                let response = object["response"] as? [String: Any],
                response["request_id"] as? String == claudeTitleRequestID,
                let payload = response["response"] as? [String: Any],
                let title = payload["title"] as? String
            else { continue }
            return title
        }
        return nil
    }

    /// The CLI's own picker, one row per resolved model: `default` only restates another entry.
    static func claudeCatalog(_ output: String) -> [InstalledAIModel] {
        for line in output.split(whereSeparator: \.isNewline) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                object["type"] as? String == "control_response",
                let response = object["response"] as? [String: Any],
                let payload = response["response"] as? [String: Any],
                let entries = payload["models"] as? [[String: Any]]
            else { continue }
            var models: [InstalledAIModel] = []
            var resolved = Set<String>()
            for entry in entries {
                guard let id = entry["value"] as? String, !id.isEmpty, id != "default" else {
                    continue
                }
                let target = entry["resolvedModel"] as? String ?? id
                guard resolved.insert(target).inserted else { continue }
                models.append(
                    InstalledAIModel(
                        id: id, name: claudeName(entry, fallback: id),
                        efforts: (entry["supportedEffortLevels"] as? [String] ?? []).map {
                            ChatGPTSubscription.Effort(id: $0, detail: nil)
                        }))
            }
            return models
        }
        return []
    }

    /// The same answer that lists the models names the account; nothing more is asked for it.
    static func claudeAccount(_ output: String) -> InstalledAIAccount? {
        for line in output.split(whereSeparator: \.isNewline) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                object["type"] as? String == "control_response",
                let response = object["response"] as? [String: Any],
                let payload = response["response"] as? [String: Any],
                let account = payload["account"] as? [String: Any]
            else { continue }
            let email = account["email"] as? String
            let plan = account["subscriptionType"] as? String
            guard email != nil || plan != nil else { return nil }
            return InstalledAIAccount(email: email, plan: plan)
        }
        return nil
    }

    /// An older CLI leads `description` with the version, "Opus 5.5 · Best…"; a newer one names it.
    private static func claudeName(_ entry: [String: Any], fallback: String) -> String {
        let parts = (entry["description"] as? String ?? "").components(separatedBy: " · ")
        let versioned = parts.count > 1 ? parts[0].trimmingCharacters(in: .whitespaces) : ""
        let displayed = entry["displayName"] as? String ?? ""
        let name = [versioned, displayed].first { !$0.isEmpty } ?? fallback
        return name.hasPrefix("Claude") ? name : "Claude " + name
    }

    /// `/effort` advertises these four; a model only honours the ones it supports.
    private static let grokEfforts = ["low", "medium", "high", "xhigh"].map {
        ChatGPTSubscription.Effort(id: $0, detail: nil)
    }

    static func grokCatalog(_ output: String) -> [InstalledAIModel] {
        let clean = output.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        var models: [InstalledAIModel] = []
        var seen = Set<String>()
        for raw in clean.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("*") || line.hasPrefix("-") else { continue }
            let rest = line.drop(while: { $0 == "*" || $0 == "-" || $0.isWhitespace })
            let token = rest.split(whereSeparator: { $0.isWhitespace || $0 == "(" }).first
            guard let token, !token.isEmpty else { continue }
            let id = String(token)
            guard seen.insert(id).inserted else { continue }
            models.append(InstalledAIModel(id: id, name: id, efforts: grokEfforts))
        }
        return models
    }

    /// `grok models` exits 0 and still prints the catalog when the CLI is signed out.
    static func grokSignedIn(_ output: String) -> Bool {
        let clean = output.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression
        )
        .lowercased()
        return !clean.contains("not authenticated") && !clean.contains("not signed in")
    }

    /// The server's `model.list` answer: only models whose provider OpenCode can already reach.
    static func openCodeCatalog(_ output: String) -> [InstalledAIModel] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
            let entries = object["data"] as? [[String: Any]]
        else { return [] }
        let models = entries.compactMap { entry -> InstalledAIModel? in
            guard let provider = entry["providerID"] as? String, let model = entry["id"] as? String
            else { return nil }
            let id = provider + "/" + model
            let variants = (entry["variants"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            let capabilities = entry["capabilities"] as? [String: Any] ?? [:]
            let input = capabilities["input"] as? [String] ?? []
            return InstalledAIModel(
                id: id, name: id,
                efforts: variants.sorted(by: effortOrder).map {
                    ChatGPTSubscription.Effort(id: $0, detail: nil)
                },
                acceptsImages: input.contains("image"),
                supportsTools: capabilities["tools"] as? Bool == true)
        }
        return models.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    /// `agent --list-models` lines look like `composer-2.5 - Composer 2.5`.
    static func cursorCatalog(_ output: String) -> [InstalledAIModel] {
        let clean = output.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        var models: [InstalledAIModel] = []
        var seen = Set<String>()
        for raw in clean.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = line.range(of: " - ") else { continue }
            let id = String(line[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            let name = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, !name.isEmpty, !seen.contains(id) else { continue }
            seen.insert(id)
            models.append(InstalledAIModel(id: id, name: name))
        }
        return models
    }

    enum AntigravityProbeOutcome: Equatable, Sendable {
        case ready(models: [InstalledAIModel], account: InstalledAIAccount?, sessionID: String?)
        case signInRequired
        case failed(String)
    }

    static let antigravitySessionRequestID = 2

    static func antigravityInitializeRequest() -> [String: Any] {
        [
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": [
                "protocolVersion": 1,
                "clientCapabilities": [
                    "fs": ["readTextFile": false, "writeTextFile": false],
                    "terminal": false
                ]
            ]
        ]
    }

    /// `session/new` validates credentials and lists active models without calling a model.
    static func antigravityProbeRequest(workspacePath: String) -> String? {
        let session: [String: Any] = [
            "jsonrpc": "2.0", "id": antigravitySessionRequestID, "method": "session/new",
            "params": ["cwd": workspacePath, "mcpServers": [] as [Any]]
        ]
        guard
            let first = try? JSONSerialization.data(
                withJSONObject: antigravityInitializeRequest()),
            let second = try? JSONSerialization.data(withJSONObject: session),
            let firstLine = String(bytes: first, encoding: .utf8),
            let secondLine = String(bytes: second, encoding: .utf8)
        else { return nil }
        return firstLine + "\n" + secondLine + "\n"
    }

    static func antigravityProbeAnswered(_ output: String) -> Bool {
        output.split(separator: "\n", omittingEmptySubsequences: false).dropLast().contains { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            else { return false }
            return (object["id"] as? NSNumber)?.intValue == antigravitySessionRequestID
        }
    }

    static func antigravityProbe(_ output: String) -> AntigravityProbeOutcome {
        for line in output.split(whereSeparator: \.isNewline) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                (object["id"] as? NSNumber)?.intValue == antigravitySessionRequestID
            else { continue }
            if let result = object["result"] as? [String: Any] {
                let sessionID = (result["sessionId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let catalog = antigravityCatalog(in: result)
                guard !catalog.isEmpty else {
                    return .failed(String(localized: "Antigravity returned no models."))
                }
                return .ready(
                    models: catalog, account: antigravityAccount(in: result), sessionID: sessionID)
            }
            if let error = object["error"] as? [String: Any] {
                let code = (error["code"] as? NSNumber)?.intValue
                let message = (error["message"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if antigravityNeedsSignIn(code: code, message: message) { return .signInRequired }
                let summary =
                    message.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty }
                return .failed(
                    summary ?? String(localized: "Antigravity could not verify its sign-in."))
            }
        }
        if antigravityNeedsSignIn(code: nil, message: output) { return .signInRequired }
        return .failed(
            String(
                localized: """
                    Antigravity did not finish its check. Update Antigravity CLI, then Check Again.
                    """))
    }

    /// Collapses effort-suffixed ACP variants (`*-low`, `*-high`) onto their base row.
    private static func antigravityCatalog(in result: [String: Any]) -> [InstalledAIModel] {
        guard let container = result["models"] as? [String: Any],
            let available = container["availableModels"] as? [[String: Any]]
        else { return [] }
        let options = antigravityModelOptions(in: result)
        var availableIDs: [String] = []
        var availableNames: [String: String] = [:]
        for entry in available {
            let id = (entry["modelId"] as? String ?? entry["id"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, availableNames[id] == nil else { continue }
            let name = (entry["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            availableIDs.append(id)
            availableNames[id] = name.isEmpty ? id : name
        }
        guard !options.isEmpty else {
            return availableIDs.map {
                InstalledAIModel(
                    id: $0, name: availableNames[$0] ?? $0, acceptsImages: true,
                    supportsTools: true)
            }
        }
        let knownEfforts = ["low", "medium", "high", "xhigh", "max"]
        var models: [InstalledAIModel] = []
        var consumed = Set<String>()
        for (baseID, baseName) in options {
            let offered = knownEfforts.filter { effort in
                availableNames[baseID + "-" + effort] != nil
            }
            if !offered.isEmpty {
                for effort in offered { consumed.insert(baseID + "-" + effort) }
                models.append(
                    InstalledAIModel(
                        id: baseID, name: baseName,
                        efforts: offered.sorted(by: effortOrder).map {
                            ChatGPTSubscription.Effort(id: $0, detail: nil)
                        },
                        acceptsImages: true, supportsTools: true))
            } else if availableNames[baseID] != nil {
                consumed.insert(baseID)
                models.append(
                    InstalledAIModel(
                        id: baseID, name: baseName, acceptsImages: true, supportsTools: true))
            }
        }
        for id in availableIDs where !consumed.contains(id) {
            models.append(
                InstalledAIModel(
                    id: id, name: availableNames[id] ?? id, acceptsImages: true,
                    supportsTools: true))
        }
        return models
    }

    private static func antigravityModelOptions(in result: [String: Any]) -> [(String, String)] {
        guard let configs = result["configOptions"] as? [[String: Any]] else { return [] }
        for config in configs where config["id"] as? String == "model" {
            let entries = config["options"] as? [[String: Any]] ?? []
            var seen = Set<String>()
            return entries.compactMap { entry in
                let id = (entry["value"] as? String ?? "").trimmingCharacters(
                    in: .whitespacesAndNewlines)
                guard !id.isEmpty, seen.insert(id).inserted else { return nil }
                let name = (entry["name"] as? String ?? "").trimmingCharacters(
                    in: .whitespacesAndNewlines)
                return (id, name.isEmpty ? id : name)
            }
        }
        return []
    }

    private static func antigravityAccount(in result: [String: Any]) -> InstalledAIAccount? {
        guard let meta = result["_meta"] as? [String: Any],
            let info = meta["antigravity"] as? [String: Any],
            let tier = info["tier"] as? [String: Any],
            let name = (tier["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        else { return nil }
        return InstalledAIAccount(email: nil, plan: name)
    }

    private static func antigravityNeedsSignIn(code: Int?, message: String) -> Bool {
        if code == 401 { return true }
        let lower = message.lowercased()
        let markers = [
            "please sign in", "sign in to", "authentication required", "not authenticated",
            "unauthenticated", "login required", "not logged in", "api key is missing",
            "invalid_grant"
        ]
        return markers.contains { lower.contains($0) }
    }

    private static func effortOrder(_ lhs: String, _ rhs: String) -> Bool {
        let order = ["none", "minimal", "low", "medium", "high", "xhigh", "max"]
        let left = order.firstIndex(of: lhs) ?? order.endIndex
        let right = order.firstIndex(of: rhs) ?? order.endIndex
        return left == right ? lhs < rhs : left < right
    }
}

/// Who a tool is signed in as, when it says; shown so the reader knows which account is billed.
struct InstalledAIAccount: Equatable, Sendable {
    let email: String?
    let plan: String?

    /// The CLI says "max" in one answer and "Claude Max" in another; a branded tier stands alone.
    var planTitle: String? {
        guard var title = plan?.trimmingCharacters(in: .whitespaces), !title.isEmpty else {
            return nil
        }
        if title.lowercased().hasPrefix("claude ") { title = String(title.dropFirst(7)) }
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    func formattedPlan(for kind: InstalledAIKind) -> String? {
        guard let plan = planTitle else { return nil }
        if kind == .antigravity { return plan }
        return "\(kind.title) \(plan)"
    }
}

struct InstalledAIStatus: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case checking
        case ready
        case signInRequired
        case notInstalled
        case failed(String)
    }

    var phase: Phase = .idle
    var version: String?
    var executable: URL?
    var models: [InstalledAIModel] = []
    var account: InstalledAIAccount?

    var isReady: Bool { phase == .ready && executable != nil && !models.isEmpty }
}
