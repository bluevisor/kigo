"""Inline calculator, like typing "2^10/3" into Spotlight or Raycast. A port
of src/Calculator.cpp."""
import math
import re

_FUNCTIONS = {
    "sqrt": math.sqrt, "cbrt": lambda x: math.copysign(abs(x) ** (1 / 3), x), "abs": abs,
    "sin": math.sin, "cos": math.cos, "tan": math.tan,
    "asin": math.asin, "acos": math.acos, "atan": math.atan,
    "ln": math.log, "log": math.log10, "log2": math.log2, "exp": math.exp,
    "floor": math.floor, "ceil": math.ceil, "round": lambda x: math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5),
}
_NUMBER = re.compile(r"(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?")


class _Fail(Exception):
    pass


class _Parser:
    # expr := term (('+'|'-') term)* ; term := power (('*'|'/'|'%'|implicit) power)*
    # power := unary ('^' power)? ; unary := ('-'|'+') unary | postfix
    # postfix := atom '!'* ; atom := number | constant | func '(' expr ')' | '(' expr ')'
    def __init__(self, text):
        self.s = text
        self.i = 0

    def peek(self, offset=0):
        j = self.i + offset
        return self.s[j] if j < len(self.s) else ""

    def skip(self):
        while self.peek() == " ":
            self.i += 1

    def accept(self, c):
        self.skip()
        if self.peek() == c:
            self.i += 1
            return True
        return False

    def evaluate(self):
        value = self.expression()
        self.skip()
        if self.i != len(self.s) or not math.isfinite(value):
            raise _Fail
        return value

    def expression(self):
        value = self.term()
        while True:
            if self.accept("+"):
                value += self.term()
            elif self.accept("-"):
                value -= self.term()
            else:
                return value

    def term(self):
        value = self.power()
        while True:
            self.skip()
            c = self.peek()
            if c == "*" or (c == "x" and not self.peek(1).isalpha()):
                self.i += 1
                value *= self.power()
            elif c in ("/", "%") and c:
                self.i += 1
                divisor = self.power()
                if divisor == 0:
                    raise _Fail
                value = value / divisor if c == "/" else math.fmod(value, divisor)
            elif c == "(" or (c.isascii() and c.isalpha()):
                # Implicit multiplication: "2pi", "3(4+5)".
                value *= self.power()
            else:
                return value

    def power(self):
        base = self.unary()
        if self.accept("^"):
            try:
                return math.pow(base, self.power())
            except (OverflowError, ValueError):
                raise _Fail
        return base

    def unary(self):
        if self.accept("-"):
            return -self.unary()
        if self.accept("+"):
            return self.unary()
        return self.postfix()

    def postfix(self):
        value = self.atom()
        while self.accept("!"):
            if value < 0 or value > 170 or value != math.floor(value):
                raise _Fail
            value = float(math.factorial(int(value)))
        return value

    def atom(self):
        self.skip()
        if self.accept("("):
            value = self.expression()
            if not self.accept(")"):
                raise _Fail
            return value
        match = _NUMBER.match(self.s, self.i)
        if match:
            self.i = match.end()
            return float(match.group(0))
        start = self.i
        while self.peek().isascii() and self.peek().isalpha():
            self.i += 1
        name = self.s[start:self.i]
        if name == "pi":
            return math.pi
        if name == "e":
            return math.e
        if name == "tau":
            return 2 * math.pi
        function = _FUNCTIONS.get(name)
        if function:
            if self.accept("("):
                argument = self.expression()
                if not self.accept(")"):
                    raise _Fail
            else:
                argument = self.power()
            try:
                return float(function(argument))
            except (ValueError, OverflowError):
                raise _Fail
        raise _Fail


def _looks_like_math(text):
    digit = operator = letters = False
    for c in text:
        if c.isascii() and c.isdigit():
            digit = True
        elif c in "+-*/^%!()":
            operator = True
        elif c.isascii() and c.isalpha():
            letters = True
        elif c not in " .":
            return False
    # Functions and constants count as math only next to an operator or
    # parenthesis, so "pi" alone stays a search but "sqrt(2)" is math.
    if letters:
        return operator
    return digit and operator


def calculate(raw):
    """The formatted answer when `raw` looks like arithmetic and evaluates
    cleanly, else None."""
    text = raw[1:] if raw.startswith("=") else raw
    text = text.lstrip(" ")
    if not text or not _looks_like_math(text):
        return None
    # A lone negative number ("-5") isn't worth a calculator row.
    if re.fullmatch(r"[+-]?\s*(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?\s*", text):
        return None
    try:
        value = _Parser(text).evaluate()
    except (_Fail, ZeroDivisionError, OverflowError, ValueError):
        return None
    if value == math.floor(value) and abs(value) < 1e15:
        return "%.0f" % value
    result = "%.10g" % value
    if "e" not in result and "." in result:
        result = result.rstrip("0").rstrip(".")
    return result
