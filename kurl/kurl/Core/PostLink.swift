//
//  PostLink.swift
//  kurl
//

import Foundation

struct PostLink: Equatable {
    let username: String
    let slug: String
    let key: String?

    init?(target: String) {
        guard let components = URLComponents(string: target) else { return nil }
        self.init(path: components.path, query: components.queryItems)
    }

    init?(widgetURL url: URL) {
        guard url.scheme == "kurlwidget", url.host == "post",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        self.init(path: components.path, query: components.queryItems)
    }

    private init?(path: String, query: [URLQueryItem]?) {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        username = parts[0]
        slug = parts[1]
        key = query?.first(where: { $0.name == "k" })?.value.flatMap { $0.isEmpty ? nil : $0 }
    }

    @MainActor
    func register() {
        guard let key else { return }
        PostAccess.shared.setKey(key, username: username, slug: slug)
    }
}
