import AppKit
import Foundation

enum SystemCheck {
    #if arch(arm64)
    static let isAppleSilicon = true
    #else
    static let isAppleSilicon = false
    #endif

    static var isRosettaInstalled: Bool {
        !isAppleSilicon || FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")
    }

    static func firstExecutable(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 설치 명령은 비밀번호 입력 등이 필요할 수 있어 터미널 창에서 사용자에게 보이게 실행한다.
    @MainActor
    static func runInTerminal(_ command: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            let alert = NSAlert()
            alert.messageText = "터미널을 열 수 없습니다"
            alert.informativeText = "명령어를 클립보드에 복사했습니다. 터미널에 붙여넣어 실행하세요.\n\n\(command)"
            alert.runModal()
        }
    }
}

enum RuntimeLocator {
    private static let appBundles = [
        "Wine Stable", "Wine Devel", "Wine Staging", "Wine Crossover", "Game Porting Toolkit",
    ]

    static func detect(customPaths: [String], userRuntimesDirectory: URL) -> [WineRuntime] {
        let fm = FileManager.default
        var found: [WineRuntime] = []
        var seen = Set<String>()

        func add(_ name: String, binary: String) {
            guard fm.isExecutableFile(atPath: binary) else { return }
            let resolved = URL(fileURLWithPath: binary).resolvingSymlinksInPath().path
            guard seen.insert(resolved).inserted else { return }
            found.append(WineRuntime(name: name, winePath: binary))
        }

        // 구버전 macOS Wine 빌드는 64비트 로더가 wine64, WoW64 빌드는 wine 하나만 제공한다.
        func addDirectory(_ name: String, _ dir: String) {
            for binary in ["wine64", "wine"] where fm.isExecutableFile(atPath: "\(dir)/\(binary)") {
                add(name, binary: "\(dir)/\(binary)")
                return
            }
        }

        for root in ["/Applications", NSHomeDirectory() + "/Applications"] {
            for app in appBundles {
                addDirectory(app, "\(root)/\(app).app/Contents/Resources/wine/bin")
            }
            addDirectory("CrossOver", "\(root)/CrossOver.app/Contents/SharedSupport/CrossOver/bin")
        }
        addDirectory("Game Porting Toolkit (Homebrew)", "/usr/local/opt/game-porting-toolkit/bin")
        addDirectory("Wine (Homebrew)", "/opt/homebrew/bin")
        addDirectory("Wine (Homebrew, Intel)", "/usr/local/bin")
        scanCaskroom(fm, addDirectory: addDirectory)
        scanEngineBundles(fm, addDirectory: addDirectory)
        scanNearbyCrossOver(fm, addDirectory: addDirectory)

        if let dirs = try? fm.contentsOfDirectory(at: userRuntimesDirectory, includingPropertiesForKeys: nil) {
            for dir in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                addDirectory(dir.lastPathComponent, dir.appending(path: "bin").path)
            }
        }

