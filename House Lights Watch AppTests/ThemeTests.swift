import SwiftUI
import Testing
@testable import House_Lights_Watch_App

struct ThemeTests {
    @Test func hexColorComponents() {
        let resolved = Color(hex: 0xFFB65C).resolve(in: EnvironmentValues())
        #expect(abs(Double(resolved.red) - 1.0) < 0.01)
        #expect(abs(Double(resolved.green) - 182.0 / 255) < 0.01)
        #expect(abs(Double(resolved.blue) - 92.0 / 255) < 0.01)
    }
}
