#include "Updater.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <AppFileInfo.h>
#include <Application.h>
#include <Directory.h>
#include <File.h>
#include <FindDirectory.h>
#include <Notification.h>
#include <OS.h>
#include <Path.h>
#include <Roster.h>
#include <String.h>
#include <StringList.h>

#include "Kigo.h"
#include "Settings.h"


static const char* kLatest
	= "https://api.github.com/repos/bluevisor/kigo/releases/latest";
static const char* kReleases = "https://github.com/bluevisor/kigo/releases";
static const time_t kDay = 24 * 60 * 60;


static const char*
AssetSuffix()
{
#if defined(__aarch64__)
	return "-arm64.hpkg";
#elif defined(__x86_64__)
	return "-x86_64.hpkg";
#elif defined(__i386__)
	return "-x86_gcc2.hpkg";
#elif defined(__riscv)
	return "-riscv64.hpkg";
#else
	return NULL;
#endif
}


static void
Notify(const char* title, const char* text, bool error = false)
{
	BNotification notification(error ? B_ERROR_NOTIFICATION
		: B_INFORMATION_NOTIFICATION);
	notification.SetGroup("Kigo");
	notification.SetTitle(title);
	notification.SetContent(text);
	notification.SetMessageID("kigo-update");
	notification.Send();
}


// Runs a program and waits; true when it exits 0. No shell, no fork.
static bool
RunAndWait(const char** argv)
{
	int argc = 0;
	while (argv[argc] != NULL)
		argc++;
	thread_id team = load_image(argc, argv, (const char**)environ);
	if (team < 0)
		return false;
	status_t result = B_ERROR;
	resume_thread(team);
	wait_for_thread(team, &result);
	return result == 0;
}


static bool
ReadFile(const char* path, BString& text)
{
	BFile file(path, B_READ_ONLY);
	off_t size;
	if (file.InitCheck() != B_OK || file.GetSize(&size) != B_OK || size > 4 << 20)
		return false;
	char* buffer = text.LockBuffer(size + 1);
	ssize_t read = file.Read(buffer, size);
	text.UnlockBuffer(read > 0 ? read : 0);
	return read == size;
}


// Every string value of "key" in a JSON document; enough for GitHub's answer.
static void
JsonStrings(const BString& json, const char* key, BStringList& out)
{
	BString needle;
	needle << '"' << key << '"';
	int32 at = 0;
	while ((at = json.FindFirst(needle, at)) >= 0) {
		at += needle.Length();
		while (at < json.Length() && (json[at] == ' ' || json[at] == '\n'
				|| json[at] == '\r' || json[at] == '\t' || json[at] == ':')) {
			at++;
		}
		if (at >= json.Length() || json[at] != '"')
			continue;
		int32 end = json.FindFirst('"', at + 1);
		if (end < 0)
			break;
		BString value;
		json.CopyInto(value, at + 1, end - at - 1);
		out.Add(value);
		at = end + 1;
	}
}


// Whether dotted version `a` is past `b`.
static bool
IsNewer(const char* a, const char* b)
{
	while (*a != '\0' || *b != '\0') {
		long x = strtol(a, (char**)&a, 10);
		long y = strtol(b, (char**)&b, 10);
		if (x != y)
			return x > y;
		if (*a == '.')
			a++;
		if (*b == '.')
			b++;
		if ((*a != '\0' && !isdigit(*a)) || (*b != '\0' && !isdigit(*b)))
			break;
	}
	return false;
}


// The packages folder Kigo was installed from, or "" for a loose build.
static BString
PackagesFolder()
{
	app_info info;
	if (be_app->GetAppInfo(&info) != B_OK)
		return "";
	BPath path(&info.ref);
	BString app(path.Path());
	if (app.StartsWith("/boot/home/config/apps/"))
		return "/boot/home/config/packages";
	if (app.StartsWith("/boot/system/apps/"))
		return "/boot/system/packages";
	return "";
}


