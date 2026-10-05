import SwiftUI

struct BottleDetailView: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle

    var body: some View {
        TabView {
            ProgramsTab(bottle: bottle)
                .tabItem { Label("프로그램", systemImage: "square.grid.2x2") }
            ToolsTab(bottle: bottle)
                .tabItem { Label("도구", systemImage: "wrench.and.screwdriver") }
            BottleSettingsTab(bottle: bottle)
                .tabItem { Label("설정", systemImage: "slider.horizontal.3") }
            LogsTab(bottle: bottle)
                .tabItem { Label("로그", systemImage: "doc.text.magnifyingglass") }
        }
        .padding()
        .navigationTitle(bottle.name)
        .navigationSubtitle(model.runtime(for: bottle)?.name ?? "런타임 없음")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    if let url = Panels.chooseWindowsFile(startingAt: model.driveC(for: bottle)) {
                        model.launchFile(url, in: bottle)
                    }
                } label: {
                    Label("실행…", systemImage: "play.fill")
                }
                .help("Windows 프로그램 또는 설치 파일 실행")

                Button {
                    let driveC = model.driveC(for: bottle)
                    let target = FileManager.default.fileExists(atPath: driveC.path) ? driveC : model.directory(for: bottle)
                    NSWorkspace.shared.open(target)
                } label: {
                    Label("C: 드라이브", systemImage: "internaldrive")
                }
                .help("Finder에서 C: 드라이브 열기")

                Button {
                    model.killAll(in: bottle)
                } label: {
                    Label("모두 종료", systemImage: "stop.fill")
                }
                .help("이 병에서 실행 중인 모든 Windows 프로그램 강제 종료")
            }
        }
    }
}

// MARK: - Programs

struct ProgramsTab: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle
    @State private var startMenu: [DiscoveredProgram] = []
    @State private var editing: PinnedProgram?
    @State private var isDropTargeted = false

    private var runningCount: Int {
        model.processes.filter { $0.bottleID == bottle.id && $0.isRunning }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.busyBottles.contains(bottle.id) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Wine 환경을 준비하는 중입니다… 처음에는 몇 분 걸릴 수 있어요.")
                            .foregroundStyle(.secondary)
                    }
                }

                dropZone

                section("고정된 프로그램") {
                    if bottle.pinnedPrograms.isEmpty {
                        Text("설치한 게임이나 프로그램의 .exe를 고정하면 여기서 바로 실행할 수 있습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], alignment: .leading, spacing: 12) {
                            ForEach(bottle.pinnedPrograms) { program in
                                ProgramCard(title: program.name, url: program.url) {
                                    model.run(program, in: bottle)
                                }
                                .contextMenu {
                                    Button("실행") { model.run(program, in: bottle) }
                                    Button("편집…") { editing = program }
                                    Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([program.url]) }
                                    Divider()
                                    Button("고정 해제", role: .destructive) { model.unpin(program, in: bottle.id) }
                                }
                            }
                        }
                    }
                }

                section("시작 메뉴") {
                    if startMenu.isEmpty {
                        Text("설치 프로그램이 시작 메뉴에 등록한 바로가기가 여기에 표시됩니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(startMenu) { program in
                                HStack {
                                    Image(systemName: "arrow.up.forward.app")
                                        .foregroundStyle(.secondary)
                                    Text(program.name)
                                    Spacer()
                                    Button("고정") { model.pin(program.url, name: program.name, in: bottle.id) }
                                        .disabled(bottle.pinnedPrograms.contains { $0.path == program.url.path })
                                    Button("실행") { model.launchFile(program.url, in: bottle) }
                                        .buttonStyle(.borderedProminent)
                                }
                                .padding(.vertical, 6)
                                Divider()
                            }
                        }
                    }
                }

                let running = model.processes.filter { $0.bottleID == bottle.id && $0.isRunning }
                if !running.isEmpty {
                    section("실행 중") {
                        VStack(spacing: 0) {
                            ForEach(running) { ProcessRow(process: $0).padding(.vertical, 6) }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach { model.launchFile($0, in: bottle) }
            return !urls.isEmpty
        } isTargeted: {
            isDropTargeted = $0
        }
        .task(id: runningCount) {
            startMenu = model.startMenuPrograms(for: bottle)
        }
        .sheet(item: $editing) { program in
            PinEditorView(bottleID: bottle.id, program: program)
        }
    }

    private var dropZone: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.app")
                .font(.system(size: 30))
                .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("설치 파일(.exe/.msi)을 여기에 끌어다 놓으세요").font(.headline)
                Text("설치가 끝나면 C: 드라이브의 실행 파일을 고정하거나, 시작 메뉴에서 바로 실행할 수 있습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("파일 선택…") {
                if let url = Panels.chooseWindowsFile(startingAt: model.driveC(for: bottle)) {
                    if url.pathExtension.lowercased() == "exe",
                       url.path.hasPrefix(model.driveC(for: bottle).path) {
                        model.pin(url, in: bottle.id)
                    }
                    model.launchFile(url, in: bottle)
                }
            }
            .controlSize(.large)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }
}

