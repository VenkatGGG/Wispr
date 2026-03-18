@preconcurrency import AVFoundation
import Foundation

struct RecordedCapture {
    let wavData: Data
    let durationMs: Int
}

final class AudioCaptureController {
    private let targetSampleRate: Double = 16_000
    private let targetChannels: AVAudioChannelCount = 1
    private let lock = NSLock()

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
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

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 14,
                userInfo: [NSLocalizedDescriptionKey: "No active microphone input device is available."]
            )
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 15,
                userInfo: [NSLocalizedDescriptionKey: "Failed to configure the recording format."]
            )
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 16,
                userInfo: [NSLocalizedDescriptionKey: "Failed to prepare the microphone audio converter."]
            )
        }

        converter.sampleRateConverterQuality = .max

        lock.withLock {
            pcmData.removeAll(keepingCapacity: true)
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            self?.appendPCM(from: buffer)
        }

        engine.prepare()
        try engine.start()

        self.engine = engine
        self.converter = converter
        self.outputFormat = outputFormat
        captureStartedAt = Date()
    }

    func cancelCapture() {
        stopEngine()
        lock.withLock {
            pcmData.removeAll(keepingCapacity: false)
        }
        captureStartedAt = nil
    }

    func finishCapture(minimumCaptureMs: Int) throws -> RecordedCapture? {
        guard engine != nil, let captureStartedAt else {
            return nil
        }

        stopEngine()

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

        guard !capturedPCM.isEmpty else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 13,
                userInfo: [NSLocalizedDescriptionKey: "No microphone audio was captured. Check the selected input device and microphone permission."]
            )
        }

        if averageSignalLevel(for: capturedPCM) < 0.003 {
            throw NSError(
                domain: "WisprMenuBar",
                code: 17,
                userInfo: [NSLocalizedDescriptionKey: "No speech was detected from the microphone. Check the active input device and input volume."]
            )
        }

        return RecordedCapture(wavData: makeWAV(from: capturedPCM), durationMs: durationMs)
    }

    private func stopEngine() {
        if let inputNode = engine?.inputNode {
            inputNode.removeTap(onBus: 0)
        }
        engine?.stop()
        engine?.reset()
        engine = nil
        converter = nil
        outputFormat = nil
    }

    private func appendPCM(from inputBuffer: AVAudioPCMBuffer) {
        guard let converter, let outputFormat else { return }

        let ratio = outputFormat.sampleRate / max(inputBuffer.format.sampleRate, 1)
        let estimatedFrames = max(1, Int(Double(inputBuffer.frameLength) * ratio) + 32)
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(estimatedFrames)
        ) else {
            return
        }

        let inputBox = InputBufferBox(buffer: inputBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            guard let buffer = inputBox.buffer else {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputBox.buffer = nil
            outStatus.pointee = .haveData
            return buffer
        }

        guard conversionError == nil else { return }
        guard status == .haveData || status == .inputRanDry || status == .endOfStream else { return }
        guard convertedBuffer.frameLength > 0 else { return }

        let audioBuffer = convertedBuffer.audioBufferList.pointee.mBuffers
        guard let bytes = audioBuffer.mData else { return }

        let byteCount = Int(audioBuffer.mDataByteSize)
        let chunk = Data(bytes: bytes, count: byteCount)
        lock.withLock {
            pcmData.append(chunk)
        }
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

private final class InputBufferBox: @unchecked Sendable {
    var buffer: AVAudioPCMBuffer?

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}
