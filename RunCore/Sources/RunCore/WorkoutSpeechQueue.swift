import Foundation

/// Pending speech only. Priority changes the next item, never the one playing.
public struct WorkoutSpeechQueue {
    public enum Item: Equatable {
        case workout(WorkoutEvent)
        case navigation(NavigationCue)

        public var text: String {
            switch self {
            case .workout(let event): event.localizedSpeech
            case .navigation(let cue): RunLanguage.text(cue.voice.speech)
            }
        }
    }

    private var pending: [Item] = []
    public init() {}
    public var isEmpty: Bool { pending.isEmpty }

    public mutating func enqueue(_ events: [WorkoutEvent], audiobookMode: Bool = false) {
        if events.contains(where: { !$0.isOptionalSpeech }) {
            discardOptionalSpeech()
        }
        if events.contains(where: \.isStageSpeech) || events.contains(.finished) {
            pending.removeAll {
                if case .workout(let event) = $0 { return event.isStageSpeech }
                return false
            }
        }
        // A delayed update can cross multiple phases. Announce only the latest.
        let latestStage = events.contains(.finished) ? nil : events.lastIndex(where: \.isStageSpeech)
        for (index, event) in events.enumerated() {
            guard !audiobookMode || event.isAudiobookCue else { continue }
            if !event.isStageSpeech || index == latestStage { pending.append(.workout(event)) }
        }
        if pending.count > 6 {
            discardOptionalSpeech()
            if pending.count > 6 {
                // Navigation sits first and should survive backlog trimming.
                let navigation = pending.first.flatMap { item -> Item? in
                    if case .navigation = item { return item }
                    return nil
                }
                let recent = pending.suffix(navigation == nil ? 6 : 5)
                pending = (navigation.map { [$0] } ?? []) + Array(recent)
            }
        }
    }

    public mutating func enqueueNavigation(_ cue: NavigationCue, audiobookMode: Bool = false) {
        cancelNavigation()
        guard !audiobookMode || cue.voice.isAudiobookCue else { return }
        discardOptionalSpeech()
        pending.insert(.navigation(cue), at: 0)
    }

    public mutating func cancelNavigation() {
        pending.removeAll { if case .navigation = $0 { return true }; return false }
    }

    public mutating func removeAll() { pending.removeAll() }

    public mutating func next(navigationIsValid: (NavigationCue) -> Bool) -> Item? {
        while !pending.isEmpty {
            let item = pending.removeFirst()
            if case .navigation(let cue) = item, !navigationIsValid(cue) { continue }
            return item
        }
        return nil
    }

    private mutating func discardOptionalSpeech() {
        pending.removeAll {
            if case .workout(let event) = $0 { return event.isOptionalSpeech }
            return false
        }
    }
}

extension WorkoutEvent {
    public var isAudiobookCue: Bool {
        switch self {
        case .freeRunStarted, .stage(.run), .stage(.walk), .stage(.cooldown): true
        case .stage(.warmup), .kilometer, .adjustment, .pace, .coaching, .distanceGoalReached, .finished: false
        }
    }
}

extension NavigationVoice {
    public var isAudiobookCue: Bool {
        switch self {
        case .advanceLeft, .advanceRight, .advanceUTurn, .advanceUnknown,
             .nearLeft, .nearRight, .nearUTurn, .nearUnknown, .arrived: true
        case .rerouting: false
        }
    }
}

private extension WorkoutEvent {
    var isStageSpeech: Bool {
        switch self { case .stage, .freeRunStarted: true; default: false }
    }

    var isOptionalSpeech: Bool {
        switch self { case .coaching, .pace, .adjustment: true; default: false }
    }
}
