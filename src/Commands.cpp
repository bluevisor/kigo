#include "Commands.h"

#include <ctype.h>
#include <stdlib.h>

#include <AppFileInfo.h>
#include <Clipboard.h>
#include <Entry.h>
#include <File.h>
#include <FindDirectory.h>
#include <InterfaceDefs.h>
#include <Messenger.h>
#include <Node.h>
#include <Path.h>
#include <Roster.h>

#include "Fuzzy.h"
#include "IconCache.h"
#include "Kigo.h"


static const char* kTrackerSignature = "application/x-vnd.Be-TRAK";
static const char* kDeskbarSignature = "application/x-vnd.Be-TSKB";
static const char* kTerminalSignature = "application/x-vnd.Haiku-Terminal";
// Tracker's private "Empty Trash" command (Commands.h in the Tracker source).
static const uint32 kTrackerEmptyTrash = 'Tetr';


struct CommandInfo {
	const char* id;
	const char* title;
	const char* subtitle;
	const char* keywords;
	const char* iconSignature;
	bool needsConfirm;
};

static const CommandInfo kCommands[] = {
	{"restart", "Restart", "System", "reboot", kDeskbarSignature, true},
	{"shutdown", "Shut Down", "System", "power off poweroff halt", kDeskbarSignature, true},
	{"empty-trash", "Empty Trash", "Tracker", "delete clean bin", kTrackerSignature, true},
	{"home", "Home", "Folder", "folder user", kTrackerSignature, false},
	{"desktop", "Desktop", "Folder", "folder", kTrackerSignature, false},
	{"trash", "Trash", "Folder", "bin deleted", kTrackerSignature, false},
	{"config", "config", "Folder", "settings folder", kTrackerSignature, false},
	{"settings-folder", "Settings Folder", "Folder", "config preferences", kTrackerSignature, false},
	{"new-terminal", "New Terminal Window", "Terminal", "shell console", kTerminalSignature, false},
	{"reindex", "Reload Applications", "Kigo", "refresh rescan reindex", kAppSignature, false},
	{"update", "Check for Updates", "Kigo " KIGO_VERSION, "upgrade update version kigo", kAppSignature, false},
	{"quit", "Quit Kigo", "Kigo", "exit close", kAppSignature, false},
};


static bool
FolderPath(const char* id, BPath& path)
{
	if (strcmp(id, "home") == 0)
		return find_directory(B_USER_DIRECTORY, &path) == B_OK;
	if (strcmp(id, "desktop") == 0)
		return find_directory(B_DESKTOP_DIRECTORY, &path) == B_OK;
	if (strcmp(id, "trash") == 0)
		return find_directory(B_TRASH_DIRECTORY, &path) == B_OK;
	if (strcmp(id, "config") == 0)
		return find_directory(B_USER_CONFIG_DIRECTORY, &path) == B_OK;
	if (strcmp(id, "settings-folder") == 0)
		return find_directory(B_USER_SETTINGS_DIRECTORY, &path) == B_OK;
	return false;
}


static Result
MakeCommand(const CommandInfo& info)
{
	Result result;
	result.kind = kKindCommand;
	result.title = info.title;
	result.subtitle = info.subtitle;
	result.id.SetToFormat("cmd:%s", info.id);
	result.payload = info.id;
	result.needsConfirm = info.needsConfirm;
	result.icon = IconCache::Get().ForSignature(info.iconSignature);

	BPath folder;
	if (FolderPath(info.id, folder)) {
		result.kind = kKindFolder;
		result.subtitle = folder.Path();
		if (get_ref_for_path(folder.Path(), &result.ref) == B_OK) {
			result.hasRef = true;
			result.icon = IconCache::Get().ForRef(result.ref);
		}
	}
	return result;
}


