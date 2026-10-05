import SwiftUI

struct CreateBottleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onCreated: (UUID) -> Void

    @State private var name = "새 병"
    @State private var windowsVersion: WindowsVersion = .win10
    @State private var runtimeID: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("새 병 만들기").font(.title2.bold())
            Text("병(Bottle)은 독립된 가상 Windows 환경입니다. 게임이나 프로그램마다 병을 따로 만들면 서로 충돌하지 않습니다.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                TextField("이름", text: $name)
                Picker("Windows 버전", selection: $windowsVersion) {
                    ForEach(WindowsVersion.allCases) { Text($0.displayName).tag($0) }
                }
                RuntimePicker(selection: $runtimeID)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 170)

            if model.runtimes.isEmpty {
                Label("Wine 런타임이 없습니다. ‘환경 점검’에서 먼저 설치하세요.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("만들기") {
                    let bottle = model.createBottle(name: trimmedName, windowsVersion: windowsVersion, runtimeID: runtimeID)
                    onCreated(bottle.id)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.runtimes.isEmpty || trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

struct RuntimePicker: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String?

    var body: some View {
        Picker("Wine 런타임", selection: $selection) {
            Text("기본값 (\(model.defaultRuntime?.name ?? "없음"))").tag(String?.none)
            ForEach(model.runtimes) { runtime in
                Text(runtime.name).tag(String?.some(runtime.id))
            }
        }
    }
}

struct OpenWithBottleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: OpenItem
    var onLaunched: (UUID) -> Void

    @State private var selectedID: UUID?
    @State private var arguments = ""
    @State private var pinProgram = true

    private var isSupported: Bool {
        Panels.windowsExtensions.contains(item.url.pathExtension.lowercased())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading) {
                    Text(item.url.lastPathComponent).font(.headline)
                    Text("어느 병에서 실행할까요?").foregroundStyle(.secondary)
                }
            }

            if !isSupported {
                Label("Windows 실행 파일(.exe, .msi, .bat, .lnk)이 아닙니다.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            if model.bottles.isEmpty {
                Text("아직 병이 없습니다. ‘기본 병’을 만들어서 바로 실행할 수 있습니다.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("병", selection: $selectedID) {
                    ForEach(model.bottles) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }

            TextField("실행 인자 (선택)", text: $arguments)
            Toggle("이 병의 고정된 프로그램에 추가", isOn: $pinProgram)

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.bottles.isEmpty ? "기본 병 만들고 실행" : "실행") { launch() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isSupported || model.runtimes.isEmpty || (!model.bottles.isEmpty && selectedID == nil))
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { selectedID = model.bottles.first?.id }
    }

    private func launch() {
        let bottle = model.bottles.first(where: { $0.id == selectedID })
            ?? model.createBottle(name: "기본 병", windowsVersion: .win10, runtimeID: nil)
        if pinProgram, item.url.pathExtension.lowercased() != "msi" {
            model.pin(item.url, arguments: arguments, in: bottle.id)
        }
        model.launchFile(item.url, arguments: arguments, in: bottle)
        onLaunched(bottle.id)
        dismiss()
    }
}

struct PinEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let bottleID: UUID
    @State var program: PinnedProgram

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("프로그램 편집").font(.title3.bold())
            Form {
                TextField("이름", text: $program.name)
                TextField("실행 인자", text: $program.arguments, prompt: Text("예: -windowed -dx11"))
                LabeledContent("경로") {
                    Text(program.path).font(.caption).textSelection(.enabled).lineLimit(3)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 170)
            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("저장") {
                    model.updatePin(program, in: bottleID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
