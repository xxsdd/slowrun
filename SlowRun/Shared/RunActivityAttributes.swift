import ActivityKit
import Foundation
import SwiftUI

struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var english: Bool? = nil
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
        var navTitle: String? = nil
        var navDetail: String? = nil
        var navSymbol: String? = nil
        var navRemaining: String? = nil
        var navRoute: [RunMiniPoint]? = nil
        var navPosition: RunMiniPoint? = nil
        var navTurn: RunMiniPoint? = nil
        var navTurnDistance: String? = nil
        var navTurnLabel: String? = nil
        var navDirectionKnown: Bool? = nil
    }
    var workoutID: String
    var title: String
}

struct RunMiniPoint: Codable, Hashable { var x: Double; var y: Double }

struct NavigationPositionArrow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.76))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

struct RunMiniRouteView: View {
    let points: [RunMiniPoint]
    let position: RunMiniPoint?
    var turn: RunMiniPoint? = nil
    var directionKnown = false
    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 8
            let width = max(1, geometry.size.width - inset * 2), height = max(1, geometry.size.height - inset * 2)
            ZStack {
                RunPalette.raised
                Path { path in
                    for (index, point) in points.enumerated() {
                        let value = CGPoint(x: inset + point.x * width, y: inset + point.y * height)
                        if index == 0 { path.move(to: value) } else { path.addLine(to: value) }
                    }
                }.stroke(RunPalette.mint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                if let turn { Circle().fill(RunPalette.mint).overlay(Circle().stroke(RunPalette.raised, lineWidth: 2)).frame(width: 11, height: 11).position(x: inset + turn.x * width, y: inset + turn.y * height) }
                if let position {
                    Group {
                        if directionKnown { NavigationPositionArrow().fill(Color.blue).overlay(NavigationPositionArrow().stroke(.white, lineWidth: 1.5)).frame(width: 14, height: 19) }
                        else { Circle().fill(Color.blue).overlay(Circle().stroke(.white, lineWidth: 1.5)).frame(width: 9, height: 9) }
                    }.position(x: inset + position.x * width, y: inset + position.y * height)
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 9))
    }
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
