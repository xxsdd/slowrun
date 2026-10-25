import Foundation

/// The finite set of Microsoft recordings shipped with the app. No network is
/// needed during a workout; variable numbers use the separate number pack.
public enum FixedVoiceCue: String, CaseIterable, Sendable {
    case warmup, run, walk, cooldown, tooFast, slowing, coaching, finished, freeRunStarted

    public var speech: String {
        switch self {
        case .freeRunStarted: return "现在开始自由跑。"
        case .warmup: return "现在步行热身五分钟。"
        case .run: return "现在开始跑步。"
        case .walk: return "现在可以慢下来走一会。"
        case .cooldown: return "现在步行放松五分钟。"
        case .tooFast: return "最近比你设定的目标配速快了一些。可以把节奏放稳，留点余力。"
        case .slowing: return "最近的节奏比前面慢了一些。留意自己的感受，累了可以继续放慢或步行恢复。"
        case .coaching: return CoachingTip.allCases.map(\.speech).joined(separator: " ")
        case .finished: return "本次训练已结束。"
        }
    }
}

extension WorkoutEvent {
    public var fixedVoiceCue: FixedVoiceCue? {
        switch self {
        case .stage(let kind):
            switch kind {
            case .warmup: return .warmup
            case .run: return .run
            case .walk: return .walk
            case .cooldown: return .cooldown
            }
        case .freeRunStarted: return .freeRunStarted
        case .coaching: return .coaching
        case .finished: return .finished
        case .adjustment(let text):
            return [FixedVoiceCue.tooFast, .slowing].first { $0.speech == text }
        case .kilometer, .pace: return nil
        }
    }
}
