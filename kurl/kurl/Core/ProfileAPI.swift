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

    /// 편집 폼 프리필용 — 현재 소개글. MyProfile 전체 중 bio 만 디코드(나머지 무시).
    static func myBio() async throws -> String? {
        let p: ProfileBio = try await client.get("/users/me/profile", authenticated: true)
        return p.bio
    }

    /// 소개글만 PUT — username/theme/socials 는 보내지 않아(null) 명함 설정이 안 지워진다.
    static func updateBio(_ bio: String) async throws {
        struct Body: Encodable { let bio: String }
        let _: ProfileBio = try await client.put(
            "/users/me/profile", body: Body(bio: bio), authenticated: true)
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
