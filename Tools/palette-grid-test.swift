@main
struct PaletteGridTests {
    static func main() {
        let geometry = PaletteGridGeometry(counts: [16, 10, 3], columns: 8)

        precondition(geometry.down(from: 0) == 8)
        precondition(geometry.up(from: 8) == 0)
        precondition(geometry.down(from: 8) == 16)
        precondition(geometry.down(from: 15) == 23)
        precondition(geometry.down(from: 20) == 25)
        precondition(geometry.down(from: 16) == 24)
        precondition(geometry.down(from: 25) == 27)
        precondition(geometry.down(from: 28) == 28)
        precondition(geometry.up(from: 26) == 24)
        precondition(geometry.up(from: 28) == 25)
        precondition(geometry.up(from: 3) == 3)
        precondition(geometry.up(from: 18) == 10)
        precondition(geometry.up(from: 23) == 15)

        let single = PaletteGridGeometry(counts: [5], columns: 5)
        precondition(single.down(from: 2) == 2)
        precondition(single.up(from: 2) == 2)
        precondition(PaletteGridGeometry(counts: [], columns: 5).down(from: 0) == 0)

        print("palette grid tests passed")
    }
}
