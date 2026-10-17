import Foundation

/// Why two adjacent holes are conductive.
enum ConductionKind: String, Codable, Sendable, CaseIterable {
    case copper
    case bareJumper
    case insulatedJumper
}

/// An undirected graph edge between two holes, normalised so `a < b`.
struct ConductionEdge: Hashable, Codable, Sendable {
    var a: GridPoint
    var b: GridPoint
    var kind: ConductionKind

    init(a: GridPoint, b: GridPoint, kind: ConductionKind) {
        if a <= b {
            self.a = a
            self.b = b
        } else {
            self.a = b
            self.b = a
        }
        self.kind = kind
    }

    func touches(_ hole: GridPoint) -> Bool { a == hole || b == hole }

    func other(than hole: GridPoint) -> GridPoint? {
        if a == hole { return b }
        if b == hole { return a }
        return nil
    }
}

/// One connected copper net.
struct ConnectivityNet: Equatable, Sendable, Identifiable {
    var index: Int
    var holes: Set<GridPoint>
    var edges: Set<ConductionEdge>

    var id: Int { index }
    var colourIndex: Int { index }
    var size: Int { holes.count }
    var sortedHoles: [GridPoint] { holes.sorted() }

    var sortedEdges: [ConductionEdge] {
        edges.sorted {
            if $0.a != $1.a { return $0.a < $1.a }
            if $0.b != $1.b { return $0.b < $1.b }
            return $0.kind.rawValue < $1.kind.rawValue
        }
    }
}

/// The conductive graph of a board.
///
/// Nodes are holes that have copper, plus jumper endpoints/route holes. Edges
/// come from the copper strips themselves and from jumpers. A cut removes the
/// copper at that hole, so the adjacent strip segments no longer meet there.
/// Soldering a pin does not join two holes and therefore does not change nets.
/// Components are electrical parts, not shorts, so they do not appear as
/// conductivity between holes.
struct Connectivity: Equatable, Sendable {
    let nodes: Set<GridPoint>
    let edges: Set<ConductionEdge>
    /// Sorted by the smallest hole, giving deterministic colour assignment.
    let nets: [ConnectivityNet]

    private let netByHole: [GridPoint: Int]
    private let adjacency: [GridPoint: Set<GridPoint>]

    init(board: Stripboard) {
        self.init(
            dimensions: board.dimensions,
            cutHoles: board.cutHoles,
            jumpers: board.jumpers
        )
    }

    init(
        dimensions: BoardDimensions,
        cutHoles: Set<GridPoint>,
        jumpers: [Jumper]
    ) {
        var nodes = Set<GridPoint>()
        for row in 0..<dimensions.rows {
            for column in 0..<dimensions.columns {
                let hole = GridPoint(column: column, row: row)
                if !cutHoles.contains(hole) {
                    nodes.insert(hole)
                }
            }
        }

        var edges = Set<ConductionEdge>()

        // Copper along each strip. A cut hole is absent and breaks the strip.
        for row in 0..<dimensions.rows {
            for column in 0..<(dimensions.columns - 1) {
                let a = GridPoint(column: column, row: row)
                let b = GridPoint(column: column + 1, row: row)
                if !cutHoles.contains(a), !cutHoles.contains(b) {
                    edges.insert(ConductionEdge(a: a, b: b, kind: .copper))
                }
            }
        }

        for jumper in jumpers {
            guard jumper.isValid(dimensions: dimensions) else { continue }
            switch jumper.kind {
            case .bare:
                for hole in jumper.route {
                    nodes.insert(hole)
                }
                for index in 1..<jumper.route.count {
                    let a = jumper.route[index - 1]
                    let b = jumper.route[index]
                    edges.insert(ConductionEdge(a: a, b: b, kind: .bareJumper))
                }
            case .insulated:
                guard let first = jumper.route.first, let last = jumper.route.last else { continue }
                nodes.insert(first)
                nodes.insert(last)
                // The sleeve is non-conductive in the middle: this is one graph
                // edge from the first pin to the last, with no intermediate nodes.
                edges.insert(ConductionEdge(a: first, b: last, kind: .insulatedJumper))
            }
        }

        let nodeList = Array(nodes)
        var unionFind = UnionFind(count: nodeList.count)
        var indexByHole: [GridPoint: Int] = [:]
        indexByHole.reserveCapacity(nodeList.count)
        for (index, hole) in nodeList.enumerated() {
            indexByHole[hole] = index
        }

        var adjacency = Dictionary(uniqueKeysWithValues: nodeList.map { ($0, Set<GridPoint>()) })
        for edge in edges {
            guard let ia = indexByHole[edge.a], let ib = indexByHole[edge.b] else { continue }
            unionFind.union(ia, ib)
            adjacency[edge.a, default: []].insert(edge.b)
            adjacency[edge.b, default: []].insert(edge.a)
        }

        var groups: [Int: Set<GridPoint>] = [:]
        for (index, hole) in nodeList.enumerated() {
            let root = unionFind.find(index)
            groups[root, default: []].insert(hole)
        }

        let sortedGroups = groups.values.sorted { lhs, rhs in
            (lhs.min() ?? GridPoint(column: 0, row: 0)) < (rhs.min() ?? GridPoint(column: 0, row: 0))
        }

        var nets: [ConnectivityNet] = []
        nets.reserveCapacity(sortedGroups.count)
        var netByHole: [GridPoint: Int] = [:]
        for (index, holes) in sortedGroups.enumerated() {
            let netEdges = edges.filter { holes.contains($0.a) && holes.contains($0.b) }
            let net = ConnectivityNet(index: index, holes: holes, edges: netEdges)
            nets.append(net)
            for hole in holes {
                netByHole[hole] = index
            }
        }

        self.nodes = nodes
        self.edges = edges
        self.nets = nets
        self.netByHole = netByHole
        self.adjacency = adjacency
    }

