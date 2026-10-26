#include "Calculator.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


namespace {

// Recursive-descent parser:
//   expr   := term (('+' | '-') term)*
//   term   := power (('*' | '/' | '%' | implicit) power)*
//   power  := unary ('^' power)?
//   unary  := ('-' | '+') unary | postfix
//   postfix:= atom '!'*
//   atom   := number | constant | func '(' expr ')' | '(' expr ')'
class Parser {
public:
	Parser(const char* input)
		:
		fInput(input),
		fPos(0),
		fFailed(false)
	{
	}

	bool Evaluate(double& value)
	{
		value = _Expression();
		_SkipSpace();
		return !fFailed && fInput[fPos] == '\0' && isfinite(value);
	}

private:
	void _SkipSpace()
	{
		while (fInput[fPos] == ' ')
			fPos++;
	}

	bool _Accept(char c)
	{
		_SkipSpace();
		if (fInput[fPos] == c) {
			fPos++;
			return true;
		}
		return false;
	}

	double _Expression()
	{
		double value = _Term();
		while (!fFailed) {
			if (_Accept('+'))
				value += _Term();
			else if (_Accept('-'))
				value -= _Term();
			else
				break;
		}
		return value;
	}

	double _Term()
	{
		double value = _Power();
		while (!fFailed) {
			_SkipSpace();
			char c = fInput[fPos];
			if (c == '*' || (c == 'x' && !isalpha(fInput[fPos + 1]))) {
				fPos++;
				value *= _Power();
			} else if (c == '/') {
				fPos++;
				double divisor = _Power();
				if (divisor == 0) {
					fFailed = true;
					return 0;
				}
				value /= divisor;
			} else if (c == '%') {
				fPos++;
				double divisor = _Power();
				if (divisor == 0) {
					fFailed = true;
					return 0;
				}
				value = fmod(value, divisor);
			} else if (c == '(' || isalpha(c)) {
				// Implicit multiplication: "2pi", "3(4+5)".
				value *= _Power();
			} else
				break;
		}
		return value;
	}

	double _Power()
	{
		double base = _Unary();
		if (_Accept('^'))
			return pow(base, _Power());
		return base;
	}

	double _Unary()
	{
		if (_Accept('-'))
			return -_Unary();
		if (_Accept('+'))
			return _Unary();
		return _Postfix();
	}

	double _Postfix()
	{
		double value = _Atom();
		while (_Accept('!')) {
			if (value < 0 || value > 170 || value != floor(value)) {
				fFailed = true;
				return 0;
			}
			double product = 1;
			for (int i = 2; i <= (int)value; i++)
				product *= i;
			value = product;
		}
		return value;
	}

	double _Atom()
	{
		_SkipSpace();
		if (fFailed)
			return 0;

		if (_Accept('(')) {
			double value = _Expression();
			if (!_Accept(')'))
				fFailed = true;
			return value;
		}

		const char* start = fInput + fPos;
		if (isdigit(*start) || *start == '.') {
			char* end;
			double value = strtod(start, &end);
			if (end == start) {
				fFailed = true;
				return 0;
			}
			fPos += end - start;
			return value;
		}

		if (isalpha(*start)) {
			int length = 0;
			while (isalpha(start[length]))
				length++;
			char name[16];
			if (length >= (int)sizeof(name)) {
				fFailed = true;
				return 0;
			}
			memcpy(name, start, length);
			name[length] = '\0';
			fPos += length;

			if (strcmp(name, "pi") == 0)
				return M_PI;
			if (strcmp(name, "e") == 0)
				return M_E;
			if (strcmp(name, "tau") == 0)
				return 2 * M_PI;

			static const struct {
				const char* name;
				double (*function)(double);
			} kFunctions[] = {
				{"sqrt", sqrt}, {"cbrt", cbrt}, {"abs", fabs},
				{"sin", sin}, {"cos", cos}, {"tan", tan},
				{"asin", asin}, {"acos", acos}, {"atan", atan},
				{"ln", log}, {"log", log10}, {"log2", log2}, {"exp", exp},
				{"floor", floor}, {"ceil", ceil}, {"round", round},
			};
			for (const auto& function : kFunctions) {
				if (strcmp(name, function.name) == 0) {
					double argument;
					if (_Accept('('))  {
						argument = _Expression();
						if (!_Accept(')'))
							fFailed = true;
					} else
						argument = _Power();
					return function.function(argument);
				}
			}
		}

		fFailed = true;
		return 0;
	}

	const char*	fInput;
	int			fPos;
	bool		fFailed;
};


bool
LooksLikeMath(const char* input)
{
	bool hasDigit = false;
	bool hasOperator = false;
	bool hasLetters = false;
	for (const char* c = input; *c != '\0'; c++) {
		if (isdigit(*c))
			hasDigit = true;
		else if (strchr("+-*/^%!()", *c) != NULL)
			hasOperator = true;
		else if (isalpha(*c))
			hasLetters = true;
		else if (*c != ' ' && *c != '.')
			return false;
	}
	if (hasLetters) {
		// Functions and constants count as math only next to an operator or
		// parenthesis, so "pi" alone stays a search but "sqrt(2)" is math.
		return hasOperator;
	}
	return hasDigit && hasOperator;
}

} // namespace


bool
Calculate(const char* input, BString& result)
{
	if (input[0] == '=')
		input++;
	while (*input == ' ')
		input++;
	if (*input == '\0' || !LooksLikeMath(input))
		return false;

	// A lone negative number ("-5") isn't worth a calculator row.
	char* end;
	strtod(input, &end);
	while (*end == ' ')
		end++;
	if (*end == '\0')
		return false;

	double value;
	Parser parser(input);
	if (!parser.Evaluate(value))
		return false;

	char buffer[64];
	if (value == floor(value) && fabs(value) < 1e15)
		snprintf(buffer, sizeof(buffer), "%.0f", value);
	else {
		snprintf(buffer, sizeof(buffer), "%.10g", value);
		// Trim trailing zeros left in the mantissa.
		char* exponent = strchr(buffer, 'e');
		if (exponent == NULL && strchr(buffer, '.') != NULL) {
			char* last = buffer + strlen(buffer) - 1;
			while (*last == '0')
				*last-- = '\0';
			if (*last == '.')
				*last = '\0';
		}
	}
	result = buffer;
	return true;
}
