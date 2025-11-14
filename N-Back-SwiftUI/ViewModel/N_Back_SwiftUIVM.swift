import Foundation
import AVFoundation
import Combine

// C-bryggans typer/funktioner finns via bridging headern:
// Nback*, create(...), getIndexOf(...)

final class N_Back_SwiftUIVM: ObservableObject {

    // MARK: - UI-bindningar
    @Published var highScore: Int = UserDefaults.standard.integer(forKey: "highScore")
    @Published var settings = NBackSettings()       // använder dina nya typer
    @Published var isPlaying = false
    @Published var currentIndex = -1                // 0..roundLength-1
    @Published var currentValue = 0                 // 1..9 (grid) / A..I (audio)
    @Published var correctCount = 0
    @Published var showErrorFlash = false
    @Published var hasMatchNow = false              // sant om aktuellt event är en n-back-match
    @Published var roundFinished = false
    @Published var lastScore = 0

    // MARK: - Privat
    private let tStep: TimeInterval = 1.8
    private let synthesizer = AVSpeechSynthesizer()
    private var timer: AnyCancellable?
    private var nbackHandle: Nback?
    private var values: [Int] = []                  // cache av sekvens från C
    

    // MARK: - Publika åtgärder
    func start(mode: GameMode) {
        roundFinished = false
        settings.mode = mode
        prepareSequence()
        correctCount = 0
        currentIndex = -1
        isPlaying = true
        

        // visa första direkt och starta sedan timer
        tick()
        timer?.cancel()
        timer = Timer.publish(every: tStep, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isPlaying = false
        lastScore = correctCount
        updateHighScoreIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.roundFinished = true
        }
    }

    /// Användaren trycker "Match!"
    func matchTapped() {
        guard isPlaying, currentIndex >= 0 else { return }
        let n = settings.n
        let isMatch = currentIndex - n >= 0 && values[currentIndex] == values[currentIndex - n]
        hasMatchNow = isMatch
        if isMatch {
            correctCount += 1
        } else {
            softErrorFlash()
        }
    }

    // MARK: - Intern logik
    private func prepareSequence() {
        // C: create(size, combinations, match%, n)
        nbackHandle = create(Int32(settings.roundLength),
                             Int32(settings.combinations),
                             Int32(settings.matchPercent),
                             Int32(settings.n))
        values = (0..<settings.roundLength).map { i in
            Int(getIndexOf(nbackHandle, Int32(i)))
        }
    }

    private func tick() {
        // Räkna ut nästa index först
        let next = currentIndex + 1

        // Om nästa skulle bli utanför – stoppa direkt och ändra inte currentIndex
        if next >= settings.roundLength {
            stop()
            return
        }

        // Annars uppdatera currentIndex och visa värdet
        currentIndex = next
        currentValue = values[currentIndex]

        let n = settings.n
        hasMatchNow = currentIndex - n >= 0 && values[currentIndex] == values[currentIndex - n]

        if settings.mode == .audio {
            speakLetter(for: currentValue)
        }
    }


    private func speakLetter(for v: Int) {
        let letters = ["A","B","C","D","E","F","G","H","I"]
        let idx = max(1, min(v, letters.count)) - 1
        let utt = AVSpeechUtterance(string: letters[idx])
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utt)
    }

    private func softErrorFlash() {
        showErrorFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.showErrorFlash = false
        }
    }

    private func updateHighScoreIfNeeded() {
        if correctCount > highScore {
            highScore = correctCount
            UserDefaults.standard.set(correctCount, forKey: "highScore")
        }
    }
}
