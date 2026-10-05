import Foundation

extension AppModel {
    func environment(for bottle: Bottle, runtime: WineRuntime) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let settings = bottle.settings
        env["WINEPREFIX"] = prefixURL(for: bottle).path
        env["PATH"] = [runtime.binDirectory, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            .joined(separator: ":")
        if settings.verboseLogging {
            env.removeValue(forKey: "WINEDEBUG")
        } else {
            env["WINEDEBUG"] = "-all"
        }
        if settings.msync { env["WINEMSYNC"] = "1" }
        if settings.esync { env["WINEESYNC"] = "1" }
        if settings.metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        if settings.advertiseAVX { env["ROSETTA_ADVERTISE_AVX"] = "1" }
        // 맥 한글 입력기가 게임 글상자로 들어가게 로케일을 맞춘다. 병의 사용자 환경 변수가 있으면 그게 이긴다.
        env["LANG"] = "ko_KR.UTF-8"
        env["LC_ALL"] = "ko_KR.UTF-8"
        // Steam 오버레이는 다른 프로세스에서 화면을 만들어 게임이 첫 프레임에서 멈추는 경우가 많다.
        let overlayOff = "gameoverlayrenderer=d;gameoverlayrenderer64=d"
        if let existing = env["WINEDLLOVERRIDES"], !existing.isEmpty {
            if !existing.contains("gameoverlayrenderer") {
                env["WINEDLLOVERRIDES"] = existing + ";" + overlayOff
            }
        } else {
            env["WINEDLLOVERRIDES"] = overlayOff
        }
        if !CrossOverStyle.apply(winePath: runtime.winePath, renderer: settings.renderer, env: &env),
           MachO.isX86_64(runtime.winePath), let shim = LibraryShim.gnutlsDirectory() {
            let existing = env["DYLD_LIBRARY_PATH"] ?? ""
            env["DYLD_LIBRARY_PATH"] = existing.isEmpty ? shim : "\(shim):\(existing)"
        }
        env.merge(settings.customEnvironment) { $1 }
        return env
    }

    @discardableResult
    func runWine(_ arguments: [String], in bottle: Bottle, title: String, workingDirectory: URL? = nil) throws -> RunningProcess {
        guard let runtime = runtime(for: bottle) else { throw MacdowError.noRuntime }
        return try launchProcess(
            title: title,
            executable: runtime.winePath,
            arguments: arguments,
            environment: environment(for: bottle, runtime: runtime),
            workingDirectory: workingDirectory,
            bottle: bottle
        )
    }

    func runWineAndWait(_ arguments: [String], in bottle: Bottle, title: String) async throws -> Int32 {
        try await runWine(arguments, in: bottle, title: title).waitForExit()
    }

    // MARK: - Bottle lifecycle

    @discardableResult
    func createBottle(name: String, windowsVersion: WindowsVersion, runtimeID: String?) -> Bottle {
        var settings = BottleSettings()
        settings.windowsVersion = windowsVersion
        settings.runtimeID = runtimeID
        let bottle = Bottle(id: UUID(), name: name, createdAt: Date(), settings: settings, pinnedPrograms: [])
        try? FileManager.default.createDirectory(at: prefixURL(for: bottle), withIntermediateDirectories: true)
        save(bottle)

        busyBottles.insert(bottle.id)
        initializationTasks[bottle.id] = Task {
            defer {
                busyBottles.remove(bottle.id)
                initializationTasks[bottle.id] = nil
            }
            do {
                let code = try await runWineAndWait(["wineboot", "--init"], in: bottle, title: "병 초기화")
                guard code == 0 else { throw MacdowError.processFailed("wineboot", code) }
                try await applyRegistrySettingsThrowing(bottle)
            } catch {
                alertMessage = "‘\(bottle.name)’ 병을 초기화하지 못했습니다.\n\(error.localizedDescription)"
            }
        }
        return bottle
    }

