#include "SearchWindow.h"

#include <algorithm>
#include <math.h>
#include <stdlib.h>

#include <Application.h>
#include <Beep.h>
#include <Bitmap.h>
#include <MessageRunner.h>
#include <Path.h>
#include <Screen.h>

#include "Calculator.h"
#include "Commands.h"
#include "Fuzzy.h"
#include "IconCache.h"
#include "Kigo.h"
#include "Prefs.h"
#include "ResultsView.h"
#include "SearchField.h"
#include "SettingsView.h"
#include "Setup.h"
#include "Theme.h"


static const bigtime_t kFileSearchDelay = 110000;
static const int32 kMaxApps = 8;
static const int32 kMaxCommands = 4;
static const int32 kMaxFiles = 8;
static const float kTopHitScore = 700;
// How long the window takes to grow into settings, or shrink back.
static const bigtime_t kMorphDuration = 220000;
static const bigtime_t kMorphFrame = 1000000 / 60;


// Background of the whole panel: border, the line under the field, and the
// magnifier glyph left of the query, which turns into the settings page's
// "‹ Settings" header as the window grows into it.
class PanelView : public BView {
public:
	PanelView(BRect frame)
		:
		BView(frame, "panel", B_FOLLOW_ALL, B_WILL_DRAW | B_FRAME_EVENTS),
		fSettings(0)
	{
		SetViewColor(B_TRANSPARENT_COLOR);
	}

	// 0 the search field's magnifier, 1 the settings header.
	void SetSettings(float amount)
	{
		if (amount != fSettings) {
			fSettings = amount;
			Invalidate(BRect(0, 0, Bounds().right, Theme::Get().fieldHeight - 1));
		}
	}

	void MouseDown(BPoint where) override
	{
		// The "‹ Settings" header goes back to searching.
		if (fSettings >= 1 && where.y < Theme::Get().fieldHeight
			&& where.x < fHeaderRight) {
			static_cast<SearchWindow*>(Window())->CloseSettings();
		}
	}

	void Draw(BRect updateRect) override
	{
		const Theme& theme = Theme::Get();
		BRect bounds = Bounds();
		SetHighColor(theme.background);
		FillRect(updateRect);

		// The magnifier fades out over the first half, then the settings
		// header fades in over the second: they share a spot, and drawn at
		// once they'd overlap.
		float size = roundf(18 * theme.scale);
		float left = theme.padding + roundf(6 * theme.scale);
		float centerY = roundf(theme.fieldHeight / 2);
		float magnifier = std::max(0.0f, 1 - 2 * fSettings);
		float header = std::max(0.0f, 2 * fSettings - 1);
		SetPenSize(roundf(2 * theme.scale));
		if (magnifier > 0) {
			BPoint center(left + size * 0.42f, centerY - size * 0.08f);
			float radius = size * 0.32f;
			SetHighColor(MixColors(theme.background, theme.dimText, magnifier));
			StrokeEllipse(center, radius, radius);
			float offset = radius * 0.72f;
			StrokeLine(BPoint(center.x + offset, center.y + offset),
				BPoint(center.x + size * 0.55f, center.y + size * 0.55f));
		}
		if (header > 0) {
			// A chevron where the magnifier was, and the page's title where
			// the query was.
			float chevron = size * 0.3f;
			float x = left + size * 0.5f;
			SetHighColor(MixColors(theme.background, theme.dimText, header));
			StrokeLine(BPoint(x + chevron * 0.5f, centerY - chevron),
				BPoint(x - chevron * 0.5f, centerY));
			StrokeLine(BPoint(x - chevron * 0.5f, centerY),
				BPoint(x + chevron * 0.5f, centerY + chevron));

			BFont font(be_bold_font);
			font.SetSize(roundf(theme.fontSize * 1.45f));
			SetFont(&font);
			font_height height;
			font.GetHeight(&height);
			float titleLeft = theme.padding + roundf(34 * theme.scale);
			SetLowColor(theme.background);
			SetHighColor(MixColors(theme.background, theme.text, header));
			DrawString("Settings", BPoint(titleLeft,
				roundf(centerY + (height.ascent - height.descent) / 2)));
			fHeaderRight = titleLeft + font.StringWidth("Settings")
				+ roundf(8 * theme.scale);
		}
		SetPenSize(1);

		if (bounds.Height() > theme.fieldHeight + 1) {
			SetHighColor(theme.separator);
			StrokeLine(BPoint(bounds.left, theme.fieldHeight),
				BPoint(bounds.right, theme.fieldHeight));
		}

		SetHighColor(theme.border);
		StrokeRect(bounds);
	}

private:
	float	fSettings;
	float	fHeaderRight = 0;
};


