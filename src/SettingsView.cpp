#include "SettingsView.h"

#include <algorithm>
#include <math.h>

#include <Window.h>

#include "Kigo.h"
#include "Prefs.h"
#include "SearchWindow.h"
#include "Theme.h"


SettingsView::SettingsView(BRect frame, SearchWindow* window)
	:
	BView(frame, "settings", B_FOLLOW_NONE,
		B_WILL_DRAW | B_FRAME_EVENTS | B_NAVIGABLE),
	fSearchWindow(window),
	fFocus(-1),
	fHover(-1),
	fScroll(0),
	fOpacity(1),
	fCleared(false)
{
	SetViewColor(B_TRANSPARENT_COLOR);
	_Build();
	_Layout();
	Reset();
}


void
SettingsView::_Build()
{
	fRows.clear();
	auto header = [&](const char* label) {
		Row row;
		row.kind = kHeader;
		row.label = label;
		fRows.push_back(row);
	};
	auto add = [&](RowKind kind, const char* label, const char* detail,
			const char* key) {
		Row row;
		row.kind = kind;
		row.label = label;
		row.detail = detail;
		row.key = key;
		fRows.push_back(row);
		return &fRows.back();
	};

	header("Search");
	add(kSwitch, "Applications", "Apps and preference panels", "search_apps");
	add(kSwitch, "Files and folders", "A live query on the disk's name index",
		"search_files");
	add(kSwitch, "Commands", "Restart, Empty Trash, workspaces and more",
		"search_commands");
	add(kSwitch, "Calculator", "Answers arithmetic as you type", "calculator");
	Row* web = add(kChoice, "Web search", "Offered last, for anything else",
		"web_search");
	for (int32 i = 0; i < kWebCount; i++)
		web->choices.push_back(kWebSearchNames[i]);

	header("Suggestions");
	add(kSwitch, "Suggest what you use most", "Shown before you type anything",
		"suggestions");
	add(kButton, "Search history", "Forget what you opened; ranking starts over",
		"clear_history");

	header("Appearance");
	Row* size = add(kChoice, "Size", "Text and rows, over the system font size",
		"size");
	for (int32 i = 0; i < kSizeCount; i++)
		size->choices.push_back(kSizeNames[i]);

	header("General");
	add(kKeys, "Open Kigo", "From anywhere; Win+Space switches input methods",
		"Alt Space");
	add(kSwitch, "Open at login", "Starts hidden, ready for the hotkey",
		"autostart");
	add(kSwitch, "Check for updates daily", "From GitHub releases", "updates");
	BString version;
	version.SetToFormat("Kigo %s", KIGO_VERSION);
	add(kButton, version.String(), "Look for a newer version now",
		"check_updates");
}


void
SettingsView::_Layout()
{
	const Theme& theme = Theme::Get();
	float top = roundf(4 * theme.scale);
	for (size_t i = 0; i < fRows.size(); i++) {
		Row& row = fRows[i];
		if (row.kind == kHeader) {
			// A gap above every section but the first.
			if (i > 0)
				top += roundf(8 * theme.scale);
			row.height = theme.headerHeight;
		} else
			row.height = roundf(theme.rowHeight * 1.12f);
		row.top = top;
		top += row.height;
	}
}


float
SettingsView::ContentHeight() const
{
	if (fRows.empty())
		return 0;
	const Row& last = fRows.back();
	return last.top + last.height + roundf(6 * Theme::Get().scale);
}


void
SettingsView::Reset()
{
	_Build();
	_Layout();
	fCleared = false;
	fScroll = 0;
	fHover = -1;
	fFocus = -1;
	_MoveFocus(1);
	// From the top: the page opens tiny and grows, so following the focus
	// would scroll it before it's any size.
	fScroll = 0;
	Invalidate();
}


void
SettingsView::ThemeChanged()
{
	_Layout();
	_ScrollTo(fScroll);
	_ScrollToFocus();
	Invalidate();
}


void
SettingsView::SetOpacity(float opacity)
{
	if (opacity == fOpacity)
		return;
	fOpacity = opacity;
	Invalidate();
}


