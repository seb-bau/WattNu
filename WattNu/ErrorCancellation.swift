import Foundation

extension Error {
    var isRequestCancellation: Bool {
        if self is CancellationError {
            return true
        }

        if let urlError = self as? URLError,
           urlError.code == .cancelled {
            return true
        }

        let error = self as NSError

        return (
            error.domain == NSURLErrorDomain
            && error.code == NSURLErrorCancelled
        )
    }
}