// Raycast-style action bar: what Enter does, plus the secondary shortcuts.
class FooterView : public BView {
public:
	FooterView(BRect frame)
		:
		BView(frame, "footer", B_FOLLOW_NONE, B_WILL_DRAW),
		fResult(NULL),
		fConfirming(false),
		fSettings(false)
	{
		SetViewColor(B_TRANSPARENT_COLOR);
	}

	void SetResult(const Result* result, bool confirming)
	{
		fResult = result;
		fConfirming = confirming;
		Invalidate();
	}

	// The settings page's keys instead of a result's actions.
	void SetSettings(bool settings)
	{
		fSettings = settings;
		Invalidate();
	}

	void Draw(BRect updateRect) override
	{
		const Theme& theme = Theme::Get();
		BRect bounds = Bounds();
		SetHighColor(theme.footerBackground);
		FillRect(bounds);
		SetHighColor(theme.separator);
		StrokeLine(bounds.LeftTop(), bounds.RightTop());
		SetHighColor(theme.border);
		StrokeLine(bounds.LeftTop(), bounds.LeftBottom());
		StrokeLine(bounds.RightTop(), bounds.RightBottom());
		StrokeLine(bounds.LeftBottom(), bounds.RightBottom());

		BFont font(be_plain_font);
		font.SetSize(roundf(Theme::Get().fontSize * 0.92f));
		SetFont(&font);
		font_height height;
		font.GetHeight(&height);
		float baseline = roundf(bounds.Height() / 2
			+ (height.ascent - height.descent) / 2);

		SetLowColor(theme.footerBackground);
		SetHighColor(theme.faintText);
		DrawString("Kigo", BPoint(theme.padding + 4 * theme.scale, baseline));

		if (fSettings) {
			float right = bounds.right - theme.padding;
			right = _DrawAction("Back", "Esc", right, baseline, font, true);
			_DrawAction("Change", "Space", right, baseline, font, false);
			return;
		}
		if (fResult == NULL)
			return;

		// Right to left: [Copy Alt Shift C]  [Reveal Alt Enter]  [Open Enter]
		float right = bounds.right - theme.padding;
		right = _DrawAction(fConfirming ? "Confirm" : PrimaryActionLabel(*fResult),
			"Enter", right, baseline, font, true);
		if (CanReveal(*fResult)) {
			right = _DrawAction("Show in Tracker", "Alt Enter", right, baseline,
				font, false);
		}
		if (fResult->kind != kKindCommand)
			_DrawAction("Copy", "Alt Shift C", right, baseline, font, false);
	}

private:
	float _DrawAction(const char* label, const char* keys, float right,
		float baseline, const BFont& font, bool primary)
	{
		const Theme& theme = Theme::Get();
		float gap = roundf(6 * theme.scale);
		float keyPadding = roundf(5 * theme.scale);

		// Keycaps, each word its own cap.
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
		font_height height;
		font.GetHeight(&height);
		for (auto it = caps.rbegin(); it != caps.rend(); ++it) {
			float width = font.StringWidth(it->String()) + 2 * keyPadding;
			BRect cap(right - width, baseline - ceilf(height.ascent) - 3 * theme.scale,
				right, baseline + ceilf(height.descent) + 2 * theme.scale);
			SetHighColor(theme.keycap);
			FillRoundRect(cap, 4 * theme.scale, 4 * theme.scale);
			SetHighColor(theme.dimText);
			SetLowColor(theme.keycap);
			DrawString(it->String(), BPoint(cap.left + keyPadding, baseline));
			right = cap.left - roundf(3 * theme.scale);
		}
		right -= gap - roundf(3 * theme.scale);

		SetLowColor(theme.footerBackground);
		SetHighColor(primary ? theme.text : theme.dimText);
		float width = font.StringWidth(label);
		DrawString(label, BPoint(right - width, baseline));
		return right - width - roundf(18 * theme.scale);
	}

	const Result*	fResult;
	bool			fConfirming;
	bool			fSettings;
};


