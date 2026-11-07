// Inline calculator, like typing "2^10/3" into Spotlight or Raycast. A port
// of src/Calculator.cpp.
import Foundation

// Recursive-descent parser:
//   expr   := term (('+' | '-') term)*
//   term   := power (('*' | '/' | '%' | implicit) power)*
//   power  := unary ('^' power)?
//   unary  := ('-' | '+') unary | postfix
//   postfix:= atom '!'*
//   atom   := number | constant | func '(' expr ')' | '(' expr ')'
private struct Parser {
	let input: [CChar]	// NUL-terminated
	var pos = 0
	var failed = false

	init(_ text: String) { input = Array(text.utf8CString) }

	private var current: CChar { input[pos] }
	private func char(_ c: Character) -> CChar { CChar(c.asciiValue!) }
	private func isAlpha(_ c: CChar) -> Bool { c >= 0 && isalpha(Int32(c)) != 0 }
	private func isDigit(_ c: CChar) -> Bool { c >= 0 && isdigit(Int32(c)) != 0 }

	mutating func evaluate() -> Double? {
		let value = expression()
		skipSpace()
		return !failed && current == 0 && value.isFinite ? value : nil
	}

	private mutating func skipSpace() {
		while current == char(" ") { pos += 1 }
	}

	private mutating func accept(_ c: Character) -> Bool {
		skipSpace()
		if current == char(c) {
			pos += 1
			return true
		}
		return false
	}

	private mutating func expression() -> Double {
		var value = term()
		while !failed {
			if accept("+") { value += term() }
			else if accept("-") { value -= term() }
			else { break }
		}
		return value
	}

	private mutating func term() -> Double {
		var value = power()
		while !failed {
			skipSpace()
			let c = current
			if c == char("*") || (c == char("x") && !isAlpha(input[pos + 1])) {
				pos += 1
				value *= power()
			} else if c == char("/") || c == char("%") {
				pos += 1
				let divisor = power()
				if divisor == 0 {
					failed = true
					return 0
				}
				value = c == char("/") ? value / divisor : fmod(value, divisor)
			} else if c == char("(") || isAlpha(c) {
				// Implicit multiplication: "2pi", "3(4+5)".
				value *= power()
			} else {
				break
			}
		}
		return value
	}

	private mutating func power() -> Double {
		let base = unary()
		if accept("^") { return pow(base, power()) }
		return base
	}

	private mutating func unary() -> Double {
		if accept("-") { return -unary() }
		if accept("+") { return unary() }
		return postfix()
	}

	private mutating func postfix() -> Double {
		var value = atom()
		while accept("!") {
			if value < 0 || value > 170 || value != floor(value) {
				failed = true
				return 0
			}
			var product = 1.0
			var i = 2.0
			while i <= value {
				product *= i
				i += 1
			}
			value = product
		}
		return value
	}

	private static let functions: [String: (Double) -> Double] = [
		"sqrt": sqrt, "cbrt": cbrt, "abs": fabs,
		"sin": sin, "cos": cos, "tan": tan,
		"asin": asin, "acos": acos, "atan": atan,
		"ln": log, "log": log10, "log2": log2, "exp": exp,
		"floor": floor, "ceil": ceil, "round": round,
	]

	private mutating func atom() -> Double {
		skipSpace()
		if failed { return 0 }

		if accept("(") {
			let value = expression()
			if !accept(")") { failed = true }
			return value
		}

		if isDigit(current) || current == char(".") {
			let (value, length) = input.withUnsafeBufferPointer { buffer -> (Double, Int) in
				let start = buffer.baseAddress! + pos
				var end: UnsafeMutablePointer<CChar>?
				let value = strtod(start, &end)
				return (value, end.map { $0 - UnsafeMutablePointer(mutating: start) } ?? 0)
			}
			if length == 0 {
				failed = true
				return 0
			}
			pos += length
			return value
		}

		if isAlpha(current) {
			var name = ""
			while isAlpha(current) {
				name.append(Character(UnicodeScalar(UInt8(current))))
				pos += 1
			}
			switch name {
			case "pi": return Double.pi
			case "e": return M_E
			case "tau": return 2 * Double.pi
			default: break
			}
			if let function = Parser.functions[name] {
				var argument: Double
				if accept("(") {
					argument = expression()
					if !accept(")") { failed = true }
				} else {
					argument = power()
				}
				return function(argument)
			}
		}

		failed = true
		return 0
	}
}

private func looksLikeMath(_ input: String) -> Bool {
	var hasDigit = false, hasOperator = false, hasLetters = false
	for c in input.utf8 {
		if c >= 48 && c <= 57 { hasDigit = true }
		else if "+-*/^%!()".utf8.contains(c) { hasOperator = true }
		else if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) { hasLetters = true }
		else if c != 32 && c != 46 { return false }
	}
	// Functions and constants count as math only next to an operator or
	// parenthesis, so "pi" alone stays a search but "sqrt(2)" is math.
	if hasLetters { return hasOperator }
	return hasDigit && hasOperator
}

/// The formatted answer when `input` looks like arithmetic rather than a
/// search and evaluates cleanly.
func calculate(_ raw: String) -> String? {
	var input = Substring(raw)
	if input.hasPrefix("=") { input = input.dropFirst() }
	let text = String(input.drop(while: { $0 == " " }))
	if text.isEmpty || !looksLikeMath(text) { return nil }

	// A lone negative number ("-5") isn't worth a calculator row.
	let lone = text.withCString { start -> Bool in
		var end: UnsafeMutablePointer<CChar>?
		strtod(start, &end)
		guard var p = end else { return false }
		while p.pointee == 32 { p += 1 }
		return p.pointee == 0
	}
	if lone { return nil }

	var parser = Parser(text)
	guard let value = parser.evaluate() else { return nil }

	if value == floor(value) && abs(value) < 1e15 {
		return String(format: "%.0f", value)
	}
	var result = String(format: "%.10g", value)
	// Trim trailing zeros left in the mantissa.
	if !result.contains("e") && result.contains(".") {
		while result.hasSuffix("0") { result.removeLast() }
		if result.hasSuffix(".") { result.removeLast() }
	}
	return result
}
