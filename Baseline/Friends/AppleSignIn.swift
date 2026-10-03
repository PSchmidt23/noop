#if os(iOS)
import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

/// Sign in with Apple for Friends (FRIENDS_SPEC.md §5.4), the Sayner pattern: a random nonce made once per appearance
/// of the sign-in screen, its SHA-256 on the Apple request, and the RAW nonce sent with the identity token to
/// Supabase's `grant_type=id_token` exchange.
///
/// No scopes are requested (D20): Friends shows the name the person types, and needs no email. The documented
/// fallback, if the Supabase project refuses Apple users without an email, is `requestedScopes = [.email]` here, plus
/// Email Address in the privacy manifest and the App Store label.
enum AppleSignIn {

    static let requestedScopes: [ASAuthorization.Scope] = []

    /// 32 characters from a 64-character set (64 divides 256, so `byte % 64` is unbiased).
    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-.")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if status != errSecSuccess {
            // Never fall back to a weak source: an empty nonce makes the exchange fail closed.
            return ""
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// For `SignInWithAppleButton(onRequest:)`: no scopes, the hashed nonce.
    static func configure(_ request: ASAuthorizationAppleIDRequest, rawNonce: String) {
        request.requestedScopes = requestedScopes
        request.nonce = sha256Hex(rawNonce)
    }

    enum Outcome: Equatable {
        case token(String)
        /// The person closed the sheet: say nothing.
        case canceled
        case failed(String)
    }

    /// For `SignInWithAppleButton(onCompletion:)`.
    static func outcome(_ result: Result<ASAuthorization, Error>) -> Outcome {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                return .failed("Apple didn't return a sign-in token. Try again.")
            }
            return .token(token)
        case .failure(let error):
            if let e = error as? ASAuthorizationError, e.code == .canceled { return .canceled }
            return .failed("Sign in with Apple didn't finish. Try again.")
        }
    }

    /// Asks Apple once more just before deleting the account, for a fresh authorization code the server exchanges
    /// and revokes (Apple's account-deletion requirement). nil when the person cancels or it fails: the account and
    /// its data are still deleted, and the screen explains how to revoke manually.
    @MainActor
    static func reauthorizeForDeletion() async -> String? {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let nonce = randomNonce()
        request.nonce = sha256Hex(nonce)
        let runner = AppleReauthorizer()
        return await runner.run(request)
    }
}

/// Bridges one `ASAuthorizationController` run into async. Holds itself alive until the delegate answers.
@MainActor
private final class AppleReauthorizer: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<String?, Never>?
    private var keepAlive: AppleReauthorizer?
    private var controller: ASAuthorizationController?

    /// The window Apple's sheet is presented over; set before the request starts.
    private var anchor: ASPresentationAnchor!

    func run(_ request: ASAuthorizationAppleIDRequest) async -> String? {
        // No window to present over (never the case behind a button): no code, and the account is still deleted.
        guard let window = Self.keyWindow() else { return nil }
        anchor = window
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            continuation = c
            keepAlive = self
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    private func finish(_ code: String?) {
        continuation?.resume(returning: code)
        continuation = nil
        controller = nil
        keepAlive = nil
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        let code = credential?.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        Task { @MainActor in self.finish(code) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { anchor }
    }

    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return active?.windows.first(where: \.isKeyWindow) ?? active?.windows.first
    }
}
#endif
