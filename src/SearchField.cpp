#include "SearchField.h"

#include <algorithm>
#include <math.h>

#include <Window.h>

#include "Kigo.h"
#include "SearchWindow.h"
#include "Theme.h"


static BFont
FieldFont()
{
	BFont font(be_plain_font);
	font.SetSize(roundf(be_plain_font->Size() * 1.7f));
	return font;
}


SearchField::SearchField(BRect frame, SearchWindow* window)
	:
	BTextView(frame, "query", frame.OffsetToCopy(B_ORIGIN), B_FOLLOW_NONE,
		B_WILL_DRAW | B_FRAME_EVENTS | B_NAVIGABLE),
	fSearchWindow(window)
{
	const Theme& theme = Theme::Get();
	BFont font = FieldFont();
	SetFontAndColor(&font, B_FONT_ALL, &theme.text);
	SetViewColor(theme.background);
	SetLowColor(theme.background);
	SetWordWrap(false);
	SetStylable(false);
	DisallowChar('\n');
	DisallowChar('\t');
	_UpdateTextRect();
}


void
SearchField::_UpdateTextRect()
{
	BRect rect = Bounds();
	float lineHeight = LineHeight(0);
	if (lineHeight <= 0) {
		font_height height;
		FieldFont().GetHeight(&height);
		lineHeight = ceilf(height.ascent + height.descent + height.leading);
	}
	rect.top = floorf((rect.Height() - lineHeight) / 2);
	rect.bottom = rect.top + lineHeight;
	SetTextRect(rect);
}


void
SearchField::FrameResized(float width, float height)
{
	BTextView::FrameResized(width, height);
	_UpdateTextRect();
}


void
SearchField::SetPlaceholder(const char* text)
{
	fPlaceholder = text;
	Invalidate();
}


void
SearchField::Draw(BRect updateRect)
{
	BTextView::Draw(updateRect);
	if (TextLength() > 0 || fPlaceholder.IsEmpty())
		return;

	const Theme& theme = Theme::Get();
	BFont font = FieldFont();
	font_height height;
	font.GetHeight(&height);
	SetFont(&font);
	SetHighColor(theme.faintText);
	SetLowColor(theme.background);
	BRect text = TextRect();
	// Leave room for the caret.
	DrawString(fPlaceholder.String(),
		BPoint(text.left + 2, text.top + ceilf(height.ascent)));
	SetHighColor(theme.text);
}


void
SearchField::KeyDown(const char* bytes, int32 numBytes)
{
	int32 modifiers = 0;
	if (Window()->CurrentMessage() != NULL)
		Window()->CurrentMessage()->FindInt32("modifiers", &modifiers);

	if (numBytes == 1 && _MacEditingKey(bytes[0], modifiers))
		return;
	if (numBytes == 1 && fSearchWindow->HandleKey(bytes[0], modifiers))
		return;
	BTextView::KeyDown(bytes, numBytes);
}


// Mac editing keys. A Mac keyboard in UTM sends Option as Haiku's Command
// (Alt) key and Cmd as Option, so: Alt+Left/Right moves by word, Option+
// Left/Right to the start/end, and the same with Backspace deletes.
bool
SearchField::_MacEditingKey(char key, int32 modifiers)
{
	bool word = (modifiers & B_COMMAND_KEY) != 0 && (modifiers & B_OPTION_KEY) == 0;
	bool line = (modifiers & B_OPTION_KEY) != 0 && (modifiers & B_COMMAND_KEY) == 0;
	bool shift = (modifiers & B_SHIFT_KEY) != 0;
	if (!word && !line)
		return false;
	if (key != B_LEFT_ARROW && key != B_RIGHT_ARROW && key != B_BACKSPACE)
		return false;

	const char* text = Text();
	int32 length = TextLength();
	int32 start, end;
	GetSelection(&start, &end);
	int32 caret = end;
	if (key != B_RIGHT_ARROW)
		caret = start;

	int32 target;
	if (line)
		target = key == B_RIGHT_ARROW ? length : 0;
	else if (key == B_RIGHT_ARROW) {
		target = caret;
		while (target < length && text[target] == ' ')
			target++;
		while (target < length && text[target] != ' ')
			target++;
	} else {
		target = caret;
		while (target > 0 && text[target - 1] == ' ')
			target--;
		while (target > 0 && text[target - 1] != ' ')
			target--;
	}

	if (key == B_BACKSPACE) {
		if (start != end)
			Delete(start, end);
		else if (target < caret)
			Delete(target, caret);
		return true;
	}
	if (shift) {
		// Extend from the end that isn't moving.
		int32 anchor = key == B_RIGHT_ARROW ? start : end;
		Select(std::min(anchor, target), std::max(anchor, target));
	} else
		Select(target, target);
	ScrollToSelection();
	return true;
}


void
SearchField::InsertText(const char* text, int32 length, int32 offset,
	const text_run_array* runs)
{
	// Pasted line breaks would make a multi-line query; flatten them.
	BString clean(text, length);
	clean.ReplaceAll('\n', ' ');
	clean.ReplaceAll('\t', ' ');
	BTextView::InsertText(clean.String(), clean.Length(), offset, runs);
	_Changed();
}


void
SearchField::DeleteText(int32 fromOffset, int32 toOffset)
{
	BTextView::DeleteText(fromOffset, toOffset);
	_Changed();
}


void
SearchField::_Changed()
{
	if (Window() != NULL)
		Window()->PostMessage(kMsgQueryChanged);
	// The placeholder disappears or comes back.
	Invalidate();
}
