import Foundation

enum AssistMode: Equatable {
    case assist(QuestionType)   // auto-answer detected question
    case whatToSay              // what should I say next?
    case followUp               // generate follow-up questions
    case recap                  // summarize conversation
    case custom(String)         // user-typed question
}

enum PromptTemplates {
    static func systemPrompt(for mode: AssistMode) -> String {
        let ctx = ContextManager.shared.contextBlock
        switch mode {

        case .assist(let type):
            switch type {
            case .coding:
                return """
                You are a real-time coding interview assistant. The user is the candidate.
                - Give concise, correct code with a brief explanation
                - Format code in markdown code blocks with language tag
                - Include time and space complexity
                - Start with the approach in 1-2 sentences, then the code
                - Keep total response under 300 words\(ctx)
                """
            case .systemDesign:
                return """
                You are a real-time system design interview assistant. The user is the candidate.
                - Structure: Requirements → High-Level Design → Deep Dive → Tradeoffs
                - Use bullet points, not long paragraphs
                - Name specific technologies (Kafka, Redis, PostgreSQL, S3, etc.)
                - Include scale estimates when relevant
                - Keep total response under 400 words\(ctx)
                """
            case .conceptual:
                return """
                You are a real-time interview assistant. The interviewer asked a knowledge or conceptual question.
                - Give a clear, direct answer — no STAR format, no personal stories
                - Structure: one-line definition → 2-3 key points or use cases → brief example if helpful
                - Use bullet points for the key points
                - Sound knowledgeable and conversational
                - Keep total response under 200 words\(ctx)
                """
            case .behavioral:
                return """
                You are a real-time behavioral interview assistant. The user is the candidate.
                - Structure the answer in STAR format: Situation, Task, Action, Result
                - Keep each section to 2-3 sentences
                - Sound natural, not rehearsed
                - Focus on impact, ownership, and lessons learned
                - Keep total response under 250 words\(ctx)
                """
            }

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
            // The transcript is now labeled [Interviewer]/[You]. Pin Claude to
            // the interviewer's latest question and use the candidate's recent
            // words as context for tailoring the answer.
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

            Answer ONLY the interviewer's latest question. Align the answer with what you (the candidate) have already said so the conversation stays consistent. Ignore earlier questions.
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
