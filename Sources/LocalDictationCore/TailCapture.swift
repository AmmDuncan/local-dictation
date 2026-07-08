import Foundation

/// Policy AND mechanism for how long to keep the mic tap alive after a stop
/// request.
///
/// The tap must stay up long enough for the final word's buffers to land
/// (releasing mid-syllable), but a fixed wait taxes every dictation with the
/// worst case. This trims the wait when the trailing audio is already silent:
/// most users pause before releasing, so their level sits at ambient the whole
/// time. Loud tails still get the full cap — the clip-protection worst case is
/// exactly the old fixed wait.
public enum TailCapture {
    /// Never stop before this: the release-mid-word buffer needs at least one
    /// tap callback (~90ms) to land.
    public static let minimumMillis = 100
    /// The old fixed wait; the worst case is unchanged.
    public static let capMillis = 400
    public static let pollMillis = 50
    /// Levels at or below this are ambient noise, not speech (speech ~0.5,
    /// room ambient ~0.2 — kept just below the recorder's speech-activity
    /// threshold, AudioFileRecorder.speechLevelThreshold).
    public static let silenceLevel = 0.25
    /// Consecutive sub-ambient polls required before an early stop.
    public static let quietPollsRequired = 2

    /// Waits out the trailing capture: polls `currentLevel` every `pollMillis`
    /// and returns once `shouldStop` says the tail is safe to cut.
    public static func wait(currentLevel: @Sendable () -> Double) async {
        var elapsed = 0
        var recentLevels: [Double] = []
        while !shouldStop(elapsedMillis: elapsed, recentLevels: recentLevels) {
            try? await Task.sleep(for: .milliseconds(pollMillis))
            elapsed += pollMillis
            recentLevels.append(currentLevel())
            if recentLevels.count > quietPollsRequired {
                recentLevels.removeFirst()
            }
        }
    }

    /// Decides whether trailing capture can end now. `recentLevels` are the
    /// most recent level samples, oldest first.
    public static func shouldStop(elapsedMillis: Int, recentLevels: [Double]) -> Bool {
        if elapsedMillis >= capMillis {
            return true
        }
        guard elapsedMillis >= minimumMillis, recentLevels.count >= quietPollsRequired else {
            return false
        }
        return recentLevels.suffix(quietPollsRequired).allSatisfy { $0 <= silenceLevel }
    }
}
