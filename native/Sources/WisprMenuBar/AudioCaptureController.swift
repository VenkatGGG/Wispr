@preconcurrency import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

struct RecordedCapture {
    let wavData: Data
    let durationMs: Int
}

final class AudioCaptureController {
    private let targetSampleRate: Double = 16_000
    private let targetChannels: AVAudioChannelCount = 1
    private let lock = NSLock()
    private let captureQueue = DispatchQueue(label: "Flow.AudioCapture")

    private var captureSession: AVCaptureSession?
    private var captureInput: AVCaptureDeviceInput?
    private var captureOutput: AVCaptureAudioDataOutput?
    private var sampleCollector: AudioSampleCollector?
    private var pcmData = Data()
    private var captureStartedAt: Date?

    func startCapture() throws {
        cancelCapture()

        guard Permissions.hasMicrophoneAccess() else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Flow needs Microphone access. Enable it in System Settings > Privacy & Security > Microphone."]
            )
        }

        guard let inputDevice = selectInputDevice() else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 14,
                userInfo: [NSLocalizedDescriptionKey: "No active microphone input device is available."]
            )
        }

        NSLog(
            "[AudioCapture] Using microphone: %@ manufacturer=%@ transport=%d uid=%@",
            inputDevice.localizedName,
            inputDevice.manufacturer,
            inputDevice.transportType,
            inputDevice.uniqueID
        )

        let captureSession = AVCaptureSession()
        let captureInput = try AVCaptureDeviceInput(device: inputDevice)
        let captureOutput = AVCaptureAudioDataOutput()
        captureOutput.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: Int(targetChannels),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let collector = AudioSampleCollector { [weak self] chunk in
            self?.appendPCM(chunk)
        }
        captureOutput.setSampleBufferDelegate(collector, queue: captureQueue)

        captureSession.beginConfiguration()

        guard captureSession.canAddInput(captureInput) else {
            captureSession.commitConfiguration()
            throw NSError(
                domain: "WisprMenuBar",
                code: 15,
                userInfo: [NSLocalizedDescriptionKey: "Flow could not attach to the selected microphone."]
            )
        }

        guard captureSession.canAddOutput(captureOutput) else {
            captureSession.commitConfiguration()
            throw NSError(
                domain: "WisprMenuBar",
                code: 16,
                userInfo: [NSLocalizedDescriptionKey: "Flow could not configure audio capture output."]
            )
        }

        captureSession.addInput(captureInput)
        captureSession.addOutput(captureOutput)
        captureSession.commitConfiguration()

        lock.withLock {
            pcmData.removeAll(keepingCapacity: true)
        }

        captureSession.startRunning()

        self.captureSession = captureSession
        self.captureInput = captureInput
        self.captureOutput = captureOutput
        self.sampleCollector = collector
        captureStartedAt = Date()
    }

    func cancelCapture() {
        stopCaptureSession()
        lock.withLock {
            pcmData.removeAll(keepingCapacity: false)
        }
        captureStartedAt = nil
    }

    func finishCapture(minimumCaptureMs: Int) throws -> RecordedCapture? {
        guard captureSession != nil, let captureStartedAt else {
            return nil
        }

        stopCaptureSession()

        let durationMs = Int(Date().timeIntervalSince(captureStartedAt) * 1000)
        self.captureStartedAt = nil

        guard durationMs >= minimumCaptureMs else {
            lock.withLock {
                pcmData.removeAll(keepingCapacity: false)
            }
            return nil
        }

        let capturedPCM = lock.withLock { () -> Data in
            let snapshot = pcmData
            pcmData.removeAll(keepingCapacity: false)
            return snapshot
        }

        let averageLevel = averageSignalLevel(for: capturedPCM)
        NSLog(
            "[AudioCapture] Finished capture. durationMs=%d bytes=%d averageLevel=%.6f",
            durationMs,
            capturedPCM.count,
            averageLevel
        )

        guard !capturedPCM.isEmpty else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 13,
                userInfo: [NSLocalizedDescriptionKey: "No microphone audio was captured. Check the selected input device and microphone permission."]
            )
        }

        return RecordedCapture(wavData: makeWAV(from: capturedPCM), durationMs: durationMs)
    }

    private func selectInputDevice() -> AVCaptureDevice? {
        let devices = availableAudioDevices()
        for device in devices {
            NSLog(
                "[AudioCapture] Discovered microphone: %@ manufacturer=%@ transport=%d uid=%@",
                device.localizedName,
                device.manufacturer,
                device.transportType,
                device.uniqueID
            )
        }

        if let builtInMic = devices.first(where: isPreferredBuiltInMicrophone) {
            return builtInMic
        }

        return devices.first
    }

    private func availableAudioDevices() -> [AVCaptureDevice] {
        if #available(macOS 14.0, *) {
            return AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone, .external],
                mediaType: .audio,
                position: .unspecified
            ).devices
        }

        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private func isPreferredBuiltInMicrophone(_ device: AVCaptureDevice) -> Bool {
        device.transportType == fourCharacterCode("bltn")
    }

    private func fourCharacterCode(_ string: String) -> Int32 {
        string.utf8.reduce(0) { partial, byte in
            (partial << 8) | Int32(byte)
        }
    }

    private func appendPCM(_ chunk: Data) {
        lock.withLock {
            pcmData.append(chunk)
        }
    }

    private func stopCaptureSession() {
        captureOutput?.setSampleBufferDelegate(nil, queue: nil)

        if let captureSession {
            captureSession.stopRunning()
            captureSession.beginConfiguration()
            if let captureOutput {
                captureSession.removeOutput(captureOutput)
            }
            if let captureInput {
                captureSession.removeInput(captureInput)
            }
            captureSession.commitConfiguration()
        }

        sampleCollector = nil
        captureOutput = nil
        captureInput = nil
        captureSession = nil
    }

    private func averageSignalLevel(for pcmData: Data) -> Double {
        let sampleCount = pcmData.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return 0 }

        let totalMagnitude: Double = pcmData.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            return samples.reduce(into: 0.0) { partial, sample in
                partial += abs(Double(sample)) / Double(Int16.max)
            }
        }

        return totalMagnitude / Double(sampleCount)
    }

    private func makeWAV(from pcmData: Data) -> Data {
        let sampleRate = UInt32(targetSampleRate)
        let channels = UInt16(targetChannels)
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let riffSize = 36 + dataSize

        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        wav.append(littleEndianBytes(riffSize))
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        wav.append(littleEndianBytes(UInt32(16)))
        wav.append(littleEndianBytes(UInt16(1)))
        wav.append(littleEndianBytes(channels))
        wav.append(littleEndianBytes(sampleRate))
        wav.append(littleEndianBytes(byteRate))
        wav.append(littleEndianBytes(blockAlign))
        wav.append(littleEndianBytes(bitsPerSample))
        wav.append("data".data(using: .ascii)!)
        wav.append(littleEndianBytes(dataSize))
        wav.append(pcmData)
        return wav
    }

    private func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> Data {
        var littleEndian = value.littleEndian
        return Data(bytes: &littleEndian, count: MemoryLayout<T>.size)
    }
}

