//
//  AppDelegate.swift
//  PodsMute
//
//  Application delegate handling app lifecycle and service initialization.
//

import Cocoa

/// Main application delegate.
///
/// Responsibilities:
/// - Initialize and wire up all services
/// - Observe the narrow audioaccessoryd AirPods mute event in unified logging
/// - Toggle the default input device through the existing global Core Audio path
/// - Handle app lifecycle events
///
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Services

    private var audioController: AudioMuteController!
    private var airPodsMuteHandler: AirPodsMuteHandler!
    private var statusBarController: StatusBarController!

    // Keep reference to BluetoothManager for device detection (status display)
    private var bluetoothManager: BluetoothManager!

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] Application launching...")

        // Initialize services
        setupServices()

        // Start the local AirPods mute-event monitor.
        setupAirPodsMuteHandler()

        print("[AppDelegate] Application ready")
        print("[AppDelegate] Press your AirPods button to toggle mute")
        print("[AppDelegate] Listening for the audioaccessoryd mute event...")
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[AppDelegate] Application terminating...")

        if audioController.isMuted {
            print("[AppDelegate] Restoring microphone to unmuted state...")
            audioController.setMute(false)
        }

        airPodsMuteHandler?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Setup

    private func setupServices() {
        // Create audio controller first (no dependencies)
        audioController = AudioMuteController()

        // Create Bluetooth manager (for device status display)
        bluetoothManager = BluetoothManager()

        airPodsMuteHandler = AirPodsMuteHandler(audioController: audioController)

        // Create status bar controller
        statusBarController = StatusBarController(
            audioController: audioController,
            bluetoothManager: bluetoothManager
        )

        // Check for paired AirPods (for status display)
        checkForAirPods()
    }

    private func setupAirPodsMuteHandler() {
        airPodsMuteHandler.onMuteStateChanged = { [weak self] isMuted in
            guard let self = self else { return }

            self.statusBarController.updateIcon()
            self.statusBarController.showMutePopover(isMuted: isMuted)
        }

        airPodsMuteHandler.onStatusChanged = { status in
            print("[AppDelegate] \(status)")
        }

        airPodsMuteHandler.start()
    }

    private func checkForAirPods() {
        let devices = bluetoothManager.pairedDevices()

        if devices.isEmpty {
            print("[AppDelegate] No paired AirPods found")
            print("[AppDelegate] Please pair your AirPods Max or AirPods Pro and try again")
        } else {
            print("[AppDelegate] Found \(devices.count) paired AirPods device(s):")
            for device in devices {
                print("  - \(device.name) (\(device.id))")
            }
        }
    }
}
