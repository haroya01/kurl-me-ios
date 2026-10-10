//
//  PeopleResults.swift
//  kurl
//

import SwiftUI

@Observable
@MainActor
final class PeopleSearchModel {
    private(set) var phase: LoadState<[PersonMatch]> = .idle
    private(set) var tooShort = false
    private(set) var loadingMore = false
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
            phase = .loaded([])
            return
        }
        if case .loaded = phase {} else { phase = .loading }
        do {
            let result = try await PeopleAPI.search(raw)
            guard myGen == generation else { return }
            hasNext = result.hasNext
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
                case .loaded where model.tooShort:
                    ContentUnavailableView(
                        "두 글자 이상 입력하면 사람을 찾아요",
                        systemImage: "person.2")
                        .padding(.top, 40)
                case .loaded(let people) where people.isEmpty:
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 40)
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
            FollowButton(username: person.username, initialStatus: person.followSeed)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("person.\(person.username)")
    }
}
