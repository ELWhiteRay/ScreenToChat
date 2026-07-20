import Foundation

@MainActor
enum ElectronMainClient {
    enum ClientError: LocalizedError {
        case unavailable, evaluationFailed

        var errorDescription: String? {
            switch self {
            case .unavailable: "main-процесс ChatGPT недоступен"
            case .evaluationFailed: "ChatGPT не перешёл в фоновый режим"
            }
        }
    }

    private struct Target: Decodable {
        let webSocketDebuggerUrl: URL?
    }

    private final class Connection {
        private let socket: URLSessionWebSocketTask
        private var nextID = 0
        private var pausedFrameID: String?

        init(url: URL) {
            socket = URLSession.shared.webSocketTask(with: url)
            socket.resume()
        }

        deinit { socket.cancel(with: .goingAway, reason: nil) }

        func evaluate(_ expression: String) async throws -> String? {
            let parameters: [String: Any] = [
                "expression": expression, "returnByValue": true, "awaitPromise": true
            ]
            let response = try await call("Runtime.evaluate", parameters)
            if let details = response["exceptionDetails"] {
                AppLog.write("CHATGPT main evaluation failed: \(details)")
                throw ClientError.evaluationFailed
            }
            return (response["result"] as? [String: Any])?["value"] as? String
        }

        func prepareAndResume() async throws {
            _ = try await call("Runtime.enable", [:])
            _ = try await call("Debugger.enable", [:])
            _ = try await call("Runtime.runIfWaitingForDebugger", [:])
            guard let pausedFrameID else { throw ClientError.evaluationFailed }
            let expression = """
            (() => {
              const {app, BrowserWindow} = require('electron');
              app.setActivationPolicy('accessory');
              globalThis.__screenToChatWindowMethods = {
                show: BrowserWindow.prototype.show,
                focus: BrowserWindow.prototype.focus
              };
              BrowserWindow.prototype.show = function() {};
              BrowserWindow.prototype.focus = function() {};
              return 'prepared';
            })()
            """
            let response = try await call("Debugger.evaluateOnCallFrame", [
                "callFrameId": pausedFrameID,
                "expression": expression,
                "returnByValue": true
            ])
            if let details = response["exceptionDetails"] {
                AppLog.write("CHATGPT first-line preparation failed: \(details)")
                throw ClientError.evaluationFailed
            }
            guard (response["result"] as? [String: Any])?["value"] as? String == "prepared" else {
                throw ClientError.evaluationFailed
            }
            AppLog.write("CHATGPT main prepared at first line")
            _ = try await call("Debugger.resume", [:])
        }

        private func call(_ method: String, _ parameters: [String: Any]) async throws -> [String: Any] {
            nextID += 1
            let id = nextID
            let data = try JSONSerialization.data(withJSONObject: [
                "id": id, "method": method, "params": parameters
            ])
            try await socket.send(.string(String(decoding: data, as: UTF8.self)))
            var result: [String: Any]?
            while true {
                let message = try await socket.receive()
                let responseData: Data
                switch message {
                case .data(let data): responseData = data
                case .string(let text): responseData = Data(text.utf8)
                @unknown default: continue
                }
                guard let response = try JSONSerialization.jsonObject(with: responseData)
                        as? [String: Any] else { continue }
                if response["method"] as? String == "Debugger.paused",
                   let parameters = response["params"] as? [String: Any],
                   let callFrames = parameters["callFrames"] as? [[String: Any]],
                   let callFrameID = callFrames.first?["callFrameId"] as? String {
                    pausedFrameID = callFrameID
                    if method == "Runtime.runIfWaitingForDebugger", let result { return result }
                    continue
                }
                guard response["id"] as? Int == id else { continue }
                if response["error"] != nil { throw ClientError.evaluationFailed }
                result = response["result"] as? [String: Any] ?? [:]
                if method != "Runtime.runIfWaitingForDebugger" || pausedFrameID != nil {
                    return result ?? [:]
                }
            }
        }
    }

    static func isAvailable() async -> Bool { (try? await connect()) != nil }

    static func prepareAndResume() async throws {
        let client = try await waitForConnection()
        try await client.prepareAndResume()
        AppLog.write("CHATGPT main resumed")
        AppLog.write("CHATGPT main prepared as accessory and resumed")
    }

    static func showInBackground() async throws {
        let client = try await connect()
        try await showInBackground(using: client)
    }

    static func restoreWindowBehavior() async throws {
        let client = try await connect()
        let expression = """
        (() => {
          const load = process.getBuiltinModule('module').createRequire(process.execPath);
          const {BrowserWindow} = load('electron');
          const saved = globalThis.__screenToChatWindowMethods;
          if (!saved) return 'unchanged';
          BrowserWindow.prototype.show = saved.show;
          BrowserWindow.prototype.focus = saved.focus;
          delete globalThis.__screenToChatWindowMethods;
          return 'restored';
        })()
        """
        guard let result = try await client.evaluate(expression),
              result == "restored" || result == "unchanged" else {
            throw ClientError.evaluationFailed
        }
        AppLog.write("CHATGPT normal window behavior restored")
    }

    private static func showInBackground(using client: Connection) async throws {
        let expression = """
        (async () => {
          const load = process.getBuiltinModule('module').createRequire(process.execPath);
          const {app, BrowserWindow} = load('electron');
          await app.whenReady();
          app.setActivationPolicy('accessory');
          const windows = BrowserWindow.getAllWindows();
          app.show();
          windows.forEach(window => {
            window.webContents.setBackgroundThrottling(false);
            window.setSkipTaskbar(true);
            if (window.isMinimized()) window.restore();
            window.showInactive();
          });
          await new Promise(resolve => setTimeout(resolve, 250));
          app.dock?.hide();
          return !app.isHidden() && windows.some(window => window.isVisible())
            ? 'background-visible'
            : 'missing-window';
        })()
        """
        guard try await client.evaluate(expression) == "background-visible" else {
            throw ClientError.evaluationFailed
        }
        AppLog.write("CHATGPT window shown inactive; renderer kept active")
    }

    private static func waitForConnection() async throws -> Connection {
        for _ in 0..<8 {
            if let client = try? await connect() { return client }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw ClientError.unavailable
    }

    private static func connect() async throws -> Connection {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:9230/json/list")!)
        request.timeoutInterval = 1
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let target = try JSONDecoder().decode([Target].self, from: data).first,
              let socketURL = target.webSocketDebuggerUrl else { throw ClientError.unavailable }
        return Connection(url: socketURL)
    }
}
