import Foundation

/// Classic Metaphone (Lawrence Philips, 1990), matched to the jellyfish
/// implementation the phonetic-snap thresholds were measured against (a
/// 290-entry generated fixture pins the conformance). Spaces are preserved so
/// multi-word windows get per-word codes ("git hub" -> "JT HB").
public enum Metaphone {
    /// Phonetic code for `text`, pre-cleaned the same way as the measurement
    /// harness: lowercased, everything but [a-z0-9 ] stripped.
    public static func key(_ text: String) -> String {
        var s = Array(text.lowercased().unicodeScalars
            .map(Character.init)
            .filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == " " })

        for prefix in ["kn", "gn", "pn", "wr", "ae"] where s.starts(with: prefix) {
            s.removeFirst()
            break
        }

        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        var result: [Character] = []
        var i = 0
        while i < s.count {
            let c = s[i]
            let next = i + 1 < s.count ? s[i + 1] : nil
            let nextnext = i + 2 < s.count ? s[i + 2] : nil
            defer { i += 1 }

            // Skip doubled letters except "cc".
            if c == next && c != "c" { continue }

            switch c {
            case "a", "e", "i", "o", "u":
                if i == 0 || s[i - 1] == " " { result.append(c) }
            case "b":
                // Silent in a word-final "mb" ("thumb" -> 0M).
                let wordEnd = next == nil || next == " "
                if !(i > 0 && s[i - 1] == "m" && wordEnd) { result.append("b") }
            case "c":
                if (next == "i" && nextnext == "a") || next == "h" {
                    result.append("x")
                    i += 1
                } else if next == "i" || next == "e" || next == "y" {
                    result.append("s")
                    i += 1
                } else {
                    result.append("k")
                }
            case "d":
                if next == "g", let nn = nextnext, "iey".contains(nn) {
                    result.append("j")
                    i += 2
                } else {
                    result.append("t")
                }
            case "f", "j", "l", "m", "n", "r":
                result.append(c)
            case "g":
                if let n = next, "iey".contains(n) {
                    result.append("j")
                } else if next == "h", let nn = nextnext, !vowels.contains(nn) {
                    i += 1
                } else if next == "n", nextnext == nil {
                    i += 1
                } else {
                    result.append("k")
                }
            case "h":
                let nextIsVowel = next.map(vowels.contains) ?? false
                if i == 0 || nextIsVowel || !vowels.contains(s[i - 1]) { result.append("h") }
            case "k":
                if i == 0 || s[i - 1] != "c" { result.append("k") }
            case "p":
                if next == "h" {
                    result.append("f")
                    i += 1
                } else {
                    result.append("p")
                }
            case "q":
                result.append("k")
            case "s":
                if next == "h" {
                    result.append("x")
                    i += 1
                } else if next == "i", let nn = nextnext, "oa".contains(nn) {
                    result.append("x")
                    i += 2
                } else {
                    result.append("s")
                }
            case "t":
                if next == "i", let nn = nextnext, "oa".contains(nn) {
                    result.append("x")
                } else if next == "h" {
                    result.append("0")
                    i += 1
                } else if !(next == "c" && nextnext == "h") {
                    result.append("t")
                }
            case "v":
                result.append("f")
            case "w":
                if i == 0 && next == "h" {
                    result.append("w")
                    i += 1
                } else if next.map(vowels.contains) ?? false {
                    result.append("w")
                }
            case "x":
                if i == 0 {
                    if next == "h" || (next == "i" && nextnext.map({ "oa".contains($0) }) ?? false) {
                        result.append("x")
                    } else {
                        result.append("s")
                    }
                } else {
                    result.append(contentsOf: "ks")
                }
            case "y":
                if next.map(vowels.contains) ?? false { result.append("y") }
            case "z":
                result.append("s")
            case " ":
                if let last = result.last, last != " " { result.append(" ") }
            default:
                break // digits carry no phonetic value
            }
        }
        return String(result).uppercased()
    }
}
