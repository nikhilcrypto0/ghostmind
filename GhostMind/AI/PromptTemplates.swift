import Foundation

enum AssistMode: Equatable {
    case assist                 // auto-answer detected question — universal format
    case whatToSay              // what should I say next?
    case followUp               // generate follow-up questions
    case recap                  // summarize conversation
    case custom(String)         // user-typed question
}

enum PromptTemplates {

    // One universal system prompt for `.assist`. We let Claude figure out the
    // question type itself and shape the structure of the details section —
    // but every answer follows the same top-line + bullets format so the user
    // can scan it mid-interview without changing reading mode.
    private static let universalAssistPrompt = """
    You are a real-time interview assistant. The user is the candidate. The interviewer just asked a question. Answer it.

    OUTPUT FORMAT (MANDATORY — same for every answer):
    1. First line: a single bold one-liner that answers the question in <15 words. Use **bold** markdown.
    2. Empty line.
    3. 3–5 bullets, each <12 words. Lead with the most important point.
    4. Optional details section, structured to fit the question type:
       - Coding question → markdown code block (always include the language tag) + one-line time/space complexity.
       - System design → "Requirements / Design / Tradeoffs" subsections, 1–2 bullets each.
       - Behavioral → "Situation / Action / Result" subsections, 1 short sentence each.
       - Conceptual → 1-line example or analogy if it clarifies.
       Skip the details section if the bullets are self-contained.

    HARD RULES:
    - Total response under 220 words. Bullets first, details only if they add real value.
    - No filler ("Great question", "It depends", "Let me explain"). Get to the point on line 1.
    - No restating the question.
    - Sound human and direct. The user is reading this with one eye while talking to a real interviewer.
    - If the question is ambiguous, pick the most likely interpretation and answer it. Don't ask the user to clarify.
    """

    static func systemPrompt(for mode: AssistMode) -> String {
        let ctx = ContextManager.shared.contextBlock
        switch mode {
        case .assist:
            return universalAssistPrompt + ctx

        case .whatToSay:
            return """
            You are a real-time interview coach. Based on the conversation, suggest exactly what the user should say next — as if they are speaking the words.
            - Write in first person, conversational tone
            - Sound natural, confident, not scripted
            - 2-4 sentences max
            - Be direct and specific to what was asked\(ctx)
            """

        case .followUp:
            return """
            You are a real-time interview assistant. Based on the conversation, generate smart follow-up questions the user could ask.
            - List exactly 4 follow-up questions
            - Number them 1–4
            - Each question under 15 words
            - Make them specific to the conversation, not generic\(ctx)
            """

        case .recap:
            return """
            You are a real-time meeting assistant. Summarize the conversation so far.
            - 4-6 bullet points
            - Cover the key topics and questions discussed
            - Note any decisions or action items if present
            - Each bullet under 20 words\(ctx)
            """

        case .custom:
            return """
            You are a helpful AI assistant in a live interview or meeting. Answer the user's question concisely and accurately.
            - Be direct and specific
            - Use context from the transcript if relevant
            - Keep response under 200 words\(ctx)
            """
        }
    }

    static func userPrompt(transcript: String, mode: AssistMode) -> String {
        let recent = String(transcript.suffix(2000))
        let lastInterviewer = TranscriptionManager.shared.lastInterviewerUtterance
        let lastCandidate = TranscriptionManager.shared.lastCandidateUtterance

        switch mode {
        case .assist:
            let questionLine: String
            if !lastInterviewer.isEmpty {
                questionLine = "The interviewer JUST asked:\n\"\(lastInterviewer)\""
            } else {
                questionLine = "Answer the most recent question in the transcript."
            }
            let candidateContext: String
            if !lastCandidate.isEmpty {
                candidateContext = "\n\nWhat you (the candidate) recently said:\n\"\(lastCandidate)\""
            } else {
                candidateContext = ""
            }
            return """
            Labeled dialog (context):
            \(recent)

            \(questionLine)\(candidateContext)

            Answer ONLY the interviewer's latest question, following the OUTPUT FORMAT above. Align with what you (the candidate) have already said so the conversation stays consistent.
            """
        case .whatToSay:
            return "Labeled dialog:\n\(recent)\n\nWhat should you (the candidate) say next?"
        case .followUp:
            return "Labeled dialog:\n\(recent)\n\nGenerate follow-up questions you could ask the interviewer."
        case .recap:
            return "Labeled dialog:\n\(recent)\n\nSummarize this conversation."
        case .custom(let question):
            return "Labeled dialog:\n\(recent)\n\nMy question: \(question)"
        }
    }
}
