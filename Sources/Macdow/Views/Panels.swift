import AppKit
import UniformTypeIdentifiers

@MainActor
enum Panels {
    static let windowsExtensions = ["exe", "msi", "bat", "cmd", "lnk"]

    static func chooseWindowsFile(startingAt directory: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.message = "실행할 Windows 프로그램이나 설치 파일을 선택하세요"
        panel.prompt = "실행"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = windowsExtensions.compactMap { UTType(filenameExtension: $0) }
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            panel.directoryURL = directory
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseWineBinary() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "wine 또는 wine64 실행 파일을 선택하세요 (보통 …/wine/bin/ 안에 있습니다)"
        panel.prompt = "추가"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
