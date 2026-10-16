import SwiftUI

struct MentionSuggestionList: View {
    let query: String?
    let onPick: (MentionCandidate) -> Void
    var onPickRemote: ((RemoteAccount) -> Void)?

    @State private var candidates: [MentionCandidate] = []
    @State private var remote: [RemoteAccount] = []
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(candidates) { candidate in
                Button {
                    onPick(candidate)
                } label: {
                    row(
                        author: Author(
                            id: 0, username: candidate.username, bio: nil, avatarUrl: candidate.avatarUrl),
                        name: candidate.displayName ?? candidate.username,
                        handle: candidate.username)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mention.\(candidate.username)")
            }
            ForEach(remote) { account in
                Button {
                    onPickRemote?(account)
                } label: {
                    row(author: account.asAuthor, name: account.shownName, handle: account.acct)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mention.remote.\(account.acct)")
            }
        }
        .animation(.smooth(duration: 0.2), value: candidates)
        .animation(.smooth(duration: 0.2), value: remote)
        .task(id: query) {
            guard let query else {
                candidates = []
                remote = []
                return
            }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let searchesRemote = onPickRemote != nil
            async let local: [MentionCandidate] = query.contains("@") ? [] : ((try? await MentionAPI.candidates(query)) ?? [])
            async let elsewhere: [RemoteAccount] = searchesRemote
                ? (await FederationAPI.searchAccounts(query, limit: FederationAPI.suggestionLimit) ?? [])
                : []
            let (foundLocal, foundRemote) = await (local, elsewhere)
            guard !Task.isCancelled else { return }
            candidates = foundLocal
            remote = foundRemote
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("멘션할 사람"))
    }

    private func row(author: Author, name: String, handle: String) -> some View {
        HStack(spacing: 10) {
            AvatarView(author: author, size: 28 * unit)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: name)
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(verbatim: "@\(handle)")
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
