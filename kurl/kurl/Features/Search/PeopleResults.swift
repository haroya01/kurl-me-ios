import SwiftUI

@Observable
@MainActor
final class PeopleSearchModel {
    private(set) var phase: LoadState<[PersonMatch]> = .idle
    private(set) var tooShort = false
    private(set) var loadingMore = false
    var remote: [RemoteAccount]?
    private var query = ""
    private var page = 0
    private var hasNext = false
    private var generation = 0

    func show(_ raw: String) async {
        generation += 1
        let myGen = generation
        query = raw
        page = 0
        hasNext = false
        tooShort = !PeopleAPI.isSearchable(raw)
        guard !tooShort else {
            remote = nil
            phase = .loaded([])
            return
        }
        if case .loaded = phase {} else { phase = .loading }
        async let remoteMatches = Self.remoteMatches(raw)
        do {
            let result = try await PeopleAPI.search(raw)
            let found = await remoteMatches
            guard myGen == generation else { return }
            hasNext = result.hasNext
            remote = found
            phase = .loaded(result.items)
        } catch {
            guard myGen == generation, !Task.isCancelled else { return }
            phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current person: PersonMatch) async {
        guard hasNext, !loadingMore, case .loaded(let items) = phase,
              let index = items.firstIndex(of: person), index >= items.count - 3 else { return }
        loadingMore = true
        defer { loadingMore = false }
        let myGen = generation
        guard let result = try? await PeopleAPI.search(query, page: page + 1) else { return }
        guard myGen == generation else { return }
        page += 1
        hasNext = result.hasNext
        let seen = Set(items.map(\.username))
        phase = .loaded(items + result.items.filter { !seen.contains($0.username) })
    }

    private static func remoteMatches(_ raw: String) async -> [RemoteAccount]? {
        guard FederationAPI.queryDomain(raw) == nil else { return nil }
        return await FederationAPI.searchAccounts(raw)
    }
}

struct PeopleResultsList: View {
    let model: PeopleSearchModel
    let query: String
    let retry: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch model.phase {
                case .failed(let message):
                    ErrorState(message: message, retry: retry)
                        .padding(.top, 16)
                case .loaded where model.tooShort:
                    FeedPlaceholder(title: "두 글자 이상 입력하면 사람을 찾아요")
                        .padding(.top, 16)
                case .loaded(let people) where people.isEmpty:
                    if let remote = model.remote, !remote.isEmpty {
                        RemotePeopleSection(accounts: remoteAccounts, divided: false)
                    } else {
                        FeedPlaceholder(title: "‘\(query)’ 결과가 없어요")
                            .padding(.top, 16)
                        if showsHint(localPeople: 0) {
                            RemotePeopleSection(accounts: remoteAccounts, divided: true)
                                .padding(.top, 12)
                        }
                    }
                case .loaded(let people):
                    ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                        PersonResultRow(person: person)
                            .rowDivider(index > 0)
                            .task { await model.loadMoreIfNeeded(current: person) }
                    }
                    if model.loadingMore {
                        KurlLoadingMark()
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                    if !(model.remote ?? []).isEmpty || showsHint(localPeople: people.count) {
                        RemotePeopleSection(accounts: remoteAccounts, divided: true)
                    }
                default:
                    KurlLoadingMark().frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(Palette.readingBg)
        .accessibilityIdentifier("search.people")
    }

    private var remoteAccounts: Binding<[RemoteAccount]> {
        Binding(get: { model.remote ?? [] }, set: { model.remote = $0 })
    }

    private func showsHint(localPeople: Int) -> Bool {
        RemoteSearchHint.shows(in: .peopleTab, query: query, remote: model.remote, localPeople: localPeople)
    }
}

private struct PersonResultRow: View {
    let person: PersonMatch

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(value: Route.author(username: person.username)) {
                HStack(alignment: .top, spacing: 12) {
                    AvatarView(author: person.asAuthor, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: person.shownName)
                            .typeScale(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        if person.shownName != person.username {
                            Text(verbatim: "@\(person.username)")
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                                .lineLimit(1)
                        }
                        if let bio = person.bio, !bio.isEmpty {
                            Text(verbatim: bio)
                                .typeScale(.footnote)
                                .foregroundStyle(Palette.secondary)
                                .lineLimit(2)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            FollowButton(username: person.username, initialStatus: person.followSeed, outlined: true)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("person.\(person.username)")
    }
}
