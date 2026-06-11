import Foundation
import UIKit

#if canImport(MSAL)
import MSAL
#endif

enum MicrosoftAuthError: LocalizedError {
    case packageMissing
    case invalidAuthority
    case missingIdToken

    var errorDescription: String? {
        switch self {
        case .packageMissing:
            return "MSAL ist im Xcode-Projekt nicht eingebunden."
        case .invalidAuthority:
            return "Die Microsoft-Authority ist ungültig."
        case .missingIdToken:
            return "Microsoft hat kein ID-Token zurückgegeben."
        }
    }
}

final class MicrosoftAuthService {
    func acquireIdToken(tenantId: String, clientId: String, redirectUri: String, scopes: [String], from viewController: UIViewController) async throws -> String {
        #if canImport(MSAL)
        return try await withCheckedThrowingContinuation { continuation in
            do {
                guard let authorityURL = URL(string: "https://login.microsoftonline.com/\(tenantId)") else {
                    continuation.resume(throwing: MicrosoftAuthError.invalidAuthority)
                    return
                }

                let authority = try MSALAADAuthority(url: authorityURL)
                let configuration = MSALPublicClientApplicationConfig(
                    clientId: clientId,
                    redirectUri: redirectUri,
                    authority: authority
                )

                let application = try MSALPublicClientApplication(configuration: configuration)
                let webParameters = MSALWebviewParameters(authPresentationViewController: viewController)

                let requestedScopes = scopes.isEmpty ? ["User.Read"] : scopes
                let parameters = MSALInteractiveTokenParameters(scopes: requestedScopes, webviewParameters: webParameters)

                application.acquireToken(with: parameters) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let idToken = result?.idToken else {
                        continuation.resume(throwing: MicrosoftAuthError.missingIdToken)
                        return
                    }

                    continuation.resume(returning: idToken)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
        #else
        throw MicrosoftAuthError.packageMissing
        #endif
    }
}