SearchWindow::SearchWindow()
	:
	BWindow(BRect(0, 0, 100, 100), "Kigo", B_NO_BORDER_WINDOW_LOOK,
		B_FLOATING_ALL_WINDOW_FEEL,
		B_NOT_MOVABLE | B_NOT_RESIZABLE | B_NOT_ZOOMABLE | B_NOT_MINIMIZABLE
			| B_NOT_CLOSABLE | B_ASYNCHRONOUS_CONTROLS,
		B_ALL_WORKSPACES),
	fSettingsOpen(false),
	fMorphRunner(NULL),
	fMorphStart(0),
	fMorphDuration(0),
	fMorphOpening(false),
	fMorphFade(true),
	fFileSearch(NULL),
	fFileSearchRunner(NULL),
	fGeneration(0),
	fFileGeneration(-1)
{
	Theme::Refresh();
	const Theme& theme = Theme::Get();
	IconCache::Get().SetIconSize(theme.iconSize);
	ResizeTo(theme.width - 1, theme.fieldHeight);

	fBackground = new PanelView(Bounds());
	AddChild(fBackground);

	float fieldLeft = theme.padding + roundf(34 * theme.scale);
	BRect fieldFrame(fieldLeft, 2, theme.width - theme.padding - 1,
		theme.fieldHeight - 2);
	fField = new SearchField(fieldFrame, this);
	fField->SetPlaceholder("Search apps, files, and commands");
	fBackground->AddChild(fField);

	fList = new ResultsView(BRect(1, theme.fieldHeight + 1, theme.width - 2,
		theme.fieldHeight + 2), this);
	fBackground->AddChild(fList);
	fList->Hide();

	fSettings = new SettingsView(BRect(1, theme.fieldHeight + 1, theme.width - 2,
		theme.fieldHeight + 2), this);
	fBackground->AddChild(fSettings);
	fSettings->Hide();

	fFooter = new FooterView(BRect(0, 0, theme.width - 1, theme.footerHeight - 1));
	fBackground->AddChild(fFooter);
	fFooter->Hide();

	fFileSearch = new FileSearch(BMessenger(this));
	fHistory.Load();
	fApps.Rebuild();

	// Alt-combos reach us as shortcuts, before the text view sees them.
	AddShortcut(B_ENTER, B_COMMAND_KEY, new BMessage('LRvl'));
	AddShortcut('C', B_COMMAND_KEY | B_SHIFT_KEY, new BMessage('LCpy'));
	for (int32 i = 1; i <= 9; i++) {
		BMessage* open = new BMessage('LNth');
		open->AddInt32("index", i - 1);
		AddShortcut('0' + i, B_COMMAND_KEY, open);
	}
	AddShortcut('W', B_COMMAND_KEY, new BMessage('LHid'));
	// Alt+, (Option+, on a Mac in UTM): settings, as everywhere. Cmd+, on a
	// Mac arrives as Option+, and is caught in DispatchMessage, since
	// shortcuts always need Alt.
	BMessage* settings = new BMessage(kMsgOpenSettings);
	settings->AddBool("toggle", true);
	AddShortcut(',', B_COMMAND_KEY, settings);
}


SearchWindow::~SearchWindow()
{
	delete fMorphRunner;
	delete fFileSearchRunner;
	delete fFileSearch;
}


bool
SearchWindow::QuitRequested()
{
	// Alt+Q quits the app; closing the panel only hides it.
	be_app->PostMessage(B_QUIT_REQUESTED);
	return false;
}


BString
SearchWindow::_Query() const
{
	BString query(fField->Text());
	query.Trim();
	return query;
}


void
SearchWindow::ShowLauncher()
{
	fApps.RefreshIfStale(30000000);

	// A third of the way down the screen the window is on, like Spotlight.
	BScreen screen(this);
	BRect frame = screen.Frame();
	const Theme& theme = Theme::Get();
	MoveTo(roundf(frame.left + (frame.Width() - theme.width) / 2),
		roundf(frame.top + frame.Height() * 0.22f));

	_UpdateResults(false);
	if (IsHidden())
		Show();
	Activate(true);
	fField->MakeFocus(true);
	fField->SelectAll();
}


void
SearchWindow::HideLauncher()
{
	if (!IsHidden())
		Hide();
	fList->SetConfirming("");
	// Next time it opens on the search field, with no animation left over.
	if (!fSettings->IsHidden()) {
		fSettingsOpen = false;
		_FinishClosing();
	}
}


void
SearchWindow::Toggle()
{
	if (!IsHidden() && IsActive())
		HideLauncher();
	else
		ShowLauncher();
}