struct ProgramCard: View {
    let title: String
    let url: URL
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 48, height: 48)
                Text(title)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 118, height: 100)
            .padding(8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(url.path)
    }
}

struct ProcessRow: View {
    let process: RunningProcess

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(process.isRunning ? Color.green : (process.exitCode == 0 ? Color.secondary : Color.red))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(process.title).lineLimit(1)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if process.isRunning {
                Button("중지") { process.terminate() }
                    .controlSize(.small)
            }
        }
    }

    private var statusText: String {
        let time = process.startedAt.formatted(date: .omitted, time: .shortened)
        if process.isRunning { return "실행 중 · \(time) 시작" }
        return "종료됨 (코드 \(process.exitCode ?? -1)) · \(time)"
    }
}

// MARK: - Tools

struct ToolsTab: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle
    @State private var customVerbs = ""

    private struct Tool: Identifiable {
        let title: String
        let icon: String
        let arguments: [String]
        var id: String { title }
    }

    private struct Component: Identifiable {
        let verb: String
        let title: String
        let detail: String
        var id: String { verb }
    }

    private let tools: [Tool] = [
        Tool(title: "Wine 설정", icon: "gearshape", arguments: ["winecfg"]),
        Tool(title: "레지스트리 편집기", icon: "list.bullet.indent", arguments: ["regedit"]),
        Tool(title: "작업 관리자", icon: "chart.bar.xaxis", arguments: ["taskmgr"]),
        Tool(title: "파일 탐색기", icon: "folder", arguments: ["explorer"]),
        Tool(title: "제어판", icon: "switch.2", arguments: ["control"]),
        Tool(title: "명령 프롬프트", icon: "terminal", arguments: ["start", "cmd.exe"]),
        Tool(title: "프로그램 제거", icon: "trash", arguments: ["uninstaller"]),
        Tool(title: "Windows 재시작", icon: "arrow.clockwise", arguments: ["wineboot", "-r"]),
    ]

    private let components: [Component] = [
        Component(verb: "cjkfonts", title: "한중일(CJK) 글꼴", detail: "한글이 네모(□)로 깨질 때 설치하세요"),
        Component(verb: "corefonts", title: "MS 기본 글꼴", detail: "Arial, Times New Roman 등"),
        Component(verb: "vcrun2022", title: "Visual C++ 2015–2022", detail: "대부분의 최신 게임/앱에 필요"),
        Component(verb: "dotnet48", title: ".NET Framework 4.8", detail: ".NET 기반 프로그램과 런처"),
        Component(verb: "d3dx9", title: "DirectX 9 (d3dx9)", detail: "구형 게임용 DirectX 런타임"),
        Component(verb: "d3dcompiler_47", title: "D3D Compiler 47", detail: "셰이더 컴파일러"),
        Component(verb: "xact", title: "XAudio / XACT", detail: "게임 사운드가 나오지 않을 때"),
        Component(verb: "physx", title: "PhysX", detail: "NVIDIA PhysX 물리 엔진"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Windows 도구").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                        ForEach(tools) { tool in
                            Button {
                                model.runTool(tool.arguments, title: tool.title, in: bottle)
                            } label: {
                                Label(tool.title, systemImage: tool.icon)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                            }
                            .controlSize(.large)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("구성 요소 설치 (Winetricks)").font(.headline)
                    if model.winetricksPath == nil {
                        HStack {
                            Label("winetricks가 설치되어 있지 않습니다.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("설치하기") { SetupView.installWinetricks(model: model) }
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(components) { component in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(component.title)
                                    Text(component.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("설치") { model.runWinetricks([component.verb], in: bottle) }
                                    .disabled(model.winetricksPath == nil)
                            }
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                    HStack {
                        TextField("기타 winetricks 항목 (공백으로 구분, 예: vcrun2010 dxvk)", text: $customVerbs)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(installCustom)
                        Button("설치", action: installCustom)
                            .disabled(model.winetricksPath == nil || customVerbs.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("설치 진행 상황은 ‘로그’ 탭에서 확인할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    private func installCustom() {
        let verbs = ShellWords.split(customVerbs)
        guard !verbs.isEmpty else { return }
        model.runWinetricks(verbs, in: bottle)
        customVerbs = ""
    }
}

// MARK: - Settings

struct BottleSettingsTab: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle
    @State private var name: String
    @State private var settings: BottleSettings
    @State private var environmentText: String

    init(bottle: Bottle) {
        self.bottle = bottle
        _name = State(initialValue: bottle.name)
        _settings = State(initialValue: bottle.settings)
        _environmentText = State(initialValue: Self.format(bottle.settings.customEnvironment))
    }

    private var editedSettings: BottleSettings {
        var result = settings
        result.customEnvironment = Self.parse(environmentText)
        return result
    }

    private var hasChanges: Bool {
        name != bottle.name || editedSettings != bottle.settings
    }

    var body: some View {
        Form {
            Section("일반") {
                TextField("이름", text: $name)
                RuntimePicker(selection: $settings.runtimeID)
                Picker("Windows 버전", selection: $settings.windowsVersion) {
                    ForEach(WindowsVersion.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("그래픽 렌더러", selection: $settings.renderer) {
                    ForEach(GraphicsRenderer.allCases) { Text($0.displayName).tag($0) }
                }
                Text("게임 화면이 멈추거나 검게 나오면 다른 렌더러로 바꿔 보세요. Sikarugir 엔진에서만 적용됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("성능") {
                Toggle(isOn: $settings.msync) {
                    Text("MSync")
                    Text("켜면 CPU 사용이 줄 수 있습니다. 화면이 멈추면 끄세요.")
                }
                Toggle(isOn: $settings.esync) {
                    Text("ESync")
                    Text("MSync를 지원하지 않는 런타임에서 대신 사용합니다.")
                }
                Toggle(isOn: $settings.advertiseAVX) {
                    Text("AVX 지원 알리기 (Rosetta)")
                    Text("AVX가 필요한 최신 게임용입니다. macOS 15 이상과 Game Porting Toolkit 계열 런타임이 필요합니다.")
                }
            }
            Section("그래픽") {
                Toggle(isOn: $settings.retinaMode) {
                    Text("Retina 모드")
                    Text("고해상도로 렌더링합니다. 화면은 선명해지지만 GPU 부하가 커집니다.")
                }
                Toggle(isOn: $settings.metalHUD) {
                    Text("Metal 성능 HUD")
                    Text("화면에 FPS와 GPU 정보를 표시합니다.")
                }
            }
            Section {
                Toggle(isOn: $settings.verboseLogging) {
                    Text("자세한 Wine 로그")
                    Text("문제 해결용입니다. 켜면 성능이 떨어질 수 있습니다.")
                }
                TextField("환경 변수", text: $environmentText, prompt: Text("KEY=VALUE 형식, 한 줄에 하나씩"), axis: .vertical)
                    .lineLimit(3...8)
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("고급")
            } footer: {
                Text("예: WINEDLLOVERRIDES=d3d11=n,b")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                if model.busyBottles.contains(bottle.id) {
                    ProgressView().controlSize(.small)
                    Text("설정 적용 중…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("되돌리기") { reset() }
                    .disabled(!hasChanges)
                Button("적용") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges || model.busyBottles.contains(bottle.id))
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private func reset() {
        name = bottle.name
        settings = bottle.settings
        environmentText = Self.format(bottle.settings.customEnvironment)
    }

    private func apply() {
        guard var updated = model.bottle(withID: bottle.id) else { return }
        let old = updated.settings
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmed.isEmpty ? updated.name : trimmed
        updated.settings = editedSettings
        model.save(updated)

        let new = updated.settings
        if old.windowsVersion != new.windowsVersion || old.retinaMode != new.retinaMode || old.runtimeID != new.runtimeID {
            Task { await model.applyRegistrySettings(updated) }
        }
    }

    private static func format(_ env: [String: String]) -> String {
        env.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }

    private static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            let key = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard parts.count == 2, !key.isEmpty else { continue }
            result[key] = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}

// MARK: - Logs

struct LogsTab: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle
    @State private var selectedID: UUID?

    private var processes: [RunningProcess] {
        model.processes.filter { $0.bottleID == bottle.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                List(processes, selection: $selectedID) { process in
                    ProcessRow(process: process)
                }
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

                Group {
                    if let process = processes.first(where: { $0.id == selectedID }) ?? processes.first {
                        LogOutputView(process: process)
                    } else {
                        ContentUnavailableView(
                            "로그 없음",
                            systemImage: "doc.text",
                            description: Text("프로그램을 실행하면 출력이 여기에 표시됩니다.")
                        )
                    }
                }
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Button("로그 폴더 열기") {
                    let logs = model.logsURL(for: bottle)
                    try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(logs)
                }
                Spacer()
                Button("종료된 항목 지우기") { model.clearFinishedProcesses(for: bottle.id) }
                    .disabled(!processes.contains { !$0.isRunning })
            }
            .padding(8)
        }
    }
}

struct LogOutputView: View {
    let process: RunningProcess

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(process.output.isEmpty ? "(출력 없음)" : process.output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                Color.clear.frame(height: 1).id("bottom")
            }
            .onChange(of: process.output.utf8.count) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .topTrailing) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([process.logURL])
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Finder에서 로그 파일 보기")
            .padding(8)
        }
    }
}
