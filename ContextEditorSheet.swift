//
//  ContextEditorSheet.swift
//  Vvox
//
//  Sheet UI for browsing, creating, editing, and deleting VocabContexts.
//

import SwiftUI

struct ContextEditorSheet: View {

    @Bindable var vocabStore: VocabContextStore
    @Environment(\.dismiss) private var dismiss

    // When non-nil, drives a programmatic navigation to a newly-created context.
    @State private var newlyCreatedID: UUID?

    var body: some View {
        NavigationStack {
            List {
                ForEach(vocabStore.contexts) { context in
                    NavigationLink {
                        ContextDetailView(vocabStore: vocabStore, contextID: context.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.name)
                            Text("\(context.words.count) word\(context.words.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteContexts)
            }
            .navigationTitle("Vocabulary Contexts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addContext()
                    } label: {
                        Label("Add Context", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(item: $newlyCreatedID) { id in
                ContextDetailView(vocabStore: vocabStore, contextID: id)
            }
            .frame(minWidth: 480, minHeight: 360)
        }
    }

    private func addContext() {
        let newContext = VocabContext(name: "New context", words: [])
        vocabStore.add(newContext)
        newlyCreatedID = newContext.id
    }

    private func deleteContexts(at offsets: IndexSet) {
        let ids = offsets.map { vocabStore.contexts[$0].id }
        for id in ids {
            vocabStore.remove(id: id)
        }
    }
}

struct ContextDetailView: View {

    @Bindable var vocabStore: VocabContextStore
    let contextID: UUID

    @State private var newWord: String = ""

    var body: some View {
        Form {
            Section {
                TextField("Name", text: nameBinding)
            } header: { Text("Name") }

            Section {
                HStack {
                    TextField("Add word", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addWord() }
                    Button("Add") { addWord() }
                        .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let context = vocabStore.context(for: contextID), context.words.isEmpty {
                    Text("No words yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let context = vocabStore.context(for: contextID) {
                    List {
                        ForEach(context.words, id: \.self) { word in
                            Text(word)
                        }
                        .onDelete(perform: deleteWords)
                    }
                    .frame(minHeight: 200)
                }
            } header: { Text("Words") }
        }
        .formStyle(.grouped)
        .navigationTitle(vocabStore.context(for: contextID)?.name ?? "Context")
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { vocabStore.context(for: contextID)?.name ?? "" },
            set: { newName in
                guard var context = vocabStore.context(for: contextID) else { return }
                context.name = newName
                vocabStore.update(context)
            }
        )
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard var context = vocabStore.context(for: contextID) else { return }
        context.words.append(trimmed)
        vocabStore.update(context)
        newWord = ""
    }

    private func deleteWords(at offsets: IndexSet) {
        guard var context = vocabStore.context(for: contextID) else { return }
        context.words.remove(atOffsets: offsets)
        vocabStore.update(context)
    }
}
