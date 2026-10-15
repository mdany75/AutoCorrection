import AVFoundation
import Speech

/// Dictée vocale : reconnaissance Apple (en français, sur le Mac quand c'est possible), texte partiel en direct.
@MainActor
final class Dictation {
    /// Moteur neuf à chaque écoute : un moteur reste lié à l'entrée par défaut du moment de sa création,
    /// et ne capte plus rien quand elle change (écouteurs mis ou retirés).
    private var engine: AVAudioEngine?
    private var configObserver: NSObjectProtocol?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var text = ""
    private var running = false
    private var onLevel: (Float) -> Void = { _ in }
    private var onError: (String) -> Void = { _ in }
    /// Format du son envoyé à la requête depuis le début de l'écoute : après un changement de micro, le son y est converti.
    private var requestFormat: AVAudioFormat?
    /// Changements de micro pendant l'écoute ; au-delà de `maxRestarts`, l'écoute s'arrête sur une erreur.
    private var restarts = 0
    private static let maxRestarts = 5
    /// Essais pour brancher un moteur, espacés de `retryDelay`.
    private static let engineAttempts = 4
    private static let retryDelay = Duration.milliseconds(400)

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
               onError: @escaping (String) -> Void) async throws {
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "AutoCorrection", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "La reconnaissance vocale en français n'est pas disponible sur ce Mac."])
        }
        // Sans micro, toucher à `inputNode` ou poser un tap lève une exception Objective-C (format à 0 Hz) qui tue l'app.
        guard AVCaptureDevice.default(for: .audio) != nil else { throw Dictation.noMicrophone }
        cancel()
        text = ""
        self.onLevel = onLevel
        self.onError = onError
        restarts = 0

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        do { try await startEngineRetrying(feeding: req) } catch { request = nil; requestFormat = nil; throw error }
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
        let req = request
        request = nil // une reprise de micro encore en attente n'a plus rien à alimenter
        req?.endAudio()
        try? await Task.sleep(for: .milliseconds(800))
        withExtendedLifetime(req) {} // la requête vit jusqu'aux derniers mots reconnus
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
        requestFormat = nil
    }

    /// Branche un moteur neuf sur l'entrée par défaut du moment et envoie son son à la requête.
    private func startEngine(feeding req: SFSpeechAudioBufferRecognitionRequest) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw Dictation.noMicrophone }
        let target = requestFormat ?? format
        let converter: AVAudioConverter?
        if format == target {
            converter = nil
        } else {
            guard let c = AVAudioConverter(from: format, to: target) else { throw Dictation.lostMicrophone }
            converter = c
        }

        let onLevel = self.onLevel
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            if let converter {
                if let converted = Dictation.convert(buffer, with: converter) { req.append(converted) }
            } else {
                req.append(buffer)
            }
            var level: Float = 0
            if let data = buffer.floatChannelData?[0] {
                let n = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<n { sum += data[i] * data[i] }
                level = n > 0 ? min(1, (sum / Float(n)).squareRoot() * 8) : 0
            }
            DispatchQueue.main.async { onLevel(level) }
        }
        self.engine = engine
        // Le moteur s'arrête de lui-même quand l'entrée ou la sortie change : on le remplace.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self, weak engine] _ in
            MainActor.assumeIsolated {
                // Un avis déjà en file d'un moteur remplacé ne compte pas.
                guard let self, let engine, self.engine === engine else { return }
                self.inputChanged()
            }
        }
        engine.prepare()
        do { try engine.start() } catch { stopEngine(); throw error }
        requestFormat = target
    }

    /// Branche un moteur neuf, en réessayant un instant : juste après un branchement ou un retrait d'écouteurs,
    /// macOS peut encore désigner l'ancien micro (erreur CoreAudio 560227702, « !dev »).
    private func startEngineRetrying(feeding req: SFSpeechAudioBufferRecognitionRequest) async throws {
        var attempt = 1
        while true {
            guard request === req else { throw CancellationError() }
            do {
                try startEngine(feeding: req)
                return
            } catch {
                guard attempt < Dictation.engineAttempts else { throw Dictation.readable(error) }
                attempt += 1
                try? await Task.sleep(for: Dictation.retryDelay)
            }
        }
    }

    /// Micro changé pendant l'écoute : un moteur neuf reprend sur la nouvelle entrée, la requête continue
    /// et garde les mots déjà reconnus.
    private func inputChanged() {
        guard running, let req = request else { return }
        stopEngine()
        restarts += 1
        guard restarts <= Dictation.maxRestarts else { onError(Dictation.lostMicrophone.localizedDescription); return }
        Task { @MainActor [weak self] in
            // Laisse à macOS le temps de désigner le nouveau micro.
            try? await Task.sleep(for: Dictation.retryDelay)
            guard let self, self.running, self.request === req else { return }
            do {
                guard AVCaptureDevice.default(for: .audio) != nil else { throw Dictation.noMicrophone }
                try await self.startEngineRetrying(feeding: req)
            } catch {
                guard self.running, self.request === req else { return }
                self.onError(error.localizedDescription)
            }
        }
    }

    private func stopEngine() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        guard let engine else { return }
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
    }

    /// Convertit un tampon du nouveau micro au format du début de l'écoute (appelé sur le fil audio).
    /// Le convertisseur garde son état d'un tampon à l'autre : le son reste continu.
    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error || out.frameLength == 0 ? nil : out
    }

    private static let noMicrophone = NSError(domain: "AutoCorrection", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "Aucun microphone n'est disponible. Branchez-en un (ou choisissez une entrée dans Réglages Système > Son), puis réessayez."])

    /// Erreur brute de CoreAudio : message lisible, le code gardé pour le diagnostic.
    private static func readable(_ error: Error) -> Error {
        let e = error as NSError
        guard e.domain != "AutoCorrection" else { return error }
        return NSError(domain: "AutoCorrection", code: 4, userInfo: [NSLocalizedDescriptionKey:
            "Le microphone ne répond pas (écouteurs branchés ou retirés à l'instant ?). Réessayez dans un moment. (Erreur \(e.code))"])
    }

    private static let lostMicrophone = NSError(domain: "AutoCorrection", code: 3, userInfo: [
        NSLocalizedDescriptionKey: "Le microphone a changé pendant la dictée et n'a pas pu être repris. Relancez la dictée."])
}
