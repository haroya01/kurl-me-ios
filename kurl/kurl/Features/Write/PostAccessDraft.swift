//
//  PostAccessDraft.swift
//  kurl
//

import Foundation

struct PostAccessDraft: Equatable {
    static let passwordRange = 4...200

    var audience: PostAudience = .everyone
    var savedAudience: PostAudience = .everyone
    var hasPassword = false
    var newPassword = ""
    var countries: [String] = []
    var savedCountries: [String] = []
    var unlistedUrl: String?
    var room: NoteRoom?

    struct Patch: Equatable {
        var audience: PostAudience?
        var password: String?
        var countries: [String]?
    }

    init() {}

    init(post: MyPost) {
        audience = post.audience ?? .everyone
        savedAudience = audience
        hasPassword = post.hasPassword ?? false
        countries = post.blockedCountries ?? []
        savedCountries = countries
        unlistedUrl = post.unlistedUrl
    }

    var signature: String {
        "\(audience.rawValue)|\(countries.sorted().joined(separator: ","))"
    }

    var blockReason: String? {
        guard audience == .password else { return nil }
        if newPassword.isEmpty {
            return hasPassword ? nil : String(localized: "비밀번호를 정하면 발행할 수 있어요.")
        }
        if newPassword.unicodeScalars.count < Self.passwordRange.lowerBound {
            return String(localized: "비밀번호는 4자 이상으로 정해 주세요.")
        }
        return nil
    }

    var passwordPending: Bool { audience == .password && !newPassword.isEmpty }

    func patch(silent: Bool) -> Patch? {
        var patch = Patch()
        let sendsPassword = !silent && passwordPending && blockReason == nil
        if audience != savedAudience, audience != .password || hasPassword || sendsPassword {
            patch.audience = audience
        }
        if sendsPassword { patch.password = newPassword }
        if Set(countries) != Set(savedCountries) { patch.countries = countries.sorted() }
        return patch == Patch() ? nil : patch
    }

    mutating func adopt(saved post: MyPost, sent patch: Patch) {
        if let audience = post.audience ?? patch.audience { savedAudience = audience }
        if patch.password != nil { newPassword = "" }
        hasPassword = post.hasPassword ?? (hasPassword || patch.password != nil)
        if let countries = post.blockedCountries ?? patch.countries { savedCountries = countries }
        unlistedUrl = post.unlistedUrl
    }
}
