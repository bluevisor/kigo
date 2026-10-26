// Every launchable app and preference panel, gathered from the Deskbar menu
// folders (system, packaged home, non-packaged) and the standard app folders.
#ifndef APP_INDEX_H
#define APP_INDEX_H

#include <vector>

#include <Entry.h>
#include <Locker.h>
#include <String.h>

#include "Result.h"

struct AppEntry {
	BString		name;
	BString		path;		// resolved, no symlinks
	BString		keywords;
	BString		category;	// "Application", "Preferences", "Demo", ...
	entry_ref	ref;
	bool		preference;
};

class AppIndex {
public:
	AppIndex();

	void Rebuild();
	// Rebuilds when the last scan is older than `maxAge`.
	void RefreshIfStale(bigtime_t maxAge);

	// Appends matching apps, scored, to `results`.
	void Search(const char* query, std::vector<Result>& results);

	// Finds an indexed app by resolved path (used to restore history items).
	bool Find(const char* path, AppEntry& entry);

	static Result MakeResult(const AppEntry& entry);

private:
	void _ScanMenu(const char* path, const char* category, int depth);
	void _ScanFolder(const char* path, const char* category, int depth);
	void _Add(const entry_ref& ref, const char* name, const char* category);

	BLocker					fLock;
	std::vector<AppEntry>	fEntries;
	bigtime_t				fLastScan;
};

#endif // APP_INDEX_H
