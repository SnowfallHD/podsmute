//
//  AirPodsMuteHandler.swift
//  PodsMute
//
//  Observes the narrow audioaccessoryd mute event exposed through unified logging.
//

import Foundation

/// Converts an AirPods mute gesture into the same global Core Audio device mute
/// used by PodsMute's menu-bar action.
///
/// macOS routes the public AVAudioApplication callback only to the selected call
/// process. Since another app owns the voice session, PodsMute instead follows the
/// content-free `AAMuteStateChanged` event already emitted by audioaccessoryd.
final class AirPodsMuteHandler {

    var onMuteStateChanged: ((Bool) -> Void)?
    var onStatusChanged: ((String) -> Void)?

    private let audioController: AudioMuteController
    private let monitorQueue = DispatchQueue(label: "com.podsmute.audio-accessory-log")
    private var monitorProcess: Process?
    private var outputBuffer = Data()
    private var isStopping = false

    init(audioController: AudioMuteController) {
        self.audioController = audioController
    }

    deinit {
        stop()
    }

    func start() {
        guard monitorProcess == nil else { return }

        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--style", "ndjson",
            "--level", "debug",
            "--predicate",
            "process == \"audioaccessoryd\" AND eventMessage CONTAINS \"Mute Control: AAMuteStateChanged message:\"",
        ]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.monitorQueue.async {
                self?.consume(data)
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            guard let self else { return }
            outputPipe.fileHandleForReading.readabilityHandler = nil
            self.monitorQueue.async {
                self.outputBuffer.removeAll(keepingCapacity: false)
            }
            DispatchQueue.main.async {
                let wasStopping = self.isStopping
                self.monitorProcess = nil
                self.isStopping = false
                if !wasStopping {
                    self.report("AirPods mute event monitor exited with status \(terminatedProcess.terminationStatus)")
                }
            }
        }

        do {
            try process.run()
            monitorProcess = process
            report("AirPods mute event monitor active")
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            report("Failed to start AirPods mute event monitor: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard let process = monitorProcess else { return }
        isStopping = true
        process.terminate()
        report("AirPods mute event monitor stopped")
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)

        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            handleLogLine(Data(line))
        }
    }

    private func handleLogLine(_ data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["eventMessage"] as? String,
            message.contains("Mute Control: AAMuteStateChanged message:")
        else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let isMuted = !self.audioController.isMuted
            let didApply = self.audioController.setMute(isMuted)
            self.report("AirPods mute gesture received; global toggle applied=\(didApply)")
            if didApply {
                self.onMuteStateChanged?(isMuted)
            }
        }
    }

    private func report(_ message: String) {
        print("[AirPodsMuteHandler] \(message)")
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChanged?(message)
        }
    }
}