void
SearchWindow::DispatchMessage(BMessage* message, BHandler* target)
{
	// Option+, (Cmd+, on a Mac in UTM) toggles settings too, whichever view
	// has focus. raw_char ignores the Option keymap, which turns ',' into
	// another character.
	if (message->what == B_KEY_DOWN || message->what == B_UNMAPPED_KEY_DOWN) {
		int32 modifiers = message->GetInt32("modifiers", 0);
		int32 raw = message->GetInt32("raw_char", 0);
		if (raw == ',' && (modifiers & B_OPTION_KEY) != 0
			&& (modifiers & (B_COMMAND_KEY | B_CONTROL_KEY)) == 0) {
			BMessage settings(kMsgOpenSettings);
			settings.AddBool("toggle", true);
			PostMessage(&settings);
			return;
		}
	}
	BWindow::DispatchMessage(message, target);
}


void
SearchWindow::WindowActivated(bool active)
{
	// Click elsewhere and it goes away, like Spotlight.
	if (!active)
		HideLauncher();
}


bool
SearchWindow::HandleKey(char key, int32 modifiers)
{
	bool command = (modifiers & B_COMMAND_KEY) != 0;
	bool control = (modifiers & B_CONTROL_KEY) != 0;
	bool shift = (modifiers & B_SHIFT_KEY) != 0;

	switch (key) {
		case B_UP_ARROW:
			fList->MoveSelection(-1);
			return true;
		case B_DOWN_ARROW:
			fList->MoveSelection(1);
			return true;
		case B_PAGE_UP:
			fList->MoveSelection(-5);
			return true;
		case B_PAGE_DOWN:
			fList->MoveSelection(5);
			return true;
		case B_ENTER:
			InvokeSelection(command, shift);
			return true;
		case B_ESCAPE:
			if (fField->TextLength() > 0)
				fField->SetText("");
			else
				HideLauncher();
			return true;
		case B_TAB:
			// Tab completes the selected title, like a shell.
			if (const Result* result = fList->SelectedResult()) {
				if (result->kind != kKindCalculator && result->kind != kKindWeb
					&& result->kind != kKindShell) {
					fField->SetText(result->title.String());
					fField->Select(fField->TextLength(), fField->TextLength());
				}
			}
			return true;
	}

	// Emacs-style Ctrl+N / Ctrl+P, as in Raycast.
	if (control && !command) {
		if (key == 0x0e) {
			fList->MoveSelection(1);
			return true;
		}
		if (key == 0x10) {
			fList->MoveSelection(-1);
			return true;
		}
	}
	return false;
}


void
SearchWindow::SelectionChanged()
{
	const Result* result = fList->SelectedResult();
	fFooter->SetResult(result, result != NULL
		&& fList->Confirming() == result->id);
}


void
SearchWindow::InvokeSelection(bool reveal, bool alternate)
{
	const Result* result = fList->SelectedResult();
	if (result == NULL) {
		beep();
		return;
	}
	// Copy it: the list owns the result and _Invoke may rebuild the list.
	Result selected = *result;
	_Invoke(selected, reveal, alternate);
}


void
SearchWindow::_Invoke(const Result& result, bool reveal, bool alternate)
{
	if (reveal) {
		if (!CanReveal(result)) {
			beep();
			return;
		}
		HideLauncher();
		if (!RevealResult(result))
			beep();
		return;
	}

	// Restart, Shut Down and Empty Trash ask twice, like Raycast.
	if (result.needsConfirm && fList->Confirming() != result.id) {
		fList->SetConfirming(result.id.String());
		return;
	}

	if (result.kind == kKindCommand && result.payload == "settings") {
		fHistory.Record(result.id.String(), result.title.String());
		fField->SetText("");
		OpenSettings();
		return;
	}

	HideLauncher();
	if (!OpenResult(result, alternate, BMessenger(be_app))) {
		beep();
		return;
	}

	bool remember = result.kind == kKindApp || result.kind == kKindPreference
		|| result.kind == kKindFile || result.kind == kKindFolder
		|| (result.kind == kKindCommand && !result.id.StartsWith("cmd:quit")
			&& !result.id.StartsWith("cmd:workspace"));
	if (remember)
		fHistory.Record(result.id.String(), result.title.String());

	// Back to a clean slate for next time, as Raycast does.
	fField->SetText("");
}


void
SearchWindow::_CopySelection()
{
	const Result* result = fList->SelectedResult();
	if (result == NULL || result->kind == kKindCommand) {
		beep();
		return;
	}
	CopyResult(*result);
	HideLauncher();
}


