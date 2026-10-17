import Foundation

/// How a component's legs are arranged on the board.
enum ComponentLayout: String, Codable, Sendable, CaseIterable {
    /// Two legs with a stretchable body between them (resistors, axial caps, …).
    case twoLead
    /// Legs in a single row, one hole apart (transistors, headers, …).
    case inline
    /// Two parallel rows three holes apart, as used by DIP packages.
    case dualInline

    var displayName: String {
        switch self {
        case .twoLead: "two leads"
        case .inline: "inline"
        case .dualInline: "DIP"
        }
    }
}

/// The number of holes a two-lead component may span.
struct ComponentStretch: Codable, Equatable, Sendable {
    var min: Int
    var max: Int

    init(min: Int, max: Int) {
        self.min = Swift.max(1, Swift.min(min, max))
        self.max = Swift.max(self.min, max)
    }

    func clamp(_ span: Int) -> Int {
        Swift.min(Swift.max(span, min), max)
    }

    /// A pleasant default when a component is placed with a click rather than a drag.
    var defaultSpan: Int {
        Swift.max(min, Swift.min(max, (min + max + 1) / 2))
    }
}

/// A recognisable, bold vector icon drawn by the palette and the board.
///
/// These are deliberately semantic rather than SF Symbols: there is no resistor
/// or capacitor in SF Symbols, and the point of the panel is that one glance is
/// enough. The view layer draws each case with simple filled strokes.
enum ComponentGlyph: String, Codable, Sendable, CaseIterable {
    case resistor
    case powerResistor
    case photoresistor
    case thermistor
    case trimmer
    case potentiometer
    case capacitor
    case electrolytic
    case tantalum
    case trimmerCapacitor
    case diode
    case schottky
    case zener
    case led
    case bridge
    case photodiode
    case transistorNPN
    case transistorPNP
    case mosfetN
    case mosfetP
    case darlington
    case jfet
    case ujt
    case ic
    case opto
    case inductor
    case ferriteBead
    case transformer
    case crystal
    case resonator
    case oscillator
    case tactileSwitch
    case pushbutton
    case toggleSwitch
    case slideSwitch
    case dipSwitch
    case reedSwitch
    case header
    case terminal
    case jack
    case barrel
    case socket
    case relay
    case buzzer
    case speaker
    case motor
    case hall
    case thermometer
    case tilt
    case pir
    case sonar
    case battery
    case regulator
    case fuse
    case testPoint
    case sparkGap
    case link
}

/// A reference to one member of one palette group.
struct ComponentReference: Hashable, Codable, Sendable, Identifiable {
    var categoryID: String
    var memberID: String

    var id: String { "\(categoryID).\(memberID)" }
}

/// One specific part in the palette.
struct ComponentSpec: Identifiable, Equatable, Codable, Sendable {
    var categoryID: String
    var memberID: String
    var shortName: String
    var tinyName: String
    var fullName: String
    var legs: Int
    var isPolarised: Bool
    var stretch: ComponentStretch?
    var layout: ComponentLayout
    var glyph: ComponentGlyph

    var id: String { "\(categoryID).\(memberID)" }
    var reference: ComponentReference {
        ComponentReference(categoryID: categoryID, memberID: memberID)
    }

    /// A single-line name for menus, accessibility, and history labels.
    var plainFullName: String {
        fullName.split(separator: "\n").joined(separator: " ")
    }

    var legDescription: String {
        legs == 1 ? "1 leg" : "\(legs) legs"
    }

    var searchTerms: [String] {
        [categoryID, memberID, shortName, tinyName, fullName, plainFullName]
            .map { $0.lowercased() }
    }
}

/// A palette group, e.g. capacitors.
struct ComponentCategory: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var shortName: String
    var tinyName: String
    var fullName: String
    var members: [ComponentSpec]

    func matches(query: String) -> Bool {
        let search = [id, shortName, tinyName, fullName]
            .map { $0.lowercased() }
            .contains { $0.contains(query) }
        if search { return true }
        return members.contains { member in
            member.searchTerms.contains { $0.contains(query) }
        }
    }

    func filteredMembers(query: String) -> [ComponentSpec] {
        members.filter { member in
            member.searchTerms.contains { $0.contains(query) }
        }
    }

    func withMembers(_ members: [ComponentSpec]) -> ComponentCategory {
        var copy = self
        copy.members = members
        return copy
    }
}

/// The complete built-in palette.
///
/// The data is intentionally broad: common construction parts and a sprinkling of
/// less-common ones so the panel is useful beyond a beginner's toolbox.
enum ComponentCatalogue {
    static let categories: [ComponentCategory] = makeCategories()

