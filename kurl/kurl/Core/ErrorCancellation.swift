import Foundation

extension Error {
    /// URLSession 은 취소를 URLError(.cancelled)로, APIClient 는 그걸 transport 로 감싼다.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        if let api = self as? APIError, case .transport(let inner) = api { return inner.isCancellation }
        return false
    }
}
