import Foundation
import Testing
@testable import DevTools

struct CodeThemeTests {
    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    @Test(arguments: CodeTheme.allCases.filter { $0.palettes != nil })
    func everyColourIsLegibleOnItsBackground(theme: CodeTheme) throws {
        let palettes = try #require(theme.palettes)
        for palette in [palettes.light, palettes.dark] {
            for colour in palette.foregrounds {
                #expect(contrast(colour, palette.background) >= 4.5, "\(theme.title) \(String(colour, radix: 16)) on \(String(palette.background, radix: 16))")
            }
        }
    }
}
