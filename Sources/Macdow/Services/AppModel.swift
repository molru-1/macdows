import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var bottles: [Bottle] = []
    var runtimes: [WineRuntime] = []
    var processes: [RunningProcess] = []
    var busyBottles: Set<UUID> = []
    var alertMessage: String?
    var winetricksPath: String?
    var brewPath: String?
    var rosettaInstalled = true

    var defaultRuntimeID: String? {
        didSet { UserDefaults.standard.set(defaultRuntimeID, forKey: Keys.defaultRuntime) }
    }

    var customRuntimePaths: [String] {
        didSet {
            UserDefaults.standard.set(customRuntimePaths, forKey: Keys.customRuntimes)
            refreshEnvironment()
        }
    }

    @ObservationIgnored var initializationTasks: [UUID: Task<Void, Never>] = [:]

    let supportDirectory: URL
    var bottlesDirectory: URL { supportDirectory.appending(path: "Bottles", directoryHint: .isDirectory) }
    var runtimesDirectory: URL { supportDirectory.appending(path: "Runtimes", directoryHint: .isDirectory) }

    var isReady: Bool { !runtimes.isEmpty && rosettaInstalled }

    private enum Keys {
        static let defaultRuntime = "defaultRuntimeID"
        static let customRuntimes = "customRuntimePaths"
    }

    init() {
        supportDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Macdow", directoryHint: .isDirectory)
        defaultRuntimeID = UserDefaults.standard.string(forKey: Keys.defaultRuntime)
        customRuntimePaths = UserDefaults.standard.stringArray(forKey: Keys.customRuntimes) ?? []
        try? FileManager.default.createDirectory(at: bottlesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: runtimesDirectory, withIntermediateDirectories: true)
        refreshEnvironment()
        loadBottles()
    }

    // MARK: - Environment

    func refreshEnvironment() {
        runtimes = RuntimeLocator.detect(customPaths: customRuntimePaths, userRuntimesDirectory: runtimesDirectory)
        winetricksPath = SystemCheck.firstExecutable(["/opt/homebrew/bin/winetricks", "/usr/local/bin/winetricks"])
        brewPath = SystemCheck.firstExecutable(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"])
        rosettaInstalled = SystemCheck.isRosettaInstalled
        if let id = defaultRuntimeID, runtimes.contains(where: { $0.id == id }) { return }
        defaultRuntimeID = runtimes.first?.id
    }

    var defaultRuntime: WineRuntime? {
        runtimes.first { $0.id == defaultRuntimeID } ?? runtimes.first
    }

    func runtime(for bottle: Bottle) -> WineRuntime? {
        if let id = bottle.settings.runtimeID, let rt = runtimes.first(where: { $0.id == id }) { return rt }
        return defaultRuntime
    }

    // MARK: - Bottles

    func bottle(withID id: UUID) -> Bottle? {
        bottles.first { $0.id == id }
    }

    func directory(for bottle: Bottle) -> URL {
        bottlesDirectory.appending(path: bottle.id.uuidString, directoryHint: .isDirectory)
    }

    func prefixURL(for bottle: Bottle) -> URL {
        directory(for: bottle).appending(path: "prefix", directoryHint: .isDirectory)
    }

    func driveC(for bottle: Bottle) -> URL {
        prefixURL(for: bottle).appending(path: "drive_c", directoryHint: .isDirectory)
    }

    func logsURL(for bottle: Bottle) -> URL {
        directory(for: bottle).appending(path: "logs", directoryHint: .isDirectory)
    }

    func loadBottles() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: bottlesDirectory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        bottles = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appending(path: "bottle.json")) else { return nil }
            return try? decoder.decode(Bottle.self, from: data)
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    func save(_ bottle: Bottle) {
        do {
            let dir = directory(for: bottle)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(bottle).write(to: dir.appending(path: "bottle.json"), options: .atomic)
            if let index = bottles.firstIndex(where: { $0.id == bottle.id }) {
                bottles[index] = bottle
            } else {
                bottles.append(bottle)
            }
        } catch {
            alertMessage = "병 정보를 저장하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func delete(_ bottle: Bottle) {
        killAll(in: bottle)
        do {
            try FileManager.default.trashItem(at: directory(for: bottle), resultingItemURL: nil)
        } catch {
            alertMessage = "병을 삭제하지 못했습니다: \(error.localizedDescription)"
            return
        }
        bottles.removeAll { $0.id == bottle.id }
        processes.removeAll { $0.bottleID == bottle.id && !$0.isRunning }
    }

    // MARK: - Pinned programs

    func pin(_ url: URL, name: String? = nil, arguments: String = "", in bottleID: UUID) {
        guard var bottle = bottle(withID: bottleID),
              !bottle.pinnedPrograms.contains(where: { $0.path == url.path }) else { return }
        bottle.pinnedPrograms.append(PinnedProgram(
            name: name ?? url.deletingPathExtension().lastPathComponent,
            path: url.path,
            arguments: arguments
        ))
        save(bottle)
    }

    func updatePin(_ program: PinnedProgram, in bottleID: UUID) {
        guard var bottle = bottle(withID: bottleID),
              let index = bottle.pinnedPrograms.firstIndex(where: { $0.id == program.id }) else { return }
        bottle.pinnedPrograms[index] = program
        save(bottle)
    }

    func unpin(_ program: PinnedProgram, in bottleID: UUID) {
        guard var bottle = bottle(withID: bottleID) else { return }
        bottle.pinnedPrograms.removeAll { $0.id == program.id }
        save(bottle)
    }

    // MARK: - Processes

    @discardableResult
    func launchProcess(
        title: String,
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?,
        bottle: Bottle
    ) throws -> RunningProcess {
        let logs = logsURL(for: bottle)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let logURL = logs.appending(path: "\(Self.timestamp())-\(Self.sanitize(title)).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        let header = "$ \(executable) \(arguments.joined(separator: " "))\n\n"
        logHandle.write(Data(header.utf8))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let running = RunningProcess(bottleID: bottle.id, title: title, logURL: logURL, process: process)
        running.append(header)

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                try? logHandle.close()
                return
            }
            logHandle.write(data)
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in running.append(text) }
        }
        process.terminationHandler = { proc in
            let code = proc.terminationStatus
            Task { @MainActor in running.finish(code) }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? logHandle.close()
            throw MacdowError.launchFailed(error.localizedDescription)
        }

        processes.insert(running, at: 0)
        trimFinishedProcesses()
        return running
    }

    func clearFinishedProcesses(for bottleID: UUID) {
        processes.removeAll { $0.bottleID == bottleID && !$0.isRunning }
    }

    private func trimFinishedProcesses() {
        let finished = processes.filter { !$0.isRunning }
        guard finished.count > 50 else { return }
        let drop = Set(finished.suffix(finished.count - 50).map(\.id))
        processes.removeAll { drop.contains($0.id) }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return String(cleaned.prefix(60))
    }
}
