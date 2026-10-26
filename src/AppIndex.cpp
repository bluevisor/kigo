#include "AppIndex.h"

#include <set>
#include <strings.h>

#include <AppFileInfo.h>
#include <Autolock.h>
#include <Directory.h>
#include <File.h>
#include <FindDirectory.h>
#include <NodeInfo.h>
#include <OS.h>
#include <Path.h>

#include "Fuzzy.h"
#include "IconCache.h"


// Extra words people search for, Spotlight-style ("browser" finds WebPositive).
static const struct {
	const char* name;
	const char* keywords;
} kKeywords[] = {
	{"Terminal", "shell console command line bash cli"},
	{"WebPositive", "browser web internet"},
	{"Chromium", "browser web internet chrome google"},
	{"StyledEdit", "text editor notepad notes"},
	{"Pe", "text editor code"},
	{"DeskCalc", "calculator math"},
	{"ShowImage", "image viewer photos pictures"},
	{"MediaPlayer", "video music movie player"},
	{"ActivityMonitor", "task manager cpu memory performance"},
	{"ProcessController", "task manager cpu memory kill"},
	{"Expander", "unzip archive extract zip"},
	{"DiskUsage", "storage space disk"},
	{"DriveSetup", "partition format disk drive"},
	{"DiskProbe", "hex editor"},
	{"CharacterMap", "emoji symbols unicode glyphs"},
	{"Devices", "hardware pci usb"},
	{"AboutSystem", "about version system info"},
	{"Appearance", "theme colors fonts dark mode look"},
	{"Backgrounds", "wallpaper desktop picture"},
	{"Deskbar", "taskbar menu"},
	{"FileTypes", "mime file associations"},
	{"Input", "mouse keyboard touchpad pointer"},
	{"Keymap", "keyboard layout"},
	{"Locale", "language region date format"},
	{"Network", "wifi wireless ethernet internet ip dns"},
	{"Notifications", "alerts"},
	{"Screen", "display resolution monitor refresh"},
	{"Shortcuts", "hotkeys keyboard bindings"},
	{"Time", "clock date timezone ntp"},
	{"Tracker", "files file manager finder"},
	{"VirtualMemory", "swap"},
	{"Sounds", "audio beep"},
	{"Media", "audio sound volume output speakers"},
	{"Printers", "print"},
	{"SoftwareUpdater", "update upgrade"},
	{"HaikuDepot", "app store install packages software"},
	{"Temino", "terminal shell console"},
	{"Haiku Code", "editor code ai"},
};


static const char*
KeywordsFor(const char* name)
{
	for (const auto& entry : kKeywords) {
		if (strcmp(entry.name, name) == 0)
			return entry.keywords;
	}
	return "";
}


static bool
IsApplication(const entry_ref& ref)
{
	BNode node(&ref);
	BNodeInfo info(&node);
	char type[B_MIME_TYPE_LENGTH];
	if (info.GetType(type) != B_OK)
		return false;
	// MIME types are case-insensitive, and packaged apps such as Temino are
	// typed "application/x-vnd.be-elfexecutable".
	return strcasecmp(type, "application/x-vnd.Be-elfexecutable") == 0
		|| strcasecmp(type, B_APP_MIME_TYPE) == 0;
}


AppIndex::AppIndex()
	:
	fLock("app index"),
	fLastScan(0)
{
}


void
AppIndex::RefreshIfStale(bigtime_t maxAge)
{
	if (system_time() - fLastScan > maxAge)
		Rebuild();
}


void
AppIndex::Rebuild()
{
	BAutolock _(fLock);
	fEntries.clear();

	// Deskbar menus first: they carry the names users see.
	static const directory_which kMenus[] = {
		B_SYSTEM_DATA_DIRECTORY,
		B_USER_DATA_DIRECTORY,
		B_USER_NONPACKAGED_DATA_DIRECTORY,
		B_SYSTEM_NONPACKAGED_DATA_DIRECTORY,
	};
	for (directory_which which : kMenus) {
		BPath path;
		if (find_directory(which, &path) != B_OK)
			continue;
		path.Append("deskbar/menu");
		_ScanMenu(path.Path(), NULL, 0);
	}
	BPath userMenu;
	if (find_directory(B_USER_SETTINGS_DIRECTORY, &userMenu) == B_OK) {
		userMenu.Append("deskbar/menu");
		_ScanMenu(userMenu.Path(), NULL, 0);
	}

	// Then anything installed but not in a menu.
	static const struct {
		directory_which which;
		const char* subdirectory;
		const char* category;
	} kFolders[] = {
		{B_SYSTEM_APPS_DIRECTORY, NULL, "Application"},
		{B_SYSTEM_PREFERENCES_DIRECTORY, NULL, "Preferences"},
		{B_USER_APPS_DIRECTORY, NULL, "Application"},
		{B_USER_NONPACKAGED_DIRECTORY, "apps", "Application"},
		{B_SYSTEM_NONPACKAGED_DIRECTORY, "apps", "Application"},
	};
	for (const auto& folder : kFolders) {
		BPath path;
		if (find_directory(folder.which, &path) != B_OK)
			continue;
		if (folder.subdirectory != NULL)
			path.Append(folder.subdirectory);
		_ScanFolder(path.Path(), folder.category, 0);
	}

	fLastScan = system_time();
}


