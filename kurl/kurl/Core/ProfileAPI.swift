//
//  ProfileAPI.swift
//  kurl
//

import Foundation

/// 내 프로필 편집 — 소개글(bio)·아바타. bio 는 부분 수정(다른 필드 null=유지)이라 소개글만
/// 보내도 테마·소셜(명함)은 보존된다. 아바타는 커버와 같은 presign→S3→commit.
enum ProfileAPI {
    private static let client = APIClient.shared

    private struct ProfileBio: Decodable { let bio: String? }

    /// 편집 폼 프리필 — 소개글 + 프라이버시 토글 현재값. MyProfile 전체 중 필요한 필드만 디코드.
    struct EditPrefill: Decodable {
        let bio: String?
        /// 아직 이 키를 안 내리는 서버(배포 전)를 위해 부재 시 false.
        let hideFollowerCount: Bool

        enum CodingKeys: String, CodingKey { case bio, hideFollowerCount }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            bio = try c.decodeIfPresent(String.self, forKey: .bio)
            hideFollowerCount = try c.decodeIfPresent(Bool.self, forKey: .hideFollowerCount) ?? false
        }
    }

    /// 편집 폼 프리필용 — 현재 소개글 + 팔로워 수 숨김 여부.
    static func myProfile() async throws -> EditPrefill {
        try await client.get("/users/me/profile", authenticated: true)
    }

    /// 부분 PUT — 보낸 필드만 바뀐다(nil=인코딩에서 생략 → 서버는 미변경). 그래서 username·bio
    /// 만 넘겨도 theme·socials(명함) 설정은 보존된다. username 검증·중복·이전 이름 유예는 서버 몫.
    static func update(
        username: String? = nil, bio: String? = nil, hideFollowerCount: Bool? = nil
    ) async throws {
        struct Body: Encodable {
            let username: String?
            let bio: String?
            let hideFollowerCount: Bool?
        }
        let _: ProfileBio = try await client.put(
            "/users/me/profile",
            body: Body(username: username, bio: bio, hideFollowerCount: hideFollowerCount),
            authenticated: true)
    }

    /// 아바타 업로드 — presign → S3 직행 PUT → commit. 반환 = 공개 avatarUrl.
    static func uploadAvatar(jpegData: Data) async throws -> String {
        struct PresignBody: Encodable { let contentType: String }
        struct Presign: Decodable {
            let uploadUrl: String
            let publicUrl: String
            let key: String
            let maxBytes: Int64
        }
        struct CommitBody: Encodable { let key: String }
        struct Commit: Decodable { let avatarUrl: String }

        let presign: Presign = try await client.post(
            "/users/me/avatar/presigned-url",
            body: PresignBody(contentType: "image/jpeg"), authenticated: true)
        guard jpegData.count <= presign.maxBytes else { throw APIError.invalidURL }

        if !Config.useMocks, let url = URL(string: presign.uploadUrl) {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.upload(for: request, from: jpegData)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw APIError.http(status: (response as? HTTPURLResponse)?.statusCode ?? -1)
            }
        }

        let commit: Commit = try await client.put(
            "/users/me/avatar", body: CommitBody(key: presign.key), authenticated: true)
        return commit.avatarUrl
    }
}
