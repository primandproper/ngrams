import Testing

@testable import Ngrams

@Suite("LanguageSelection")
struct LanguageSelectionTests {
  @Test("round-trips through its stored form")
  func roundTrips() {
    let selection = LanguageSelection([.es, .en])

    #expect(selection.rawValue == "en,es")
    #expect(LanguageSelection(rawValue: selection.rawValue) == selection)
  }

  @Test("drops codes it doesn't know")
  func dropsUnknown() {
    #expect(LanguageSelection(rawValue: "fr,es")?.languages == [.es])
    #expect(LanguageSelection(rawValue: "")?.languages.isEmpty == true)
  }

  @Test("suggests the device's languages")
  func suggests() {
    #expect(LanguageSelection.suggested(from: ["es-MX", "fr-FR"]).languages == [.es])
    #expect(LanguageSelection.suggested(from: ["en-GB", "es-419"]).languages == [.en, .es])
    #expect(LanguageSelection.suggested(from: ["ja-JP"]).languages.isEmpty)
  }
}
