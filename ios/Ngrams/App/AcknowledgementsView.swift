import SwiftUI

/// Credits for the word lists every puzzle is built from, as their licenses ask, and for the
/// app's own source.
struct AcknowledgementsView: View {
  private struct Credit: Identifiable {
    let name: String
    let use: LocalizedStringResource
    let license: LocalizedStringResource
    let url: URL

    var id: String { name }
  }

  private static let wordLists = [
    Credit(
      name: "ENABLE", use: "The English dictionary.", license: "Public domain",
      url: URL(string: "https://github.com/dolph/dictionary")!),
    Credit(
      name: "RLA-ES",
      use: "The Mexican Spanish dictionary, from Recursos Lingüísticos Abiertos del Español.",
      license: "MPL 1.1", url: URL(string: "https://github.com/sbosio/rla-es")!),
    Credit(
      name: "FrequencyWords",
      use:
        "Word frequencies from OpenSubtitles 2018, by Hermit Dave, which decide the common words.",
      license: "CC BY-SA 4.0", url: URL(string: "https://github.com/hermitdave/FrequencyWords")!),
  ]

  private static let source = Credit(
    name: "n-grams", use: "This app's source and puzzle bank.",
    license: "MIT, puzzles CC BY-SA 4.0",
    url: URL(string: "https://github.com/primandproper/ngrams")!)

  var body: some View {
    List {
      Section("Word lists") {
        ForEach(Self.wordLists) { row($0) }
      }
      Section("Source") {
        row(Self.source)
      }
    }
    .navigationTitle("Acknowledgements")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func row(_ credit: Credit) -> some View {
    Link(destination: credit.url) {
      VStack(alignment: .leading, spacing: 4) {
        Text(credit.name).font(.headline)
        Text(credit.use).font(.subheadline).foregroundStyle(.secondary)
        Text(credit.license).font(.caption).foregroundStyle(.secondary)
      }
    }
    .foregroundStyle(.primary)
  }
}
