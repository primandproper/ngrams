import Foundation

/// The words a word puzzle of one language and length accepts as guesses, built offline by
/// the generator alongside the bank.
nonisolated struct GuessList: Sendable {
  let accepted: Set<String>
  /// Valid but offensive words, answered apart from words the list doesn't know.
  let blocked: Set<String>

  init(accepted: Set<String>, blocked: Set<String> = []) {
    self.accepted = accepted
    self.blocked = blocked
  }

  /// Parses the generator's one-word-per-line files.
  init(accepted: String, blocked: String) {
    func words(_ text: String) -> Set<String> {
      Set(text.split(whereSeparator: \.isNewline).map(String.init))
    }
    self.init(accepted: words(accepted), blocked: words(blocked))
  }

  /// Reads the list bundled for `language` and `n`, off the main actor.
  @concurrent
  static func loadBundled(
    language: Language, n: Int, from bundle: Bundle = .main
  ) async throws -> GuessList {
    func read(_ name: String) throws -> String {
      guard let url = bundle.url(forResource: name, withExtension: "txt", subdirectory: "guesses")
      else {
        throw GuessListError.missing(name)
      }
      return try String(contentsOf: url, encoding: .utf8)
    }
    let name = "\(language.rawValue)-\(n)"
    return GuessList(accepted: try read(name), blocked: try read("\(name)-blocked"))
  }
}

nonisolated enum GuessListError: Error, Equatable, CustomStringConvertible {
  case missing(String)

  var description: String {
    switch self {
    case .missing(let name): "the app has no guess list \(name)"
    }
  }
}
