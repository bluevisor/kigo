#include "Fuzzy.h"

#include <ctype.h>
#include <string.h>

#include <String.h>


static bool
IsBoundary(const char* text, int i)
{
	if (i == 0)
		return true;
	unsigned char prev = text[i - 1];
	unsigned char cur = text[i];
	if (!isalnum(prev) && prev < 0x80)
		return true;
	// camelCase: "WebPositive" has a boundary at 'P'.
	if (islower(prev) && isupper(cur))
		return true;
	// "Haiku3D": letters to digits.
	if (isalpha(prev) && isdigit(cur))
		return true;
	return false;
}


static float
ScoreWord(const char* query, const char* text)
{
	BString lowerText(text);
	lowerText.ToLower();
	BString lowerQuery(query);
	lowerQuery.ToLower();
	const char* t = lowerText.String();
	const char* q = lowerQuery.String();
	int textLength = lowerText.Length();
	int queryLength = lowerQuery.Length();
	if (queryLength == 0)
		return 0;
	if (queryLength > textLength)
		return 0;

	if (strcmp(t, q) == 0)
		return 1000;
	if (strncmp(t, q, queryLength) == 0)
		return 900 - (textLength - queryLength) * 0.5f;

	// A later word starting with the query: "pos" in "WebPositive".
	for (int i = 1; i + queryLength <= textLength; i++) {
		if (IsBoundary(text, i) && strncmp(t + i, q, queryLength) == 0)
			return 800 - i;
	}

	// Acronym: "dc" -> "DeskCalc", "sm" -> "Software Manager".
	if (queryLength >= 2) {
		BString initials;
		for (int i = 0; i < textLength; i++) {
			if (IsBoundary(text, i) && isalnum((unsigned char)t[i]))
				initials += t[i];
		}
		if (initials.Length() >= queryLength
			&& strncmp(initials.String(), q, queryLength) == 0) {
			return 750 - (initials.Length() - queryLength) * 2;
		}
	}

	const char* found = strstr(t, q);
	if (found != NULL)
		return 600 - (found - t) * 2;

	// Subsequence with a penalty for each gap and a bonus for boundaries.
	float score = 400;
	int qi = 0;
	int last = -1;
	for (int i = 0; i < textLength && qi < queryLength; i++) {
		if (t[i] != q[qi])
			continue;
		if (last >= 0 && i != last + 1)
			score -= 6 + (i - last - 1);
		else if (last < 0)
			score -= i * 2;
		if (IsBoundary(text, i))
			score += 8;
		last = i;
		qi++;
	}
	if (qi < queryLength)
		return 0;
	return score < 50 ? 50 : score;
}


float
FuzzyScore(const char* query, const char* text)
{
	if (query == NULL || text == NULL || query[0] == '\0')
		return 0;

	if (strchr(query, ' ') == NULL)
		return ScoreWord(query, text);

	// A multi-word query matching the whole text as a phrase wins.
	float phrase = ScoreWord(query, text);
	if (phrase >= 600)
		return phrase;

	// Otherwise every word has to match somewhere.
	BString words(query);
	float total = 0;
	int count = 0;
	int32 start = 0;
	while (start < words.Length()) {
		int32 end = words.FindFirst(' ', start);
		if (end < 0)
			end = words.Length();
		if (end > start) {
			BString word;
			words.CopyInto(word, start, end - start);
			float score = ScoreWord(word.String(), text);
			if (score <= 0)
				return 0;
			total += score;
			count++;
		}
		start = end + 1;
	}
	if (count == 0)
		return 0;
	return total / count * 0.9f;
}
