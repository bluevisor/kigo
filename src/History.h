// Launch history for frecency ranking (frequency x recency, like Raycast) and
// the suggestions shown before typing. Saved in ~/config/settings/Kigo.
#ifndef HISTORY_H
#define HISTORY_H

#include <map>
#include <vector>

#include <String.h>

struct HistoryItem {
	int32		count = 0;
	time_t		lastUsed = 0;
	BString		title;
};

class History {
public:
	History();

	void Load();
	void Save();

	void Record(const char* id, const char* title);
	// Bonus added to a result's match score.
	float Boost(const char* id) const;
	// Ids by frecency, best first.
	std::vector<BString> Top(int32 count) const;

private:
	float _Frecency(const HistoryItem& item, time_t now) const;

	std::map<BString, HistoryItem>	fItems;
};

#endif // HISTORY_H