    static let allMembers: [ComponentSpec] = categories.flatMap(\.members)

    static func category(id: String) -> ComponentCategory? {
        categories.first { $0.id == id }
    }

    static func spec(categoryID: String, memberID: String) -> ComponentSpec? {
        category(id: categoryID)?.members.first { $0.memberID == memberID }
    }

    static func spec(for reference: ComponentReference) -> ComponentSpec? {
        spec(categoryID: reference.categoryID, memberID: reference.memberID)
    }

    static func spec(for component: PlacedComponent) -> ComponentSpec? {
        spec(for: component.reference)
    }

    static func category(for reference: ComponentReference) -> ComponentCategory? {
        category(id: reference.categoryID)
    }

    /// Case-insensitive palette search. A category-name match shows the whole group.
    static func filteredCategories(matching query: String) -> [ComponentCategory] {
        let normalised = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalised.isEmpty else { return categories }
        return categories.compactMap { category in
            let categoryMatches = [category.id, category.shortName, category.tinyName, category.fullName]
                .map { $0.lowercased() }
                .contains { $0.contains(normalised) }
            let members = categoryMatches ? category.members : category.filteredMembers(query: normalised)
            guard !members.isEmpty else { return nil }
            return category.withMembers(members)
        }
    }

    static func matchingSpecs(_ query: String) -> [ComponentSpec] {
        filteredCategories(matching: query).flatMap(\.members)
    }

    /// Structural checks used by functional tests and by debug assertions.
    static var validationIssues: [String] {
        var issues: [String] = []
        var seenIDs = Set<String>()
        for category in categories {
            if category.id.isEmpty { issues.append("empty category id") }
            if category.shortName.isEmpty { issues.append("\(category.id): empty short name") }
            if category.tinyName.isEmpty { issues.append("\(category.id): empty tiny name") }
            if category.members.isEmpty { issues.append("\(category.id): no members") }
            for member in category.members {
                if member.id.isEmpty { issues.append("\(category.id): empty member id") }
                if !seenIDs.insert(member.id).inserted {
                    issues.append("duplicate component id \(member.id)")
                }
                if member.categoryID != category.id {
                    issues.append("\(member.id): category mismatch")
                }
                if member.legs < 1 { issues.append("\(member.id): no legs") }
                if member.shortName.isEmpty { issues.append("\(member.id): empty short name") }
                if member.tinyName.isEmpty { issues.append("\(member.id): empty tiny name") }
                if member.fullName.isEmpty { issues.append("\(member.id): empty full name") }
                switch member.layout {
                case .twoLead:
                    if member.legs != 2 { issues.append("\(member.id): two-lead layout needs 2 legs") }
                    if member.stretch == nil { issues.append("\(member.id): two-lead layout needs a stretch") }
                case .inline:
                    if member.legs < 1 { issues.append("\(member.id): inline needs legs") }
                    if member.stretch != nil { issues.append("\(member.id): inline should not stretch") }
                case .dualInline:
                    if member.legs < 2 || member.legs.isMultiple(of: 2) == false {
                        issues.append("\(member.id): DIP layout needs an even number of legs")
                    }
                    if member.stretch != nil { issues.append("\(member.id): DIP should not stretch") }
                }
                if let stretch = member.stretch, stretch.min > stretch.max {
                    issues.append("\(member.id): invalid stretch")
                }
            }
        }
        return issues
    }

    // MARK: - Data

