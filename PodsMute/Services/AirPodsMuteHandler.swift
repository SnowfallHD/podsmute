//
//  AirPodsMuteHandler.swift
//  PodsMute
//
//  Participates in the public macOS AirPods mute-control path.
//

import AVFAudio
import Foundation

/// Opens a minimal input stream and handles AirPods mute requests for this app.
///
/// The input tap intentionally discards every buffer. It exists only to make
/// PodsMute an active input-audio app while testing Apple's public mute API.
final class AirPodsMuteHandler {

    var onMuteStateChanged: ((Bool) -> Void)?
    var onStatusChanged: ((String) -> Void)?

    private let audioController: AudioMuteController
    private let audioApplication = AVAudioApplication.shared
    private let audioEngine = AVAudioEngine()
    private var hasInputTap = false
    private var isRunning = false

    init(audioController: AudioMuteController) {
        self.audioController = audioController
    }

    deinit {
        stop()
    }

    func start() {
        guard !isRunning else { return }

        switch audioApplication.recordPermission {
        case .granted:
            startInputAndHandler()
        case .denied:
            report("Microphone access is denied; AirPods gesture experiment is inactive")
        case .undetermined:
            report("Waiting for microphone authorization")
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.startInputAndHandler()
                    } else {
                        self.report("Microphone access was not granted; AirPods gesture experiment is inactive")
                    }
                }
            }
        @unknown default:
            report("Unknown microphone authorization state; AirPods gesture experiment is inactive")
        }
    }

    func stop() {
        guard isRunning || hasInputTap else { return }

        do {
            try audioApplication.setInputMuteStateChangeHandler(nil)
        } catch {
            report("Failed to clear AirPods mute handler: \(error.localizedDescription)")
        }

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }

        isRunning = false
        report("AirPods mute handler stopped; microphone mute state was preserved")
    }

    private func startInputAndHandler() {
        guard !isRunning else { return }

        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            report("Default input has no channels; AirPods gesture experiment is inactive")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { _, _ in
            // Deliberately discard microphone samples. Nothing is retained or sent.
        }
        hasInputTap = true
        audioEngine.prepare()

        do {
            try audioEngine.start()
            try audioApplication.setInputMuteStateChangeHandler { [weak self] shouldMute in
                guard let self else { return false }

                let didApply = self.audioController.setMute(shouldMute)
                self.report("AirPods requested mute=\(shouldMute); applied=\(didApply)")

                if didApply {
                    DispatchQueue.main.async {
                        self.onMuteStateChanged?(shouldMute)
                    }
                }
                return didApply
            }
            isRunning = true
            report("AirPods mute handler active with a discard-only input stream")
        } catch {
            try? audioApplication.setInputMuteStateChangeHandler(nil)
            audioEngine.stop()
            inputNode.removeTap(onBus: 0)
            hasInputTap = false
            report("Failed to start AirPods mute handler: \(error.localizedDescription)")
        }
    }

    private func report(_ message: String) {
        print("[AirPodsMuteHandler] \(message)")
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChanged?(message)
        }
    }
}