void
SearchCommands(const char* query, std::vector<Result>& results)
{
	for (const CommandInfo& info : kCommands) {
		float score = FuzzyScore(query, info.title);
		BString keywords(info.keywords);
		int32 start = 0;
		while (start < keywords.Length()) {
			int32 end = keywords.FindFirst(' ', start);
			if (end < 0)
				end = keywords.Length();
			BString word;
			keywords.CopyInto(word, start, end - start);
			float keywordScore = FuzzyScore(query, word.String()) * 0.75f;
			if (keywordScore >= 600 && keywordScore > score)
				score = keywordScore;
			start = end + 1;
		}
		if (score <= 0)
			continue;
		Result result = MakeCommand(info);
		result.score = score;
		results.push_back(result);
	}

	// "workspace 3", "ws 2": jump to a workspace.
	int32 count = count_workspaces();
	for (int32 i = 0; i < count; i++) {
		BString title;
		title.SetToFormat("Workspace %" B_PRId32, i + 1);
		float score = FuzzyScore(query, title.String());
		if (score <= 0)
			continue;
		Result result;
		result.kind = kKindCommand;
		result.title = title;
		result.subtitle = i == current_workspace() ? "Current workspace"
			: "Switch workspace";
		result.id.SetToFormat("cmd:workspace-%" B_PRId32, i + 1);
		result.payload.SetToFormat("workspace-%" B_PRId32, i + 1);
		result.icon = IconCache::Get().ForPath("/boot/system/apps/Workspaces");
		result.score = score - 30;
		results.push_back(result);
	}
}


bool
CommandForId(const char* id, Result& result)
{
	if (strncmp(id, "cmd:", 4) != 0)
		return false;
	for (const CommandInfo& info : kCommands) {
		if (strcmp(info.id, id + 4) == 0) {
			result = MakeCommand(info);
			return true;
		}
	}
	return false;
}


static bool
LaunchArgs(const char* signature, int argc, const char** argv)
{
	status_t status = be_roster->Launch(signature, argc, argv);
	return status == B_OK || status == B_ALREADY_RUNNING;
}


static bool
RunProgram(const char* path, const char* arg)
{
	const char* argv[] = {path, arg, NULL};
	thread_id thread = load_image(arg != NULL ? 2 : 1, argv,
		(const char**)environ);
	if (thread < 0)
		return false;
	resume_thread(thread);
	return true;
}


static bool
RunCommand(const Result& result, const BMessenger& app)
{
	const char* id = result.payload.String();
	if (strcmp(id, "restart") == 0)
		return RunProgram("/bin/shutdown", "-r");
	if (strcmp(id, "shutdown") == 0)
		return RunProgram("/bin/shutdown", NULL);
	if (strcmp(id, "empty-trash") == 0) {
		BMessenger tracker(kTrackerSignature);
		return tracker.SendMessage(kTrackerEmptyTrash) == B_OK;
	}
	if (strcmp(id, "new-terminal") == 0) {
		status_t status = be_roster->Launch(kTerminalSignature);
		return status == B_OK;
	}
	if (strcmp(id, "reindex") == 0)
		return app.SendMessage(kMsgReindex) == B_OK;
	if (strcmp(id, "update") == 0)
		return app.SendMessage(kMsgCheckUpdates) == B_OK;
	if (strcmp(id, "quit") == 0)
		return app.SendMessage(B_QUIT_REQUESTED) == B_OK;
	if (strncmp(id, "workspace-", 10) == 0) {
		activate_workspace(atoi(id + 10) - 1);
		return true;
	}
	return false;
}


static bool
OpenApp(const entry_ref& ref, bool newInstance)
{
	// Like Spotlight: bring a running app forward instead of starting a
	// second copy. Shift+Enter starts a new one for multi-launch apps.
	BFile file(&ref, B_READ_ONLY);
	BAppFileInfo info(&file);
	char signature[B_MIME_TYPE_LENGTH];
	if (!newInstance && info.InitCheck() == B_OK
		&& info.GetSignature(signature) == B_OK) {
		team_id team = be_roster->TeamFor(signature);
		if (team >= 0)
			return be_roster->ActivateApp(team) == B_OK;
	}
	status_t status = be_roster->Launch(&ref);
	return status == B_OK || status == B_ALREADY_RUNNING;
}


