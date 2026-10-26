#include "History.h"

#include <algorithm>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include <Directory.h>
#include <File.h>
#include <FindDirectory.h>
#include <Path.h>


static const int32 kMaxItems = 300;


static BPath
HistoryPath()
{
	BPath path;
	find_directory(B_USER_SETTINGS_DIRECTORY, &path, true);
	path.Append("Kigo");
	create_directory(path.Path(), 0755);
	path.Append("history");
	return path;
}


History::History()
{
}


void
History::Load()
{
	fItems.clear();
	FILE* file = fopen(HistoryPath().Path(), "r");
	if (file == NULL)
		return;

	// One item per line: count<TAB>last-used<TAB>id<TAB>title
	char line[2048];
	while (fgets(line, sizeof(line), file) != NULL) {
		BString text(line);
		text.RemoveAll("\n");
		int32 tab1 = text.FindFirst('\t');
		int32 tab2 = tab1 < 0 ? -1 : text.FindFirst('\t', tab1 + 1);
		int32 tab3 = tab2 < 0 ? -1 : text.FindFirst('\t', tab2 + 1);
		if (tab3 < 0)
			continue;
		BString count, used, id, title;
		text.CopyInto(count, 0, tab1);
		text.CopyInto(used, tab1 + 1, tab2 - tab1 - 1);
		text.CopyInto(id, tab2 + 1, tab3 - tab2 - 1);
		text.CopyInto(title, tab3 + 1, text.Length() - tab3 - 1);
		HistoryItem item;
		item.count = atoi(count.String());
		item.lastUsed = (time_t)atoll(used.String());
		item.title = title;
		fItems[id] = item;
	}
	fclose(file);
}


void
History::Save()
{
	BPath path = HistoryPath();
	BString temp(path.Path());
	temp << ".new";
	FILE* file = fopen(temp.String(), "w");
	if (file == NULL)
		return;
	for (const auto& entry : fItems) {
		fprintf(file, "%" B_PRId32 "\t%lld\t%s\t%s\n", entry.second.count,
			(long long)entry.second.lastUsed, entry.first.String(),
			entry.second.title.String());
	}
	fclose(file);
	rename(temp.String(), path.Path());
}


float
History::_Frecency(const HistoryItem& item, time_t now) const
{
	double days = difftime(now, item.lastUsed) / 86400.0;
	if (days < 0)
		days = 0;
	// Recent use counts for more; a week-old launch is worth about half.
	return (float)(log2(1.0 + item.count) / (1.0 + days / 7.0));
}


void
History::Record(const char* id, const char* title)
{
	HistoryItem& item = fItems[id];
	item.count++;
	item.lastUsed = time(NULL);
	item.title = title;

	if ((int32)fItems.size() > kMaxItems) {
		// Forget the stalest entry.
		time_t now = time(NULL);
		auto worst = fItems.begin();
		for (auto it = fItems.begin(); it != fItems.end(); ++it) {
			if (_Frecency(it->second, now) < _Frecency(worst->second, now))
				worst = it;
		}
		fItems.erase(worst);
	}
	Save();
}


float
History::Boost(const char* id) const
{
	auto found = fItems.find(id);
	if (found == fItems.end())
		return 0;
	return _Frecency(found->second, time(NULL)) * 60;
}


std::vector<BString>
History::Top(int32 count) const
{
	time_t now = time(NULL);
	std::vector<std::pair<float, BString>> ranked;
	for (const auto& entry : fItems)
		ranked.push_back({_Frecency(entry.second, now), entry.first});
	std::sort(ranked.begin(), ranked.end(),
		[](const auto& a, const auto& b) { return a.first > b.first; });

	std::vector<BString> ids;
	for (const auto& entry : ranked) {
		if ((int32)ids.size() >= count)
			break;
		ids.push_back(entry.second);
	}
	return ids;
}
