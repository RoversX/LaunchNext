import AVFoundation
import Foundation

@MainActor
final class VoiceManager: NSObject {
    static let shared = VoiceManager()

    private let synthesizer = AVSpeechSynthesizer()
    private weak var appStore: AppStore?
    private var pendingAnnouncement: DispatchWorkItem?
    private var isSynthesizerSpeaking = false
    private var activePhrase: String?
    private var queuedPhrase: String?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func bind(appStore: AppStore) {
        self.appStore = appStore
    }

    func announceSelection(item: LaunchpadItem?) {
        guard let store = appStore, store.voiceFeedbackEnabled else { return }

        pendingAnnouncement?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.speak(for: item)
        }
        pendingAnnouncement = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func stop() {
        pendingAnnouncement?.cancel()
        pendingAnnouncement = nil
        activePhrase = nil
        queuedPhrase = nil
        if isSynthesizerSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func speak(for item: LaunchpadItem?) {
        guard let store = appStore, store.voiceFeedbackEnabled else { return }

        let phrase: String?
        switch item {
        case .app(let app):
            phrase = String(format: store.localized(.voiceAnnouncementAppFormat), app.name)
        case .folder(let folder):
            phrase = String(format: store.localized(.voiceAnnouncementFolderFormat), folder.name)
        default:
            phrase = nil
        }

        guard let phrase, !phrase.isEmpty else { return }
        guard phrase != activePhrase else { return }

        if isSynthesizerSpeaking {
            queuedPhrase = phrase
            return
        }
        speak(phrase: phrase)
    }

    private func speak(phrase: String) {
        activePhrase = phrase
        queuedPhrase = nil
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = preferredVoice()
        synthesizer.speak(utterance)
    }

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        if let localizedVoice = AVSpeechSynthesisVoice(language: Locale.current.identifier) {
            return localizedVoice
        }
        if let languageCode = Locale.current.language.languageCode?.identifier,
           let fallbackVoice = AVSpeechSynthesisVoice(language: languageCode) {
            return fallbackVoice
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    private func handleSpeechDidStart(_ phrase: String) {
        isSynthesizerSpeaking = true
        activePhrase = phrase
    }

    private func handleSpeechDidFinish(_ phrase: String) {
        isSynthesizerSpeaking = false
        if activePhrase == phrase {
            activePhrase = nil
        }
        speakQueuedPhraseIfNeeded()
    }

    private func speakQueuedPhraseIfNeeded() {
        guard let store = appStore, store.voiceFeedbackEnabled else {
            queuedPhrase = nil
            return
        }
        guard let queuedPhrase, queuedPhrase != activePhrase else { return }
        speak(phrase: queuedPhrase)
    }
}

extension VoiceManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let phrase = utterance.speechString
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.handleSpeechDidStart(phrase)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let phrase = utterance.speechString
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.handleSpeechDidFinish(phrase)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let phrase = utterance.speechString
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.handleSpeechDidFinish(phrase)
            }
        }
    }
}