static status_t
CheckThread(void* data)
{
	bool manual = data != NULL;

	const char* suffix = AssetSuffix();
	if (suffix == NULL) {
		if (manual)
			Notify("Can't update Kigo", "There are no builds for this system.", true);
		return B_ERROR;
	}

	BPath dir;
	find_directory(B_USER_SETTINGS_DIRECTORY, &dir);
	dir.Append("Kigo/update");
	BString folder(dir.Path());
	const char* cleanup[] = {"/bin/rm", "-rf", folder.String(), NULL};
	RunAndWait(cleanup);
	create_directory(folder.String(), 0755);

	BString json(folder);
	json << "/latest.json";
	const char* query[] = {"/bin/curl", "-fsSL", "--max-time", "30", "-H",
		"Accept: application/vnd.github+json", "-o", json.String(), kLatest,
		NULL};
	BString text;
	if (!RunAndWait(query) || !ReadFile(json.String(), text)) {
		if (manual)
			Notify("Can't check for updates", "Couldn't reach GitHub.", true);
		return B_ERROR;
	}

	BStringList tags, urls;
	JsonStrings(text, "tag_name", tags);
	JsonStrings(text, "browser_download_url", urls);
	if (tags.IsEmpty()) {
		if (manual)
			Notify("Can't check for updates", "No Kigo release found.", true);
		return B_ERROR;
	}
	BString version(tags.StringAt(0));
	if (version.StartsWith("v"))
		version.Remove(0, 1);

	if (!IsNewer(version.String(), KIGO_VERSION)) {
		if (manual) {
			BString message;
			message.SetToFormat("Kigo %s is the latest version.", KIGO_VERSION);
			Notify("Kigo is up to date", message.String());
		}
		return B_OK;
	}

	BString url;
	for (int32 i = 0; i < urls.CountStrings(); i++) {
		if (urls.StringAt(i).EndsWith(suffix)) {
			url = urls.StringAt(i);
			break;
		}
	}
	BString packages = PackagesFolder();
	if (url.IsEmpty() || packages.IsEmpty()) {
		// No package for this system, or a loose build that isn't ours to
		// replace: point at the release instead.
		BString message;
		message.SetToFormat("Kigo %s is available at %s", version.String(),
			kReleases);
		Notify("Kigo update available", message.String());
		return B_OK;
	}

	BString package(folder);
	package << '/' << url.String() + url.FindLast('/') + 1;
	const char* download[] = {"/bin/curl", "-fsSL", "--max-time", "600", "-o",
		package.String(), url.String(), NULL};
	BString magic;
	if (!RunAndWait(download) || !ReadFile(package.String(), magic)
		|| !magic.StartsWith("hpkg")) {
		if (manual)
			Notify("Can't update Kigo", "The download failed.", true);
		return B_ERROR;
	}

	BString message;
	message.SetToFormat("Installing Kigo %s.", version.String());
	Notify("Updating Kigo", message.String());

	// A shell that outlives Kigo swaps the packages once Kigo has quit,
	// then starts the new Kigo, hidden.
	BString script;
	script.SetToFormat("sleep 1; for old in \"%s\"/kigo-*.hpkg; do "
		"rm -f \"$old\"; done; mv \"%s\" \"%s\"/ && rm -rf \"%s\"; sleep 3; "
		"\"%s/../apps/Kigo\" --background --updated > /dev/null 2>&1 &",
		packages.String(), package.String(), packages.String(),
		folder.String(), packages.String());
	const char* swap[] = {"/bin/sh", "-c", script.String(), NULL};
	thread_id team = load_image(3, swap, (const char**)environ);
	if (team < 0) {
		Notify("Can't update Kigo", "Couldn't start the installer.", true);
		return B_ERROR;
	}
	resume_thread(team);
	// Quit now: a package swap doesn't always stop the running copy, and
	// the new Kigo must be the one that answers Alt+Space.
	be_app->PostMessage(B_QUIT_REQUESTED);
	return B_OK;
}


void
Updater::Check(bool manual)
{
	if (!manual) {
		time_t now = time(NULL);
		time_t last = (time_t)atoll(Settings::Get("update_checked").String());
		// The VM clock can start at 1970; don't record a bogus time.
		if (now < 1700000000 || now - last < kDay)
			return;
		BString value;
		value << (int64)now;
		Settings::Set("update_checked", value.String());
	}
	thread_id thread = spawn_thread(CheckThread, "kigo update",
		B_LOW_PRIORITY, manual ? (void*)1 : NULL);
	if (thread >= 0)
		resume_thread(thread);
}


void
Updater::AnnounceUpdated()
{
	BString message;
	message.SetToFormat("Kigo %s is installed.", KIGO_VERSION);
	Notify("Kigo updated", message.String());
}
