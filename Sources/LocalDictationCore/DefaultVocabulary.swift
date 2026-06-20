import Foundation

/// A built-in starter vocabulary of terms whisper routinely mishears — AI tools,
/// dev tooling, and product names — biased toward by default so they transcribe
/// correctly without the user adding anything (e.g. "Claude" instead of "cloud").
/// Kept deliberately tight: whisper's prompt context is only ~224 tokens, and
/// the user's own custom vocabulary always takes priority over this list.
public enum DefaultVocabulary {
    public static let terms: [String] = [
        // AI / assistants
        "Claude", "Anthropic", "ChatGPT", "OpenAI", "Qwen", "Gemini", "LLM",
        // languages / frameworks
        "TypeScript", "JavaScript", "Python", "Swift", "SwiftUI", "React", "Next.js",
        "Tailwind", "Node.js",
        // dev tooling / infra
        "GitHub", "Xcode", "npm", "Docker", "Kubernetes", "Postgres", "API",
        // products / services
        "Figma", "Slack", "Notion", "Vercel", "Supabase",
        // coinages
        "vibe coding",
    ]
}
