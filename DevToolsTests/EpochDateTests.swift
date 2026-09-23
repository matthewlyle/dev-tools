import Foundation
import Testing
@testable import DevTools

struct EpochDateTests {
    @Test func epochNamesIncludeOperatorKeysAndExcludeDateStrings() {
        #expect(EpochDate.isEpochName("viewedAt"))
        #expect(EpochDate.isEpochName("addedAt>>"))
        #expect(EpochDate.isEpochName("timestamp"))
        #expect(!EpochDate.isEpochName("originallyAvailableAt"))
        #expect(!EpochDate.isEpochName("after"))
        #expect(!EpochDate.isEpochName("time"))
    }

    @Test func onlyOperatorKeysAcceptRelativeValues() {
        #expect(EpochDate.acceptsRelative("addedAt>>"))
        #expect(EpochDate.acceptsRelative("lastViewedAt<<"))
        #expect(!EpochDate.acceptsRelative("viewedAt"))
    }

    @Test func relativeValuesReadInTheSpecsUnits() {
        #expect(EpochDate.relative("-7d") == "7 days ago")
        #expect(EpochDate.relative("-1mon") == "1 month ago")
        #expect(EpochDate.relative("-3m") == "3 minutes ago")
        #expect(EpochDate.relative("+2h") == "in 2 hours")
        #expect(EpochDate.relative("-30") == "30 seconds ago")
        #expect(EpochDate.relative("7d") == nil)
        #expect(EpochDate.relative("-0d") == nil)
        #expect(EpochDate.relative("-3x") == nil)
    }

    @Test func smallNumbersAreNotDates() {
        #expect(EpochDate.date("2000") == nil)
        #expect(EpochDate.date("1712345678") == Date(timeIntervalSince1970: 1_712_345_678))
        #expect(EpochDate.describe("abc") == nil)
    }

    @Test func pickedDatesRoundTripAsWholeSeconds() {
        let date = Date(timeIntervalSince1970: 1_712_345_678.9)
        #expect(EpochDate.epoch(date) == "1712345678")
        #expect(EpochDate.date(EpochDate.epoch(date)) == Date(timeIntervalSince1970: 1_712_345_678))
    }

    @Test func everyQuickChoiceIsReadable() {
        for choice in EpochDate.recent {
            #expect(EpochDate.relative(choice) != nil, "\(choice)")
        }
    }
}
