// Kigo: a Spotlight/Raycast-style launcher for Haiku.
//
//   Kigo               show the launcher (starting Kigo if needed)
//   Kigo --background  start hidden; the hotkey shows it (used at boot)
//   Kigo --toggle      show or hide it
//
// The global hotkey (Alt+Space) comes from the KigoHotkey input_server
// filter, which sends kMsgToggle here.

#include <Application.h>
#include <Roster.h>

#include <stdio.h>
#include <string.h>

#include "Kigo.h"
#include "SearchWindow.h"
#include "Setup.h"
#include "Updater.h"


class KigoApp : public BApplication {
public:
	KigoApp()
		:
		BApplication(kAppSignature),
		fWindow(NULL),
		fBackground(false),
		fUpdated(false)
	{
	}

	void ArgvReceived(int32 argc, char** argv) override
	{
		bool toggle = false;
		for (int32 i = 1; i < argc; i++) {
			if (strcmp(argv[i], "--background") == 0)
				fBackground = true;
			else if (strcmp(argv[i], "--updated") == 0)
				fUpdated = true;
			else if (strcmp(argv[i], "--toggle") == 0)
				toggle = true;
			else if (strcmp(argv[i], "--help") == 0) {
				printf("Kigo %s\nusage: Kigo [--background | --toggle]\n", KIGO_VERSION);
				fBackground = true;
				PostMessage(B_QUIT_REQUESTED);
			}
		}
		// A second launch delivers its arguments to the running copy.
		if (fWindow != NULL)
			fWindow->PostMessage(toggle ? kMsgToggle : kMsgShow);
	}

	void ReadyToRun() override
	{
		Setup::Run();
		if (fUpdated)
			Updater::AnnounceUpdated();
		Updater::Check(false);

		fWindow = new SearchWindow();
		// Start the window's thread while keeping it hidden.
		fWindow->Hide();
		fWindow->Show();
		if (!fBackground)
			fWindow->PostMessage(kMsgShow);
	}

	void MessageReceived(BMessage* message) override
	{
		switch (message->what) {
			case kMsgToggle:
			case kMsgShow:
			case kMsgReindex:
				if (fWindow != NULL)
					fWindow->PostMessage(message);
				break;
			case kMsgCheckUpdates:
				Updater::Check(true);
				break;
			case B_SILENT_RELAUNCH:
				// Opened again from Deskbar or Tracker.
				if (fWindow != NULL)
					fWindow->PostMessage(kMsgShow);
				break;
			default:
				BApplication::MessageReceived(message);
		}
	}

	bool QuitRequested() override
	{
		// The window refuses to close on its own (it only hides), so quit it
		// directly instead of asking.
		if (fWindow != NULL && fWindow->Lock()) {
			fWindow->Quit();
			fWindow = NULL;
		}
		return true;
	}

private:
	SearchWindow*	fWindow;
	bool			fBackground;
	bool			fUpdated;
};


int
main()
{
	KigoApp app;
	app.Run();
	return 0;
}
