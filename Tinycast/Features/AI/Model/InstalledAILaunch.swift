import Foundation

struct InstalledAIOverride: Codable, Equatable, Sendable {
    /// Empty leaves finding the command to `ExecutableLocator`.
    var commandPath = ""
    /// Names only, in the reader's order; a value is often a key, so values live in the Keychain.
    var environmentNames: [String] = []

    var isEmpty: Bool { commandPath.isEmpty && environmentNames.isEmpty }
}

/// One variable as the reader edits it: the name from settings, the value from the Keychain.
struct InstalledAIVariable: Equatable, Sendable {
    var name: String
    var value: String
}

/// Where the variables' values are kept, behind closures so a harness needs no Keychain.
struct InstalledAIEnvironmentStore: Sendable {
    /// Throws when the values cannot be read, so an editor never takes that for none being set.
    var values: @Sendable (InstalledAIKind) throws -> [String: String]
    var save: @Sendable ([String: String], InstalledAIKind) throws -> Void

    static let none = InstalledAIEnvironmentStore(values: { _ in [:] }, save: { _, _ in })
}

/// An override resolved for one launch: the path checked, the variables' values read.
struct InstalledAILaunch: Equatable, Sendable {
    enum Command: Equatable, Sendable {
        /// No path was set, so the command is looked up the way a Terminal would find it.
        case automatic
        case executable(URL)
        /// A path was set and nothing runnable is there; the lookup is not a fallback for it.
        case missing(path: String)
    }

    var commandPath = ""
    var environment: [String: String] = [:]

    init(commandPath: String = "", environment: [String: String] = [:]) {
        self.commandPath = commandPath
        self.environment = environment
    }

    /// The set path wins or fails: falling back would hide the mistake the path was set to fix.
    func command(
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> Command {
        let trimmed = commandPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .automatic }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), isExecutable(expanded) else {
            return .missing(path: trimmed)
        }
        return .executable(URL(fileURLWithPath: expanded))
    }

    /// What a launch inherits: the app's variables under the reader's, minus those Tinycast sets.
    func inherited(
        for kind: InstalledAIKind,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let mine = environment.filter {
            Self.isVariableName($0.key) && !kind.isManagedVariable($0.key)
        }
        return base.merging(mine) { _, new in new }
    }

    static func missingCommandMessage(_ path: String) -> String {
        String(localized: "Nothing can be run at \(path). Check the command path.")
    }

    nonisolated static func isVariableName(_ name: String) -> Bool {
        guard let first = name.first, first == "_" || (first.isASCII && first.isLetter) else {
            return false
        }
        return name.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }
}

extension InstalledAIKind {
    /// Set on every chat launch to keep the tool inside the chat; a reader's value never wins.
    var managedEnvironment: [String: String] {
        switch self {
        case .openCode:
            return ["OPENCODE_CONFIG_CONTENT": Self.openCodeConfiguration]
        case .claude:
            return ["CLAUDE_CODE_SKIP_PROMPT_HISTORY": "1", "ENABLE_CLAUDEAI_MCP_SERVERS": "false"]
        case .grok:
            return ["GROK_DISABLE_AUTOUPDATER": "1", "GROK_AGENT_DASHBOARD": "0"]
        case .antigravity, .cursor, .codex:
            return [:]
        }
    }

    /// `NO_COLOR` keeps output parseable; `TC_MCP_` names carry Tinycast's MCP secrets to Codex.
    func isManagedVariable(_ name: String) -> Bool {
        name == "NO_COLOR" || name.hasPrefix("TC_MCP_") || managedEnvironment[name] != nil
    }

    static let antigravityNoToolsHooks =
        #"{"tinycast-no-tools":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","#
        + #""command":"printf '{\"decision\":\"deny\","#
        + #"\"reason\":\"Tools are disabled inside Tinycast.\"}\\n'"}]}]}}"#

