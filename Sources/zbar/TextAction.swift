import Foundation

/// A preset prompt applied to selected text.
///
/// zdx has no non-interactive preset or named-prompt flag, so the instructions
/// live here as plain text and are sent with each request.
struct TextAction {
    let title: String
    let subtitle: String
    let instructions: String
    /// Whether the result is meant to stand in for the original text.
    let replaces: Bool

    func prompt(for text: String) -> String {
        "\(instructions)\n\nTEXT:\n\(text)"
    }

    static let all: [TextAction] = [proofread, translate, explainInPortuguese]

    static let proofread = TextAction(
        title: "Prof-read",
        subtitle: "Fix grammar and spelling, keep the meaning",
        instructions: """
        Proofread the text below. Correct grammar, spelling, and punctuation, and \
        fix awkward phrasing. Preserve the original meaning, tone, register, and \
        language — do not translate it and do not make it more formal than it was. \
        Reply with the corrected text only: no commentary, no quotes, no explanation.
        """,
        replaces: true
    )

    static let translate = TextAction(
        title: "Translate",
        subtitle: "English ↔ Brazilian Portuguese",
        instructions: """
        Translate the text below. If it is in English, translate it to Brazilian \
        Portuguese. Otherwise, translate it to English. Preserve tone and register. \
        Reply with the translation only: no commentary, no quotes, no explanation.
        """,
        replaces: true
    )

    static let explainInPortuguese = TextAction(
        title: "Explain in Portuguese",
        subtitle: "What it means, plus vocabulary worth learning",
        instructions: """
        Explain the text below in Brazilian Portuguese, clearly and concisely. Say \
        what it means and what it implies. If it contains English vocabulary, idioms, \
        or phrasal verbs worth learning, list them briefly at the end with short \
        Portuguese glosses. Reply in Brazilian Portuguese.
        """,
        replaces: false
    )
}
