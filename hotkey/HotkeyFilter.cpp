// KigoHotkey: an input_server filter that turns Alt+Space (Haiku's Command
// key; Option+Space on a Mac keyboard in UTM) into "toggle Kigo", the way
// Spotlight and Raycast own a global shortcut.
//
// Install in ~/config/non-packaged/add-ons/input_server/filters/; the
// input_server picks up new filters without a restart.

#include <InputServerFilter.h>
#include <InterfaceDefs.h>
#include <Message.h>
#include <Messenger.h>
#include <OS.h>
#include <Roster.h>

#include "../src/Kigo.h"


static const int32 kSpaceKey = 0x5e;
static const uint32 kModifierMask = B_COMMAND_KEY | B_CONTROL_KEY
	| B_OPTION_KEY | B_SHIFT_KEY;


class KigoHotkeyFilter : public BInputServerFilter {
public:
	KigoHotkeyFilter()
		:
		fSwallowKeyUp(false)
	{
	}

	filter_result Filter(BMessage* message, BList* outList) override
	{
		if (message->what != B_KEY_DOWN && message->what != B_KEY_UP)
			return B_DISPATCH_MESSAGE;

		int32 key;
		if (message->FindInt32("key", &key) != B_OK || key != kSpaceKey)
			return B_DISPATCH_MESSAGE;

		if (message->what == B_KEY_UP) {
			if (!fSwallowKeyUp)
				return B_DISPATCH_MESSAGE;
			fSwallowKeyUp = false;
			return B_SKIP_MESSAGE;
		}

		int32 modifiers = message->GetInt32("modifiers", 0);
		if ((modifiers & kModifierMask) != B_COMMAND_KEY)
			return B_DISPATCH_MESSAGE;

		fSwallowKeyUp = true;
		if (message->GetInt32("be:key_repeat", 0) == 0) {
			// Never block the input_server's event thread on the roster.
			thread_id thread = spawn_thread(_Toggle, "kigo hotkey",
				B_NORMAL_PRIORITY, NULL);
			if (thread >= 0)
				resume_thread(thread);
		}
		return B_SKIP_MESSAGE;
	}

private:
	static status_t _Toggle(void*)
	{
		BMessenger kigo(kAppSignature);
		if (kigo.IsValid() && kigo.SendMessage(kMsgToggle) == B_OK)
			return B_OK;
		// Not running yet: start it, and it shows itself.
		return be_roster->Launch(kAppSignature);
	}

	bool	fSwallowKeyUp;
};


extern "C" BInputServerFilter*
instantiate_input_filter()
{
	return new(std::nothrow) KigoHotkeyFilter();
}
