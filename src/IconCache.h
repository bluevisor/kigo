// Tracker icons for result rows, cached by path or app signature.
#ifndef ICON_CACHE_H
#define ICON_CACHE_H

#include <map>

#include <Locker.h>
#include <String.h>

class BBitmap;
struct entry_ref;

class IconCache {
public:
	static IconCache& Get();

	void SetIconSize(int32 size);
	int32 IconSize() const { return fSize; }

	// The returned bitmaps live as long as the cache; callers don't free them.
	BBitmap* ForRef(const entry_ref& ref);
	BBitmap* ForPath(const char* path);
	BBitmap* ForSignature(const char* signature);
	BBitmap* ForMimeType(const char* type);

private:
	IconCache();

	void _Clear();

	BLocker							fLock;
	std::map<BString, BBitmap*>		fIcons;
	int32							fSize;
};

#endif // ICON_CACHE_H
