// Fuzzy matching in the spirit of Spotlight/Raycast: exact > prefix >
// word-start > acronym > substring > subsequence.
#ifndef FUZZY_H
#define FUZZY_H

// Returns 0 when `query` doesn't match `text`, otherwise a score where higher
// is better (exact match = 1000). Case-insensitive. Each space-separated word
// of the query must match.
float FuzzyScore(const char* query, const char* text);

#endif // FUZZY_H