void
SearchWindow::MessageReceived(BMessage* message)
{
	switch (message->what) {
		case kMsgToggle:
			Toggle();
			break;
		case kMsgShow:
			ShowLauncher();
			break;
		case kMsgQueryChanged:
			_QueryChanged();
			break;
		case kMsgRunFileSearch:
		{
			delete fFileSearchRunner;
			fFileSearchRunner = NULL;
			int32 generation;
			if (message->FindInt32("generation", &generation) == B_OK
				&& generation == fGeneration) {
				fFileQuery = _Query();
				fFileSearch->Start(fFileQuery.String(), generation);
			}
			break;
		}
		case kMsgFileResults:
			_FileResultsArrived(message);
			break;
		case kMsgReindex:
			fApps.Rebuild();
			_UpdateResults(true);
			break;
		case kMsgOpenSettings:
			// Alt+, again goes back.
			if (fSettingsOpen) {
				if (message->GetBool("toggle", false))
					CloseSettings();
			} else {
				if (IsHidden())
					ShowLauncher();
				OpenSettings();
			}
			break;
		case kMsgSettingChanged:
			_SettingChanged(message->GetString("key", ""));
			break;
		case kMsgMorph:
			_MorphStep();
			break;
		case 'LRvl':
			if (!fSettingsOpen)
				InvokeSelection(true, false);
			break;
		case 'LCpy':
			if (!fSettingsOpen)
				_CopySelection();
			break;
		case 'LNth':
		{
			if (fSettingsOpen)
				break;
			int32 index;
			if (message->FindInt32("index", &index) == B_OK
				&& index < fList->CountResults()) {
				Result result = fList->Results()[index];
				_Invoke(result, false, false);
			}
			break;
		}
		case 'LHid':
			HideLauncher();
			break;
		case B_COLORS_UPDATED:
		case B_FONTS_UPDATED:
		{
			// Appearance changed: rebuild metrics and icons at the new size.
			Theme::Refresh();
			_ApplyTheme();
			_UpdateResults(true);
			break;
		}
		default:
			BWindow::MessageReceived(message);
	}
}


void
SearchWindow::_QueryChanged()
{
	fGeneration++;
	BString query = _Query();

	// Re-score the previous file hits against the new query so the list
	// doesn't flash empty while the new search runs.
	std::vector<Result> kept;
	for (Result& result : fFileResults) {
		float score = FuzzyScore(query.String(), result.title.String());
		if (score > 0) {
			result.score = score * 0.75f;
			kept.push_back(result);
		}
	}
	fFileResults = kept;
	_UpdateResults(false);

	delete fFileSearchRunner;
	fFileSearchRunner = NULL;
	BString calc;
	bool calculated = Prefs::Get().calculator && Calculate(query.String(), calc);
	if (Prefs::Get().searchFiles && query.Length() >= 2 && query[0] != '>'
		&& !calculated) {
		BMessage run(kMsgRunFileSearch);
		run.AddInt32("generation", fGeneration);
		fFileSearchRunner = new BMessageRunner(BMessenger(this), &run,
			kFileSearchDelay, 1);
	} else {
		fFileSearch->Cancel();
		fFileResults.clear();
	}
}


void
SearchWindow::_FileResultsArrived(BMessage* message)
{
	int32 generation;
	if (message->FindInt32("generation", &generation) != B_OK
		|| generation != fGeneration) {
		return;
	}

	fFileResults.clear();
	entry_ref ref;
	for (int32 i = 0; message->FindRef("ref", i, &ref) == B_OK; i++) {
		float score = message->GetFloat("score", i, 0);
		BEntry entry(&ref);
		BPath path(&entry);
		Result result;
		result.kind = entry.IsDirectory() ? kKindFolder : kKindFile;
		result.title = ref.name;
		BPath parent;
		path.GetParent(&parent);
		BString where(parent.Path());
		where.ReplaceFirst("/boot/home", "~");
		result.subtitle = where;
		result.id.SetToFormat("file:%s", path.Path());
		result.ref = ref;
		result.hasRef = true;
		result.icon = IconCache::Get().ForRef(ref);
		result.score = score;
		fFileResults.push_back(result);
	}
	fFileGeneration = generation;
	_UpdateResults(true);
}


void
SearchWindow::_AddSuggestions(std::vector<Result>& results)
{
	for (const BString& id : fHistory.Top(8)) {
		Result result;
		if (id.StartsWith("app:")) {
			AppEntry entry;
			if (!fApps.Find(id.String() + 4, entry))
				continue;
			result = AppIndex::MakeResult(entry);
		} else if (id.StartsWith("file:")) {
			BEntry entry(id.String() + 5);
			if (!entry.Exists() || entry.GetRef(&result.ref) != B_OK)
				continue;
			result.kind = entry.IsDirectory() ? kKindFolder : kKindFile;
			result.title = result.ref.name;
			BPath path(&entry);
			BPath parent;
			path.GetParent(&parent);
			result.subtitle = parent.Path();
			result.subtitle.ReplaceFirst("/boot/home", "~");
			result.id = id;
			result.hasRef = true;
			result.icon = IconCache::Get().ForRef(result.ref);
		} else if (!CommandForId(id.String(), result))
			continue;
		result.section = "Suggestions";
		results.push_back(result);
	}
}


