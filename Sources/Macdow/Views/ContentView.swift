import SwiftUI

enum SidebarItem: Hashable {
    case setup
    case bottle(UUID)
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(OpenRequests.self) private var openRequests
    @State private var selection: SidebarItem?
    @State private var showingCreate = false
    @State private var pendingDelete: Bottle?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(isPresented: $showingCreate) {
            CreateBottleView { selection = .bottle($0) }
        }
        .sheet(item: Binding(
            get: { openRequests.items.first },
            set: { if $0 == nil, !openRequests.items.isEmpty { openRequests.items.removeFirst() } }
        )) { item in
            OpenWithBottleView(item: item) { selection = .bottle($0) }
        }
        .alert("알림", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("확인") {}
        } message: {
            Text(model.alertMessage ?? "")
        }
        .confirmationDialog(
            "‘\(pendingDelete?.name ?? "")’ 병을 삭제할까요?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("휴지통으로 이동", role: .destructive) {
                if let bottle = pendingDelete {
                    if selection == .bottle(bottle.id) { selection = nil }
                    model.delete(bottle)
                }
            }
        } message: {
            Text("병 안에 설치된 모든 프로그램과 저장 데이터가 함께 삭제됩니다.")
        }
        .onAppear {
            guard selection == nil else { return }
            if model.isReady, let first = model.bottles.first {
                selection = .bottle(first.id)
            } else {
                selection = .setup
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("시작하기") {
                Label("환경 점검", systemImage: model.isReady ? "checkmark.seal" : "exclamationmark.triangle")
                    .tag(SidebarItem.setup)
            }
            Section("병") {
                ForEach(model.bottles) { bottle in
                    HStack {
                        Label(bottle.name, systemImage: "shippingbox")
                        Spacer()
                        if model.busyBottles.contains(bottle.id) {
                            ProgressView().controlSize(.mini)
                        } else if model.processes.contains(where: { $0.bottleID == bottle.id && $0.isRunning }) {
                            Circle().fill(.green).frame(width: 7, height: 7)
                        }
                    }
                    .tag(SidebarItem.bottle(bottle.id))
                    .contextMenu {
                        Button("C: 드라이브 열기") { NSWorkspace.shared.open(model.driveC(for: bottle)) }
                        Button("모든 프로그램 종료") { model.killAll(in: bottle) }
                        Divider()
                        Button("삭제…", role: .destructive) { pendingDelete = bottle }
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        .toolbar {
            ToolbarItem {
                Button { showingCreate = true } label: { Label("새 병", systemImage: "plus") }
                    .help("새 병 만들기")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            openRequests.items += urls.map { OpenItem(url: $0) }
            return !urls.isEmpty
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .setup?:
            SetupView()
        case .bottle(let id)?:
            if let bottle = model.bottle(withID: id) {
                BottleDetailView(bottle: bottle).id(id)
            } else {
                placeholder
            }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        ContentUnavailableView {
            Label("병을 선택하세요", systemImage: "shippingbox")
        } description: {
            Text("병은 Windows 프로그램이 설치되는 독립된 가상 Windows 환경입니다.")
        } actions: {
            Button("새 병 만들기") { showingCreate = true }
                .disabled(model.runtimes.isEmpty)
        }
    }
}
