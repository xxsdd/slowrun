import XCTest
@testable import RunCore

final class RunLanguageTests: XCTestCase {
    func testEnglishSplitLabelsAndMicrosoftPhrases() throws {
        let format = RunLanguage.english("第 %1$@ 公里")
        XCTAssertEqual(String(format: format, "3"), "Kilometre 3")
        XCTAssertEqual(RunLanguage.english(NavigationVoice.nearRight.speech), "Turn right here.")
        XCTAssertEqual(RunLanguage.english(FixedVoiceCue.run.speech), "Start running.")
        XCTAssertEqual(RunLanguage.english(try XCTUnwrap(NumberVoiceScript.texts["minute_1"])), "1 minute")
        XCTAssertEqual(RunLanguage.english(try XCTUnwrap(NumberVoiceScript.texts["second_30"])), "30 seconds")
    }
}
