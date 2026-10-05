import SwiftUI

struct SetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Text("Macdow는 오픈소스 호환 계층인 **Wine**으로 Windows 프로그램을 실행합니다. Apple Silicon Mac에서는 **Rosetta 2**가 x86 Windows 코드를 변환하고, 게임의 DirectX 호출은 런타임에 포함된 **D3DMetal/DXVK**가 Metal로 변환합니다.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            if SystemCheck.isAppleSilicon {
                Section("1. Rosetta 2") {
                    statusRow(
                        ok: model.rosettaInstalled,
                        title: model.rosettaInstalled ? "설치됨" : "설치 필요",
                        detail: "Intel(x86) 코드를 Apple Silicon에서 실행하는 데 필요합니다."
                    ) {
                        if !model.rosettaInstalled {
                            Button("설치") {
                                SystemCheck.runInTerminal("softwareupdate --install-rosetta --agree-to-license")
                            }
                        }
                    }
                }
            }

            Section("2. Homebrew") {
                statusRow(
                    ok: model.brewPath != nil,
                    title: model.brewPath != nil ? "설치됨" : "설치되지 않음",
                    detail: "Wine과 winetricks를 자동으로 설치할 때 사용합니다. 없어도 Wine을 직접 받아 쓸 수 있습니다."
                ) {
                    if model.brewPath == nil {
                        Button("brew.sh 열기") { NSWorkspace.shared.open(URL(string: "https://brew.sh")!) }
                    }
                }
            }

            Section("3. Wine 런타임") {
                if model.runtimes.isEmpty {
                    statusRow(ok: false, title: "찾은 런타임 없음", detail: "아래 중 하나를 설치하세요.") { EmptyView() }
                } else {
                    ForEach(model.runtimes) { runtime in
                        LabeledContent {
                            if runtime.id == model.defaultRuntime?.id {
                                Text("기본값").foregroundStyle(.secondary)
                            } else {
                                Button("기본값으로") { model.defaultRuntimeID = runtime.id }
                            }
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(runtime.name)
                                    Text(runtime.winePath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            } icon: {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                }

                installRow(
                    title: "Wine Stable",
                    detail: "일반 프로그램과 가벼운 게임용. 가장 무난한 선택입니다.",
                    command: "brew install --cask wine-stable && xattr -dr com.apple.quarantine \"/Applications/Wine Stable.app\""
                )
                installRow(
                    title: "Game Porting Toolkit",
                    detail: "DirectX 11/12 게임용. Apple의 D3DMetal이 포함되어 최신 게임 호환성이 가장 좋습니다.",
                    command: "brew install --cask gcenx/wine/game-porting-toolkit && xattr -dr com.apple.quarantine \"/Applications/Game Porting Toolkit.app\""
                )

                HStack {
                    Button("직접 다운로드 페이지") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases")!)
                    }
                    Button("wine 실행 파일 직접 추가…") {
                        if let url = Panels.chooseWineBinary() {
                            model.customRuntimePaths.append(url.path)
                        }
                    }
                    Spacer()
                    Button("다시 검색") { model.refreshEnvironment() }
                }
                Text("직접 받은 Wine은 응용 프로그램 폴더에 넣거나, `~/Library/Application Support/Macdow/Runtimes/<이름>/bin/wine` 형태로 두면 자동으로 인식됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("4. Winetricks (선택)") {
                statusRow(
                    ok: model.winetricksPath != nil,
                    title: model.winetricksPath != nil ? "설치됨" : "설치되지 않음",
                    detail: "Visual C++, .NET, 한글 글꼴 같은 Windows 구성 요소를 쉽게 설치합니다."
                ) {
                    if model.winetricksPath == nil {
                        Button("설치") { Self.installWinetricks(model: model) }
                            .disabled(model.brewPath == nil)
                    }
                }
            }

            Section("다음 단계") {
                Text("1) 왼쪽 위 **＋** 버튼으로 병을 만듭니다.\n2) 게임 설치 파일(.exe)을 병에 끌어다 놓아 설치합니다.\n3) 한글이 깨지면 ‘도구’ 탭에서 **한중일(CJK) 글꼴**을 설치합니다.\n4) 설치된 게임을 ‘시작 메뉴’에서 실행하거나 고정합니다.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("환경 점검")
        .toolbar {
            Button { model.refreshEnvironment() } label: { Label("다시 검색", systemImage: "arrow.clockwise") }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshEnvironment()
        }
    }

    static func installWinetricks(model: AppModel) {
        let brew = model.brewPath ?? "brew"
        SystemCheck.runInTerminal("\"\(brew)\" install winetricks")
    }

    private func installRow(title: String, detail: String, command: String) -> some View {
        LabeledContent {
            Button("Homebrew로 설치") {
                let brew = model.brewPath ?? "brew"
                SystemCheck.runInTerminal(command.replacingOccurrences(of: "brew install", with: "\"\(brew)\" install"))
            }
            .disabled(model.brewPath == nil)
        } label: {
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func statusRow<Trailing: View>(
        ok: Bool,
        title: String,
        detail: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        LabeledContent {
            trailing()
        } label: {
            Label {
                VStack(alignment: .leading) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ok ? .green : .orange)
            }
        }
    }
}

struct AppSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Wine 런타임") {
                Picker("기본 런타임", selection: $model.defaultRuntimeID) {
                    if model.runtimes.isEmpty { Text("없음").tag(String?.none) }
                    ForEach(model.runtimes) { Text($0.name).tag(String?.some($0.id)) }
                }
                ForEach(model.customRuntimePaths, id: \.self) { path in
                    LabeledContent {
                        Button("제거") { model.customRuntimePaths.removeAll { $0 == path } }
                    } label: {
                        Text(path).font(.caption).lineLimit(2)
                    }
                }
                HStack {
                    Button("wine 실행 파일 추가…") {
                        if let url = Panels.chooseWineBinary() { model.customRuntimePaths.append(url.path) }
                    }
                    Button("Runtimes 폴더 열기") { NSWorkspace.shared.open(model.runtimesDirectory) }
                }
            }
            Section("저장 위치") {
                LabeledContent("병 폴더") {
                    Button("Finder에서 열기") { NSWorkspace.shared.open(model.bottlesDirectory) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 360)
    }
}
