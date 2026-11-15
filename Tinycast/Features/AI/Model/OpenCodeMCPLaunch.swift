import Foundation

enum OpenCodeMCPLaunch {
    struct Endpoint: Equatable, Sendable {
        let url: String
        let bearer: String
    }

    static let antigravityServer = "tinycast_bridge"

    static var antigravityToolPrefix: String {
        "mcp_\(antigravityServer)_"
    }

    static func configuration(
        server: String, url: String, bearer: String, tools: [AITool]
    ) throws -> String {
        var permissions: [[String: String]] = [
            ["action": "*", "resource": "*", "effect": "deny"]
        ]
        permissions += tools.indices.map {
            ["action": server + "_" + toolName(at: $0), "resource": "*", "effect": "allow"]
        }
        let config: [String: Any] = [
            "share": "disabled", "snapshots": false,
            "agents": [
                InstalledAIKind.openCodeAgent: [
                    "system": "You are generating text inside Tinycast. Use only the supplied MCP tools.",
                    "permissions": permissions
                ]
            ],
            "mcp": [
                "servers": [
                    server: [
                        "type": "remote", "url": url, "oauth": false, "codemode": false,
                        "headers": ["Authorization": "Bearer " + bearer]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw AIProviderError.malformedResponse
        }
        return text
    }

    /// `/usr/bin/plutil` ships with macOS and blocks global MCP servers while allowing the bridge.
    static var antigravityBridgeHooks: String {
        let command =
            "name=$(/usr/bin/plutil -extract toolCall.name raw -o - - 2>/dev/null); "
            + "case \"$name\" in \(antigravityToolPrefix)*) "
            + "printf '{\"decision\":\"allow\"}\\n';; "
            + "*) printf '{\"decision\":\"deny\","
            + "\"reason\":\"Tools are disabled inside Tinycast.\"}\\n';; esac"
        let payload: [String: Any] = [
            "tinycast-mcp": [
                "PreToolUse": [
                    [
                        "matcher": "*",
                        "hooks": [["type": "command", "command": command]]
                    ]
                ]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            let text = String(bytes: data, encoding: .utf8)
        else { return InstalledAIKind.antigravityNoToolsHooks }
        return text
    }

    static func toolName(at index: Int) -> String { "tool_\(index)" }
}
