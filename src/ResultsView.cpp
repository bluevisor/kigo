#include "ResultsView.h"

#include <algorithm>
#include <math.h>

#include <Bitmap.h>
#include <Font.h>
#include <Window.h>

#include "SearchWindow.h"
#include "Theme.h"


const char*
ResultKindLabel(ResultKind kind)
{
	switch (kind) {
		case kKindApp:			return "Application";
		case kKindPreference:	return "Preferences";
		case kKindFile:			return "File";
		case kKindFolder:		return "Folder";
		case kKindCommand:		return "Command";
		case kKindCalculator:	return "Calculator";
		case kKindURL:			return "Link";
		case kKindWeb:			return "Web";
		case kKindShell:		return "Terminal";
	}
	return "";
}


const char*
PrimaryActionLabel(const Result& result)
{
	switch (result.kind) {
		case kKindApp:			return "Open Application";
		case kKindPreference:	return "Open Preferences";
		case kKindFile:			return "Open File";
		case kKindFolder:		return "Open Folder";
		case kKindCommand:		return "Run Command";
		case kKindCalculator:	return "Copy Answer";
		case kKindURL:			return "Open Link";
		case kKindWeb:			return "Search Web";
		case kKindShell:		return "Run in Terminal";
	}
	return "Open";
}


ResultsView::ResultsView(BRect frame, SearchWindow* window)
	:
	BView(frame, "results", B_FOLLOW_NONE, B_WILL_DRAW | B_FRAME_EVENTS),
	fSearchWindow(window),
	fSelection(-1),
	fScroll(0),
	fLastMouse(-1, -1)
{
	SetViewColor(B_TRANSPARENT_COLOR);
}


void
ResultsView::SetResults(const std::vector<Result>& results, int32 selection)
{
	fResults = results;
	fSelection = fResults.empty() ? -1
		: std::max((int32)0, std::min(selection, CountResults() - 1));
	fConfirming = "";
	fScroll = 0;
	_BuildLines();
	_ScrollToSelection();
	Invalidate();
}


void
ResultsView::_BuildLines()
{
	const Theme& theme = Theme::Get();
	fLines.clear();
	float top = roundf(6 * theme.scale);
	BString section;
	for (int32 i = 0; i < CountResults(); i++) {
		const Result& result = fResults[i];
		if (result.section != section) {
			section = result.section;
			if (!section.IsEmpty()) {
				fLines.push_back(Line{true, -1, top, theme.headerHeight,
					section});
				top += theme.headerHeight;
			}
		}
		fLines.push_back(Line{false, i, top, theme.rowHeight, ""});
		top += theme.rowHeight;
	}
}


float
ResultsView::_ContentHeight() const
{
	if (fLines.empty())
		return 0;
	const Line& last = fLines.back();
	return last.top + last.height + roundf(6 * Theme::Get().scale);
}


float
ResultsView::PreferredHeight() const
{
	const Theme& theme = Theme::Get();
	float max = theme.maxRows * theme.rowHeight + 2 * theme.headerHeight;
	return std::min(_ContentHeight(), max);
}


const Result*
ResultsView::SelectedResult() const
{
	if (fSelection < 0 || fSelection >= CountResults())
		return NULL;
	return &fResults[fSelection];
}


void
ResultsView::Select(int32 index)
{
	if (index < 0 || index >= CountResults() || index == fSelection)
		return;
	fSelection = index;
	fConfirming = "";
	_ScrollToSelection();
	Invalidate();
	fSearchWindow->SelectionChanged();
}


void
ResultsView::MoveSelection(int32 delta)
{
	if (fResults.empty())
		return;
	int32 index = fSelection + delta;
	// Single steps wrap around like Raycast; page jumps stop at the ends.
	if (delta == 1 || delta == -1) {
		if (index < 0)
			index = CountResults() - 1;
		else if (index >= CountResults())
			index = 0;
	} else
		index = std::max((int32)0, std::min(index, CountResults() - 1));
	Select(index);
}


void
ResultsView::SetConfirming(const char* id)
{
	fConfirming = id;
	Invalidate();
	fSearchWindow->SelectionChanged();
}


