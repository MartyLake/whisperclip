import Foundation
import AVFoundation
import ScreenCaptureKit
import Accelerate

/// Audio source identifier for speaker detection
enum AudioSource {
    case microphone  // User's voice -> Speaker.me
    case system      // Other participants -> Speaker.other
    
    var speaker: Speaker {
        switch self {
        case .microphone: return .me
        case .system: return .other
        }
    }
}

/// Callback for audio chunks with source identification
typealias AudioChunkCallback = (AudioSource, [Float], TimeInterval) -> Void

/// Captures audio from both microphone and system audio separately
/// Uses AVAudioEngine for microphone and ScreenCaptureKit for system audio
@MainActor
class DualChannelAudioCapture: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var isCapturing = false
    @Published private(set) var micLevel: Float = -160
    @Published private(set) var systemLevel: Float = -160
    @Published private(set) var hasScreenCapturePermission = false
    @Published private(set) var lastError: String?
    
    // MARK: - Audio Engine (Microphone)
    
    private var audioEngine: AVAudioEngine?
    private var activeMicrophoneRoute: MicrophoneRoute?
    private var engineConfigurationObserver: NSObjectProtocol?
    private var defaultInputMonitor: DefaultInputDevice.Monitor?
    private let microphoneHeartbeat = CaptureHeartbeat()
    
    // MARK: - Screen Capture (System Audio)
    
    private var scStream: SCStream?
    
    // MARK: - Device Change Recovery
    
    /// True from the end of `startCapture` until `stopCapture` begins.
    private var recoveryEnabled = false
    private var microphoneRestartTask: Task<Void, Never>?
    private var microphoneWatchdogTask: Task<Void, Never>?
    private var systemAudioRestartTask: Task<Void, Never>?
    
    // MARK: - Thread-safe buffers (using actor for synchronization)
    
    private let audioBuffers = AudioBufferActor()
    
    // MARK: - Configuration
    
    let sampleRate: Int = 16000
    
    // MARK: - State
    
    /// Set once before capture starts, read from nonisolated audio callbacks
    nonisolated(unsafe) private var startTime: Date?
    private var levelTimer: Timer?
    private var audioCallback: AudioChunkCallback?
    nonisolated(unsafe) private var onSystemBatch: (@Sendable ([Float], TimeInterval) -> Void)?
    nonisolated(unsafe) private var onMicrophoneLevel: (@Sendable (Float) -> Void)?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    // MARK: - Permission Check
    
    /// Check if screen capture permission is available (required for system audio)
    func checkPermissions() async -> Bool {
        do {
            // This will prompt for permission if not already granted
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            hasScreenCapturePermission = !content.displays.isEmpty
            return hasScreenCapturePermission
        } catch {
            Logger.log("Screen capture permission check failed: \(error)", log: Logger.general, type: .error)
            hasScreenCapturePermission = false
            return false
        }
    }
    
    // MARK: - Capture Control
    
    /// Start capturing from both microphone and system audio
    func startCapture(
        onAudioChunk: @escaping AudioChunkCallback,
        onSystemBatch: @escaping @Sendable ([Float], TimeInterval) -> Void,
        onMicrophoneLevel: (@Sendable (Float) -> Void)? = nil
    ) async throws {
        guard !isCapturing else {
            throw DualChannelError.alreadyCapturing
        }
        
        audioCallback = onAudioChunk
        self.onSystemBatch = onSystemBatch
        self.onMicrophoneLevel = onMicrophoneLevel
        startTime = Date()
        
        // Start microphone capture
        try startMicrophoneCapture()
        
        // Start system audio capture (if permission granted)
        if await checkPermissions() {
            do {
                try await startSystemAudioCapture()
            } catch {
                teardownMicrophoneEngine()
                throw error
            }
        } else {
            Logger.log("System audio capture not available - only microphone will be used", log: Logger.general)
            lastError = "System audio permission not granted. Only your voice will be captured."
        }
        
        // Start level monitoring
        startLevelMonitoring()
        
        isCapturing = true
        startMicrophoneRecovery()
        Logger.log("Dual channel audio capture started", log: Logger.general)
    }
    
    /// Stop all audio capture and return any remaining buffered audio.
    /// Callers should process the returned samples before tearing down the
    /// transcription pipeline.
    @discardableResult
    func stopCapture() async -> (samples: [Float], startTime: TimeInterval) {
        guard isCapturing else {
            return ([], 0)
        }
        
        // Stop timers
        levelTimer?.invalidate()
        levelTimer = nil
        
        // Stop recovery first so nothing restarts an input while it is being torn down
        stopRecovery()
        if let restart = systemAudioRestartTask {
            await restart.value
        }
        
        // Stop audio inputs first so no new samples arrive
        teardownMicrophoneEngine()
        
        if let stream = scStream {
            try? await stream.stopCapture()
            scStream = nil
        }
        
        // Drain remaining microphone audio from buffers (awaited, not fire-and-forget)
        let micResult = await audioBuffers.getMicSamples()

        isCapturing = false
        audioCallback = nil
        onSystemBatch = nil
        onMicrophoneLevel = nil
        
        Logger.log("Dual channel audio capture stopped", log: Logger.general)
        
        return micResult
    }
    
    // MARK: - Microphone Capture
    
    private func startMicrophoneCapture() throws {
        audioEngine = AVAudioEngine()
        
        guard let engine = audioEngine else {
            throw DualChannelError.microphoneSetupFailed
        }
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let route = MicrophoneRoute.current(format: inputFormat)
        
        guard route.isUsable else {
            Logger.log("Microphone format not ready: \(route)", log: Logger.audio, type: .error)
            throw DualChannelError.microphoneSetupFailed
        }
        
        // Create converter to 16kHz mono
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )!
        
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw DualChannelError.microphoneSetupFailed
        }
        
        // Install tap on microphone input
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processMicrophoneBuffer(buffer, converter: converter, outputFormat: outputFormat)
        }
        
        engine.prepare()
        try engine.start()
        
        observeConfigurationChanges(of: engine)
        activeMicrophoneRoute = route
        microphoneHeartbeat.beat()
        
        Logger.log("Microphone capture started on \(route)", log: Logger.audio)
    }
    
    private func teardownMicrophoneEngine() {
        if let observer = engineConfigurationObserver {
            NotificationCenter.default.removeObserver(observer)
            engineConfigurationObserver = nil
        }
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        activeMicrophoneRoute = nil
    }
    
    // MARK: - Microphone Recovery
    
    private func startMicrophoneRecovery() {
        recoveryEnabled = true
        defaultInputMonitor = DefaultInputDevice.Monitor { [weak self] in
            Task { @MainActor in
                self?.microphoneRouteMayHaveChanged(reason: "default input changed")
            }
        }
        microphoneWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.checkMicrophoneHeartbeat()
            }
        }
    }
    
    private func stopRecovery() {
        recoveryEnabled = false
        defaultInputMonitor = nil
        microphoneWatchdogTask?.cancel()
        microphoneWatchdogTask = nil
        microphoneRestartTask?.cancel()
        microphoneRestartTask = nil
        systemAudioRestartTask?.cancel()
    }
    
    private func observeConfigurationChanges(of engine: AVAudioEngine) {
        engineConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.microphoneRouteMayHaveChanged(reason: "engine configuration changed")
            }
        }
    }
    
    private func microphoneRouteMayHaveChanged(reason: String) {
        guard recoveryEnabled, let engine = audioEngine else { return }
        
        let current = MicrophoneRoute.current(format: engine.inputNode.outputFormat(forBus: 0))
        let active = activeMicrophoneRoute.map(String.init(describing:)) ?? "none"
        Logger.log("Microphone event: \(reason); running=\(engine.isRunning), active=\(active), current=\(current)",
                   log: Logger.audio)
        
        guard MicrophoneRecovery.shouldRestart(
            active: activeMicrophoneRoute,
            current: current,
            isEngineRunning: engine.isRunning
        ) else { return }
        
        scheduleMicrophoneRestart(reason: reason)
    }
    
    private func checkMicrophoneHeartbeat() {
        guard recoveryEnabled, microphoneRestartTask == nil else { return }
        let silence = microphoneHeartbeat.secondsSinceLastBeat()
        guard MicrophoneRecovery.isStalled(secondsSinceLastBuffer: silence) else { return }
        scheduleMicrophoneRestart(reason: String(format: "no buffers for %.1fs", silence))
    }
    
    /// Rebuilds the engine, retrying while the new device settles. A new engine is required
    /// because the old one keeps its device and format. A later event replaces a pending
    /// restart, which collapses bursts into one rebuild.
    private func scheduleMicrophoneRestart(reason: String) {
        guard recoveryEnabled else { return }
        
        microphoneRestartTask?.cancel()
        microphoneRestartTask = Task { [weak self] in
            for delay in MicrophoneRecovery.restartDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                if self.restartMicrophone(reason: reason) { break }
            }
            guard !Task.isCancelled else { return }
            self?.microphoneRestartTask = nil
        }
    }
    
    private func restartMicrophone(reason: String) -> Bool {
        let gap = microphoneHeartbeat.secondsSinceLastBeat()
        teardownMicrophoneEngine()
        do {
            try startMicrophoneCapture()
            Logger.log(String(format: "Microphone restarted after %.1fs gap (%@)", gap, reason), log: Logger.audio)
            return true
        } catch {
            teardownMicrophoneEngine()
            Logger.log("Microphone restart failed (\(reason)): \(error)", log: Logger.audio, type: .error)
            return false
        }
    }
    
    private func processMicrophoneBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFormat: AVAudioFormat) {
        // Convert to 16kHz mono
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * Double(sampleRate) / buffer.format.sampleRate)
        
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return
        }
        
        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        guard error == nil,
              let channelData = convertedBuffer.floatChannelData,
              convertedBuffer.frameLength > 0 else {
            return
        }
        
        // Copy samples to buffer
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(convertedBuffer.frameLength)))
        
        // Update level from recent samples
        if samples.count > 0 {
            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
            let db = 20 * log10(max(rms, 0.0001))
            Task { @MainActor in
                self.micLevel = db
            }
            if let levelCallback = self.onMicrophoneLevel {
                levelCallback(db)
            }
        }
        
        microphoneHeartbeat.beat()
        
        // Add to buffer using actor with elapsed time
        let elapsed = self.startTime.map { Date().timeIntervalSince($0) } ?? 0
        dispatchMicrophoneSamples(samples, elapsed: elapsed)
    }
    
    // MARK: - System Audio Capture
    
    private func startSystemAudioCapture() async throws {
        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        
        guard let display = content.displays.first else {
            throw DualChannelError.noDisplayFound
        }
        
        // Configure to capture only audio (no video)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true  // Don't capture our own app's audio
        config.sampleRate = sampleRate
        config.channelCount = 1
        
        // Minimize video capture (we only want audio)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 FPS minimum
        
        // Create and start stream
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.whisperclip.systemAudio"))
        
        try await stream.startCapture()
        scStream = stream
        
        Logger.log("System audio capture started", log: Logger.general)
    }
    
    /// Processes raw system audio buffer data and invokes onSystemBatch.
    /// Extracted for testability - SCStreamOutput handler calls this after format validation.
    nonisolated internal func processSystemAudioSamples(
        data: UnsafeRawPointer,
        byteCount: Int,
        onSystemBatch: ([Float], TimeInterval) -> Void,
        elapsed: TimeInterval
    ) {
        let count = byteCount / MemoryLayout<Float>.size
        guard count > 0 else { return }
        let samples = Array(
            UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: Float.self),
                count: count
            )
        )
        onSystemBatch(samples, elapsed)
    }

    /// Routes converted microphone samples to the live callback immediately.
    /// Falls back to buffering only when the live callback is unavailable.
    internal func dispatchMicrophoneSamples(
        _ samples: [Float],
        elapsed: TimeInterval,
        callbackOverride: AudioChunkCallback? = nil
    ) {
        guard !samples.isEmpty else { return }

        if let callback = callbackOverride ?? audioCallback {
            callback(.microphone, samples, elapsed)
            return
        }

        Task {
            await self.audioBuffers.appendMicSamples(samples, atTime: elapsed)
        }
    }
    
    // MARK: - Level Monitoring
    
    private func startLevelMonitoring() {
        // Levels are updated in the buffer processing callbacks
        // Timer not needed since we update on each buffer callback
        levelTimer = nil
    }
    
    // MARK: - Utility
    
    var elapsedTime: TimeInterval {
        startTime.map { Date().timeIntervalSince($0) } ?? 0
    }
    
    var formattedElapsedTime: String {
        let totalSeconds = Int(elapsedTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - SCStreamDelegate

extension DualChannelAudioCapture: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let stoppedStream = ObjectIdentifier(stream)
        Task { @MainActor in
            Logger.log("System audio stream stopped with error: \(error)", log: Logger.general, type: .error)
            self.lastError = error.localizedDescription
            self.scheduleSystemAudioRestart(after: stoppedStream)
        }
    }
}