    private static func makeCategories() -> [ComponentCategory] {
        func member(
            _ categoryID: String,
            _ memberID: String,
            _ shortName: String,
            _ tinyName: String,
            _ fullName: String,
            legs: Int,
            polarised: Bool = false,
            layout: ComponentLayout,
            stretch: (min: Int, max: Int)? = nil,
            glyph: ComponentGlyph
        ) -> ComponentSpec {
            ComponentSpec(
                categoryID: categoryID,
                memberID: memberID,
                shortName: shortName,
                tinyName: tinyName,
                fullName: fullName,
                legs: legs,
                isPolarised: polarised,
                stretch: stretch.map { ComponentStretch(min: $0.min, max: $0.max) },
                layout: layout,
                glyph: glyph
            )
        }

        return [
            ComponentCategory(
                id: "resistor",
                shortName: "res",
                tinyName: "R",
                fullName: "Resistors",
                members: [
                    member("resistor", "standard", "res", "R", "resistor", legs: 2, layout: .twoLead, stretch: (4, 6), glyph: .resistor),
                    member("resistor", "power", "pwr res", "PR", "power\nresistor", legs: 2, layout: .twoLead, stretch: (4, 8), glyph: .powerResistor),
                    member("resistor", "precision", "1% res", "R1%", "precision\nresistor", legs: 2, layout: .twoLead, stretch: (4, 6), glyph: .resistor),
                    member("resistor", "trimmer", "trimmer", "TR", "trimmer\npotentiometer", legs: 3, layout: .inline, glyph: .trimmer),
                    member("resistor", "potentiometer", "pot", "VR", "rotary\npotentiometer", legs: 3, layout: .inline, glyph: .potentiometer),
                    member("resistor", "photoresistor", "LDR", "LDR", "photoresistor", legs: 2, layout: .twoLead, stretch: (2, 4), glyph: .photoresistor),
                    member("resistor", "thermistor", "therm", "TH", "thermistor", legs: 2, layout: .twoLead, stretch: (2, 4), glyph: .thermistor),
                ]
            ),
            ComponentCategory(
                id: "capacitor",
                shortName: "cap",
                tinyName: "C",
                fullName: "Capacitors",
                members: [
                    member("capacitor", "ceramic", "cer cap", "C", "ceramic\ncapacitor", legs: 2, layout: .twoLead, stretch: (2, 3), glyph: .capacitor),
                    member("capacitor", "film", "film cap", "FC", "film capacitor", legs: 2, layout: .twoLead, stretch: (3, 6), glyph: .capacitor),
                    member("capacitor", "electrolytic", "elec. cap", "EC", "electrolytic\ncapacitor", legs: 2, polarised: true, layout: .twoLead, stretch: (2, 6), glyph: .electrolytic),
                    member("capacitor", "tantalum", "tant cap", "TC", "tantalum\ncapacitor", legs: 2, polarised: true, layout: .twoLead, stretch: (2, 4), glyph: .tantalum),
                    member("capacitor", "supercapacitor", "supercap", "SC", "supercapacitor", legs: 2, polarised: true, layout: .twoLead, stretch: (2, 4), glyph: .electrolytic),
                    member("capacitor", "trimmer", "trim cap", "VC", "trimmer\ncapacitor", legs: 2, layout: .twoLead, stretch: (2, 4), glyph: .trimmerCapacitor),
                ]
            ),
            ComponentCategory(
                id: "diode",
                shortName: "diode",
                tinyName: "D",
                fullName: "Diodes",
                members: [
                    member("diode", "signal", "signal", "D", "signal diode", legs: 2, polarised: true, layout: .twoLead, stretch: (3, 5), glyph: .diode),
                    member("diode", "rectifier", "rect", "DR", "rectifier\ndiode", legs: 2, polarised: true, layout: .twoLead, stretch: (3, 6), glyph: .diode),
                    member("diode", "schottky", "Schottky", "DS", "Schottky diode", legs: 2, polarised: true, layout: .twoLead, stretch: (3, 5), glyph: .schottky),
                    member("diode", "zener", "Zener", "DZ", "Zener diode", legs: 2, polarised: true, layout: .twoLead, stretch: (3, 5), glyph: .zener),
                    member("diode", "LED", "LED", "LED", "light-emitting\ndiode", legs: 2, polarised: true, layout: .twoLead, stretch: (2, 4), glyph: .led),
                    member("diode", "bridge", "bridge", "BR", "bridge\nrectifier", legs: 4, polarised: true, layout: .inline, glyph: .bridge),
                    member("diode", "photodiode", "photo D", "PD", "photodiode", legs: 2, polarised: true, layout: .twoLead, stretch: (2, 4), glyph: .photodiode),
                ]
            ),
            ComponentCategory(
                id: "transistor",
                shortName: "trans",
                tinyName: "Q",
                fullName: "Transistors",
                members: [
                    member("transistor", "npn", "NPN", "Q", "NPN\ntransistor", legs: 3, polarised: true, layout: .inline, glyph: .transistorNPN),
                    member("transistor", "pnp", "PNP", "Q", "PNP\ntransistor", legs: 3, polarised: true, layout: .inline, glyph: .transistorPNP),
                    member("transistor", "nmos", "N-MOS", "Q", "N-channel\nMOSFET", legs: 3, polarised: true, layout: .inline, glyph: .mosfetN),
                    member("transistor", "pmos", "P-MOS", "Q", "P-channel\nMOSFET", legs: 3, polarised: true, layout: .inline, glyph: .mosfetP),
                    member("transistor", "darlington", "Darling", "Q", "Darlington\ntransistor", legs: 3, polarised: true, layout: .inline, glyph: .darlington),
                    member("transistor", "jfet", "JFET", "J", "JFET", legs: 3, polarised: true, layout: .inline, glyph: .jfet),
                    member("transistor", "ujt", "UJT", "U", "unijunction\ntransistor", legs: 3, polarised: true, layout: .inline, glyph: .ujt),
                ]
            ),
            ComponentCategory(
                id: "ic",
                shortName: "IC",
                tinyName: "IC",
                fullName: "Integrated circuits",
                members: [
                    member("ic", "opamp8", "op-amp", "IC", "dual op-amp\n(DIP-8)", legs: 8, polarised: true, layout: .dualInline, glyph: .ic),
                    member("ic", "timer8", "555", "IC", "555 timer\n(DIP-8)", legs: 8, polarised: true, layout: .dualInline, glyph: .ic),
                    member("ic", "logic14", "logic", "IC", "logic gate\n(DIP-14)", legs: 14, polarised: true, layout: .dualInline, glyph: .ic),
                    member("ic", "logic16", "logic 16", "IC", "logic / driver\n(DIP-16)", legs: 16, polarised: true, layout: .dualInline, glyph: .ic),
                    member("ic", "micro28", "MCU", "IC", "microcontroller\n(DIP-28)", legs: 28, polarised: true, layout: .dualInline, glyph: .ic),
                    member("ic", "opto4", "opto", "IC", "optocoupler\n(DIP-4)", legs: 4, polarised: true, layout: .dualInline, glyph: .opto),
                ]
            ),
            ComponentCategory(
                id: "inductor",
                shortName: "ind",
                tinyName: "L",
                fullName: "Inductors",
                members: [
                    member("inductor", "axial", "choke", "L", "axial choke", legs: 2, layout: .twoLead, stretch: (2, 5), glyph: .inductor),
                    member("inductor", "radial", "rad ind", "L", "radial choke", legs: 2, layout: .twoLead, stretch: (2, 4), glyph: .inductor),
                    member("inductor", "toroid", "toroid", "L", "toroidal\ninductor", legs: 2, layout: .twoLead, stretch: (2, 4), glyph: .inductor),
                    member("inductor", "ferrite", "ferrite", "FB", "ferrite bead", legs: 2, layout: .twoLead, stretch: (2, 3), glyph: .ferriteBead),
                    member("inductor", "transformer", "audio T", "T", "audio\ntransformer", legs: 6, polarised: true, layout: .dualInline, glyph: .transformer),
                ]
            ),
            ComponentCategory(
                id: "crystal",
                shortName: "xtal",
                tinyName: "X",
                fullName: "Crystals & oscillators",
                members: [
                    member("crystal", "hc49", "xtal", "X", "quartz crystal", legs: 2, layout: .twoLead, stretch: (2, 3), glyph: .crystal),
                    member("crystal", "resonator", "resonator", "XT", "ceramic\nresonator", legs: 3, layout: .inline, glyph: .resonator),
                    member("crystal", "can", "osc", "OSC", "can oscillator", legs: 4, polarised: true, layout: .inline, glyph: .oscillator),
                    member("crystal", "mems", "MEMS", "OSC", "MEMS oscillator", legs: 4, polarised: true, layout: .inline, glyph: .oscillator),
                ]
            ),
            ComponentCategory(
                id: "switch",
                shortName: "sw",
                tinyName: "SW",
                fullName: "Switches",
                members: [
                    member("switch", "tactile", "tact", "SW", "tactile switch", legs: 4, layout: .inline, glyph: .tactileSwitch),
                    member("switch", "pushbutton", "push", "SW", "pushbutton", legs: 2, layout: .twoLead, stretch: (2, 4), glyph: .pushbutton),
                    member("switch", "toggle", "toggle", "SW", "toggle switch", legs: 3, layout: .inline, glyph: .toggleSwitch),
                    member("switch", "slide", "slide", "SW", "slide switch", legs: 3, layout: .inline, glyph: .slideSwitch),
                    member("switch", "dip4", "DIP sw", "SW", "DIP switch\n(4-way)", legs: 8, layout: .dualInline, glyph: .dipSwitch),
                    member("switch", "reed", "reed", "SW", "reed switch", legs: 2, layout: .twoLead, stretch: (2, 4), glyph: .reedSwitch),
                ]
            ),
            ComponentCategory(
                id: "connector",
                shortName: "conn",
                tinyName: "J",
                fullName: "Connectors",
                members: [
                    member("connector", "header2", "2-pin", "J", "pin header\n(2-pin)", legs: 2, layout: .inline, glyph: .header),
                    member("connector", "header4", "4-pin", "J", "pin header\n(4-pin)", legs: 4, layout: .inline, glyph: .header),
                    member("connector", "header6", "6-pin", "J", "pin header\n(6-pin)", legs: 6, layout: .inline, glyph: .header),
                    member("connector", "terminal2", "term 2", "TB", "screw terminal\n(2-way)", legs: 2, layout: .inline, glyph: .terminal),
                    member("connector", "terminal3", "term 3", "TB", "screw terminal\n(3-way)", legs: 3, layout: .inline, glyph: .terminal),
                    member("connector", "audioJack", "jack", "J", "audio jack", legs: 3, layout: .inline, glyph: .jack),
                    member("connector", "barrel", "power", "J", "barrel jack", legs: 3, polarised: true, layout: .inline, glyph: .barrel),
                    member("connector", "socket8", "socket 8", "IC", "IC socket\n(DIP-8)", legs: 8, polarised: true, layout: .dualInline, glyph: .socket),
                ]
            ),
            ComponentCategory(
                id: "relay",
                shortName: "relay",
                tinyName: "K",
                fullName: "Relays & electromechanical",
                members: [
                    member("relay", "spdt", "relay", "K", "SPDT relay", legs: 5, polarised: true, layout: .inline, glyph: .relay),
                    member("relay", "dpdt", "relay 2", "K", "DPDT relay", legs: 8, polarised: true, layout: .inline, glyph: .relay),
                    member("relay", "reed", "reed relay", "K", "reed relay", legs: 4, polarised: true, layout: .inline, glyph: .relay),
                    member("relay", "buzzer", "buzzer", "BZ", "piezo buzzer", legs: 2, polarised: true, layout: .twoLead, stretch: (2, 3), glyph: .buzzer),
                    member("relay", "speaker", "spkr", "SP", "speaker", legs: 2, polarised: true, layout: .twoLead, stretch: (2, 4), glyph: .speaker),
                    member("relay", "motor", "motor", "M", "DC motor", legs: 2, polarised: true, layout: .twoLead, stretch: (2, 3), glyph: .motor),
                ]
            ),
            ComponentCategory(
                id: "sensor",
                shortName: "sense",
                tinyName: "S",
                fullName: "Sensors",
                members: [
                    member("sensor", "hall", "Hall", "H", "Hall effect\nsensor", legs: 3, polarised: true, layout: .inline, glyph: .hall),
                    member("sensor", "temperature", "temp", "T", "temperature\nsensor", legs: 3, polarised: true, layout: .inline, glyph: .thermometer),
                    member("sensor", "tilt", "tilt", "T", "tilt switch", legs: 2, layout: .twoLead, stretch: (2, 3), glyph: .tilt),
                    member("sensor", "pir", "PIR", "PIR", "PIR motion\nsensor", legs: 3, polarised: true, layout: .inline, glyph: .pir),
                    member("sensor", "ultrasonic", "sonar", "US", "ultrasonic\nranger", legs: 4, polarised: true, layout: .inline, glyph: .sonar),
                ]
            ),
            ComponentCategory(
                id: "power",
                shortName: "pwr",
                tinyName: "PWR",
                fullName: "Power & protection",
                members: [
                    member("power", "battery", "battery", "BT", "battery holder\n(2×AA)", legs: 2, polarised: true, layout: .twoLead, stretch: (2, 4), glyph: .battery),
                    member("power", "regulator", "reg", "VR", "voltage\nregulator", legs: 3, polarised: true, layout: .inline, glyph: .regulator),
                    member("power", "fuse", "fuse", "F", "fuse", legs: 2, layout: .twoLead, stretch: (2, 4), glyph: .fuse),
                    member("power", "polyfuse", "polyfuse", "F", "resettable\nfuse", legs: 2, layout: .twoLead, stretch: (2, 3), glyph: .fuse),
                    member("power", "sparkgap", "spark gap", "SG", "spark gap", legs: 2, layout: .twoLead, stretch: (2, 3), glyph: .sparkGap),
                ]
            ),
            ComponentCategory(
                id: "misc",
                shortName: "misc",
                tinyName: "U",
                fullName: "Other parts",
                members: [
                    member("misc", "testpoint", "test pt", "TP", "test point", legs: 1, layout: .inline, glyph: .testPoint),
                    member("misc", "solderLink", "link", "JP", "solder link", legs: 2, layout: .twoLead, stretch: (1, 2), glyph: .link),
                ]
            ),
        ]
    }
}
