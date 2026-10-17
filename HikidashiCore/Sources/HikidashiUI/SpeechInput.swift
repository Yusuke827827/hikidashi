// 音声入力。マイクボタンを押している間、話した内容を文字にして入力欄に入れる。
// 端末上の音声認識（Speech）を使う。初回はマイクと音声認識の許可を求める。

#if os(iOS)
import AVFoundation
import Foundation
import HikidashiKit
import Observation
import Speech

@Observable
@MainActor
final class SpeechInput {
    private(set) var isRecording = false
    var error: String?

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    nonisolated init() {}

    /// base: 今入力欄にある文。話した内容はその後ろに足す
    func toggle(base: String, update: @escaping (String) -> Void) {
        if isRecording {
            stop()
        } else {
            Task { await start(base: base, update: update) }
        }
    }

    private func start(base: String, update: @escaping (String) -> Void) async {
        error = nil
        let speechOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else {
            error = L("マイクと音声認識を「設定」アプリで許可してください。", "Allow the microphone and speech recognition in the Settings app.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: AppLanguage.current.locale), recognizer.isAvailable else {
            error = L("今は音声認識を使えません。", "Speech recognition isn't available right now.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            Self.installTap(engine.inputNode, request: request)
            engine.prepare()
            try engine.start()
            self.engine = engine
            self.request = request
            isRecording = true
            let prefix = base.isEmpty ? "" : (base.hasSuffix("\n") ? base : base + "\n")
            task = Self.recognize(recognizer, request: request) { [weak self] text, done in
                Task { @MainActor in
                    if let text { update(prefix + text) }
                    if done { self?.stop() }
                }
            }
        } catch {
            self.error = L("録音を始められませんでした。", "Couldn't start recording.")
            stop()
        }
    }

    func stop() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        engine = nil
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // 録音と認識の呼び返しは別のスレッドで来るため、画面側の状態に触れない関数で受ける
    nonisolated private static func installTap(_ input: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest) {
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognize(_ recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest,
                                              handler: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, error != nil || (result?.isFinal ?? false))
        }
    }
}
#endif