void
SettingsView::FrameResized(float width, float height)
{
	_ScrollTo(fScroll);
	// Resized while showing (a new Size): keep the focused row in view. Not
	// while it fades in, growing from nothing.
	if (fOpacity >= 1)
		_ScrollToFocus();
	Invalidate();
}


rgb_color
SettingsView::_Faded(rgb_color color) const
{
	return MixColors(Theme::Get().background, color, fOpacity);
}


bool
SettingsView::_Value(const Row& row) const
{
	const Prefs& prefs = Prefs::Get();
	if (row.key == "search_apps")
		return prefs.searchApps;
	if (row.key == "search_files")
		return prefs.searchFiles;
	if (row.key == "search_commands")
		return prefs.searchCommands;
	if (row.key == "calculator")
		return prefs.calculator;
	if (row.key == "suggestions")
		return prefs.suggestions;
	if (row.key == "autostart")
		return prefs.autostart;
	if (row.key == "updates")
		return prefs.updates;
	return false;
}


int32
SettingsView::_Choice(const Row& row) const
{
	if (row.key == "web_search")
		return Prefs::Get().webSearch;
	if (row.key == "size")
		return Prefs::Get().size;
	return 0;
}


// Changes the setting on `row`: a switch flips, a choice goes to `choice`
// (-1: the next one), a button does its action. The window applies what it
// has to (sizes, the login item, the history).
void
SettingsView::_Activate(int32 index, int32 choice)
{
	if (index < 0 || index >= (int32)fRows.size())
		return;
	const Row& row = fRows[index];
	switch (row.kind) {
		case kSwitch:
			Prefs::Set(row.key.String(), !_Value(row));
			break;
		case kChoice:
		{
			int32 count = (int32)row.choices.size();
			if (choice < 0)
				choice = (_Choice(row) + 1) % count;
			if (choice == _Choice(row))
				return;
			Prefs::SetChoice(row.key.String(), choice);
			break;
		}
		case kButton:
			if (row.key == "clear_history") {
				if (fCleared)
					return;
				fCleared = true;
			}
			break;
		default:
			return;
	}
	BMessage changed(kMsgSettingChanged);
	changed.AddString("key", row.key);
	Window()->PostMessage(&changed);
	Invalidate();
}


void
SettingsView::_MoveFocus(int32 delta)
{
	int32 count = (int32)fRows.size();
	int32 index = fFocus;
	for (int32 step = 0; step < count; step++) {
		index += delta > 0 ? 1 : -1;
		if (index < 0 || index >= count)
			return;
		RowKind kind = fRows[index].kind;
		if (kind != kHeader && kind != kKeys) {
			fFocus = index;
			_ScrollToFocus();
			Invalidate();
			return;
		}
	}
}


void
SettingsView::_ScrollTo(float scroll)
{
	float most = std::max(0.0f, ContentHeight() - Bounds().Height() - 1);
	scroll = std::min(std::max(scroll, 0.0f), most);
	if (scroll != fScroll) {
		fScroll = scroll;
		Invalidate();
	}
}


void
SettingsView::_ScrollToFocus()
{
	if (fFocus < 0)
		return;
	const Row& row = fRows[fFocus];
	float visible = Bounds().Height() + 1;
	// Keep the section's header in view with its first row.
	float top = row.top;
	if (fFocus > 0 && fRows[fFocus - 1].kind == kHeader)
		top = fRows[fFocus - 1].top;
	if (top < fScroll)
		_ScrollTo(top);
	else if (row.top + row.height > fScroll + visible)
		_ScrollTo(row.top + row.height - visible);
}


