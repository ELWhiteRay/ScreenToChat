import Foundation

@MainActor
final class DevToolsClient {
    struct SendResult {
        let method: String
        let response: String
    }

    private let socket: URLSessionWebSocketTask
    private var nextID = 0

    private init(socketURL: URL) {
        socket = URLSession.shared.webSocketTask(with: socketURL)
        socket.resume()
    }

    deinit {
        socket.cancel(with: .goingAway, reason: nil)
    }

    static func send(imageAt imageURL: URL) async throws -> SendResult {
        let client = try await connect()
        let previousTurn = try await client.lastTurnKey()
        let filename = try await client.attachImage(at: imageURL)
        let method = try await client.waitAndPressSend(filename: filename)
        AppLog.write("SEND DevTools submitted; method=\(method)")
        AppLog.write("RESPONSE DOM polling started")
        let response = try await client.waitForResponse(after: previousTurn)
        return SendResult(method: method, response: response)
    }

    static func prepareChat() async throws {
        let client = try await connect()
        AppLog.write("PROMPT opening prepared chat")
        guard let opened: String = try await client.value(of: ChatGPTDOM.openPreparedChat),
              opened.hasPrefix("opened:") else {
            throw DevToolsError.preparedChatMissing
        }
        AppLog.write("PROMPT prepared chat selected; \(opened)")
    }

    static func isAvailable() async -> Bool {
        (try? await connect()) != nil
    }

    static func waitUntilAvailable() async throws {
        for _ in 0..<8 {
            if await isAvailable() { return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw DevToolsError.unavailable
    }

    private static func connect() async throws -> DevToolsClient {
        let endpoint = URL(string: "http://127.0.0.1:9222/json/list")!
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 2
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw DevToolsError.unavailable
        }
        let targets = try JSONDecoder().decode([DevToolsTarget].self, from: data)
        guard let socketURL = targets.first(where: {
            $0.type == "page" && $0.url == "app://-/index.html" && $0.webSocketDebuggerUrl != nil
        })?.webSocketDebuggerUrl else {
            throw DevToolsError.noPage
        }
        return DevToolsClient(socketURL: socketURL)
    }

    private func lastTurnKey() async throws -> String {
        let expression = "[...document.querySelectorAll('[data-turn-key]')].at(-1)?.dataset.turnKey || ''"
        return try await value(of: expression) ?? ""
    }

    private func attachImage(at imageURL: URL) async throws -> String {
        let filename = "screen-to-chat-\(UUID().uuidString).png"
        let base64 = try Data(contentsOf: imageURL).base64EncodedString()
        let expression = ChatGPTDOM.attachImage(filename: filename, base64: base64)
        guard try await value(of: expression) == "attached" else {
            throw DevToolsError.attachmentFailed
        }
        return filename
    }

    private func waitAndPressSend(filename: String) async throws -> String {
        let expression = Self.pressSendScript(filename: filename)
        for _ in 0..<40 {
            if let result: String = try await value(of: expression), result != "waiting" {
                return result
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw DevToolsError.noSendButton
    }

    private func waitForResponse(after previousTurn: String) async throws -> String {
        var latest = ""
        let expression = Self.responseScript(previousTurn: previousTurn)
        for _ in 0..<180 {
            if let json: String = try await value(of: expression),
               let data = json.data(using: .utf8),
               let state = try? JSONDecoder().decode(DevToolsResponseState.self, from: data) {
                latest = state.text
                if state.ready, !latest.isEmpty { return latest }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        if !latest.isEmpty { return latest }
        throw DevToolsError.noResponse
    }

    private func value<T>(of expression: String) async throws -> T? {
        let response = try await call("Runtime.evaluate", [
            "expression": expression, "returnByValue": true, "awaitPromise": true
        ])
        return (response["result"] as? [String: Any])?["value"] as? T
    }

    private func call(_ method: String, _ parameters: [String: Any]) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id, "method": method, "params": parameters
        ])
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
        while true {
            let message = try await socket.receive()
            let responseData: Data
            switch message {
            case .data(let data): responseData = data
            case .string(let text): responseData = Data(text.utf8)
            @unknown default: continue
            }
            guard let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                  response["id"] as? Int == id else {
                await Task.yield()
                continue
            }
            if let error = response["error"] as? [String: Any] {
                throw DevToolsError.protocolError(error["message"] as? String ?? "unknown")
            }
            return response["result"] as? [String: Any] ?? [:]
        }
    }

    private static func pressSendScript(filename: String) -> String {
        """
        (() => {
          const editor = document.querySelector('[data-codex-composer=true]');
          const attachment = document.querySelector('button[aria-label="Remove \(filename)"]');
          for (let root = editor, depth = 0; root && depth < 8; root = root.parentElement, depth++) {
            const buttons = [...root.querySelectorAll('button.bg-token-foreground:not(:disabled)')];
            const arrow = buttons.find(button =>
              button.querySelector('svg path[d^="M9.33467"]'));
            if (attachment && root.contains(attachment) && arrow) {
              arrow.click();
              return 'button:composer-arrow';
            }
          }
          return 'waiting';
        })()
        """
    }

    private static func responseScript(previousTurn: String) -> String {
        """
        (() => {
          const turn = [...document.querySelectorAll('[data-turn-key]')].at(-1);
          if (!turn || turn.dataset.turnKey === '\(previousTurn)')
            return JSON.stringify({text: '', ready: false});
          const assistants = [...turn.querySelectorAll('[data-content-search-unit-key$=":assistant"]')]
            .filter(assistant => assistant.getClientRects().length > 0);
          const lines = assistants
            .flatMap(assistant => (assistant.innerText || '').split('\\n'))
            .map(line => line.trim())
            .filter(Boolean);
          if (/^\\d{1,2}:\\d{2}$/.test(lines.at(-1) || '')) lines.pop();
          const text = lines.join('\\n');
          const editor = document.querySelector('[data-codex-composer=true]');
          let ready = false;
          for (let root = editor, depth = 0; root && depth < 8; root = root.parentElement, depth++) {
            ready ||= [...root.querySelectorAll('button.bg-token-foreground:not(:disabled)')]
              .some(button => button.querySelector('svg path[d^="M9.33467"]'));
          }
          return JSON.stringify({text, ready});
        })()
        """
    }

}