private final class AudioSampleCollector: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let onSample: (Data) -> Void
    private var hasLoggedSampleFormat = false
    private var hasLoggedBufferFailure = false

    init(onSample: @escaping (Data) -> Void) {
        self.onSample = onSample
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        if !hasLoggedSampleFormat,
           let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
           let basicDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
            let basicDescription = basicDescriptionPointer.pointee
            NSLog(
                "[AudioCapture] First sample buffer format: sampleRate=%.1f channels=%u formatID=%u bytesPerFrame=%u",
                basicDescription.mSampleRate,
                basicDescription.mChannelsPerFrame,
                basicDescription.mFormatID,
                basicDescription.mBytesPerFrame
            )
            hasLoggedSampleFormat = true
        }

        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            if !hasLoggedBufferFailure {
                NSLog("[AudioCapture] Sample buffer did not contain a CMBlockBuffer.")
                hasLoggedBufferFailure = true
            }
            return
        }

        let byteCount = CMBlockBufferGetDataLength(dataBuffer)
        guard byteCount > 0 else {
            return
        }

        var chunk = Data(count: byteCount)
        let status = chunk.withUnsafeMutableBytes { rawBuffer -> OSStatus in
            guard let baseAddress = rawBuffer.baseAddress else {
                return kCMBlockBufferBadCustomBlockSourceErr
            }
            return CMBlockBufferCopyDataBytes(
                dataBuffer,
                atOffset: 0,
                dataLength: byteCount,
                destination: baseAddress
            )
        }

        guard status == noErr else {
            if !hasLoggedBufferFailure {
                NSLog("[AudioCapture] Failed to copy audio bytes from sample buffer (OSStatus %d).", status)
                hasLoggedBufferFailure = true
            }
            return
        }

        onSample(chunk)
    }
}