bool
OpenResult(const Result& result, bool newInstance, const BMessenger& app)
{
	switch (result.kind) {
		case kKindApp:
		case kKindPreference:
			return OpenApp(result.ref, newInstance);

		case kKindFile:
		case kKindFolder:
		{
			status_t status = be_roster->Launch(&result.ref);
			return status == B_OK || status == B_ALREADY_RUNNING;
		}

		case kKindCommand:
			return RunCommand(result, app);

		case kKindCalculator:
			CopyToClipboard(result.payload.String());
			return true;

		case kKindURL:
		case kKindWeb:
			return OpenURL(result.payload.String());

		case kKindShell:
			return RunInTerminal(result.payload.String());
	}
	return false;
}


bool
CanReveal(const Result& result)
{
	return result.hasRef && result.kind != kKindCommand;
}


bool
RevealResult(const Result& result)
{
	if (!CanReveal(result))
		return false;

	BEntry entry(&result.ref);
	BEntry parent;
	entry_ref parentRef;
	node_ref node;
	if (entry.GetParent(&parent) != B_OK || parent.GetRef(&parentRef) != B_OK
		|| entry.GetNodeRef(&node) != B_OK) {
		return false;
	}

	// Tracker opens the folder and selects the node, like Finder's reveal.
	BMessage message(B_REFS_RECEIVED);
	message.AddRef("refs", &parentRef);
	message.AddData("nodeRefToSelect", B_RAW_TYPE, &node, sizeof(node_ref));
	return BMessenger(kTrackerSignature).SendMessage(&message) == B_OK;
}


void
CopyToClipboard(const char* text)
{
	if (!be_clipboard->Lock())
		return;
	be_clipboard->Clear();
	BMessage* clip = be_clipboard->Data();
	clip->AddData("text/plain", B_MIME_TYPE, text, strlen(text));
	be_clipboard->Commit();
	be_clipboard->Unlock();
}


void
CopyResult(const Result& result)
{
	if (result.hasRef) {
		BPath path(&result.ref);
		CopyToClipboard(path.Path());
		return;
	}
	if (!result.payload.IsEmpty())
		CopyToClipboard(result.payload.String());
	else
		CopyToClipboard(result.title.String());
}


bool
OpenURL(const char* url)
{
	const char* argv[] = {url, NULL};
	BString scheme(url);
	int32 colon = scheme.FindFirst(':');
	if (colon > 0) {
		scheme.Truncate(colon);
		BString type("application/x-vnd.Be.URL.");
		type << scheme;
		if (LaunchArgs(type.String(), 1, argv))
			return true;
	}
	return LaunchArgs("text/html", 1, argv);
}


bool
RunInTerminal(const char* command)
{
	// Run it, then leave an interactive login shell (which hands over to
	// the user's shell) in the window, like Raycast's "Run in Terminal".
	BString script(command);
	script << "; exec bash -l";
	const char* argv[] = {"/bin/bash", "-lc", script.String(), NULL};
	return LaunchArgs(kTerminalSignature, 3, argv);
}


bool
LooksLikeURL(const char* text, BString& url)
{
	BString input(text);
	input.Trim();
	if (input.IsEmpty() || input.FindFirst(' ') >= 0)
		return false;

	if (input.IStartsWith("http://") || input.IStartsWith("https://")
		|| input.IStartsWith("ftp://") || input.IStartsWith("file://")) {
		url = input;
		return true;
	}
	if (input.IStartsWith("www.")) {
		url = "https://";
		url << input;
		return true;
	}

	// "haiku-os.org", "github.com/x": a dot followed by a 2+ letter TLD.
	int32 slash = input.FindFirst('/');
	BString host(input);
	if (slash >= 0)
		host.Truncate(slash);
	int32 dot = host.FindLast('.');
	if (dot <= 0 || dot >= host.Length() - 2)
		return false;
	for (int32 i = dot + 1; i < host.Length(); i++) {
		if (!isalpha((unsigned char)host[i]))
			return false;
	}
	for (int32 i = 0; i < host.Length(); i++) {
		char c = host[i];
		if (!isalnum((unsigned char)c) && c != '.' && c != '-' && c != ':')
			return false;
	}
	url = "https://";
	url << input;
	return true;
}
