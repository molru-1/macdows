import Foundation

enum WindowsVersion: String, Codable, CaseIterable, Identifiable {
    case win11, win10, win81, win8, win7, winxp64

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .win11: "Windows 11"
        case .win10: "Windows 10"
        case .win81: "Windows 8.1"
        case .win8: "Windows 8"
        case .win7: "Windows 7"
        case .winxp64: "Windows XP"
        }
    }
}

enum GraphicsRenderer: String, Codable, CaseIterable, Identifiable {
    case automatic, d3dmetal, dxmt, wined3d

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "자동 (D3DMetal 우선)"
        case .d3dmetal: "D3DMetal (Apple, DX11/12)"
        case .dxmt: "DXMT (DX11)"
        case .wined3d: "Wine 기본 (OpenGL/Vulkan)"
        }
    }
}

struct BottleSettings: Codable, Hashable {
    var windowsVersion: WindowsVersion = .win10
    var renderer: GraphicsRenderer = .automatic
    /// nil이면 앱 기본 런타임을 사용
    var runtimeID: String?
    var msync = false
    var esync = false
    var retinaMode = false
    var metalHUD = false
    var advertiseAVX = false
    var verboseLogging = false
    var customEnvironment: [String: String] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BottleSettings()
        windowsVersion = try c.decodeIfPresent(WindowsVersion.self, forKey: .windowsVersion) ?? d.windowsVersion
        renderer = try c.decodeIfPresent(GraphicsRenderer.self, forKey: .renderer) ?? d.renderer
        runtimeID = try c.decodeIfPresent(String.self, forKey: .runtimeID)
        msync = try c.decodeIfPresent(Bool.self, forKey: .msync) ?? d.msync
        esync = try c.decodeIfPresent(Bool.self, forKey: .esync) ?? d.esync
        retinaMode = try c.decodeIfPresent(Bool.self, forKey: .retinaMode) ?? d.retinaMode
        metalHUD = try c.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? d.metalHUD
        advertiseAVX = try c.decodeIfPresent(Bool.self, forKey: .advertiseAVX) ?? d.advertiseAVX
        verboseLogging = try c.decodeIfPresent(Bool.self, forKey: .verboseLogging) ?? d.verboseLogging
        customEnvironment = try c.decodeIfPresent([String: String].self, forKey: .customEnvironment) ?? [:]
    }
}

struct PinnedProgram: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var path: String
    var arguments: String = ""

    var url: URL { URL(fileURLWithPath: path) }
}

struct Bottle: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    var settings: BottleSettings
    var pinnedPrograms: [PinnedProgram]
}

struct DiscoveredProgram: Identifiable, Hashable {
    var id: String { url.path }
    var name: String
    var url: URL
}

struct WineRuntime: Identifiable, Hashable {
    var name: String
    var winePath: String

    var id: String { winePath }
    var binDirectory: String { (winePath as NSString).deletingLastPathComponent }
    var wineserverPath: String { binDirectory + "/wineserver" }
}

struct OpenItem: Identifiable {
    let id = UUID()
    let url: URL
}

enum MacdowError: LocalizedError {
    case noRuntime
    case launchFailed(String)
    case processFailed(String, Int32)
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .noRuntime:
            "사용할 수 있는 Wine 런타임이 없습니다. '환경 점검'에서 Wine을 설치하세요."
        case .launchFailed(let reason):
            "프로세스를 시작하지 못했습니다: \(reason)"
        case .processFailed(let name, let code):
            "\(name) 실행이 실패했습니다 (종료 코드 \(code)). 로그 탭을 확인하세요."
        case .missingFile(let path):
            "파일을 찾을 수 없습니다: \(path)"
        }
    }
}