void
ResultsView::_ScrollToSelection()
{
	for (const Line& line : fLines) {
		if (line.header || line.index != fSelection)
			continue;
		float visible = Bounds().Height() + 1;
		float top = line.top;
		// Keep the section header in view for the first row of a section.
		if (&line != &fLines.front() && (&line - 1)->header)
			top = (&line - 1)->top;
		if (top < fScroll)
			fScroll = top - roundf(6 * Theme::Get().scale);
		else if (line.top + line.height > fScroll + visible)
			fScroll = line.top + line.height - visible
				+ roundf(6 * Theme::Get().scale);
		fScroll = std::max(0.0f, std::min(fScroll,
			std::max(0.0f, _ContentHeight() - visible)));
		return;
	}
}


void
ResultsView::_ScrollBy(float delta)
{
	float visible = Bounds().Height() + 1;
	float max = std::max(0.0f, _ContentHeight() - visible);
	float scroll = std::max(0.0f, std::min(fScroll + delta, max));
	if (scroll != fScroll) {
		fScroll = scroll;
		Invalidate();
	}
}


void
ResultsView::Draw(BRect updateRect)
{
	const Theme& theme = Theme::Get();
	SetHighColor(theme.background);
	FillRect(updateRect);

	for (const Line& line : fLines) {
		float top = line.top - fScroll;
		if (top > updateRect.bottom || top + line.height < updateRect.top)
			continue;
		if (line.header)
			_DrawHeader(line);
		else
			_DrawRow(line);
	}

	// Hint that the list scrolls.
	float visible = Bounds().Height() + 1;
	if (_ContentHeight() > visible) {
		float trackTop = 4 * theme.scale;
		float trackHeight = visible - 8 * theme.scale;
		float thumbHeight = std::max(20 * theme.scale,
			trackHeight * visible / _ContentHeight());
		float progress = fScroll / (_ContentHeight() - visible);
		float thumbTop = trackTop + (trackHeight - thumbHeight) * progress;
		BRect thumb(Bounds().right - 5 * theme.scale, thumbTop,
			Bounds().right - 2 * theme.scale, thumbTop + thumbHeight);
		SetHighColor(theme.separator);
		FillRoundRect(thumb, 1.5f * theme.scale, 1.5f * theme.scale);
	}
}


void
ResultsView::_DrawHeader(const Line& line)
{
	const Theme& theme = Theme::Get();
	BFont font(be_bold_font);
	font.SetSize(roundf(Theme::Get().fontSize * 0.92f));
	SetFont(&font);
	font_height height;
	font.GetHeight(&height);
	SetHighColor(theme.dimText);
	SetLowColor(theme.background);
	float top = line.top - fScroll;
	float baseline = top + line.height - roundf(7 * theme.scale)
		- ceilf(height.descent);
	DrawString(line.label.String(), BPoint(theme.padding + 4 * theme.scale,
		baseline));
}


