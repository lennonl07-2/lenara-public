import Foundation
import llama

actor LocalLlamaEngine {
    static let shared = LocalLlamaEngine()

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var loadedModelID: String?

    func unload() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        self.context = nil
        self.model = nil
        self.vocab = nil
        loadedModelID = nil
        llama_backend_free()
    }

    func respond(to text: String, modelURL: URL, modelID: String) throws -> String {
        if model == nil || loadedModelID != modelID {
            unload()
            try loadModel(at: modelURL, id: modelID)
        }
        guard model != nil, let context, let vocab else { throw InferenceError.failedToLoad }
        let prompt = formattedPrompt(text, modelID: modelID)
        let tokens = tokenize(prompt, vocab: vocab)
        guard !tokens.isEmpty, tokens.count < 900 else { throw InferenceError.promptTooLong }

        var batch = llama_batch_init(Int32(tokens.count + 1), 0, 1)
        defer { llama_batch_free(batch) }
        for (index, token) in tokens.enumerated() {
            batch.token[index] = token
            batch.pos[index] = Int32(index)
            batch.n_seq_id[index] = 1
            batch.seq_id[index]![0] = 0
            batch.logits[index] = 0
            batch.n_tokens += 1
        }
        batch.logits[Int(batch.n_tokens) - 1] = 1
        guard llama_decode(context, batch) == 0 else { throw InferenceError.generationFailed }

        let samplerParams = llama_sampler_chain_default_params()
        guard let sampler = llama_sampler_chain_init(samplerParams) else { throw InferenceError.generationFailed }
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.25))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(42))

        var output: [CChar] = []
        var currentPosition = Int32(tokens.count)
        let maxTokens: Int32 = 160
        for _ in 0..<maxTokens {
            let next = llama_sampler_sample(sampler, context, batch.n_tokens - 1)
            if llama_vocab_is_eog(vocab, next) { break }
            output.append(contentsOf: tokenPiece(next, vocab: vocab))
            var nextBatch = llama_batch_init(1, 0, 1)
            nextBatch.token[0] = next
            nextBatch.pos[0] = currentPosition
            nextBatch.n_seq_id[0] = 1
            nextBatch.seq_id[0]![0] = 0
            nextBatch.logits[0] = 1
            nextBatch.n_tokens = 1
            guard llama_decode(context, nextBatch) == 0 else {
                llama_batch_free(nextBatch)
                throw InferenceError.generationFailed
            }
            llama_batch_free(batch)
            batch = nextBatch
            currentPosition += 1
            if currentPosition >= 1024 { break }
        }
        llama_kv_self_clear(context)
        let answer = String(cString: output + [0]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw InferenceError.generationFailed }
        return answer
    }

    private func loadModel(at url: URL, id: String) throws {
        llama_backend_init()
        var parameters = llama_model_default_params()
        parameters.n_gpu_layers = 0
        guard let loadedModel = llama_model_load_from_file(url.path, parameters) else { throw InferenceError.failedToLoad }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 1024
        let threads = Int32(max(1, min(4, ProcessInfo.processInfo.processorCount - 2)))
        contextParams.n_threads = threads
        contextParams.n_threads_batch = threads
        guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
            llama_model_free(loadedModel)
            throw InferenceError.failedToLoad
        }
        model = loadedModel
        context = loadedContext
        vocab = llama_model_get_vocab(loadedModel)
        loadedModelID = id
    }

    private func formattedPrompt(_ input: String, modelID: String) -> String {
        let system = AssistantPromptStore.prompt(for: modelID)
        if modelID == "tinyllama-11-q4" {
            return "<|system|>\n\(system)</s>\n<|user|>\n\(input)</s>\n<|assistant|>\n"
        }
        return "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(input)<|im_end|>\n<|im_start|>assistant\n"
    }

    private func tokenize(_ text: String, vocab: OpaquePointer) -> [llama_token] {
        let size = text.utf8.count
        let capacity = size + 2
        let buffer = UnsafeMutablePointer<llama_token>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        let count = llama_tokenize(vocab, text, Int32(size), buffer, Int32(capacity), true, false)
        guard count > 0 else { return [] }
        return (0..<Int(count)).map { buffer[$0] }
    }

    private func tokenPiece(_ token: llama_token, vocab: OpaquePointer) -> [CChar] {
        let initialCapacity = 32
        let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: initialCapacity)
        defer { buffer.deallocate() }
        let count = llama_token_to_piece(vocab, token, buffer, Int32(initialCapacity), 0, false)
        guard count > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: buffer, count: Int(count)))
    }

    enum InferenceError: LocalizedError {
        case failedToLoad, promptTooLong, generationFailed
        var errorDescription: String? {
            switch self {
            case .failedToLoad: "No se pudo abrir el modelo local."
            case .promptTooLong: "El mensaje es demasiado largo para este modelo."
            case .generationFailed: "El modelo no pudo generar una respuesta."
            }
        }
    }
}