    static let antigravitySessionRequestID = InstalledAIModel.antigravitySessionRequestID
    static let antigravityModelRequestID = 3
    static let antigravityPromptRequestID = 4

    static func antigravitySessionRequest(
        workspacePath: String, instructions: String,
        mcpEndpoint: OpenCodeMCPLaunch.Endpoint? = nil
    ) -> Data? {
        let servers: [[String: Any]] =
            mcpEndpoint.map { endpoint in
                [
                    [
                        "type": "http",
                        "name": OpenCodeMCPLaunch.antigravityServer,
                        "url": endpoint.url,
                        "headers": [
                            ["name": "Authorization", "value": "Bearer " + endpoint.bearer]
                        ]
                    ]
                ]
            } ?? []
        let session: [String: Any] = [
            "jsonrpc": "2.0", "id": antigravitySessionRequestID, "method": "session/new",
            "params": [
                "cwd": workspacePath,
                "mcpServers": servers,
                "_meta": [
                    "antigravity": [
                        "disableBuiltInTools": true,
                        "systemPrompt": ["append": instructions]
                    ]
                ]
            ]
        ]
        return jsonLines([InstalledAIModel.antigravityInitializeRequest(), session])
    }

    static func antigravityPromptRequest(
        sessionID: String, model: String, effort: String?, availableModels: Set<String> = [],
        prompt: String, images: [AIImage] = []
    ) -> Data? {
        let suffixed = effort.map { "\(model)-\($0)" }
        let resolvedModel: String
        if let suffixed, availableModels.isEmpty || availableModels.contains(suffixed) {
            resolvedModel = suffixed
        } else {
            resolvedModel = model
        }
        let setModel: [String: Any] = [
            "jsonrpc": "2.0", "id": antigravityModelRequestID, "method": "session/set_model",
            "params": ["sessionId": sessionID, "modelId": resolvedModel]
        ]
        let pictures: [[String: Any]] = images.map { image in
            [
                "type": "image",
                "mimeType": image.mimeType,
                "data": image.data.base64EncodedString()
            ]
        }
        let sendPrompt: [String: Any] = [
            "jsonrpc": "2.0", "id": antigravityPromptRequestID, "method": "session/prompt",
            "params": [
                "sessionId": sessionID,
                "prompt": pictures + [["type": "text", "text": prompt]]
            ]
        ]
        return jsonLines([setModel, sendPrompt])
    }

    static func antigravityServerReply(_ object: [String: Any]) -> Data? {
        guard let method = object["method"] as? String, let id = object["id"] else { return nil }
        if method == "session/request_permission",
            let params = object["params"] as? [String: Any],
            let options = params["options"] as? [[String: Any]],
            let rejected = options.first(where: {
                (($0["kind"] as? String) ?? "").lowercased().contains("reject")
            }),
            let optionID = rejected["optionId"] as? String
        {
            return jsonLines([
                [
                    "jsonrpc": "2.0", "id": id,
                    "result": ["outcome": ["outcome": "selected", "optionId": optionID]]
                ]
            ])
        }
        return jsonLines([
            [
                "jsonrpc": "2.0", "id": id,
                "error": ["code": -32601, "message": "Tinycast does not answer this request."]
            ]
        ])
    }

    private static func jsonLines(_ objects: [[String: Any]]) -> Data? {
        var output = Data()
        for object in objects {
            guard let line = try? JSONSerialization.data(withJSONObject: object) else {
                return nil
            }
            output.append(line)
            output.append(0x0A)
        }
        return output
    }

    static let openCodeAgent = "tinycast"

    /// A trailing `*` deny drops every tool from the request, not just refuses the call.
    private static let openCodeConfiguration = """
        {"share":"disabled","snapshots":false,"agents":{"\(openCodeAgent)":{"system":\
        "You are generating text inside Tinycast. Use only the conversation in this request.",\
        "permissions":[{"action":"*","resource":"*","effect":"deny"}]}}}
        """
}