        for path in customPaths {
            let url = URL(fileURLWithPath: path)
            let label = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            add("사용자 지정: \(label)", binary: path)
        }
        return found
    }

    /// Homebrew cask로 받은 Wine은 응용 프로그램 폴더가 아니라 Caskroom 안에만 있는 경우가 있다.
    private static func scanCaskroom(
        _ fm: FileManager,
        addDirectory: (String, String) -> Void
    ) {
        for root in ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"] {
            guard let casks = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for cask in casks {
                guard let versions = try? fm.contentsOfDirectory(atPath: "\(root)/\(cask)") else { continue }
                for version in versions {
                    let versionDir = "\(root)/\(cask)/\(version)"
                    guard let entries = try? fm.contentsOfDirectory(atPath: versionDir) else { continue }
                    for entry in entries where entry.hasSuffix(".app") {
                        let name = String(entry.dropLast(4))
                        addDirectory(name, "\(versionDir)/\(entry)/Contents/Resources/wine/bin")
                    }
                }
            }
        }
    }

    /// Highball/Sikarugir 엔진은 CrossOver에서 갈라진 Wine이고, bin이 engine/bin 아래에 있다.
    private static func scanEngineBundles(
        _ fm: FileManager,
        addDirectory: (String, String) -> Void
    ) {
        let roots = [
            NSHomeDirectory() + "/Library/Application Support/Highball/engines",
            NSHomeDirectory() + "/Library/Application Support/Sikarugir/engines",
        ]
        for root in roots {
            guard let engines = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for engine in engines.sorted() {
                let label = engine.lowercased().contains("sikarugir") ? "Sikarugir (CrossOver 계열)" : engine
                addDirectory(label, "\(root)/\(engine)/engine/bin")
            }
        }
    }

    /// 프로젝트 옆에 풀어 둔 CrossOver.app 또는 그 Contents 폴더를 찾는다.
    private static func scanNearbyCrossOver(
        _ fm: FileManager,
        addDirectory: (String, String) -> Void
    ) {
        var starts = [Bundle.main.bundleURL]
        if let arg = CommandLine.arguments.first {
            starts.append(URL(fileURLWithPath: arg).deletingLastPathComponent())
        }
        for start in starts {
            var current = start
            for _ in 0..<6 {
                let bins = [
                    current.appending(path: "CrossOver.app/Contents/SharedSupport/CrossOver/bin").path,
                    current.appending(path: "Contents/SharedSupport/CrossOver/bin").path,
                ]
                for bin in bins where fm.isExecutableFile(atPath: bin + "/wine") {
                    addDirectory("CrossOver", bin)
                }
                let parent = current.deletingLastPathComponent()
                if parent.path == current.path { break }
                current = parent
            }
        }
    }
}

enum CrossOverStyle {
    /// Sikarugir처럼 엔진 폴더에 GnuTLS와 DXMT가 있으면 CrossOver와 같은 방식으로 경로를 잡는다.
    /// 적용했으면 true를 반환하고, 그때는 다른 GnuTLS를 앞에 두지 않는다.
    static func apply(winePath: String, renderer: GraphicsRenderer, env: inout [String: String]) -> Bool {
        let fm = FileManager.default
        let engine = URL(fileURLWithPath: winePath).deletingLastPathComponent().deletingLastPathComponent()
        guard fm.fileExists(atPath: engine.appending(path: "lib/libgnutls.30.dylib").path) else { return false }
        let bundle = engine.deletingLastPathComponent()
        let frameworks = bundle.appending(path: "frameworks")
        var libraryPaths: [String] = []
        var frameworkPaths: [String] = []
        if fm.fileExists(atPath: frameworks.path) {
            libraryPaths = [frameworks.path, frameworks.appending(path: "GStreamer.framework/Versions/1.0/lib").path]
            frameworkPaths = [frameworks.path]
        } else {
            libraryPaths = [engine.appending(path: "lib").path]
        }

        let d3dmetal = frameworks.appending(path: "renderer/d3dmetal")
        let dxmt = bundle.appending(path: "renderers/dxmt/wine")
        let hasD3DMetal = fm.fileExists(atPath: d3dmetal.appending(path: "external/D3DMetal.framework").path)
        let hasDXMT = fm.fileExists(atPath: dxmt.path)
        var chosen = renderer
        if chosen == .automatic { chosen = hasD3DMetal ? .d3dmetal : (hasDXMT ? .dxmt : .wined3d) }

        var rendererDLLs: URL?
        switch chosen {
        case .d3dmetal where hasD3DMetal:
            // d3d11.so가 @rpath/libd3dshared.dylib와 D3DMetal.framework를 찾을 수 있어야 한다.
            let external = d3dmetal.appending(path: "external").path
            libraryPaths.insert(external, at: 0)
            frameworkPaths.insert(external, at: 0)
            rendererDLLs = d3dmetal.appending(path: "wine")
        case .dxmt where hasDXMT:
            rendererDLLs = dxmt
            // Steam 오버레이나 게임 런처가 다른 프로세스에서 화면을 만들 때 필요하다.
            env["DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN"] = "1"
        default:
            break
        }
        if let overlay = DLLOverlay.prepare(name: chosen.rawValue, renderer: rendererDLLs) {
            env["WINEDLLPATH_PREPEND"] = overlay.path
        } else if let rendererDLLs {
            env["WINEDLLPATH_PREPEND"] = rendererDLLs.path
        }
        env["DYLD_FALLBACK_LIBRARY_PATH"] = libraryPaths.joined(separator: ":")
        if !frameworkPaths.isEmpty { env["DYLD_FALLBACK_FRAMEWORK_PATH"] = frameworkPaths.joined(separator: ":") }
        if fm.fileExists(atPath: frameworks.appending(path: "GStreamer.framework").path) {
            env["GST_PLUGIN_PATH"] = frameworks.appending(path: "GStreamer.framework/Versions/1.0/lib/gstreamer-1.0").path
        }
        return true
    }
}

