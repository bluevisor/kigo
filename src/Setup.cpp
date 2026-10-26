#include "Setup.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include <Application.h>
#include <Directory.h>
#include <Entry.h>
#include <File.h>
#include <FindDirectory.h>
#include <Path.h>
#include <Roster.h>
#include <String.h>


static BPath
AppPath()
{
	app_info info;
	be_app->GetAppInfo(&info);
	return BPath(&info.ref);
}


// The filter shipped with this Kigo: in a package it's data/kigo/KigoHotkey,
// next to a development build it's build/KigoHotkey.
static bool
BundledFilter(BPath& filter)
{
	BPath app = AppPath();
	BPath folder;
	if (app.GetParent(&folder) != B_OK)
		return false;

	BPath beside(folder.Path(), "KigoHotkey");
	if (BEntry(beside.Path()).Exists()) {
		filter = beside;
		return true;
	}
	BPath packaged(folder.Path(), "../data/kigo/KigoHotkey");
	if (BEntry(packaged.Path()).Exists()) {
		filter = packaged;
		return true;
	}
	return false;
}


static bool
SameContents(const char* a, const char* b)
{
	BFile first(a, B_READ_ONLY);
	BFile second(b, B_READ_ONLY);
	off_t sizeA, sizeB;
	if (first.InitCheck() != B_OK || second.InitCheck() != B_OK
		|| first.GetSize(&sizeA) != B_OK || second.GetSize(&sizeB) != B_OK
		|| sizeA != sizeB) {
		return false;
	}
	char bufferA[16384];
	char bufferB[16384];
	for (;;) {
		ssize_t readA = first.Read(bufferA, sizeof(bufferA));
		ssize_t readB = second.Read(bufferB, sizeof(bufferB));
		if (readA != readB)
			return false;
		if (readA <= 0)
			return readA == 0;
		if (memcmp(bufferA, bufferB, readA) != 0)
			return false;
	}
}


static bool
CopyFile(const char* from, const char* to)
{
	BFile source(from, B_READ_ONLY);
	BFile target(to, B_WRITE_ONLY | B_CREATE_FILE | B_ERASE_FILE);
	if (source.InitCheck() != B_OK || target.InitCheck() != B_OK)
		return false;
	char buffer[16384];
	ssize_t read;
	while ((read = source.Read(buffer, sizeof(buffer))) > 0) {
		if (target.Write(buffer, read) != read)
			return false;
	}
	target.SetPermissions(0755);
	return read == 0;
}


static void
InstallFilter()
{
	BPath bundled;
	if (!BundledFilter(bundled))
		return;

	BPath folder;
	if (find_directory(B_USER_NONPACKAGED_ADDONS_DIRECTORY, &folder, true)
			!= B_OK) {
		return;
	}
	folder.Append("input_server");
	BPath filters(folder.Path(), "filters");
	create_directory(filters.Path(), 0755);
	BPath installed(filters.Path(), "KigoHotkey");

	if (SameContents(bundled.Path(), installed.Path()))
		return;

	// Never rewrite the installed filter in place: the input_server has it
	// mapped, and changing the mapped file crashed the input_server (no
	// keyboard or mouse). A rename leaves the old file alive until the
	// input_server unloads it; the temporary copy sits outside the watched
	// filters folder so it's never loaded half-written.
	BPath temp(folder.Path(), ".KigoHotkey.new");
	if (!CopyFile(bundled.Path(), temp.Path())
		|| rename(temp.Path(), installed.Path()) != 0) {
		unlink(temp.Path());
	}
}


static void
InstallAutostart()
{
	BString app(AppPath().Path());
	// Only an installed Kigo starts at login, not a development build.
	if (app.FindFirst("/build/") >= 0)
		return;

	BPath script;
	if (find_directory(B_USER_SETTINGS_DIRECTORY, &script) != B_OK)
		return;
	script.Append("boot/UserBootscript");

	BString contents;
	BFile file(script.Path(), B_READ_ONLY);
	off_t size = 0;
	if (file.InitCheck() == B_OK && file.GetSize(&size) == B_OK && size > 0) {
		char* buffer = contents.LockBuffer(size + 1);
		ssize_t read = file.Read(buffer, size);
		contents.UnlockBuffer(read > 0 ? read : 0);
	}
	file.Unset();
	if (contents.FindFirst("Kigo --background") >= 0)
		return;

	FILE* out = fopen(script.Path(), "a");
	if (out == NULL)
		return;
	fprintf(out, "\n# Kigo launcher (Alt+Space)\n"
		"\"%s\" --background > /dev/null 2>&1 &\n", app.String());
	fclose(out);
}


void
Setup::Run()
{
	InstallFilter();
	InstallAutostart();
}
