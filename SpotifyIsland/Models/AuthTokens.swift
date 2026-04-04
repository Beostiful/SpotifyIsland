import Foundation

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let grantedAt: Date
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case grantedAt = "granted_at"
        case scope
    }

    /// True if the access token has expired (with 60-second safety buffer).
    var isExpired: Bool {
        let expiryDate = grantedAt.addingTimeInterval(Double(expiresIn) - 60)
        return Date() >= expiryDate
    }
}
