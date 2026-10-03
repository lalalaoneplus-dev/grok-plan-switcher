import SwiftUI

struct PlanCard: View {
    let plan: GrokPlan
    let status: PlanStatus
    let canLaunch: Bool
    let onSignIn: () -> Void
    let onLaunch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 38, height: 38)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.name).font(.headline)
                    Text("Separate Grok Build login")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                statusBadge
            }

            statusContent

            HStack(spacing: 10) {
                Button(action: onSignIn) {
                    Label("Sign in", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(!canLaunch)

                Button(action: onLaunch) {
                    Label("Use \(plan.name)", systemImage: "terminal")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!canLaunch)

                Spacer()
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .ready(let usage) where usage.remainingPercent <= 0:
            Label("Usage full", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        case .ready:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .checking:
            ProgressView().controlSize(.small)
        case .notConnected:
            Label("Not connected", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
        case .signInAgain:
            Label("Sign in again", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        case .failed:
            Label("Unavailable", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch status {
        case .ready(let usage):
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(usage.remainingPercent.rounded()))%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("left \(usage.periodName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((100 - usage.remainingPercent).rounded()))% used")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: usage.remainingPercent, total: 100)
                    .tint(usage.remainingPercent < 15 ? .orange : .green)

                HStack {
                    if let resetAt = usage.resetAt {
                        Label("Resets \(resetAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "arrow.clockwise")
                    } else {
                        Text("Shared usage across Grok products")
                    }
                    Spacer()
                    Text("Updated \(usage.fetchedAt.formatted(date: .omitted, time: .shortened))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        case .checking:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Checking account usage…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 61)
        case .notConnected:
            Text("Sign in with the account for this plan to see its remaining usage.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 61)
        case .signInAgain:
            Text("This profile needs a fresh Grok sign-in. Sign in, then refresh usage.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 61)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 61)
        }
    }
}
