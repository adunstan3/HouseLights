import Foundation

/// The triangle of xy colors a bulb can show. Hue bulbs report it as `color.gamut`;
/// most current color bulbs are gamut C. A point outside the triangle is moved to the
/// nearest point on its edge.
nonisolated struct Gamut: Codable, Sendable, Hashable {
    var red: XY
    var green: XY
    var blue: XY

    static let a = Gamut(red: XY(x: 0.704, y: 0.296), green: XY(x: 0.2151, y: 0.7106), blue: XY(x: 0.138, y: 0.08))
    static let b = Gamut(red: XY(x: 0.675, y: 0.322), green: XY(x: 0.409, y: 0.518), blue: XY(x: 0.167, y: 0.04))
    static let c = Gamut(red: XY(x: 0.6915, y: 0.3083), green: XY(x: 0.17, y: 0.7), blue: XY(x: 0.1532, y: 0.0475))

    init(red: XY, green: XY, blue: XY) {
        self.red = red; self.green = green; self.blue = blue
    }

    init(_ dto: HueGamutDTO) {
        self.init(red: XY(x: dto.red.x, y: dto.red.y), green: XY(x: dto.green.x, y: dto.green.y),
                  blue: XY(x: dto.blue.x, y: dto.blue.y))
    }

    func contains(_ p: XY) -> Bool {
        func cross(_ a: XY, _ b: XY, _ p: XY) -> Double { (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) }
        let d1 = cross(red, green, p), d2 = cross(green, blue, p), d3 = cross(blue, red, p)
        let hasNeg = d1 < 0 || d2 < 0 || d3 < 0
        let hasPos = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNeg && hasPos)
    }

    func clamp(_ p: XY) -> XY {
        if contains(p) { return p }
        let candidates = [closest(p, red, green), closest(p, green, blue), closest(p, blue, red)]
        return candidates.min { $0.distance(to: p) < $1.distance(to: p) }!
    }

    private func closest(_ p: XY, _ a: XY, _ b: XY) -> XY {
        let abx = b.x - a.x, aby = b.y - a.y
        let t = ((p.x - a.x) * abx + (p.y - a.y) * aby) / max(abx * abx + aby * aby, 1e-12)
        let k = min(max(t, 0), 1)
        return XY(x: a.x + abx * k, y: a.y + aby * k)
    }
}
