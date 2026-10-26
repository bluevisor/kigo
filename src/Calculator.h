// Inline calculator, like typing "2^10/3" into Spotlight or Raycast.
#ifndef CALCULATOR_H
#define CALCULATOR_H

#include <String.h>

// True when `input` looks like arithmetic rather than a search, and it
// evaluates cleanly. `result` gets the formatted value.
bool Calculate(const char* input, BString& result);

#endif // CALCULATOR_H
