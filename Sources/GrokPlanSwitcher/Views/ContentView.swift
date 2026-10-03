import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("workingDirectoryPath") private var workingDirectoryPath = NSHomeDirectory()
    @State private var statuses = Dictionary(uniqueKeysWithValues: GrokPlan.all.map { ($0.id, PlanStatus.checking) })
    @State private var isBusy = false
    @State private var showingFolderPicker = false
    @State private var alertMessage: String?
    @State private var noticeMessage: String?

    private let usageService = GrokUsageService()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            workspacePicker

            VStack(spacing: 14) {
                ForEach(GrokPlan.all) { plan in
                    PlanCard(
                        plan: plan,
                        status: statuses[plan.id] ?? .checking,
                        canLaunch: GrokCLI.executable != nil && !isBusy,
                        onSignIn: { signIn(plan) },
                        onLaunch: { use(plan) }
                    )
                }
            }

            if let noticeMessage {
                Label(noticeMessage, systemImage: "arrow.left.arrow.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 7) {
                Image(systemName: "info.circle")
                Text("At 100%, the next launch uses the other plan; running sessions stay on their account.")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .task { await refreshAll() }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                workingDirectoryPath = url.path
            }
        }
        .alert("Grok Plan Switcher", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 52, height: 52)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))

            VStack(alignment: .leading, spacing: 4) {
                Text("Grok Plan Switcher")
                    .font(.title2.weight(.bold))
                Text("Exhausted plans automatically fall back on the next launch.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                Task { await refreshAll() }
            } label: {
                if isBusy {
                    ProgressView().controlSize(.small).frame(width: 18, height: 18)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isBusy)
            .help("Refresh both plans")
        }
    }

    private var workspacePicker: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("CLI opens in")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(workingDirectoryPath)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button("Choose Folder…") { showingFolderPicker = true }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
    }

    private func refreshAll() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await refreshStatuses()
    }

    private func refreshStatuses() async {
        async let first = usageService.status(for: GrokPlan.all[0])
        async let second = usageService.status(for: GrokPlan.all[1])
        let (firstStatus, secondStatus) = await (first, second)
        statuses = [GrokPlan.all[0].id: firstStatus, GrokPlan.all[1].id: secondStatus]
    }

    private func signIn(_ plan: GrokPlan) {
        do {
            try GrokCLI.open(plan: plan, signIn: true, workingDirectory: workingDirectoryPath)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func use(_ preferred: GrokPlan) {
        guard !isBusy else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            noticeMessage = nil
            await refreshStatuses()

            guard let plan = GrokPlan.planToUse(preferred: preferred, statuses: statuses) else {
                let other = GrokPlan.all.first { $0 != preferred }!
                alertMessage = "\(preferred.name) is exhausted, and \(other.name)'s remaining usage could not be confirmed. Sign in or refresh that plan, then try again."
                return
            }

            if plan != preferred {
                noticeMessage = "\(preferred.name) is at its limit. Opening \(plan.name) instead."
            }

            do {
                try GrokCLI.open(plan: plan, signIn: false, workingDirectory: workingDirectoryPath)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }
}