void
AppIndex::_ScanMenu(const char* path, const char* category, int depth)
{
	BDirectory directory(path);
	if (directory.InitCheck() != B_OK || depth > 3)
		return;

	BEntry entry;
	while (directory.GetNextEntry(&entry, false) == B_OK) {
		char name[B_FILE_NAME_LENGTH];
		entry.GetName(name);
		BPath entryPath;
		entry.GetPath(&entryPath);

		BEntry resolved(entryPath.Path(), true);
		if (resolved.IsDirectory()) {
			// Top-level folders name the category ("Preferences", "Demos").
			BString sub(category != NULL ? category : name);
			if (sub == "Applications")
				sub = "Application";
			else if (sub == "Demos")
				sub = "Demo";
			else if (sub == "Desktop applets")
				sub = "Desktop applet";
			_ScanMenu(entryPath.Path(), sub.String(), depth + 1);
			continue;
		}

		// Anything Deskbar lists is launchable, including scripts like
		// "Haiku Code", so menu entries skip the executable check.
		entry_ref ref;
		if (resolved.Exists() && resolved.GetRef(&ref) == B_OK)
			_Add(ref, name, category != NULL ? category : "Application");
	}
}


void
AppIndex::_ScanFolder(const char* path, const char* category, int depth)
{
	BDirectory directory(path);
	if (directory.InitCheck() != B_OK || depth > 1)
		return;

	BEntry entry;
	while (directory.GetNextEntry(&entry, true) == B_OK) {
		if (entry.IsDirectory()) {
			BPath sub;
			entry.GetPath(&sub);
			_ScanFolder(sub.Path(), category, depth + 1);
			continue;
		}
		entry_ref ref;
		if (entry.GetRef(&ref) == B_OK && IsApplication(ref))
			_Add(ref, ref.name, category);
	}
}


void
AppIndex::_Add(const entry_ref& ref, const char* name, const char* category)
{
	BPath path(&ref);
	for (const AppEntry& existing : fEntries) {
		if (existing.path == path.Path())
			return;
	}

	AppEntry entry;
	entry.name = name;
	entry.path = path.Path();
	entry.ref = ref;
	entry.category = category;
	entry.preference = entry.category == "Preferences";
	entry.keywords = KeywordsFor(name);
	if (entry.keywords.IsEmpty())
		entry.keywords = KeywordsFor(ref.name);
	if (entry.preference)
		entry.keywords << " settings preferences";
	fEntries.push_back(entry);
}


Result
AppIndex::MakeResult(const AppEntry& entry)
{
	Result result;
	result.kind = entry.preference ? kKindPreference : kKindApp;
	result.title = entry.name;
	// The kind label already says "Application"; only say what's unusual.
	if (entry.category != "Application" && entry.category != "Preferences")
		result.subtitle = entry.category;
	result.id.SetToFormat("app:%s", entry.path.String());
	result.ref = entry.ref;
	result.hasRef = true;
	result.icon = IconCache::Get().ForRef(entry.ref);
	return result;
}


void
AppIndex::Search(const char* query, std::vector<Result>& results)
{
	BAutolock _(fLock);
	for (const AppEntry& entry : fEntries) {
		float score = FuzzyScore(query, entry.name.String());
		if (score <= 0 && !entry.keywords.IsEmpty()) {
			// Match single keywords so "web" finds browsers; whole-word
			// prefixes only, so short queries don't light up everything.
			BString words(entry.keywords);
			int32 start = 0;
			while (start < words.Length()) {
				int32 end = words.FindFirst(' ', start);
				if (end < 0)
					end = words.Length();
				BString word;
				words.CopyInto(word, start, end - start);
				float keywordScore = FuzzyScore(query, word.String());
				if (keywordScore >= 800 && keywordScore * 0.7f > score)
					score = keywordScore * 0.7f;
				start = end + 1;
			}
		}
		if (score <= 0)
			continue;

		Result result = MakeResult(entry);
		// Apps outrank preferences outrank applets and demos at equal match
		// quality (files rank lower still).
		float bonus = 10;
		if (entry.category == "Application")
			bonus = 40;
		else if (entry.preference)
			bonus = 30;
		result.score = score + bonus;
		results.push_back(result);
	}
}


bool
AppIndex::Find(const char* path, AppEntry& found)
{
	BAutolock _(fLock);
	for (const AppEntry& entry : fEntries) {
		if (entry.path == path) {
			found = entry;
			return true;
		}
	}
	return false;
}