    func applyRegistrySettings(_ bottle: Bottle) async {
        busyBottles.insert(bottle.id)
        defer { busyBottles.remove(bottle.id) }
        do {
            try await applyRegistrySettingsThrowing(bottle)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func applyRegistrySettingsThrowing(_ bottle: Bottle) async throws {
        let version = bottle.settings.windowsVersion
        _ = try await runWineAndWait(["winecfg", "-v", version.rawValue], in: bottle, title: "Windows 버전 설정")
        _ = try await runWineAndWait([
            "reg", "add", #"HKCU\Software\Wine\Mac Driver"#,
            "/v", "RetinaMode", "/t", "REG_SZ", "/d", bottle.settings.retinaMode ? "y" : "n", "/f",
        ], in: bottle, title: "Retina 모드 설정")
        try await applyKoreanInput(bottle)
    }

    /// 윈도우 키보드를 한국어로 두고, 죽으면 디버거에 멈춰 창이 얼어 보이지 않게 한다.
    private func applyKoreanInput(_ bottle: Bottle) async throws {
        let commands: [(String, [String])] = [
            ("한국어 키보드", [
                "reg", "add", #"HKCU\Keyboard Layout\Preload"#,
                "/v", "1", "/t", "REG_SZ", "/d", "00000412", "/f",
            ]),
            ("한국어 로케일", [
                "reg", "add", #"HKCU\Control Panel\International"#,
                "/v", "LocaleName", "/t", "REG_SZ", "/d", "ko-KR", "/f",
            ]),
            ("한국어 코드페이지", [
                "reg", "add", #"HKLM\System\CurrentControlSet\Control\Nls\CodePage"#,
                "/v", "ACP", "/t", "REG_SZ", "/d", "949", "/f",
            ]),
        ]
        for (title, args) in commands {
            _ = try await runWineAndWait(args, in: bottle, title: title)
        }
        _ = try await runWineAndWait([
            "reg", "add", #"HKLM\System\CurrentControlSet\Control\Nls\CodePage"#,
            "/v", "OEMCP", "/t", "REG_SZ", "/d", "949", "/f",
        ], in: bottle, title: "OEM 코드페이지")
        _ = try await runWineAndWait([
            "reg", "add", #"HKLM\Software\Microsoft\Windows NT\CurrentVersion\AeDebug"#,
            "/v", "Auto", "/t", "REG_SZ", "/d", "0", "/f",
        ], in: bottle, title: "충돌 시 멈춤 방지")
    }

    // MARK: - Launching

    func launchFile(_ url: URL, arguments: String = "", in bottle: Bottle) {
        if let task = initializationTasks[bottle.id] {
            Task {
                await task.value
                launchFileNow(url, arguments: arguments, bottleID: bottle.id)
            }
        } else {
            launchFileNow(url, arguments: arguments, bottleID: bottle.id)
        }
    }

    private func launchFileNow(_ url: URL, arguments: String, bottleID: UUID, relaunchDepth: Int = 0) {
        guard let bottle = bottle(withID: bottleID) else { return }
        do {
            guard FileManager.default.fileExists(atPath: url.path) else { throw MacdowError.missingFile(url.path) }
            let extra = ShellWords.split(arguments)
            var args: [String]
            switch url.pathExtension.lowercased() {
            case "msi": args = ["msiexec", "/i", url.path] + extra
            case "bat", "cmd": args = ["cmd", "/c", url.path] + extra
            case "lnk": args = ["start", "/unix", url.path] + extra
            default: args = [url.path] + extra
            }
            if url.lastPathComponent.lowercased() == "steam.exe",
               !args.contains(where: { $0.caseInsensitiveCompare("-cef-disable-sandbox") == .orderedSame }) {
                args.append("-cef-disable-sandbox")
            }
            let running = try runWine(
                args,
                in: bottle,
                title: url.deletingPathExtension().lastPathComponent,
                workingDirectory: url.deletingLastPathComponent()
            )
            // Steam은 업데이트가 끝나면 종료 코드 42로 끝나고, 다시 실행해야 창이 뜬다.
            if relaunchDepth < 3, url.lastPathComponent.lowercased() == "steam.exe" {
                let bottleID = bottle.id
                Task {
                    let code = await running.waitForExit()
                    guard code == 42 else { return }
                    launchFileNow(url, arguments: arguments, bottleID: bottleID, relaunchDepth: relaunchDepth + 1)
                }
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func run(_ program: PinnedProgram, in bottle: Bottle) {
        launchFile(program.url, arguments: program.arguments, in: bottle)
    }

    func runTool(_ arguments: [String], title: String, in bottle: Bottle) {
        do {
            try runWine(arguments, in: bottle, title: title)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func killAll(in bottle: Bottle) {
        guard let runtime = runtime(for: bottle) else { return }
        let process = Process()
        if FileManager.default.isExecutableFile(atPath: runtime.wineserverPath) {
            process.executableURL = URL(fileURLWithPath: runtime.wineserverPath)
            process.arguments = ["-k"]
        } else {
            process.executableURL = URL(fileURLWithPath: runtime.winePath)
            process.arguments = ["wineboot", "-k"]
        }
        process.environment = environment(for: bottle, runtime: runtime)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: - Winetricks

    func runWinetricks(_ verbs: [String], in bottle: Bottle) {
        guard !verbs.isEmpty else { return }
        guard let winetricks = winetricksPath else {
            alertMessage = "winetricks가 설치되어 있지 않습니다. '환경 점검'에서 설치하세요."
            return
        }
        guard let runtime = runtime(for: bottle) else {
            alertMessage = MacdowError.noRuntime.localizedDescription
            return
        }
        var env = environment(for: bottle, runtime: runtime)
        env["WINE"] = runtime.winePath
        env["WINESERVER"] = runtime.wineserverPath
        do {
            try launchProcess(
                title: "winetricks \(verbs.joined(separator: " "))",
                executable: winetricks,
                arguments: ["-q", "--unattended"] + verbs,
                environment: env,
                workingDirectory: nil,
                bottle: bottle
            )
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    // MARK: - Discovery

    /// 설치 프로그램이 만든 시작 메뉴 바로가기(.lnk)를 찾는다.
    func startMenuPrograms(for bottle: Bottle) -> [DiscoveredProgram] {
        let fm = FileManager.default
        let driveC = driveC(for: bottle)
        let startMenu = "Microsoft/Windows/Start Menu/Programs"
        var roots = [driveC.appending(path: "ProgramData/\(startMenu)")]
        let users = driveC.appending(path: "users")
        if let names = try? fm.contentsOfDirectory(atPath: users.path) {
            roots += names.map { users.appending(path: "\($0)/AppData/Roaming/\(startMenu)") }
        }

        let skipWords = ["uninstall", "제거", "readme", "help", "website"]
        var result: [DiscoveredProgram] = []
        var seen = Set<String>()
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "lnk" {
                let name = url.deletingPathExtension().lastPathComponent
                let lower = name.lowercased()
                guard !skipWords.contains(where: lower.contains), seen.insert(lower).inserted else { continue }
                result.append(DiscoveredProgram(name: name, url: url))
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
