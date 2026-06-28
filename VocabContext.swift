//
//  VocabContext.swift
//  Vvox
//
//  Named, reusable, editable collections of vocabulary words that the user
//  can switch between at session start. The active list's words are unioned
//  with the free-text editor's words and fed into
//  AnalysisContext.contextualStrings[.general].
//

import Foundation
import Observation

struct VocabContext: Identifiable, Codable, Equatable, Hashable {

    let id: UUID
    var name: String
    var words: [String]

    init(id: UUID = UUID(), name: String, words: [String]) {
        self.id = id
        self.name = name
        self.words = words
    }
}

@MainActor
@Observable
final class VocabContextStore {

    private static let defaultsKey = "VvoxVocabContexts.v1"

    var contexts: [VocabContext]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([VocabContext].self, from: data) {
            self.contexts = decoded
        } else {
            self.contexts = Self.seedDefaults()
            self.save()
        }
    }

    func add(_ context: VocabContext) {
        contexts.append(context)
        save()
    }

    func update(_ context: VocabContext) {
        guard let idx = contexts.firstIndex(where: { $0.id == context.id }) else { return }
        contexts[idx] = context
        save()
    }

    func remove(id: UUID) {
        contexts.removeAll { $0.id == id }
        save()
    }

    func context(for id: UUID?) -> VocabContext? {
        guard let id else { return nil }
        return contexts.first(where: { $0.id == id })
    }

    // MARK: Private

    private func save() {
        if let data = try? JSONEncoder().encode(contexts) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func seedDefaults() -> [VocabContext] {
        [
            VocabContext(name: "Lab",
                         words: ["assay", "ELISA", "Western blot", "qPCR", "spectrophotometer", "chromatography"]),
            VocabContext(name: "Scholarship",
                         words: ["essay", "thesis", "abstract", "footnote", "citation", "bibliography"]),
            VocabContext(name: "Music",
                         words: ["arpeggio", "ostinato", "cadenza", "pizzicato", "staccato"])
        ]
    }
}
