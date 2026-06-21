import Accelerate
import Foundation

/// Pure peak-normalization for captured PCM, factored out of the recorder so the
/// gain math is unit-testable (the recorder itself needs a live mic to exercise).
public enum AudioNormalizer {
    /// Scales `samples` so the loudest peak sits at `target` (~-1 dBFS by default),
    /// giving Whisper usable headroom on a quiet mic — a weak signal makes
    /// large-v3-turbo confabulate plausible fillers instead of transcribing. A
    /// no-op when the clip is already hot (peaks ≥ 0.7, so good levels are left
    /// untouched) or effectively silent (peak ≤ 0.001, so a noise floor isn't
    /// amplified). `maxGain` caps the boost so a single stray click can't blow the
    /// whole clip up.
    public static func peakNormalized(_ samples: [Float], target: Float = 0.9, maxGain: Float = 30) -> [Float] {
        guard !samples.isEmpty else { return samples }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        guard peak > 0.001, peak < 0.7 else { return samples }
        var gain = min(target / peak, maxGain)
        var output = [Float](repeating: 0, count: samples.count)
        vDSP_vsmul(samples, 1, &gain, &output, 1, vDSP_Length(samples.count))
        return output
    }
}
