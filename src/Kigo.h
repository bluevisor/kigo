// Shared constants for Kigo, a Spotlight/Raycast-style launcher for Haiku.
#ifndef KIGO_H
#define KIGO_H

#include <SupportDefs.h>

#define kAppSignature "application/x-vnd.bluevisor-Kigo"

// Set by the Makefile from the VERSION file.
#ifndef KIGO_VERSION
#define KIGO_VERSION "0.0.0"
#endif

enum {
	// Sent by the input_server hotkey filter (and `Kigo --toggle`).
	kMsgToggle = 'LTgl',
	kMsgShow = 'LShw',

	// Internal.
	kMsgQueryChanged = 'LQry',
	kMsgRunFileSearch = 'LRfs',
	kMsgFileResults = 'LFil',
	kMsgReindex = 'LRix',
	kMsgCheckUpdates = 'LUpd',
	// The settings page: open it (`Kigo --settings`), one setting changed,
	// and a frame of the window growing into it or shrinking back.
	kMsgOpenSettings = 'LSop',
	kMsgSettingChanged = 'LSet',
	kMsgMorph = 'LMor',
};

#endif // KIGO_H