void
ResultsView::_DrawRow(const Line& line)
{
	const Theme& theme = Theme::Get();
	const Result& result = fResults[line.index];
	bool selected = line.index == fSelection;
	bool confirming = selected && !fConfirming.IsEmpty()
		&& fConfirming == result.id;

	float top = line.top - fScroll;
	BRect row(roundf(8 * theme.scale), top, Bounds().right
		- roundf(8 * theme.scale), top + line.height - 1);
	rgb_color low = theme.background;
	if (selected) {
		low = theme.selection;
		SetHighColor(low);
		float radius = roundf(7 * theme.scale);
		FillRoundRect(row, radius, radius);
	}
	SetLowColor(low);

	// Icon.
	float iconSize = theme.iconSize;
	float iconLeft = theme.padding + 4 * theme.scale;
	BRect iconRect(iconLeft, top + roundf((line.height - iconSize) / 2),
		iconLeft + iconSize - 1, 0);
	iconRect.bottom = iconRect.top + iconSize - 1;
	if (result.icon != NULL) {
		SetDrawingMode(B_OP_ALPHA);
		SetBlendingMode(B_PIXEL_ALPHA, B_ALPHA_OVERLAY);
		DrawBitmap(result.icon, result.icon->Bounds(), iconRect,
			B_FILTER_BITMAP_BILINEAR);
		SetDrawingMode(B_OP_COPY);
	} else {
		// A rounded tile with the first letter, for things without icons.
		SetHighColor(MixColors(low, theme.accent, 0.75f));
		BRect tile = iconRect.InsetByCopy(2 * theme.scale, 2 * theme.scale);
		FillRoundRect(tile, 6 * theme.scale, 6 * theme.scale);
		BFont font(be_bold_font);
		font.SetSize(roundf(iconSize * 0.5f));
		SetFont(&font);
		const char* glyph = result.kind == kKindCalculator ? "="
			: result.kind == kKindShell ? ">" : result.title.String();
		char letter[2] = {glyph[0], '\0'};
		font_height height;
		font.GetHeight(&height);
		SetHighColor(255, 255, 255);
		SetLowColor(MixColors(low, theme.accent, 0.75f));
		float width = font.StringWidth(letter);
		DrawString(letter, BPoint(tile.left + (tile.Width() - width) / 2,
			tile.top + (tile.Height() + height.ascent - height.descent) / 2));
		SetLowColor(low);
	}

	// Right-hand kind label or confirmation prompt.
	BFont small(be_plain_font);
	small.SetSize(roundf(Theme::Get().fontSize * 0.95f));
	const char* label = confirming ? "Press Enter again to confirm"
		: ResultKindLabel(result.kind);
	float labelWidth = small.StringWidth(label);
	float right = row.right - theme.padding;
	font_height smallHeight;
	small.GetHeight(&smallHeight);
	float center = top + line.height / 2;
	SetFont(&small);
	SetHighColor(confirming ? theme.warning : theme.faintText);
	DrawString(label, BPoint(right - labelWidth,
		center + (smallHeight.ascent - smallHeight.descent) / 2));
	right -= labelWidth + 16 * theme.scale;

	// Title, then the subtitle dimmed beside it (Raycast style).
	float textLeft = iconRect.right + roundf(12 * theme.scale);
	BFont titleFont(be_plain_font);
	titleFont.SetSize(roundf(Theme::Get().fontSize * 1.08f));
	if (result.kind == kKindCalculator)
		titleFont.SetFace(B_BOLD_FACE);
	font_height titleHeight;
	titleFont.GetHeight(&titleHeight);
	float baseline = center + (titleHeight.ascent - titleHeight.descent) / 2;

	BString title(result.title);
	titleFont.TruncateString(&title, B_TRUNCATE_END, right - textLeft);
	SetFont(&titleFont);
	SetHighColor(theme.text);
	DrawString(title.String(), BPoint(textLeft, baseline));

	float subtitleLeft = textLeft + titleFont.StringWidth(title.String())
		+ roundf(10 * theme.scale);
	if (!result.subtitle.IsEmpty() && subtitleLeft < right - 40 * theme.scale) {
		BString subtitle(result.subtitle);
		small.TruncateString(&subtitle, B_TRUNCATE_MIDDLE, right - subtitleLeft);
		SetFont(&small);
		SetHighColor(theme.dimText);
		DrawString(subtitle.String(), BPoint(subtitleLeft, baseline));
	}
}


int32
ResultsView::_IndexAt(BPoint where) const
{
	float y = where.y + fScroll;
	for (const Line& line : fLines) {
		if (!line.header && y >= line.top && y < line.top + line.height)
			return line.index;
	}
	return -1;
}


void
ResultsView::MouseDown(BPoint where)
{
	int32 index = _IndexAt(where);
	if (index < 0)
		return;
	Select(index);
	int32 modifiers = 0;
	if (Window()->CurrentMessage() != NULL)
		Window()->CurrentMessage()->FindInt32("modifiers", &modifiers);
	fSearchWindow->InvokeSelection((modifiers & B_COMMAND_KEY) != 0,
		(modifiers & B_SHIFT_KEY) != 0);
}


void
ResultsView::MouseMoved(BPoint where, uint32 transit,
	const BMessage* dragMessage)
{
	// Hover selects, but only on real movement: a list that changes under a
	// resting pointer must not steal the keyboard selection.
	if (transit == B_EXITED_VIEW || where == fLastMouse)
		return;
	bool first = fLastMouse.x < 0;
	fLastMouse = where;
	if (first)
		return;
	int32 index = _IndexAt(where);
	if (index >= 0)
		Select(index);
}


void
ResultsView::MessageReceived(BMessage* message)
{
	if (message->what == B_MOUSE_WHEEL_CHANGED) {
		float delta;
		if (message->FindFloat("be:wheel_delta_y", &delta) == B_OK)
			_ScrollBy(delta * Theme::Get().rowHeight);
		return;
	}
	BView::MessageReceived(message);
}
