import ApplicationServices
import AVFoundation
@preconcurrency import AppKit
import Foundation

enum Permissions {
    static func requestMicrophoneAccessIfNeeded() -> Bool {
        if hasMicrophoneAccess() {
            return true
        }

        activateForPermissionPrompt()

        let semaphore = DispatchSemaphore(value: 0)
        let permissionBox = MicrophonePermissionBox()

        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                AVAudioApplication.requestRecordPermission { allowed in
                    permissionBox.granted = allowed
                    semaphore.signal()
                }
                _ = semaphore.wait(timeout: .now() + 10)
                return permissionBox.granted
            @unknown default:
                return false
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                permissionBox.granted = allowed
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 10)
            return permissionBox.granted
        @unknown default:
            return false
        }
    }

    static func hasMicrophoneAccess() -> Bool {
        if #available(macOS 14.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        }
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestListenEventAccessIfNeeded() -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }
        return CGRequestListenEventAccess()
    }

    static func requestAccessibilityIfNeeded() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestPostEventAccessIfNeeded() -> Bool {
        if CGPreflightPostEventAccess() {
            return true
        }
        return CGRequestPostEventAccess()
    }

    static func hasAccessibilityAccess() -> Bool {
        AXIsProcessTrusted()
    }

    static func canListenToEvents() -> Bool {
        CGPreflightListenEventAccess()
    }

    static func canPostEvents() -> Bool {
        CGPreflightPostEventAccess()
    }

    private static func activateForPermissionPrompt() {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private final class MicrophonePermissionBox: @unchecked Sendable {
    var granted = false
}