void
SettingsView::KeyDown(const char* bytes, int32 numBytes)
{
	if (numBytes != 1) {
		BView::KeyDown(bytes, numBytes);
		return;
	}
	int32 modifiers = 0;
	if (Window()->CurrentMessage() != NULL)
		Window()->CurrentMessage()->FindInt32("modifiers", &modifiers);
	bool control = (modifiers & B_CONTROL_KEY) != 0;
	bool shift = (modifiers & B_SHIFT_KEY) != 0;

	const Row* row = fFocus >= 0 ? &fRows[fFocus] : NULL;
	switch (bytes[0]) {
		case B_ESCAPE:
			fSearchWindow->CloseSettings();
			return;
		case B_UP_ARROW:
			_MoveFocus(-1);
			return;
		case B_DOWN_ARROW:
			_MoveFocus(1);
			return;
		case B_TAB:
			_MoveFocus(shift ? -1 : 1);
			return;
		case B_HOME:
			fFocus = -1;
			_MoveFocus(1);
			return;
		case B_END:
			fFocus = (int32)fRows.size();
			_MoveFocus(-1);
			return;
		case B_PAGE_UP:
			_ScrollTo(fScroll - Bounds().Height() * 0.8f);
			return;
		case B_PAGE_DOWN:
			_ScrollTo(fScroll + Bounds().Height() * 0.8f);
			return;
		case B_SPACE:
		case B_ENTER:
			_Activate(fFocus, -1);
			return;
		case B_LEFT_ARROW:
		case B_RIGHT_ARROW:
		{
			if (row == NULL)
				return;
			bool right = bytes[0] == B_RIGHT_ARROW;
			if (row->kind == kChoice) {
				int32 choice = _Choice(*row) + (right ? 1 : -1);
				if (choice >= 0 && choice < (int32)row->choices.size())
					_Activate(fFocus, choice);
			} else if (row->kind == kSwitch && _Value(*row) != right)
				_Activate(fFocus, -1);
			return;
		}
	}
	// Emacs-style Ctrl+N / Ctrl+P, as in the results list.
	if (control && bytes[0] == 0x0e) {
		_MoveFocus(1);
		return;
	}
	if (control && bytes[0] == 0x10) {
		_MoveFocus(-1);
		return;
	}
	BView::KeyDown(bytes, numBytes);
}


void
SettingsView::MouseDown(BPoint where)
{
	MakeFocus(true);
	for (const Hit& hit : fHits) {
		if (hit.rect.Contains(where)) {
			fFocus = hit.row;
			_Activate(hit.row, hit.choice);
			Invalidate();
			return;
		}
	}
}


void
SettingsView::MouseMoved(BPoint where, uint32 transit,
	const BMessage* dragMessage)
{
	int32 hover = -1;
	if (transit != B_EXITED_VIEW && transit != B_OUTSIDE_VIEW) {
		float y = where.y + fScroll;
		for (size_t i = 0; i < fRows.size(); i++) {
			const Row& row = fRows[i];
			if (row.kind != kHeader && row.kind != kKeys && y >= row.top
				&& y < row.top + row.height) {
				hover = (int32)i;
			}
		}
	}
	if (hover != fHover) {
		fHover = hover;
		Invalidate();
	}
}


void
SettingsView::MessageReceived(BMessage* message)
{
	if (message->what == B_MOUSE_WHEEL_CHANGED) {
		float delta = message->GetFloat("be:wheel_delta_y", 0);
		_ScrollTo(fScroll + delta * Theme::Get().rowHeight);
		return;
	}
	BView::MessageReceived(message);
}


void
SettingsView::Draw(BRect updateRect)
{
	const Theme& theme = Theme::Get();
	SetHighColor(theme.background);
	FillRect(updateRect);
	fHits.clear();
	for (size_t i = 0; i < fRows.size(); i++) {
		const Row& row = fRows[i];
		float top = row.top - fScroll;
		if (top > updateRect.bottom || top + row.height < updateRect.top)
			continue;
		_DrawRow((int32)i);
	}

	// Hint that the page scrolls.
	float visible = Bounds().Height() + 1;
	if (ContentHeight() > visible) {
		float trackTop = 4 * theme.scale;
		float trackHeight = visible - 8 * theme.scale;
		float thumbHeight = std::max(20 * theme.scale,
			trackHeight * visible / ContentHeight());
		float progress = fScroll / (ContentHeight() - visible);
		float thumbTop = trackTop + (trackHeight - thumbHeight) * progress;
		BRect thumb(Bounds().right - 5 * theme.scale, thumbTop,
			Bounds().right - 2 * theme.scale, thumbTop + thumbHeight);
		SetHighColor(_Faded(theme.separator));
		FillRoundRect(thumb, 1.5f * theme.scale, 1.5f * theme.scale);
	}
}


