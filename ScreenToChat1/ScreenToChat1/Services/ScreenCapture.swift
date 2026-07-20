import AppKit

enum ScreenCapture {
    static func mainScreen() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("screen-to-chat.png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-m", "-t", "png", url.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, NSImage(contentsOf: url) != nil else {
            throw NSError(domain: "ScreenToChat", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "проверьте разрешение «Запись экрана»"])
        }
        return url
    }
}
