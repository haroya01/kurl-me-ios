import SwiftUI

struct MentionSuggestionList: View {
    let query: String?
    let onPick: (MentionCandidate) -> Void

    @State private var candidates: [MentionCandidate] = []
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(candidates) { candidate in
                Button {
                    onPick(candidate)
                } label: {
                    HStack(spacing: 10) {
                        AvatarView(
                            author: Author(
                                id: 0, username: candidate.username, bio: nil, avatarUrl: candidate.avatarUrl),
                            size: 28 * unit)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: candidate.displayName ?? candidate.username)
                                .typeScale(.body)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text(verbatim: "@\(candidate.username)")
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mention.\(candidate.username)")
            }
        }
        .animation(.smooth(duration: 0.2), value: candidates)
        .task(id: query) {
            guard let query else {
                candidates = []
                return
            }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let found = (try? await MentionAPI.candidates(query)) ?? []
            guard !Task.isCancelled else { return }
            candidates = found
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("멘션할 사람"))
    }
}
