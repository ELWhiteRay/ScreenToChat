import Foundation

enum DevToolsError: LocalizedError {
    case unavailable, noPage, preparedChatMissing, attachmentFailed, noSendButton, noResponse
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "локальный DevTools-порт недоступен"
        case .noPage: "в DevTools не найден открытый чат"
        case .preparedChatMissing: "подготовленный чат «Ждать скриншот задания» не найден"
        case .attachmentFailed: "чат не принял screenshot через drag-and-drop"
        case .noSendButton: "стрелка отправки не появилась"
        case .noResponse: "ответ ChatGPT не появился"
        case .protocolError(let message): "ошибка DevTools: \(message)"
        }
    }
}

struct DevToolsTarget: Decodable {
    let type: String
    let url: String
    let webSocketDebuggerUrl: URL?
}

struct DevToolsResponseState: Decodable {
    let text: String
    let ready: Bool
}