/// 엔진이 경로 하나만 앞에 둘 수 있어서(WINEDLLPATH_PREPEND), 렌더러 DLL과
/// Macdow가 CrossOver LGPL 소스로 빌드한 DLL(Resources/WineOverrides)을 한 폴더에 링크로 모은다.
enum DLLOverlay {
    static func prepare(name: String, renderer: URL?) -> URL? {
        let fm = FileManager.default
        guard let patches = Bundle.main.resourceURL?.appending(path: "WineOverrides"),
              fm.fileExists(atPath: patches.path) else { return nil }
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let overlay = support.appending(path: "Macdow/DLLOverlays/\(name)")
        try? fm.removeItem(at: overlay)

        for source in [renderer, patches].compactMap({ $0 }) {
            guard let archs = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for arch in archs where (try? arch.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let target = overlay.appending(path: arch.lastPathComponent)
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                for file in (try? fm.contentsOfDirectory(at: arch, includingPropertiesForKeys: nil)) ?? [] {
                    let link = target.appending(path: file.lastPathComponent)
                    try? fm.removeItem(at: link)
                    try? fm.createSymbolicLink(at: link, withDestinationURL: file)
                }
            }
        }
        return overlay
    }
}

enum MachO {
    /// Rosetta로 도는 x86_64 Wine인지 확인한다. arm64 GnuTLS는 이 바이너리가 불러올 수 없다.
    static func isX86_64(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 8)
        guard data.count >= 8 else { return false }
        let bytes = [UInt8](data)
        // MH_MAGIC_64, CPU_TYPE_X86_64
        return bytes[0] == 0xCF && bytes[1] == 0xFA && bytes[2] == 0xED && bytes[3] == 0xFE
            && bytes[4] == 0x07 && bytes[5] == 0x00 && bytes[6] == 0x00 && bytes[7] == 0x01
    }
}

enum LibraryShim {
    /// x86_64 Wine이 HTTPS(Steam 업데이트, 로그인)에 쓰는 libgnutls.30.dylib 위치.
    /// /usr/local에 없으면 Game Porting Toolkit에 포함된 x86_64 라이브러리를 가리킨다.
    static func gnutlsDirectory() -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: "/usr/local/lib/libgnutls.30.dylib") { return nil }
        let bundled = [
            "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/libgnutls.30.dylib",
            NSHomeDirectory() + "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/libgnutls.30.dylib",
        ]
        guard let source = bundled.first(where: { fm.fileExists(atPath: $0) }) else { return nil }
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Macdow/LibraryShim", directoryHint: .isDirectory)
        let link = dir.appending(path: "libgnutls.30.dylib")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: link.path) {
                try fm.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: source))
            }
        } catch {
            return nil
        }
        return dir.path
    }
}

enum ShellWords {
    /// 따옴표를 고려해 실행 인자 문자열을 나눈다.
    static func split(_ string: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var hasToken = false
        for ch in string {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
                hasToken = true
            } else if ch.isWhitespace {
                if hasToken || !current.isEmpty {
                    result.append(current)
                    current = ""
                    hasToken = false
                }
            } else {
                current.append(ch)
            }
        }
        if hasToken || !current.isEmpty { result.append(current) }
        return result
    }
}