static void
TakeBest(std::vector<Result>& from, int32 count, const char* section,
	std::vector<Result>& to)
{
	std::stable_sort(from.begin(), from.end(),
		[](const Result& a, const Result& b) { return a.score > b.score; });
	for (int32 i = 0; i < (int32)from.size() && i < count; i++) {
		from[i].section = section;
		to.push_back(from[i]);
	}
}


void
SearchWindow::_UpdateResults(bool keepSelection)
{
	BString previous;
	if (keepSelection && fList->SelectedResult() != NULL)
		previous = fList->SelectedResult()->id;

	BString query = _Query();
	std::vector<Result> results;

	const Prefs& prefs = Prefs::Get();
	if (query.IsEmpty()) {
		if (prefs.suggestions)
			_AddSuggestions(results);
	} else if (query[0] == '>') {
		// "> command" runs a shell command in Terminal.
		BString command(query.String() + 1);
		command.Trim();
		Result shell;
		shell.kind = kKindShell;
		shell.title = command.IsEmpty() ? "Type a shell command" : command;
		shell.subtitle = "Run in Terminal";
		shell.payload = command;
		shell.id = "shell";
		shell.section = "Terminal";
		shell.icon = IconCache::Get().ForSignature(
			"application/x-vnd.Haiku-Terminal");
		if (!command.IsEmpty())
			results.push_back(shell);
	} else {
		BString value;
		if (prefs.calculator && Calculate(query.String(), value)) {
			Result calc;
			calc.kind = kKindCalculator;
			calc.title.SetToFormat("= %s", value.String());
			calc.subtitle = query;
			calc.payload = value;
			calc.id = "calc";
			calc.section = "Calculator";
			calc.icon = IconCache::Get().ForSignature(
				"application/x-vnd.Haiku-DeskCalc");
			results.push_back(calc);
		}

		BString url;
		if (LooksLikeURL(query.String(), url)) {
			Result link;
			link.kind = kKindURL;
			link.title.SetToFormat("Open %s", query.String());
			link.subtitle = url;
			link.payload = url;
			link.id = "url";
			link.section = "Link";
			link.icon = IconCache::Get().ForMimeType("text/html");
			results.push_back(link);
		}

		std::vector<Result> apps, commands, files;
		if (prefs.searchApps)
			fApps.Search(query.String(), apps);
		// Kigo Settings stays findable with commands off.
		SearchCommands(query.String(), commands, prefs.searchCommands);
		if (prefs.searchFiles)
			files = fFileResults;
		for (auto* list : {&apps, &commands, &files}) {
			for (Result& result : *list)
				result.score += fHistory.Boost(result.id.String());
		}

		// Top Hit: the single best match across kinds, Spotlight-style.
		Result* best = NULL;
		std::vector<Result>* bestList = NULL;
		for (auto* list : {&apps, &commands, &files}) {
			for (Result& result : *list) {
				if (result.score >= kTopHitScore
					&& (best == NULL || result.score > best->score)) {
					best = &result;
					bestList = list;
				}
			}
		}
		if (best != NULL) {
			Result top = *best;
			top.section = "Top Hit";
			bestList->erase(bestList->begin() + (best - bestList->data()));
			results.push_back(top);
		}

		TakeBest(apps, kMaxApps, "Applications", results);
		TakeBest(commands, kMaxCommands, "Commands", results);
		TakeBest(files, kMaxFiles, "Files", results);

		// Fallbacks, always last: search the web, or run it as a command.
		BString fallbacks;
		fallbacks.SetToFormat("Use \"%s\" with...", query.String());
		if (prefs.webSearch != kWebOff) {
			Result web;
			web.kind = kKindWeb;
			web.title.SetToFormat("Search the web for \"%s\"", query.String());
			web.subtitle = prefs.WebSearchName();
			BString encoded(query);
			encoded.ReplaceAll("%", "%25");
			encoded.ReplaceAll("&", "%26");
			encoded.ReplaceAll("#", "%23");
			encoded.ReplaceAll("+", "%2B");
			encoded.ReplaceAll(" ", "+");
			prefs.WebSearchURL(encoded.String(), web.payload);
			web.id = "web";
			web.section = fallbacks;
			web.icon = IconCache::Get().ForMimeType("text/html");
			results.push_back(web);
		}

		Result shell;
		shell.kind = kKindShell;
		shell.title.SetToFormat("Run \"%s\"", query.String());
		shell.subtitle = "in Terminal (or type > first)";
		shell.payload = query;
		shell.id = "shell";
		shell.section = fallbacks;
		shell.icon = IconCache::Get().ForSignature(
			"application/x-vnd.Haiku-Terminal");
		results.push_back(shell);
	}

	int32 selection = 0;
	if (!previous.IsEmpty()) {
		for (int32 i = 0; i < (int32)results.size(); i++) {
			if (results[i].id == previous) {
				selection = i;
				break;
			}
		}
	}
	fList->SetResults(results, selection);
	SelectionChanged();
	_Relayout();
}


