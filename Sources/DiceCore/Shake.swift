import CoreGraphics
import Foundation

/// Spots a quick side-to-side shake of the pointer during a drag.
public struct ShakeDetector {
    /// How far the pointer must come back from its furthest point before a change of direction counts. Jitter in a
    /// steady drag never travels that far back.
    public var reach: CGFloat = 30
    /// Changes of direction needed, all within `window` seconds: three is a right–left–right–left wiggle.
    public var turnsNeeded = 3
    public var window: TimeInterval = 0.7
    private var furthest: CGFloat?
    private var heading: CGFloat = 0
    private var turns: [TimeInterval] = []
    public init() {}
    public mutating func reset() { furthest = nil; heading = 0; turns = [] }
    /// Feeds one horizontal pointer position. True once the pointer has shaken; it then starts counting afresh.
    public mutating func shook(x: CGFloat, at time: TimeInterval) -> Bool {
        guard let far = furthest else { furthest = x; return false }
        if heading == 0 {
            if abs(x - far) >= reach { heading = x > far ? 1 : -1; furthest = x }
            return false
        }
        if (x - far) * heading > 0 { furthest = x }
        else if abs(x - far) >= reach { heading = -heading; furthest = x; turns.append(time) }
        turns.removeAll { time - $0 > window }
        guard turns.count >= turnsNeeded else { return false }
        reset(); return true
    }
}
