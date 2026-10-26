#include "IconCache.h"

#include <string.h>

#include <Autolock.h>
#include <Bitmap.h>
#include <Entry.h>
#include <IconUtils.h>
#include <MimeType.h>
#include <NodeInfo.h>
#include <Path.h>
#include <Roster.h>


IconCache&
IconCache::Get()
{
	static IconCache sCache;
	return sCache;
}


IconCache::IconCache()
	:
	fLock("icon cache"),
	fSize(32)
{
}


void
IconCache::SetIconSize(int32 size)
{
	BAutolock _(fLock);
	if (size == fSize)
		return;
	_Clear();
	fSize = size;
}


void
IconCache::_Clear()
{
	for (auto& entry : fIcons)
		delete entry.second;
	fIcons.clear();
}


BBitmap*
IconCache::ForRef(const entry_ref& ref)
{
	BPath path(&ref);
	if (path.InitCheck() != B_OK)
		return NULL;

	BAutolock _(fLock);
	BString key("path:");
	key << path.Path();
	auto found = fIcons.find(key);
	if (found != fIcons.end())
		return found->second;

	BBitmap* icon = new BBitmap(BRect(0, 0, fSize - 1, fSize - 1), B_RGBA32);
	if (BNodeInfo::GetTrackerIcon(&ref, icon, (icon_size)fSize) != B_OK) {
		delete icon;
		icon = NULL;
	}
	fIcons[key] = icon;
	return icon;
}


BBitmap*
IconCache::ForPath(const char* path)
{
	entry_ref ref;
	if (get_ref_for_path(path, &ref) != B_OK)
		return NULL;
	return ForRef(ref);
}


BBitmap*
IconCache::ForSignature(const char* signature)
{
	entry_ref ref;
	if (be_roster->FindApp(signature, &ref) == B_OK) {
		if (BBitmap* icon = ForRef(ref))
			return icon;
	}

	// Running apps (Kigo itself, for one) are known by team.
	app_info info;
	if (be_roster->GetAppInfo(signature, &info) == B_OK) {
		if (BBitmap* icon = ForRef(info.ref))
			return icon;
	}

	// The roster can't always resolve system apps (no app hint in the MIME
	// database), so try where they live.
	static const char* kFolders[] = {
		"/boot/system/apps/", "/boot/system/preferences/", "/boot/system/",
	};
	static const struct {
		const char* signature;
		const char* name;
	} kKnown[] = {
		{"application/x-vnd.Haiku-Terminal", "Terminal"},
		{"application/x-vnd.Haiku-DeskCalc", "DeskCalc"},
		{"application/x-vnd.Be-WORK", "Workspaces"},
		{"application/x-vnd.Be-TSKB", "Deskbar"},
		{"application/x-vnd.Be-TRAK", "Tracker"},
	};
	for (const auto& known : kKnown) {
		if (strcmp(known.signature, signature) != 0)
			continue;
		for (const char* folder : kFolders) {
			BString path(folder);
			path << known.name;
			BEntry entry(path.String());
			if (entry.Exists() && entry.GetRef(&ref) == B_OK)
				return ForRef(ref);
		}
	}
	return ForMimeType(signature);
}


BBitmap*
IconCache::ForMimeType(const char* type)
{
	BAutolock _(fLock);
	BString key("mime:");
	key << type;
	auto found = fIcons.find(key);
	if (found != fIcons.end())
		return found->second;

	BBitmap* icon = new BBitmap(BRect(0, 0, fSize - 1, fSize - 1), B_RGBA32);
	BMimeType mime(type);
	uint8* data = NULL;
	size_t size = 0;
	bool ok = false;
	if (mime.GetIcon(&data, &size) == B_OK) {
		ok = BIconUtils::GetVectorIcon(data, size, icon) == B_OK;
		delete[] data;
	}
	if (!ok) {
		// Fall back to the icon of the type's super type ("text" for
		// "text/plain"), which every installed type has.
		BMimeType super;
		if (mime.GetSupertype(&super) == B_OK
			&& super.GetIcon(&data, &size) == B_OK) {
			ok = BIconUtils::GetVectorIcon(data, size, icon) == B_OK;
			delete[] data;
		}
	}
	if (!ok) {
		delete icon;
		icon = NULL;
	}
	fIcons[key] = icon;
	return icon;
}