float
SearchWindow::_SearchHeight() const
{
	const Theme& theme = Theme::Get();
	float height = theme.fieldHeight;
	if (fList->CountResults() > 0)
		height += 1 + fList->PreferredHeight() + theme.footerHeight;
	return height;
}


void
SearchWindow::_Relayout()
{
	// The settings page lays itself out while it's showing.
	if (!fSettings->IsHidden())
		return;
	const Theme& theme = Theme::Get();
	bool hasResults = fList->CountResults() > 0;
	float listHeight = hasResults ? fList->PreferredHeight() : 0;
	float height = _SearchHeight();

	if (hasResults) {
		fList->MoveTo(1, theme.fieldHeight + 1);
		fList->ResizeTo(theme.width - 3, listHeight - 1);
		if (fList->IsHidden())
			fList->Show();
		fFooter->MoveTo(0, theme.fieldHeight + 1 + listHeight);
		fFooter->ResizeTo(theme.width - 1, theme.footerHeight - 1);
		if (fFooter->IsHidden())
			fFooter->Show();
	} else {
		if (!fList->IsHidden())
			fList->Hide();
		if (!fFooter->IsHidden())
			fFooter->Hide();
	}

	if (Bounds().Height() != height - 1 || Bounds().Width() != theme.width - 1) {
		ResizeTo(theme.width - 1, height - 1);
		fBackground->Invalidate();
	}
	fList->Invalidate();
}


// Settings ------------------------------------------------------------------


// The settings page's frame: wider than the launcher, as tall as its rows
// (scrolling past most of the screen), keeping the launcher's top and center.
BRect
SearchWindow::_SettingsFrame() const
{
	const Theme& theme = Theme::Get();
	BRect frame = Frame();
	float width = roundf(theme.width * 1.12f);
	float center = frame.left + (frame.Width() + 1) / 2;
	BRect screen = BScreen(const_cast<SearchWindow*>(this)).Frame();
	float chrome = theme.fieldHeight + 1 + theme.footerHeight;
	float most = screen.bottom - frame.top - roundf(48 * theme.scale) - chrome;
	float body = std::min(fSettings->ContentHeight(), std::max(most,
		theme.rowHeight * 3));
	float left = roundf(center - width / 2);
	return BRect(left, frame.top, left + width - 1, frame.top + chrome + body - 1);
}


void
SearchWindow::OpenSettings()
{
	if (fSettingsOpen)
		return;
	fSettingsOpen = true;
	if (fSettings->IsHidden()) {
		fField->Hide();
		fList->Hide();
		fSettings->Reset();
		fSettings->SetOpacity(0);
		fSettings->Show();
		fFooter->SetSettings(true);
		if (fFooter->IsHidden())
			fFooter->Show();
		_PlaceSettings();
	}
	fSettings->MakeFocus(true);
	_Morph(_SettingsFrame(), true);
}


void
SearchWindow::CloseSettings()
{
	if (!fSettingsOpen)
		return;
	fSettingsOpen = false;
	// The results as they'll be with the new settings, so the window
	// shrinks to the right height.
	_UpdateResults(false);
	const Theme& theme = Theme::Get();
	BRect frame = Frame();
	float center = frame.left + (frame.Width() + 1) / 2;
	float left = roundf(center - theme.width / 2);
	_Morph(BRect(left, frame.top, left + theme.width - 1,
		frame.top + _SearchHeight() - 1), false);
}


