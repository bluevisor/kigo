// What the user picked in Kigo's settings panel, read once and kept in
// memory; each change is saved to ~/config/settings/Kigo/settings at once.
#ifndef PREFS_H
#define PREFS_H

#include <SupportDefs.h>

enum WebSearch {
	kWebOff,
	kWebDuckDuckGo,
	kWebGoogle,
	kWebBing,
	kWebCount,
};

enum SizeChoice {
	kSizeSmall,
	kSizeDefault,
	kSizeLarge,
	kSizeLarger,
	kSizeCount,
};

struct Prefs {
	bool	searchApps = true;
	bool	searchFiles = true;
	bool	searchCommands = true;
	bool	calculator = true;
	bool	suggestions = true;
	int32	webSearch = kWebDuckDuckGo;
	int32	size = kSizeDefault;
	bool	autostart = true;
	bool	updates = true;

	static const Prefs& Get();
	// Changes one setting and saves it.
	static void Set(const char* key, bool on);
	static void SetChoice(const char* key, int32 choice);

	// How much bigger than the system font everything is drawn.
	float SizeScale() const;
	const char* WebSearchName() const;
	// The search URL for an already-encoded query.
	void WebSearchURL(const char* encodedQuery, class BString& url) const;
};

extern const char* kWebSearchNames[kWebCount];
extern const char* kSizeNames[kSizeCount];

#endif // PREFS_H
