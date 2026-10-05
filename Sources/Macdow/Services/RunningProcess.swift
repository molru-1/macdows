import Foundation
import Observation

@MainActor
@Observable
final class RunningProcess: Identifiable {
    let id = UUID()
    let bottleID: UUID
    let title: String
    let startedAt = Date()
    let logURL: URL
    private(set) var output = ""
    private(set) var isRunning = true
    private(set) var exitCode: Int32?

    @ObservationIgnored private let process: Process
    @ObservationIgnored private var waiters: [CheckedContinuation<Int32, Never>] = []

    private static let maxOutputBytes = 300_000

    init(bottleID: UUID, title: String, logURL: URL, process: Process) {
        self.bottleID = bottleID
        self.title = title
        self.logURL = logURL
        self.process = process
    }

    func append(_ text: String) {
        output += text
        if output.utf8.count > Self.maxOutputBytes {
            output = "… (이전 출력 생략, 전체 내용은 로그 파일 참고)\n" + String(output.suffix(Self.maxOutputBytes * 2 / 3))
        }
    }

    func finish(_ code: Int32) {
        guard isRunning else { return }
        isRunning = false
        exitCode = code
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: code) }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    func waitForExit() async -> Int32 {
        if !isRunning { return exitCode ?? -1 }
        return await withCheckedContinuation { waiters.append($0) }
    }
}