void
SettingsView::_DrawRow(int32 index)
{
	const Theme& theme = Theme::Get();
	const Row& row = fRows[index];
	BRect bounds = Bounds();
	float top = row.top - fScroll;
	float left = theme.padding + 4 * theme.scale;

	if (row.kind == kHeader) {
		BFont font(be_bold_font);
		font.SetSize(roundf(theme.fontSize * 0.92f));
		SetFont(&font);
		font_height height;
		font.GetHeight(&height);
		SetHighColor(_Faded(theme.dimText));
		SetLowColor(theme.background);
		DrawString(row.label.String(), BPoint(left,
			top + row.height - roundf(7 * theme.scale) - ceilf(height.descent)));
		return;
	}

	// The focused row is lit like the selected result; the hovered one less.
	rgb_color back = theme.background;
	if (index == fFocus && IsFocus())
		back = theme.selection;
	else if (index == fHover)
		back = MixColors(theme.background, theme.selection, 0.45f);
	back = _Faded(back);
	BRect rowRect(roundf(6 * theme.scale), top + 1,
		bounds.right - roundf(6 * theme.scale), top + row.height - 1);
	if (back != theme.background) {
		SetHighColor(back);
		FillRoundRect(rowRect, 6 * theme.scale, 6 * theme.scale);
	}

	BFont font(be_plain_font);
	font.SetSize(theme.fontSize * 1.08f);
	BFont small(be_plain_font);
	small.SetSize(roundf(theme.fontSize * 0.92f));
	font_height big, little;
	font.GetHeight(&big);
	small.GetHeight(&little);
	float textHeight = ceilf(big.ascent + big.descent)
		+ roundf(3 * theme.scale) + ceilf(little.ascent + little.descent);
	float labelBase = roundf(top + (row.height - textHeight) / 2 + big.ascent);
	float detailBase = roundf(labelBase + big.descent + roundf(3 * theme.scale)
		+ little.ascent);

	SetLowColor(back);
	SetFont(&font);
	SetHighColor(_Faded(theme.text));
	DrawString(row.label.String(), BPoint(left, labelBase));
	SetFont(&small);
	SetHighColor(_Faded(theme.dimText));
	DrawString(row.detail.String(), BPoint(left, detailBase));

	float right = bounds.right - theme.padding - roundf(4 * theme.scale);
	float centerY = roundf(top + row.height / 2);
	switch (row.kind) {
		case kSwitch:
		{
			BRect knob = _DrawSwitch(right, centerY, _Value(row));
			fHits.push_back(Hit{rowRect | knob, index, -1});
			break;
		}
		case kChoice:
			_DrawChoices(index, right, centerY);
			break;
		case kButton:
		{
			bool cleared = row.key == "clear_history" && fCleared;
			const char* label = row.key == "clear_history"
				? (cleared ? "Cleared" : "Clear") : "Check Now";
			BRect button = _DrawButton(label, right, centerY, !cleared);
			fHits.push_back(Hit{button, index, -1});
			break;
		}
		case kKeys:
			_DrawKeys(row.key.String(), right, centerY);
			break;
		default:
			break;
	}
}


BRect
SettingsView::_DrawSwitch(float right, float centerY, bool on)
{
	const Theme& theme = Theme::Get();
	float width = roundf(36 * theme.scale);
	float height = roundf(20 * theme.scale);
	BRect track(right - width, centerY - height / 2, right, centerY + height / 2);
	float radius = height / 2;
	SetHighColor(_Faded(on ? theme.accent : theme.keycap));
	FillRoundRect(track, radius, radius);
	if (!on) {
		SetHighColor(_Faded(theme.border));
		StrokeRoundRect(track, radius, radius);
	}
	float inset = roundf(3 * theme.scale);
	float knob = height - 2 * inset;
	float x = on ? track.right - inset - knob : track.left + inset;
	SetHighColor(_Faded(on ? make_color(255, 255, 255) : theme.dimText));
	FillEllipse(BRect(x, track.top + inset, x + knob, track.top + inset + knob));
	return track;
}


