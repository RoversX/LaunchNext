/// A complete single-item reorder, including per-page compaction. Existing
/// slots retain their source indices; nil slots become new empty placeholders.
/// Both the landing animation and the model consume this same calculation.
struct GridReorderPlan {
    let slots: [Int?]
    let destinationIndex: Int

    static func make(occupied: [Bool], from source: Int, to target: Int,
                     itemsPerPage: Int, cascading: Bool) -> Self? {
        guard itemsPerPage > 0, occupied.indices.contains(source), occupied[source],
              target >= 0, target <= occupied.count else { return nil }
        let p = itemsPerPage
        var slots = occupied.indices.map(Optional.some)
        func isOccupied(_ slot: Int?) -> Bool { slot.map { occupied[$0] } ?? false }

        if cascading {
            slots[source] = nil
            let padding = (p - slots.count % p) % p
            slots.append(contentsOf: repeatElement(nil, count: padding))
            var page = target / p
            var local = target % p
            var carry: Int? = source
            while let moving = carry {
                let start = page * p
                let end = start + p
                if slots.count < end {
                    slots.append(contentsOf: repeatElement(nil, count: end - slots.count))
                }
                var slice = Array(slots[start..<end])
                slice.insert(moving, at: local)
                let spilled = slice.removeLast()
                slots.replaceSubrange(start..<end, with: slice)
                carry = isOccupied(spilled) ? spilled : nil
                page += 1
                local = 0
            }
        } else {
            guard source / p == target / p else { return nil }
            let start = source / p * p
            let end = min(start + p, slots.count)
            let destination = min(target, end - 1)
            let moving = slots.remove(at: source)
            slots.insert(moving, at: destination)
        }

        var finalSlots: [Int?] = []
        finalSlots.reserveCapacity(slots.count)
        for start in stride(from: 0, to: slots.count, by: p) {
            let page = slots[start..<min(start + p, slots.count)]
            let filled = page.filter(isOccupied)
            // Cross-page moves also remove fully empty pages, before publishing.
            if cascading && filled.isEmpty { continue }
            finalSlots.append(contentsOf: filled)
            finalSlots.append(contentsOf: page.filter { !isOccupied($0) })
        }
        guard let destination = finalSlots.firstIndex(where: { $0 == source }) else { return nil }
        return Self(slots: finalSlots, destinationIndex: destination)
    }
}
