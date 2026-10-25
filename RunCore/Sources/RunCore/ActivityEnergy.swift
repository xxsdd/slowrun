import Foundation

/// Broad adult, level-ground estimate from the 2024 Adult Compendium.
/// https://pacompendium.com/walking/ and https://pacompendium.com/running/
/// Speed bands use nearest table entries; they are NOT gait detection.
/// Grade, age, individual resting metabolism and load are not measured.
public enum ActivityEnergy {
    public static func met(kind: StageKind, pace: Double?) -> Double {
        guard let pace, pace.isFinite, pace > 0 else { return kind == .run ? 7.5 : 3.0 }
        let mph = 3600 / pace / 1.609344
        let table: [(Double, Double)]
        if kind == .run && mph >= 3.8 {
            table = [(4.1,6.5),(4.55,7.8),(5.1,8.5),(5.65,9.0),(6.15,9.3),(6.7,10.5),(7,11),(7.5,11.8),(8,12),(8.6,12.5),(9,13),(9.6,14.8),(11,16.8),(12,18.5)]
        } else {
            table = [(1.5,2.3),(2.2,2.8),(2.5,3),(3.1,3.8),(3.7,4.8),(4.2,5.5),(4.7,7),(5.25,8.5)]
        }
        return table.min(by: { abs($0.0 - mph) < abs($1.0 - mph) })!.1
    }
}
