import Foundation
import Testing
@testable import Lumora

@Suite("Sign in with Apple")
@MainActor
struct AppleAccountTests {
    private func item() -> KeychainItem {
        KeychainItem(service: "com.mobapptech.lumora.tests", account: UUID().uuidString)
    }

    @Test func theAppleIDIsRememberedAndForgotten() {
        let keychain = item()
        defer { keychain.delete() }
        #expect(keychain.read() == nil)
        keychain.write("001234.abcd")
        #expect(keychain.read() == "001234.abcd")
        keychain.write("001234.efgh")   // replaces, never duplicates
        #expect(keychain.read() == "001234.efgh")

        let account = AppleAccount(keychain: keychain)
        #expect(account.isSignedIn)
        account.signOut()
        #expect(!account.isSignedIn)
        #expect(keychain.read() == nil)
    }

    @Test func appleNameFillsAnEmptyNameOnly() throws {
        let context = try TestFixtures.makeContext()
        let app = AppModel(container: context.container, launchOptions: LaunchOptions.parse(["-lumora-ui-testing"]))
        app.signedInWithApple(givenName: "Furkan")
        #expect(app.preferences.displayName == "Furkan")
        app.signedInWithApple(givenName: "Someone")
        #expect(app.preferences.displayName == "Furkan")
        app.signedInWithApple(givenName: nil)
        #expect(app.preferences.displayName == "Furkan")
    }
}
