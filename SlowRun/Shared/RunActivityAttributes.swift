import ActivityKit
import Foundation
import SwiftUI

struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distance: String
        var pace: String
        var elapsed: String
        var timerStart: Date
        var timerRunning: Bool
        var stage: String
        var paused: Bool
        var includesWalking: Bool
        var stageEndsAt: Date? = nil
        var stageRemainingSeconds: Double? = nil
        var remainingDistance: String? = nil
        var mainDistance: String? = nil
        var phaseLabel: String? = nil
        var stageSymbol: String? = nil
    }
    var workoutID: String
    var title: String
}

enum RunPalette {
    static let background = Color(red: 12/255, green: 17/255, blue: 16/255)
    static let surface = Color(red: 25/255, green: 30/255, blue: 32/255)
    static let raised = Color(red: 35/255, green: 42/255, blue: 45/255)
    static let line = Color(red: 52/255, green: 62/255, blue: 66/255)
    static let text = Color(red: 244/255, green: 246/255, blue: 247/255)
    static let secondary = Color(red: 171/255, green: 180/255, blue: 185/255)
    static let mint = Color(red: 168/255, green: 239/255, blue: 170/255)
    static let onMint = Color(red: 16/255, green: 36/255, blue: 22/255)
}
