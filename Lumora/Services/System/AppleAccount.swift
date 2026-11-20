import AuthenticationServices
import Foundation
import Observation
import Security

/// Optional Sign in with Apple. Lumora works fully without it; signing in
/// gives your universe your name and a stable identity, without any server:
/// the Apple user ID lives in the iCloud Keychain (so a new device knows
/// you), and only the full name is requested — never the email.
///
/// The ID is checked with Apple on launch and when Apple says it was revoked
/// (Settings › Apple ID › Sign in with Apple), which signs you out here.
@MainActor
@Observable
final class AppleAccount {
    private(set) var userID: String?
    var isSignedIn: Bool { userID != nil }

    @ObservationIgnored private let keychain: KeychainItem
    @ObservationIgnored private var revoked: (any NSObjectProtocol)?

    init(keychain: KeychainItem = KeychainItem(service: "com.mobapptech.lumora.apple", account: "userID")) {
        self.keychain = keychain
        userID = keychain.read()
        revoked = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.signOut() }
        }
    }

    /// Asks only for the name.
    static func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    /// Stores the signed-in user. Returns the given name Apple shared (only
    /// on the first sign-in with this app), to use as the universe's name.
    @discardableResult
    func complete(_ result: Result<ASAuthorization, any Error>) -> Result<String?, AppleAccountError> {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                return .failure(.failed)
            }
            keychain.write(credential.user)
            userID = credential.user
            let given = credential.fullName?.givenName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(given?.isEmpty == false ? given : nil)
        case let .failure(error):
            if let error = error as? ASAuthorizationError, error.code == .canceled { return .failure(.canceled) }
            return .failure(.failed)
        }
    }

    /// Checks with Apple that the stored ID is still authorised.
    func refresh() async {
        guard let userID else { return }
        let state = await withCheckedContinuation { (done: CheckedContinuation<ASAuthorizationAppleIDProvider.CredentialState, Never>) in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in done.resume(returning: state) }
        }
        if state == .revoked || state == .notFound { signOut() }
    }

    /// Forgets the Apple ID on this device and in the iCloud Keychain. The
    /// universe stays: it never depended on the account.
    func signOut() {
        keychain.delete()
        userID = nil
    }
}

enum AppleAccountError: Error, Equatable {
    case canceled, failed
}

/// One string in the keychain, shared through the iCloud Keychain.
struct KeychainItem: Sendable {
    var service: String
    var account: String

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kCFBooleanTrue as Any]
    }

    func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String) {
        delete()
        var q = query
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