// MARK: - System Audio Recovery

extension DualChannelAudioCapture {
    private func scheduleSystemAudioRestart(after stoppedStream: ObjectIdentifier) {
        guard recoveryEnabled, let scStream, ObjectIdentifier(scStream) == stoppedStream else { return }
        self.scStream = nil
        
        systemAudioRestartTask = Task { [weak self] in
            for delay in MicrophoneRecovery.restartDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                do {
                    try await self.startSystemAudioCapture()
                    self.lastError = nil
                    Logger.log("System audio restarted", log: Logger.audio)
                    return
                } catch {
                    Logger.log("System audio restart failed: \(error)", log: Logger.audio, type: .error)
                }
            }
            self?.lastError = "System audio stopped and could not be restarted."
        }
    }
}

// MARK: - SCStreamOutput

extension DualChannelAudioCapture: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            Logger.log("System audio: missing format description - discarding buffer", log: Logger.general, type: .error)
            return
        }

        guard asbd.mFormatID == kAudioFormatLinearPCM,
              asbd.mFormatFlags & kLinearPCMFormatFlagIsFloat != 0,
              asbd.mBitsPerChannel == 32 else {
            Logger.log(
                "System audio: unexpected format (id=\(asbd.mFormatID), flags=\(asbd.mFormatFlags), bits=\(asbd.mBitsPerChannel)) - discarding buffer",
                log: Logger.general,
                type: .error
            )
            return
        }

        _ = try? sampleBuffer.withAudioBufferList { audioBufferList, _ -> Void in
            for buffer in audioBufferList {
                guard let mData = buffer.mData else { continue }
                let byteCount = Int(buffer.mDataByteSize)
                guard byteCount > 0 else { continue }

                let count = byteCount / MemoryLayout<Float>.size
                let samples = Array(
                    UnsafeBufferPointer(
                        start: mData.assumingMemoryBound(to: Float.self),
                        count: count
                    )
                )
                guard !samples.isEmpty else { continue }

                var rms: Float = 0
                vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
                let db = 20 * log10(max(rms, 0.0001))
                Task { @MainActor [weak self] in
                    self?.systemLevel = db
                }

                let elapsed = self.startTime.map { Date().timeIntervalSince($0) } ?? 0
                if let onSystemBatch = self.onSystemBatch {
                    self.processSystemAudioSamples(
                        data: UnsafeRawPointer(mData),
                        byteCount: byteCount,
                        onSystemBatch: onSystemBatch,
                        elapsed: elapsed
                    )
                }
            }
        }
    }
}

