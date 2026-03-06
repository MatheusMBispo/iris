import Foundation
import Vision

#if canImport(FoundationModels)
import FoundationModels

// MARK: - IrisProvider.appleFoundationModels Factory

@available(iOS 26.0, macOS 26.0, *)
extension IrisProvider {

    /// An on-device provider that uses Apple's Foundation Models framework for document parsing.
    ///
    /// This provider performs parsing entirely on-device using two stages:
    /// 1. Vision framework OCR to extract text from the image
    /// 2. `LanguageModelSession` (on-device 3B model) to structure the text as JSON
    ///
    /// No API key is required and no network calls are made.
    ///
    /// - Parameter maxRetries: Number of attempts to generate valid JSON from the on-device model.
    ///   Defaults to `3`. On-device model output is non-deterministic — retries handle invalid JSON.
    /// - Returns: An `IrisProvider` configured for on-device inference via Apple Foundation Models.
    /// - Note: Requires iOS 26.0 or macOS 26.0. Check `SystemLanguageModel.default.isAvailable`
    ///   before use — the model may not be downloaded yet even on a compatible OS version.
    public static func appleFoundationModels(maxRetries: Int = 3) -> IrisProvider {
        IrisProvider { imageData, prompt in
            // Stage 1: OCR via Vision
            let ocrText = try await extractText(from: imageData)

            // Stage 2: Build combined prompt
            let fmPrompt = buildFoundationModelsPrompt(ocrText: ocrText, schemaPrompt: prompt)

            // Stage 3: Generate JSON with validation + retry
            // NOTE: This is the Apple FM internal retry for invalid JSON.
            // It is INDEPENDENT of IrisClient's RetryEngine (which only retries networkError).
            // RetryEngine never retries modelFailure, so this loop is the only safety net.
            let session = LanguageModelSession(model: SystemLanguageModel.default)
            let attemptLimit = max(1, maxRetries)

            for attempt in 1...attemptLimit {
                // Wrap FoundationModels errors — system errors must not escape this layer
                let responseContent: String
                do {
                    responseContent = try await session.respond(to: fmPrompt).content
                } catch {
                    throw IrisError.modelFailure(
                        message: "Apple Foundation Model unavailable or failed: \(error.localizedDescription)"
                    )
                }

                let candidate = extractJSON(from: responseContent)

                // Validate JSON
                if let data = candidate.data(using: .utf8),
                   (try? JSONSerialization.jsonObject(with: data)) != nil {
                    return candidate
                }

                if attempt == attemptLimit {
                    throw IrisError.modelFailure(
                        message: "Apple Foundation Model failed to produce valid JSON after \(attemptLimit) attempts"
                    )
                }
            }

            throw IrisError.modelFailure(message: "Apple Foundation Model: no attempts executed")
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension IrisProvider {

    /// Internal factory for testing the retry/validation loop without real Foundation Models.
    ///
    /// `sessionResponder` replaces `LanguageModelSession.respond(to:)`, receiving the FM prompt
    /// and returning raw text (which may or may not be valid JSON).
    /// This mirrors the `IrisProvider.claude(apiKey:session:)` testable seam pattern.
    static func _appleFoundationModels(
        maxRetries: Int = 3,
        sessionResponder: @escaping @Sendable (_ prompt: String) async throws -> String
    ) -> IrisProvider {
        IrisProvider { imageData, prompt in
            let ocrText = try await extractText(from: imageData)
            let fmPrompt = buildFoundationModelsPrompt(ocrText: ocrText, schemaPrompt: prompt)
            let attemptLimit = max(1, maxRetries)

            for attempt in 1...attemptLimit {
                let rawText: String
                do {
                    rawText = try await sessionResponder(fmPrompt)
                } catch {
                    throw IrisError.modelFailure(
                        message: "Apple Foundation Model unavailable or failed: \(error.localizedDescription)"
                    )
                }

                let candidate = extractJSON(from: rawText)

                if let data = candidate.data(using: .utf8),
                   (try? JSONSerialization.jsonObject(with: data)) != nil {
                    return candidate
                }

                if attempt == attemptLimit {
                    throw IrisError.modelFailure(
                        message: "Apple Foundation Model failed to produce valid JSON after \(attemptLimit) attempts"
                    )
                }
            }

            throw IrisError.modelFailure(message: "Apple Foundation Model: no attempts executed")
        }
    }
}

// MARK: - Private Helpers (inside #if canImport block)

// No @available — Vision is iOS 13+; the #if canImport guard + calling context are sufficient
private func extractText(from jpegData: Data) async throws -> String {
    guard let dataProvider = CGDataProvider(data: jpegData as CFData),
          let cgImage = CGImage(
              jpegDataProviderSource: dataProvider,
              decode: nil,
              shouldInterpolate: true,
              intent: .defaultIntent
          ) else {
        throw IrisError.imageUnreadable(reason: "Cannot create CGImage for Vision OCR")
    }

    return try await Task.detached(priority: .userInitiated) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw IrisError.imageUnreadable(reason: error.localizedDescription)
        }
        // results is [VNRecognizedTextObservation]? — no cast needed
        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }.value
}

@available(iOS 26.0, macOS 26.0, *)
func buildFoundationModelsPrompt(ocrText: String, schemaPrompt: String) -> String {
    """
    You are a document data extraction assistant.

    The following text was extracted from a document image via OCR:
    ---
    \(ocrText)
    ---

    \(schemaPrompt)

    IMPORTANT: Respond with ONLY valid JSON. Do not include markdown code fences, explanations, or any text outside the JSON object. Start your response with { and end with }.
    """
}

// No @available — pure String manipulation, no platform dependency
func extractJSON(from text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    // Extract content inside markdown code fences when present.
    if let firstFence = trimmed.range(of: "```") {
        let afterFirstFence = trimmed[firstFence.upperBound...]
        if let secondFenceRel = afterFirstFence.range(of: "```") {
            var fenced = String(afterFirstFence[..<secondFenceRel.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if fenced.hasPrefix("json") {
                fenced.removeFirst(4)
                fenced = fenced.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !fenced.isEmpty {
                return fenced
            }
        }
    }

    // Fallback: extract first balanced JSON object from surrounding prose.
    if let open = trimmed.firstIndex(of: "{") {
        var depth = 0
        var inString = false
        var escaping = false
        var cursor = open
        while cursor < trimmed.endIndex {
            let ch = trimmed[cursor]
            if inString {
                if escaping {
                    escaping = false
                } else if ch == "\\" {
                    escaping = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(trimmed[open...cursor])
                    }
                }
            }
            cursor = trimmed.index(after: cursor)
        }
    }

    return trimmed
}

#endif
