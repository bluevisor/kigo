// Fuzzy matching in the spirit of Spotlight/Raycast: exact > prefix >
// word-start > acronym > substring > subsequence. A port of src/Fuzzy.cpp,
// so both Kigos rank the same way.

private func isAlnum(_ c: UInt8) -> Bool { isAlpha(c) || isDigit(c) }
private func isAlpha(_ c: UInt8) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) }
private func isDigit(_ c: UInt8) -> Bool { c >= 48 && c <= 57 }
private func isLower(_ c: UInt8) -> Bool { c >= 97 && c <= 122 }
private func isUpper(_ c: UInt8) -> Bool { c >= 65 && c <= 90 }
private func lower(_ c: UInt8) -> UInt8 { isUpper(c) ? c + 32 : c }

private func isBoundary(_ text: [UInt8], _ i: Int) -> Bool {
	if i == 0 { return true }
	let prev = text[i - 1], cur = text[i]
	if !isAlnum(prev) && prev < 0x80 { return true }
	// camelCase: "WebPositive" has a boundary at 'P'.
	if isLower(prev) && isUpper(cur) { return true }
	// "Haiku3D": letters to digits.
	if isAlpha(prev) && isDigit(cur) { return true }
	return false
}

private func startsWith(_ t: [UInt8], at i: Int, _ q: [UInt8]) -> Bool {
	if i + q.count > t.count { return false }
	for j in 0..<q.count where t[i + j] != q[j] { return false }
	return true
}

private func scoreWord(_ query: [UInt8], _ text: [UInt8]) -> Double {
	let t = text.map(lower)
	let q = query.map(lower)
	if q.isEmpty || q.count > t.count { return 0 }

	if t == q { return 1000 }
	if startsWith(t, at: 0, q) { return 900 - Double(t.count - q.count) * 0.5 }

	// A later word starting with the query: "pos" in "WebPositive".
	var i = 1
	while i + q.count <= t.count {
		if isBoundary(text, i) && startsWith(t, at: i, q) { return 800 - Double(i) }
		i += 1
	}

	// Acronym: "vsc" -> "Visual Studio Code", "sm" -> "System Monitor".
	if q.count >= 2 {
		var initials: [UInt8] = []
		for i in 0..<t.count where isBoundary(text, i) && isAlnum(t[i]) {
			initials.append(t[i])
		}
		if initials.count >= q.count && startsWith(initials, at: 0, q) {
			return 750 - Double(initials.count - q.count) * 2
		}
	}

	var start = 0
	while start + q.count <= t.count {
		if startsWith(t, at: start, q) { return 600 - Double(start) * 2 }
		start += 1
	}

	// Subsequence with a penalty for each gap and a bonus for boundaries.
	var score = 400.0
	var qi = 0
	var last = -1
	for i in 0..<t.count where qi < q.count {
		if t[i] != q[qi] { continue }
		if last >= 0 && i != last + 1 {
			score -= 6 + Double(i - last - 1)
		} else if last < 0 {
			score -= Double(i) * 2
		}
		if isBoundary(text, i) { score += 8 }
		last = i
		qi += 1
	}
	if qi < q.count { return 0 }
	return max(score, 50)
}

/// 0 when `query` doesn't match `text`, otherwise a score where higher is
/// better (exact match = 1000). Case-insensitive. Each space-separated word of
/// the query must match.
func fuzzyScore(_ query: String, _ text: String) -> Double {
	if query.isEmpty || text.isEmpty { return 0 }
	let q = Array(query.utf8), t = Array(text.utf8)
	if !q.contains(32) { return scoreWord(q, t) }

	// A multi-word query matching the whole text as a phrase wins.
	let phrase = scoreWord(q, t)
	if phrase >= 600 { return phrase }

	// Otherwise every word has to match somewhere.
	var total = 0.0
	var count = 0
	for word in q.split(separator: 32) {
		let score = scoreWord(Array(word), t)
		if score <= 0 { return 0 }
		total += score
		count += 1
	}
	return count == 0 ? 0 : total / Double(count) * 0.9
}
