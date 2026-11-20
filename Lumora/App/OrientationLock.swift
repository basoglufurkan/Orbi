import SwiftUI
import UIKit

/// iPhone stays in portrait, except while a session runs: then the focus
/// screen may turn sideways (a phone on a stand). iPad turns freely.
@MainActor
enum OrientationLock {
    static var allowsLandscape = false {
        didSet {
            guard allowsLandscape != oldValue else { return }
            apply()
        }
    }

    static var mask: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad { return .all }
        return allowsLandscape ? .allButUpsideDown : .portrait
    }

    private static func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
            if !allowsLandscape, UIDevice.current.userInterfaceIdiom == .phone {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
    }
}

final class LumoraAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
