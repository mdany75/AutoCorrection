import AVFoundation
import Speech

/// Dictée vocale : reconnaissance Apple (en français, sur le Mac quand c'est possible), texte partiel en direct.
@MainActor
final class Dictation {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var text = ""
    private var running = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-CA"))
        ?? SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))

    /// Demande les deux autorisations (reconnaissance vocale, microphone). Renvoie un message d'erreur, ou nil si tout est accordé.
    static func authorize() async -> String? {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else {
            return "La reconnaissance vocale n'est pas autorisée. Accordez-la à AutoCorrection dans Réglages Système > Confidentialité et sécurité."
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            return "Le microphone n'est pas autorisé. Accordez-le à AutoCorrection dans Réglages Système > Confidentialité et sécurité."
        }
        return nil
    }

    func start(onText: @escaping (String) -> Void, onLevel: @escaping (Float) -> Void,
               onError: @escaping (String) -> Void) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "AutoCorrection", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "La reconnaissance vocale en français n'est pas disponible sur ce Mac."])
        }
        cancel()
        text = ""

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
            var level: Float = 0
            if let data = buffer.floatChannelData?[0] {
                let n = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<n { sum += data[i] * data[i] }
                level = n > 0 ? min(1, (sum / Float(n)).squareRoot() * 8) : 0
            }
            DispatchQueue.main.async { onLevel(level) }
        }
        engine.prepare()
        try engine.start()
        running = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.running else { return }
                if let result {
                    self.text = result.bestTranscription.formattedString
                    onText(self.text)
                }
                if let error, (error as NSError).code != 1110, (error as NSError).code != 216 {
                    onError(error.localizedDescription)
                }
            }
        }
    }

    /// Arrête l'écoute, laisse arriver les derniers mots reconnus et renvoie le texte.
    func finish() async -> String {
        stopEngine()
        request?.endAudio()
        try? await Task.sleep(for: .milliseconds(800))
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cancel()
        return result
    }

    func cancel() {
        running = false
        stopEngine()
        task?.cancel()
        task = nil
        request = nil
    }

    private func stopEngine() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }
}
