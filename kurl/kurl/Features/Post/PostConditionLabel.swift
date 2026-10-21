import Foundation

enum PostConditionLabel {
    static func text(
        for post: PostListItem, isOwner: Bool, countryName: (String) -> String = Countries.name(for:)
    ) -> String? {
        let parts = parts(for: post, isOwner: isOwner, countryName: countryName)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func parts(
        for post: PostListItem, isOwner: Bool, countryName: (String) -> String = Countries.name(for:)
    ) -> [String] {
        guard post.locked == nil else { return [] }
        var parts: [String] = []
        switch post.audience ?? .everyone {
        case .everyone: break
        case .followers: parts.append(String(localized: "팔로워 공개"))
        case .unlisted: parts.append(String(localized: "링크로만 공개"))
        case .password: parts.append(String(localized: "비밀번호 글"))
        case .room: parts.append(String(localized: "방 멤버만"))
        }
        let countries = isOwner ? (post.blockedCountries ?? []) : []
        if !countries.isEmpty {
            let names = countries.map(countryName)
                .sorted { $0.localizedCompare($1) == .orderedAscending }
                .joined(separator: "·")
            parts.append(String(localized: "\(names) 제한"))
        } else if post.regionRestricted == true {
            parts.append(String(localized: "일부 나라 제한"))
        }
        return parts
    }
}