// MARK: - Errors

// MARK: - Thread-safe Audio Buffer Actor

private actor AudioBufferActor {
    var micBuffer: [Float] = []
    var micBufferStartTime: TimeInterval?
    
    func appendMicSamples(_ samples: [Float], atTime time: TimeInterval) {
        if micBuffer.isEmpty {
            micBufferStartTime = time
        }
        micBuffer.append(contentsOf: samples)
    }
    
    func getMicSamples() -> (samples: [Float], startTime: TimeInterval) {
        let samples = micBuffer
        let startTime = micBufferStartTime ?? 0
        micBuffer = []
        micBufferStartTime = nil
        return (samples, startTime)
    }

    func clearAll() {
        micBuffer = []
        micBufferStartTime = nil
    }
}

enum DualChannelError: LocalizedError {
    case alreadyCapturing
    case microphoneSetupFailed
    case systemAudioSetupFailed
    case noDisplayFound
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .alreadyCapturing:
            return "Audio capture is already in progress"
        case .microphoneSetupFailed:
            return "Failed to setup microphone capture"
        case .systemAudioSetupFailed:
            return "Failed to setup system audio capture"
        case .noDisplayFound:
            return "No display found for screen capture"
        case .permissionDenied:
            return "Screen recording permission denied. Grant permission in System Settings > Privacy & Security > Screen Recording"
        }
    }
}
