import Foundation

@main
struct OpenCodeMCPTests {
    @MainActor
    static func main() async throws {
        let tool = AITool(
            name: "mcp_test_echo", description: "Echo", parameters: .object(["type": .string("object")]),
            origin: "Test", title: "Echo")
        var calls: [AIToolCall] = []
        var events: [AIStreamEvent] = []
        var failures: [String] = []
        let session = AIToolSession(tools: [tool], maxCalls: 2) { call in
            await MainActor.run { calls.append(call) }
            return AIToolResult(callID: call.id, content: call.arguments, isError: false)
        }
        let bridge = OpenCodeMCPBridge(session: session) {
            events.append($0)
        } failure: {
            failures.append($0)
        }
        let configuration = try await bridge.start()
        let config = JSONValue(data: Data(configuration.utf8))!.objectValue!
        let servers = config["mcp"]!.objectValue!["servers"]!.objectValue!
        let name = servers.keys.first!
        let server = servers[name]!.objectValue!
        let url = URL(string: server["url"]!.stringValue!)!
        let auth = server["headers"]!.objectValue!["Authorization"]!.stringValue!
        assert(url.host() == "127.0.0.1")
        assert(server["oauth"] == .bool(false) && server["codemode"] == .bool(false))
        let permissions = config["agents"]!.objectValue!["tinycast"]!.objectValue!["permissions"]!
            .arrayValue!
        assert(permissions.count == 2)
        assert(permissions[0].objectValue!["action"] == .string("*"))
        assert(permissions[0].objectValue!["effect"] == .string("deny"))
        let wireName = OpenCodeMCPLaunch.toolName(at: 0)
        assert(permissions[1].objectValue!["action"] == .string(name + "_" + wireName))
        assert((name + "_" + wireName).count <= 64)
        assert(permissions[1].objectValue!["effect"] == .string("allow"))

        let networkConfig = URLSessionConfiguration.ephemeral
        networkConfig.urlCache = nil
        let network = URLSession(configuration: networkConfig)
        defer { network.invalidateAndCancel(); bridge.stop() }
        func request(
            _ method: String, params: [String: Any] = [:], authorization: String? = nil,
            origin: String? = nil, notification: Bool = false, configuration: String? = nil
        ) async throws -> (Int, JSONValue?) {
            var destination = url
            var credential = auth
            if let configuration {
                let config = JSONValue(data: Data(configuration.utf8))!.objectValue!
                let server = config["mcp"]!.objectValue!["servers"]!.objectValue!.values.first!
                    .objectValue!
                destination = URL(string: server["url"]!.stringValue!)!
                credential = server["headers"]!.objectValue!["Authorization"]!.stringValue!
            }
            var request = URLRequest(url: destination)
            request.timeoutInterval = 5
            request.httpMethod = "POST"
            request.setValue(authorization ?? credential, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
            var object: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
            if !notification { object["id"] = 1 }
            request.httpBody = try JSONSerialization.data(withJSONObject: object)
            let (data, response) = try await network.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, JSONValue(data: data))
        }
        let unauthorized = try await request("tools/list", authorization: "Bearer wrong")
        assert(unauthorized.0 == 403)
        let browser = try await request("tools/list", origin: "https://example.com")
        assert(browser.0 == 403)
        for _ in 0..<20 {
            let rejected = try await request("tools/list", authorization: "Bearer wrong")
            assert(rejected.0 == 403)
            let ping = try await request("ping")
            assert(ping.0 == 200)
        }
        let initialized = try await request("initialize", params: ["protocolVersion": "2025-06-18"])
        assert(
            initialized.1?.objectValue?["result"]?.objectValue?["protocolVersion"]
                == .string("2025-06-18"))
        let notification = try await request("notifications/initialized", notification: true)
        assert(notification.0 == 202)
        let list = try await request("tools/list")
        assert(list.1?.objectValue?["result"]?.objectValue?["tools"]?.arrayValue?.count == 1)
        let unknown = try await request("tools/call", params: ["name": "shell", "arguments": [:]])
        assert(unknown.1?.objectValue?["result"]?.objectValue?["isError"] == .bool(true))
        assert(calls.isEmpty && events.isEmpty)
        let reply = try await request(
            "tools/call",
            params: [
                "name": wireName, "arguments": ["text": "hello"]
            ])
        assert(reply.1?.objectValue?["result"]?.objectValue?["isError"] == .bool(false))
        assert(calls.count == 1 && calls[0].name == tool.name)
        assert(JSONValue(data: Data(calls[0].arguments.utf8))?.objectValue?["text"] == .string("hello"))
        assert(
            events == [
                .toolCall(id: calls[0].id, origin: "Test", title: "Echo"),
                .toolResult(id: calls[0].id, isError: false)
            ])
        _ = try await request("tools/call", params: ["name": wireName])
        do {
            _ = try await request("tools/call", params: ["name": wireName])
        } catch {}
        assert(calls.count == 2 && failures.count == 1)
        bridge.stop()

        var running = 0
        var peak = 0
        var budgetFailures: [String] = []
        let budgetSession = AIToolSession(tools: [tool], maxCalls: nil) { call in
            await MainActor.run {
                running += 1
                peak = max(peak, running)
            }
            try? await Task.sleep(for: .milliseconds(20))
            await MainActor.run { running -= 1 }
            return .failure(call.id, String(repeating: "x", count: 100_000))
        }
        let budgetBridge = OpenCodeMCPBridge(session: budgetSession, event: { _ in }) {
            budgetFailures.append($0)
        }
        let budgetConfig = try await budgetBridge.start()
        async let first = request("tools/call", params: ["name": wireName], configuration: budgetConfig)
        async let second = request("tools/call", params: ["name": wireName], configuration: budgetConfig)
        let budgetReplies = try await [first, second]
        for reply in budgetReplies {
            let result = reply.1!.objectValue!["result"]!.objectValue!
            assert(result["isError"] == .bool(true))
            let text = result["content"]!.arrayValue![0].objectValue!["text"]!.stringValue!
            assert(text.utf8.count < 33_000 && text.hasSuffix("…truncated."))
        }
        assert(peak == 1)
        for _ in 0..<2 {
            _ = try await request("tools/call", params: ["name": wireName], configuration: budgetConfig)
        }
        do {
            _ = try await request("tools/call", params: ["name": wireName], configuration: budgetConfig)
        } catch {}
        assert(budgetFailures.count == 1)
        budgetBridge.stop()

        var started: CheckedContinuation<Void, Never>?
        var cancelled: CheckedContinuation<Void, Never>?
        var cancellationEvents: [AIStreamEvent] = []
        let cancellationSession = AIToolSession(tools: [tool], maxCalls: nil) { call in
            await MainActor.run {
                started?.resume(); started = nil
            }
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                await MainActor.run {
                    cancelled?.resume(); cancelled = nil
                }
            }
            return .failure(call.id, "Cancelled")
        }
        let cancellationBridge = OpenCodeMCPBridge(session: cancellationSession) {
            cancellationEvents.append($0)
        } failure: { _ in
            assertionFailure("Cancellation must not fail the turn")
        }
        let cancellationConfig = try await cancellationBridge.start()
        let pending = Task {
            try? await request("tools/call", params: ["name": wireName], configuration: cancellationConfig)
        }
        await withCheckedContinuation { started = $0 }
        cancellationBridge.stop()
        await withCheckedContinuation { cancelled = $0 }
        _ = await pending.value
        assert(cancellationEvents.count == 1)
        try await installedTurn(tool: tool)
        try await antigravityTurn(tool: tool)
        print("OpenCode MCP bridge tests passed")
    }

    @MainActor
    private static func installedTurn(tool: AITool) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appending(path: "opencode")
        let script = #"""
            #!/usr/bin/python3
            import json, os, sys, urllib.request
            assert '--standalone' in sys.argv
            assert sys.argv[sys.argv.index('--agent') + 1] == 'tinycast'
            config = json.loads(os.environ['OPENCODE_CONFIG_CONTENT'])
            prompt = sys.stdin.read()
            rules = config['agents']['tinycast']['permissions']
            assert rules[0] == {'action': '*', 'resource': '*', 'effect': 'deny'}
            if 'mcp' in config:
                assert 'The only tools you may use are the MCP tools' in prompt
                server = next(iter(config['mcp']['servers'].values()))
                def rpc(method, params):
                    body = json.dumps({'jsonrpc':'2.0', 'id':1, 'method':method, 'params':params}).encode()
                    request = urllib.request.Request(server['url'], data=body, headers=server['headers'])
                    return json.load(urllib.request.urlopen(request, timeout=5))['result']
                tools = rpc('tools/list', {})['tools']
                assert len(tools) == 1
                result = rpc('tools/call', {'name':tools[0]['name'], 'arguments':{'text':'through CLI'}})
                assert not result['isError']
                assert result['content'][0]['text'] == 'through CLI'
            else:
                assert len(rules) == 1
                assert 'Do not invoke tools' in prompt
            print(json.dumps({'type':'text', 'part':{'text':'Complete'}}), flush=True)
            """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        var invocations = 0
        let session = AIToolSession(tools: [tool], maxCalls: 1) { call in
            await MainActor.run { invocations += 1 }
            let arguments = JSONValue(data: Data(call.arguments.utf8))!.objectValue!
            return AIToolResult(
                callID: call.id, content: arguments["text"]!.stringValue!, isError: false)
        }
        for tools in [session, nil] {
            let provider = InstalledCLIProvider(
                kind: .openCode, executable: executable, model: "test/model", effort: nil,
                workspace: directory, toolSession: tools)
            var events: [AIStreamEvent] = []
            for try await event in provider.stream(
                AIRequest(messages: [AIMessage(role: .user, text: "Hello")]))
            {
                events.append(event)
            }
            assert(events.contains(.text("Complete")) && events.last == .finished)
            assert(events.count == (tools == nil ? 2 : 4))
        }
        assert(invocations == 1)
    }

    @MainActor
    private static func antigravityTurn(tool: AITool) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let dataRoot = directory.appending(path: "agy-data", directoryHint: .isDirectory)
        let workspace = directory.appending(path: "workspace", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appending(path: "agy")
        let script = #"""
            #!/usr/bin/python3
            import json, os, pathlib, subprocess, sys, urllib.request
            args = sys.argv[1:]
            assert args[:3] == ['acp', '--include-default-customizations=false', '--sandbox']
            init_req = json.loads(sys.stdin.readline())
            assert init_req['method'] == 'initialize' and init_req['id'] == 1
            session_req = json.loads(sys.stdin.readline())
            assert session_req['method'] == 'session/new' and session_req['id'] == 2
            params = session_req['params']
            assert params['cwd'] == os.path.realpath(os.getcwd())
            meta = params['_meta']['antigravity']
            assert meta['disableBuiltInTools'] is True
            servers = params['mcpServers']
            hooks = json.loads(pathlib.Path('.agents/hooks.json').read_text())
            if servers:
                assert '--dangerously-skip-permissions' in args
                assert 'mcp_tinycast_bridge_' in meta['systemPrompt']['append']
                hook_cmd = hooks['tinycast-mcp']['PreToolUse'][0]['hooks'][0]['command']
                allow_out = subprocess.run(
                    ['/bin/sh', '-c', hook_cmd],
                    input=json.dumps({'toolCall': {'name': 'mcp_tinycast_bridge_tool_0'}}),
                    text=True, capture_output=True, check=True
                ).stdout
                assert json.loads(allow_out)['decision'] == 'allow'
                deny_out = subprocess.run(
                    ['/bin/sh', '-c', hook_cmd],
                    input=json.dumps({'toolCall': {'name': 'run_command', 'args': {}}}),
                    text=True, capture_output=True, check=True
                ).stdout
                assert json.loads(deny_out)['decision'] == 'deny'
                bridge = servers[0]
                assert bridge['name'] == 'tinycast_bridge' and bridge['type'] == 'http'
                headers = {h['name']: h['value'] for h in bridge['headers']}
                def rpc(method, rpc_params):
                    body = json.dumps({'jsonrpc':'2.0', 'id':1, 'method':method, 'params':rpc_params}).encode()
                    req = urllib.request.Request(bridge['url'], data=body, headers=headers)
                    return json.load(urllib.request.urlopen(req, timeout=5))['result']
                tools = rpc('tools/list', {})['tools']
                assert len(tools) == 1
                res = rpc('tools/call', {'name': tools[0]['name'], 'arguments': {'text': 'via agy'}})
                assert not res['isError'] and res['content'][0]['text'] == 'via agy'
                conv_id = 'conv_agy_mcp'
            else:
                assert '--dangerously-skip-permissions' not in args
                assert 'Do not invoke tools' in meta['systemPrompt']['append']
                assert hooks['tinycast-no-tools']['PreToolUse'][0]['matcher'] == '*'
                conv_id = 'conv_agy_plain'
            print(json.dumps({'jsonrpc': '2.0', 'id': 1, 'result': {'protocolVersion': 1}}), flush=True)
            print(json.dumps({
                'jsonrpc': '2.0', 'id': 2,
                'result': {
                    'sessionId': conv_id,
                    'models': {'availableModels': [{'modelId': 'gemini-4-carbon-high'}]}
                }
            }), flush=True)
            model_req = json.loads(sys.stdin.readline())
            assert model_req['method'] == 'session/set_model' and model_req['id'] == 3
            assert model_req['params'] == {'sessionId': conv_id, 'modelId': 'gemini-4-carbon-high'}
            prompt_req = json.loads(sys.stdin.readline())
            assert prompt_req['method'] == 'session/prompt' and prompt_req['id'] == 4
            blocks = prompt_req['params']['prompt']
            assert blocks[0] == {'type': 'image', 'mimeType': 'image/png', 'data': 'iVA='}
            assert blocks[1]['type'] == 'text' and 'Hello Antigravity' in blocks[1]['text']
            data_dir = pathlib.Path(os.environ['TC_ANTIGRAVITY_DATA_DIR'])
            conv_dir = data_dir / 'conversations'
            brain_dir = data_dir / 'brain' / conv_id
            mcp_cache = data_dir / 'mcp' / 'tinycast_bridge'
            conv_dir.mkdir(parents=True, exist_ok=True)
            brain_dir.mkdir(parents=True, exist_ok=True)
            mcp_cache.mkdir(parents=True, exist_ok=True)
            (conv_dir / f'{conv_id}.db').write_text('sqlite')
            (conv_dir / f'{conv_id}.db-wal').write_text('wal')
            (brain_dir / 'notes.md').write_text('brain')
            (mcp_cache / 'tool_0.json').write_text('{}')
            print(json.dumps({
                'jsonrpc': '2.0', 'method': 'session/update',
                'params': {
                    'sessionId': conv_id,
                    'update': {'sessionUpdate': 'usage_update', 'used': 8, 'size': 1048576}
                }
            }), flush=True)
            print(json.dumps({
                'jsonrpc': '2.0', 'method': 'session/update',
                'params': {
                    'sessionId': conv_id,
                    'update': {
                        'sessionUpdate': 'agent_message_chunk',
                        'content': {'type': 'text', 'text': 'Pong'}
                    }
                }
            }), flush=True)
            print(json.dumps({
                'jsonrpc': '2.0', 'id': 4,
                'result': {
                    'stopReason': 'end_turn',
                    'usage': {
                        'inputTokens': 5, 'outputTokens': 3,
                        'thoughtTokens': 1, 'cachedReadTokens': 0, 'totalTokens': 8
                    }
                }
            }), flush=True)
            assert sys.stdin.read() == ''
            """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        var invocations = 0
        let session = AIToolSession(tools: [tool], maxCalls: 1) { call in
            await MainActor.run { invocations += 1 }
            let arguments = JSONValue(data: Data(call.arguments.utf8))!.objectValue!
            return AIToolResult(
                callID: call.id, content: arguments["text"]!.stringValue!, isError: false)
        }
        let image = AIImage(data: Data([0x89, 0x50]), mimeType: "image/png")
        for (tools, convID) in [(session, "conv_agy_mcp"), (nil, "conv_agy_plain")] {
            let provider = InstalledCLIProvider(
                kind: .antigravity, executable: executable, model: "gemini-4-carbon",
                effort: "high", workspace: workspace,
                launch: InstalledAILaunch(environment: ["TC_ANTIGRAVITY_DATA_DIR": dataRoot.path]),
                toolSession: tools)
            var events: [AIStreamEvent] = []
            for try await event in provider.stream(
                AIRequest(
                    messages: [AIMessage(role: .user, text: "Hello Antigravity", images: [image])]))
            {
                events.append(event)
            }
            assert(events.contains(.text("Pong")))
            assert(
                events.contains(
                    .usage(
                        AIUsage(
                            inputTokens: 5, outputTokens: 3, reasoningTokens: 1,
                            contextWindow: 1_048_576))))
            assert(events.last == .finished)
            assert(events.count == (tools == nil ? 3 : 5))
            let dbFile = dataRoot.appending(path: "conversations/\(convID).db")
            let walFile = dataRoot.appending(path: "conversations/\(convID).db-wal")
            let brainFolder = dataRoot.appending(path: "brain/\(convID)")
            let mcpCache = dataRoot.appending(path: "mcp/tinycast_bridge")
            for _ in 0..<25 where FileManager.default.fileExists(atPath: dbFile.path) {
                try await Task.sleep(for: .milliseconds(20))
            }
            assert(!FileManager.default.fileExists(atPath: dbFile.path))
            assert(!FileManager.default.fileExists(atPath: walFile.path))
            assert(!FileManager.default.fileExists(atPath: brainFolder.path))
            assert(!FileManager.default.fileExists(atPath: mcpCache.path))
            let remaining = (try? FileManager.default.contentsOfDirectory(atPath: workspace.path)) ?? []
            assert(remaining.isEmpty)
        }
        assert(invocations == 1)
    }
}

@MainActor
enum InstalledAIManager {
    static let hasManagedMCPPolicy = false
    static let claudeWithoutMCPArguments: [String] = []
}
