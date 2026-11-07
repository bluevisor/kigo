// Kigo's settings, shown in the launcher window itself: the window grows
// into this page (Alt+, or the Kigo Settings command) and shrinks back on
// Esc. Drawn by hand to match the results list; keyboard first, like the
// rest of Kigo.
#ifndef SETTINGS_VIEW_H
#define SETTINGS_VIEW_H

#include <vector>

#include <String.h>
#include <View.h>

class SearchWindow;

class SettingsView : public BView {
public:
	SettingsView(BRect frame, SearchWindow* window);

	void Draw(BRect updateRect) override;
	void MouseDown(BPoint where) override;
	void MouseMoved(BPoint where, uint32 transit,
		const BMessage* dragMessage) override;
	void KeyDown(const char* bytes, int32 numBytes) override;
	void MessageReceived(BMessage* message) override;
	void FrameResized(float width, float height) override;

	// 0 shows only the background, 1 the whole page; the window fades the
	// page in and out while it grows and shrinks.
	void SetOpacity(float opacity);
	// Back to the top, the first setting focused; called on each opening.
	void Reset();
	// The Size setting or the system font changed.
	void ThemeChanged();
	// Height the page wants, all of it showing.
	float ContentHeight() const;

private:
	enum RowKind {
		kHeader,
		kSwitch,
		kChoice,
		kButton,
		kKeys,
	};

	struct Row {
		RowKind		kind;
		BString		label;
		BString		detail;
		// The setting it changes, or the action a button takes.
		BString		key;
		std::vector<BString> choices;
		float		top = 0;
		float		height = 0;
	};

	struct Hit {
		BRect	rect;
		int32	row;
		// The choice a segment picks; -1 for the row itself.
		int32	choice;
	};

	void _Build();
	void _Layout();
	bool _Value(const Row& row) const;
	int32 _Choice(const Row& row) const;
	void _Activate(int32 row, int32 choice);
	void _MoveFocus(int32 delta);
	void _ScrollTo(float scroll);
	void _ScrollToFocus();

	void _DrawRow(int32 index);
	BRect _DrawSwitch(float right, float centerY, bool on);
	void _DrawChoices(int32 index, float right, float centerY);
	BRect _DrawButton(const char* label, float right, float centerY, bool enabled);
	void _DrawKeys(const char* keys, float right, float centerY);
	rgb_color _Faded(rgb_color color) const;

	SearchWindow*		fSearchWindow;
	std::vector<Row>	fRows;
	std::vector<Hit>	fHits;
	int32				fFocus;
	int32				fHover;
	float				fScroll;
	float				fOpacity;
	bool				fCleared;
};

#endif // SETTINGS_VIEW_H