void
SearchWindow::_Morph(BRect to, bool opening, bool fade)
{
	fMorphFrom = Frame();
	fMorphTo = to;
	fMorphOpening = opening;
	fMorphFade = fade;
	fMorphStart = system_time();
	// KIGO_SLOW=10 plays it ten times slower, to look at the frames.
	fMorphDuration = kMorphDuration;
	if (const char* slow = getenv("KIGO_SLOW")) {
		if (atof(slow) > 0)
			fMorphDuration = (bigtime_t)(kMorphDuration * atof(slow));
	}
	if (fMorphRunner == NULL) {
		BMessage step(kMsgMorph);
		fMorphRunner = new BMessageRunner(BMessenger(this), &step, kMorphFrame);
	}
	_MorphStep();
}


// One frame of the window growing into settings (or shrinking back): the
// frame eases out, the page fades in after the window has started to grow,
// and fades out quickly when going back.
void
SearchWindow::_MorphStep()
{
	if (fMorphRunner == NULL)
		return;
	float t = (system_time() - fMorphStart) / (float)fMorphDuration;
	t = std::min(std::max(t, 0.0f), 1.0f);
	float eased = 1 - powf(1 - t, 3);

	BRect frame(
		roundf(fMorphFrom.left + (fMorphTo.left - fMorphFrom.left) * eased),
		roundf(fMorphFrom.top + (fMorphTo.top - fMorphFrom.top) * eased),
		roundf(fMorphFrom.right + (fMorphTo.right - fMorphFrom.right) * eased),
		roundf(fMorphFrom.bottom + (fMorphTo.bottom - fMorphFrom.bottom) * eased));
	MoveTo(frame.LeftTop());
	ResizeTo(frame.Width(), frame.Height());

	if (fMorphFade) {
		float shown = fMorphOpening
			? std::min(std::max((t - 0.2f) / 0.8f, 0.0f), 1.0f)
			: std::max(1 - t * 2.5f, 0.0f);
		fSettings->SetOpacity(1 - powf(1 - shown, 2));
		fBackground->SetSettings(fMorphOpening ? eased : 1 - eased);
	}
	_PlaceSettings();
	fBackground->Invalidate();

	if (t < 1)
		return;
	delete fMorphRunner;
	fMorphRunner = NULL;
	if (!fMorphOpening)
		_FinishClosing();
}


// Back on the search field, as the launcher was before settings.
void
SearchWindow::_FinishClosing()
{
	delete fMorphRunner;
	fMorphRunner = NULL;
	fSettings->Hide();
	fFooter->SetSettings(false);
	fBackground->SetSettings(0);
	fField->Show();
	fField->MakeFocus(true);
	_Relayout();
	SelectionChanged();
	fBackground->Invalidate();
}


// The page fills the window between the header and the footer, at whatever
// size the window is mid-animation.
void
SearchWindow::_PlaceSettings()
{
	const Theme& theme = Theme::Get();
	BRect bounds = Bounds();
	float footerTop = bounds.bottom + 1 - theme.footerHeight;
	fSettings->MoveTo(1, theme.fieldHeight + 1);
	fSettings->ResizeTo(bounds.Width() - 2,
		std::max(0.0f, footerTop - theme.fieldHeight - 2));
	fFooter->MoveTo(0, footerTop);
	fFooter->ResizeTo(bounds.Width(), theme.footerHeight - 1);
	fFooter->Invalidate();
}


// Metrics changed (the Size setting or the system font): everything that
// was measured once is measured again.
void
SearchWindow::_ApplyTheme()
{
	const Theme& theme = Theme::Get();
	IconCache::Get().SetIconSize(theme.iconSize);
	fApps.Rebuild();
	float fieldLeft = theme.padding + roundf(34 * theme.scale);
	fField->MoveTo(fieldLeft, 2);
	fField->ResizeTo(theme.width - theme.padding - 1 - fieldLeft,
		theme.fieldHeight - 4);
	fField->ThemeChanged();
	fSettings->ThemeChanged();
	if (!IsHidden())
		fBackground->Invalidate();
}


void
SearchWindow::_SettingChanged(const char* key)
{
	BString changed(key);
	if (changed == "size") {
		Theme::Refresh();
		_ApplyTheme();
		_UpdateResults(true);
		// Grow or shrink to the new size, smoothly too.
		if (fSettingsOpen)
			_Morph(_SettingsFrame(), true, false);
	} else if (changed == "autostart")
		Setup::SetAutostart(Prefs::Get().autostart);
	else if (changed == "clear_history")
		fHistory.Clear();
	else if (changed == "check_updates")
		be_app->PostMessage(kMsgCheckUpdates);
}