void
SettingsView::_DrawChoices(int32 index, float right, float centerY)
{
	const Theme& theme = Theme::Get();
	const Row& row = fRows[index];
	BFont font(be_plain_font);
	font.SetSize(roundf(theme.fontSize * 0.95f));
	font_height height;
	font.GetHeight(&height);
	float pad = roundf(10 * theme.scale);
	float h = roundf(24 * theme.scale);
	float total = 0;
	for (const BString& choice : row.choices)
		total += ceilf(font.StringWidth(choice.String())) + 2 * pad;

	BRect outer(right - total, centerY - h / 2, right, centerY + h / 2);
	float radius = roundf(6 * theme.scale);
	SetHighColor(_Faded(theme.footerBackground));
	FillRoundRect(outer, radius, radius);
	SetHighColor(_Faded(theme.border));
	StrokeRoundRect(outer, radius, radius);

	int32 selected = _Choice(row);
	float x = outer.left;
	SetFont(&font);
	float baseline = roundf(centerY + (height.ascent - height.descent) / 2);
	for (int32 i = 0; i < (int32)row.choices.size(); i++) {
		const BString& choice = row.choices[i];
		float width = ceilf(font.StringWidth(choice.String())) + 2 * pad;
		BRect segment(x, outer.top, x + width, outer.bottom);
		rgb_color back = theme.footerBackground;
		if (i == selected) {
			back = theme.accent;
			SetHighColor(_Faded(back));
			FillRoundRect(segment.InsetByCopy(2, 2), radius - 2, radius - 2);
		} else if (i > 0 && i - 1 != selected) {
			SetHighColor(_Faded(theme.separator));
			StrokeLine(BPoint(x, outer.top + 5 * theme.scale),
				BPoint(x, outer.bottom - 5 * theme.scale));
		}
		SetLowColor(_Faded(back));
		SetHighColor(_Faded(i == selected ? make_color(255, 255, 255)
			: theme.text));
		DrawString(choice.String(), BPoint(x + pad, baseline));
		fHits.push_back(Hit{segment, index, i});
		x += width;
	}
}


BRect
SettingsView::_DrawButton(const char* label, float right, float centerY,
	bool enabled)
{
	const Theme& theme = Theme::Get();
	BFont font(be_plain_font);
	font.SetSize(roundf(theme.fontSize * 0.95f));
	font_height height;
	font.GetHeight(&height);
	float pad = roundf(12 * theme.scale);
	float h = roundf(24 * theme.scale);
	float width = ceilf(font.StringWidth(label)) + 2 * pad;
	BRect button(right - width, centerY - h / 2, right, centerY + h / 2);
	float radius = roundf(6 * theme.scale);
	SetHighColor(_Faded(theme.keycap));
	FillRoundRect(button, radius, radius);
	SetHighColor(_Faded(theme.border));
	StrokeRoundRect(button, radius, radius);
	SetFont(&font);
	SetLowColor(_Faded(theme.keycap));
	SetHighColor(_Faded(enabled ? theme.text : theme.faintText));
	DrawString(label, BPoint(button.left + pad,
		roundf(centerY + (height.ascent - height.descent) / 2)));
	return button;
}


void
SettingsView::_DrawKeys(const char* keys, float right, float centerY)
{
	const Theme& theme = Theme::Get();
	BFont font(be_plain_font);
	font.SetSize(roundf(theme.fontSize * 0.95f));
	font_height height;
	font.GetHeight(&height);
	SetFont(&font);
	float pad = roundf(7 * theme.scale);
	float h = roundf(22 * theme.scale);
	float baseline = roundf(centerY + (height.ascent - height.descent) / 2);

	// Each word its own keycap, laid out right to left.
	BString all(keys);
	std::vector<BString> caps;
	int32 start = 0;
	while (start < all.Length()) {
		int32 end = all.FindFirst(' ', start);
		if (end < 0)
			end = all.Length();
		BString cap;
		all.CopyInto(cap, start, end - start);
		caps.push_back(cap);
		start = end + 1;
	}
	for (auto it = caps.rbegin(); it != caps.rend(); ++it) {
		float width = ceilf(font.StringWidth(it->String())) + 2 * pad;
		BRect cap(right - width, centerY - h / 2, right, centerY + h / 2);
		SetHighColor(_Faded(theme.keycap));
		FillRoundRect(cap, 4 * theme.scale, 4 * theme.scale);
		SetLowColor(_Faded(theme.keycap));
		SetHighColor(_Faded(theme.dimText));
		DrawString(it->String(), BPoint(cap.left + pad, baseline));
		right = cap.left - roundf(4 * theme.scale);
	}
}