    var netCount: Int { nets.count }
    var edgeCount: Int { edges.count }
    var nodeCount: Int { nodes.count }

    func net(containing hole: GridPoint) -> ConnectivityNet? {
        guard let index = netByHole[hole], nets.indices.contains(index) else { return nil }
        return nets[index]
    }

    func netIndex(containing hole: GridPoint) -> Int? {
        netByHole[hole]
    }

    func isConnected(_ a: GridPoint, _ b: GridPoint) -> Bool {
        guard let ia = netByHole[a], let ib = netByHole[b] else { return false }
        return ia == ib
    }

    func neighbours(of hole: GridPoint) -> Set<GridPoint> {
        adjacency[hole] ?? []
    }

    /// Summary for the status bar, e.g. "7 nets · 7 colour-coded".
    var summary: String {
        netCount == 1 ? "1 net" : "\(netCount) nets"
    }
}

/// Disjoint-set with path compression and union by rank.
private struct UnionFind {
    private var parent: [Int]
    private var rank: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    mutating func find(_ value: Int) -> Int {
        var value = value
        while parent[value] != value {
            parent[value] = parent[parent[value]]
            value = parent[value]
        }
        return value
    }

    mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a)
        let rootB = find(b)
        guard rootA != rootB else { return }
        if rank[rootA] < rank[rootB] {
            parent[rootA] = rootB
        } else if rank[rootA] > rank[rootB] {
            parent[rootB] = rootA
        } else {
            parent[rootB] = rootA
            rank[rootA] += 1
        }
    }
}

// MARK: - Net colours

/// A deterministic colour for a net. Kept free of SwiftUI so the same colours
/// can be tested and used by any renderer.
struct NetColour: Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: UInt32) {
        self.red = Double((hex >> 16) & 0xFF) / 255
        self.green = Double((hex >> 8) & 0xFF) / 255
        self.blue = Double(hex & 0xFF) / 255
    }

    var hex: UInt32 {
        let r = UInt32((red * 255).rounded())
        let g = UInt32((green * 255).rounded())
        let b = UInt32((blue * 255).rounded())
        return (r << 16) | (g << 8) | b
    }

    /// HSV→RGB, with hue in turns (0...1).
    init(hue: Double, saturation: Double, value: Double) {
        let h = (hue - floor(hue)) * 6
        let sector = Int(h)
        let f = h - Double(sector)
        let p = value * (1 - saturation)
        let q = value * (1 - saturation * f)
        let t = value * (1 - saturation * (1 - f))
        switch sector % 6 {
        case 0: self.init(red: value, green: t, blue: p)
        case 1: self.init(red: q, green: value, blue: p)
        case 2: self.init(red: p, green: value, blue: t)
        case 3: self.init(red: p, green: q, blue: value)
        case 4: self.init(red: t, green: p, blue: value)
        default: self.init(red: value, green: p, blue: q)
        }
    }
}

enum NetColourPalette {
    /// High-contrast, colour-blind-friendly-ish choices for the first handful of
    /// nets on a tan/green board. Every entry is distinct.
    static let curated: [NetColour] = [
        NetColour(hex: 0xFF5A5F),
        NetColour(hex: 0xFFB300),
        NetColour(hex: 0x00A6A6),
        NetColour(hex: 0x2D7FF9),
        NetColour(hex: 0x8C54FF),
        NetColour(hex: 0xE6399B),
        NetColour(hex: 0x74B816),
        NetColour(hex: 0xFF7A1A),
        NetColour(hex: 0x00B8D9),
        NetColour(hex: 0xF06292),
        NetColour(hex: 0x5C6BC0),
        NetColour(hex: 0xF9D423),
        NetColour(hex: 0x22C1A8),
        NetColour(hex: 0xB24BCB),
        NetColour(hex: 0xFF6347),
        NetColour(hex: 0x4FC3F7),
    ]

    private static let goldenAngle = 0.6180339887498949

    /// Generates a new, visually distinct colour for every net index. Curated
    /// colours are used first; beyond them a golden-angle hue walk keeps
    /// neighbouring nets far apart in hue.
    static func colour(forNet index: Int) -> NetColour {
        if index < curated.count {
            return curated[index]
        }
        let generatedIndex = index - curated.count
        let hue = (Double(generatedIndex) * goldenAngle + 0.37).truncatingRemainder(dividingBy: 1)
        let saturation = 0.68 + Double(generatedIndex % 3) * 0.1
        let value = 0.92 - Double((generatedIndex / 3) % 4) * 0.06
        return NetColour(hue: hue, saturation: min(saturation, 0.95), value: value)
    }

    /// Distinct colours for an array of nets, ready for a legend.
    static func colours(for nets: [ConnectivityNet]) -> [NetColour] {
        nets.map { colour(forNet: $0.colourIndex) }
    }
}
