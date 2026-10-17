import Foundation

@MainActor
func runCatalogueTests(_ t: TestLog) {
    t.equal(ComponentCatalogue.validationIssues, [], "catalogue data must be structurally valid")
    t.expect(ComponentCatalogue.categories.count >= 12)
    t.expect(ComponentCatalogue.allMembers.count >= 70)

    let ids = ComponentCatalogue.allMembers.map(\.id)
    t.equal(Set(ids).count, ids.count, "component IDs are unique")

    let categoryIDs = Set(ComponentCatalogue.categories.map(\.id))
    t.equal(categoryIDs.count, ComponentCatalogue.categories.count)
    for category in ComponentCatalogue.categories {
        t.expect(category.members.count >= 2, "\(category.id) should offer choices")
        t.expect(!category.shortName.isEmpty)
        t.expect(!category.tinyName.isEmpty)
        for member in category.members {
            t.equal(member.categoryID, category.id)
        }
    }

    // The data the product brief called out, plus some uncommon parts.
    let electrolytic = ComponentCatalogue.spec(categoryID: "capacitor", memberID: "electrolytic")
    t.isNotNil(electrolytic)
    t.equal(electrolytic?.shortName, "elec. cap")
    t.equal(electrolytic?.tinyName, "EC")
    t.equal(electrolytic?.fullName, "electrolytic\ncapacitor")
    t.equal(electrolytic?.legs, 2)
    t.equal(electrolytic?.isPolarised, true)
    t.equal(electrolytic?.stretch, ComponentStretch(min: 2, max: 6))
    t.equal(electrolytic?.layout, .twoLead)

    let resistor = ComponentCatalogue.spec(categoryID: "resistor", memberID: "standard")
    t.equal(resistor?.shortName, "res")
    t.equal(resistor?.tinyName, "R")
    t.equal(resistor?.legs, 2)
    t.equal(resistor?.isPolarised, false)
    t.equal(resistor?.stretch?.min, 4)
    t.equal(resistor?.stretch?.max, 6)

    for expectedID in [
        "resistor.trimmer",
        "capacitor.supercapacitor",
        "diode.bridge",
        "transistor.jfet",
        "transistor.ujt",
        "ic.micro28",
        "inductor.transformer",
        "crystal.resonator",
        "switch.dip4",
        "connector.socket8",
        "relay.dpdt",
        "sensor.pir",
        "power.regulator",
        "misc.testpoint",
    ] {
        t.isNotNil(ComponentCatalogue.allMembers.first { $0.id == expectedID }, expectedID)
    }

    // Search is available to the panel and exercised without a UI.
    let emptySearch = ComponentCatalogue.filteredCategories(matching: "   ")
    t.equal(emptySearch.count, ComponentCatalogue.categories.count)

    let capSearch = ComponentCatalogue.filteredCategories(matching: "CAP")
    t.expect(capSearch.contains { $0.id == "capacitor" })
    t.equal(capSearch.first { $0.id == "capacitor" }?.members.count, 6)

    let ledSearch = ComponentCatalogue.matchingSpecs("led")
    t.expect(ledSearch.contains { $0.memberID == "LED" && $0.categoryID == "diode" })

    let timerSearch = ComponentCatalogue.matchingSpecs("555")
    t.equal(timerSearch.map(\.id), ["ic.timer8"])

    let optoSearch = ComponentCatalogue.matchingSpecs("opto")
    t.expect(optoSearch.contains { $0.id == "ic.opto4" })
    t.expect(optoSearch.contains { $0.id == "ic.timer8" } == false)

    let trimmerSearch = ComponentCatalogue.matchingSpecs("trimmer")
    t.expect(trimmerSearch.contains { $0.id == "resistor.trimmer" })
    t.expect(trimmerSearch.contains { $0.id == "capacitor.trimmer" })

    t.equal(ComponentCatalogue.matchingSpecs("no-such-part"), [])

    let stretch = ComponentStretch(min: 4, max: 6)
    t.equal(stretch.clamp(2), 4)
    t.equal(stretch.clamp(5), 5)
    t.equal(stretch.clamp(9), 6)
    t.equal(stretch.defaultSpan, 5)

    t.equal(ComponentPlacement.defaultSpan(for: resistor!), 5)
    t.equal(ComponentPlacement.defaultSpan(for: electrolytic!), 4)
    t.equal(
        ComponentPlacement.suggestedSpans(for: resistor!),
        [5, 4, 6]
    )

    let twoLeadCount = ComponentCatalogue.allMembers.filter { $0.layout == .twoLead }.count
    let dipCount = ComponentCatalogue.allMembers.filter { $0.layout == .dualInline }.count
    t.expect(twoLeadCount > 20)
    t.expect(dipCount >= 8)
}
