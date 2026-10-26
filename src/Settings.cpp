#include "Settings.h"

#include <stdio.h>

#include <Autolock.h>
#include <Directory.h>
#include <FindDirectory.h>
#include <Locker.h>
#include <Path.h>
#include <StringList.h>


static BLocker sLock("kigo settings");


BString
Settings::Folder()
{
	BPath path;
	find_directory(B_USER_SETTINGS_DIRECTORY, &path, true);
	path.Append("Kigo");
	create_directory(path.Path(), 0755);
	return path.Path();
}


static BString
SettingsPath()
{
	BString path = Settings::Folder();
	path << "/settings";
	return path;
}


static void
ReadLines(BStringList& lines)
{
	FILE* file = fopen(SettingsPath().String(), "r");
	if (file == NULL)
		return;
	char line[1024];
	while (fgets(line, sizeof(line), file) != NULL) {
		BString text(line);
		text.RemoveAll("\n");
		if (!text.IsEmpty())
			lines.Add(text);
	}
	fclose(file);
}


BString
Settings::Get(const char* key)
{
	BAutolock _(sLock);
	BStringList lines;
	ReadLines(lines);
	BString prefix(key);
	prefix << '=';
	for (int32 i = 0; i < lines.CountStrings(); i++) {
		if (lines.StringAt(i).StartsWith(prefix))
			return BString(lines.StringAt(i).String() + prefix.Length());
	}
	return "";
}


void
Settings::Set(const char* key, const char* value)
{
	BAutolock _(sLock);
	BStringList lines;
	ReadLines(lines);
	BString prefix(key);
	prefix << '=';
	BString entry(prefix);
	entry << value;
	bool replaced = false;
	for (int32 i = 0; i < lines.CountStrings(); i++) {
		if (lines.StringAt(i).StartsWith(prefix)) {
			lines.Replace(i, entry);
			replaced = true;
		}
	}
	if (!replaced)
		lines.Add(entry);

	BString path = SettingsPath();
	BString temp(path);
	temp << ".new";
	FILE* file = fopen(temp.String(), "w");
	if (file == NULL)
		return;
	for (int32 i = 0; i < lines.CountStrings(); i++)
		fprintf(file, "%s\n", lines.StringAt(i).String());
	fclose(file);
	rename(temp.String(), path.String());
}
