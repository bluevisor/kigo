#include "Prefs.h"

#include <initializer_list>
#include <string.h>

#include <String.h>

#include "Settings.h"


const char* kWebSearchNames[kWebCount] = {"Off", "DuckDuckGo", "Google", "Bing"};
const char* kSizeNames[kSizeCount] = {"Small", "Default", "Large", "Larger"};

// How each choice is written in the settings file.
static const char* kWebSearchKeys[kWebCount] = {"off", "duckduckgo", "google", "bing"};
static const char* kSizeKeys[kSizeCount] = {"small", "default", "large", "larger"};
static const float kSizeScales[kSizeCount] = {0.88f, 1.0f, 1.15f, 1.3f};

static Prefs sPrefs;
static bool sLoaded = false;


static bool
ReadBool(const char* key, bool fallback)
{
	BString value = Settings::Get(key);
	if (value == "on")
		return true;
	if (value == "off")
		return false;
	return fallback;
}


static int32
ReadChoice(const char* key, const char* const* keys, int32 count, int32 fallback)
{
	BString value = Settings::Get(key);
	for (int32 i = 0; i < count; i++) {
		if (value == keys[i])
			return i;
	}
	return fallback;
}


// The field in Prefs that a settings key names, if it's a switch.
static bool*
Switch(Prefs& prefs, const char* key)
{
	if (strcmp(key, "search_apps") == 0)
		return &prefs.searchApps;
	if (strcmp(key, "search_files") == 0)
		return &prefs.searchFiles;
	if (strcmp(key, "search_commands") == 0)
		return &prefs.searchCommands;
	if (strcmp(key, "calculator") == 0)
		return &prefs.calculator;
	if (strcmp(key, "suggestions") == 0)
		return &prefs.suggestions;
	if (strcmp(key, "autostart") == 0)
		return &prefs.autostart;
	if (strcmp(key, "updates") == 0)
		return &prefs.updates;
	return NULL;
}


const Prefs&
Prefs::Get()
{
	if (!sLoaded) {
		Prefs defaults;
		for (const char* key : {"search_apps", "search_files", "search_commands",
				"calculator", "suggestions", "autostart", "updates"}) {
			*Switch(sPrefs, key) = ReadBool(key, *Switch(defaults, key));
		}
		sPrefs.webSearch = ReadChoice("web_search", kWebSearchKeys, kWebCount,
			defaults.webSearch);
		sPrefs.size = ReadChoice("size", kSizeKeys, kSizeCount, defaults.size);
		sLoaded = true;
	}
	return sPrefs;
}


void
Prefs::Set(const char* key, bool on)
{
	Get();
	if (bool* field = Switch(sPrefs, key)) {
		*field = on;
		Settings::Set(key, on ? "on" : "off");
	}
}


void
Prefs::SetChoice(const char* key, int32 choice)
{
	Get();
	if (strcmp(key, "web_search") == 0 && choice >= 0 && choice < kWebCount) {
		sPrefs.webSearch = choice;
		Settings::Set(key, kWebSearchKeys[choice]);
	} else if (strcmp(key, "size") == 0 && choice >= 0 && choice < kSizeCount) {
		sPrefs.size = choice;
		Settings::Set(key, kSizeKeys[choice]);
	}
}


float
Prefs::SizeScale() const
{
	return kSizeScales[size];
}


const char*
Prefs::WebSearchName() const
{
	return kWebSearchNames[webSearch];
}


void
Prefs::WebSearchURL(const char* encodedQuery, BString& url) const
{
	switch (webSearch) {
		case kWebGoogle:
			url.SetToFormat("https://www.google.com/search?q=%s", encodedQuery);
			break;
		case kWebBing:
			url.SetToFormat("https://www.bing.com/search?q=%s", encodedQuery);
			break;
		default:
			url.SetToFormat("https://duckduckgo.com/?q=%s", encodedQuery);
			break;
	}
}
