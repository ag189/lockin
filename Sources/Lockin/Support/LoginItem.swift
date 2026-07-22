import Foundation
import ServiceManagement
import os

/// Launch-at-login via `SMAppService.mainApp`. Only meaningful when running as a bundled,
/// signed `.app`; degrades silently during `swift run` development.
enum LoginItem {
    private static let log = Logger(subsystem: "com.lockin.app", category: "login")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            log.error("Login item toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
