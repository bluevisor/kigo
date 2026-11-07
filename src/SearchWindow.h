// The launcher panel: query field, results, and an action footer.
#ifndef SEARCH_WINDOW_H
#define SEARCH_WINDOW_H

#include <vector>

#include <Window.h>

#include "AppIndex.h"
#include "FileSearch.h"
#include "History.h"
#include "Result.h"

class BMessageRunner;
class FooterView;
class PanelView;
class ResultsView;
class SearchField;
class SettingsView;

class SearchWindow : public BWindow {
public:
	SearchWindow();
	~SearchWindow() override;

	void DispatchMessage(BMessage* message, BHandler* target) override;
	void MessageReceived(BMessage* message) override;
	void WindowActivated(bool active) override;
	bool QuitRequested() override;

	// Called with the window locked.
	void ShowLauncher();
	void HideLauncher();
	void Toggle();

	// The window grows into the settings page, and shrinks back.
	void OpenSettings();
	void CloseSettings();

	// From SearchField; returns true when the key was handled.
	bool HandleKey(char key, int32 modifiers);
	void InvokeSelection(bool reveal, bool alternate);
	void SelectionChanged();

private:
	void _QueryChanged();
	void _UpdateResults(bool keepSelection);
	void _AddSuggestions(std::vector<Result>& results);
	void _FileResultsArrived(BMessage* message);
	void _Invoke(const Result& result, bool reveal, bool alternate);
	void _CopySelection();
	void _Relayout();
	float _SearchHeight() const;
	BRect _SettingsFrame() const;
	void _Morph(BRect to, bool opening, bool fade = true);
	void _MorphStep();
	void _FinishClosing();
	void _PlaceSettings();
	void _ApplyTheme();
	void _SettingChanged(const char* key);
	BString _Query() const;

	SearchField*		fField;
	ResultsView*		fList;
	FooterView*			fFooter;
	PanelView*			fBackground;
	SettingsView*		fSettings;
	bool				fSettingsOpen;
	BMessageRunner*		fMorphRunner;
	bigtime_t			fMorphStart;
	bigtime_t			fMorphDuration;
	BRect				fMorphFrom;
	BRect				fMorphTo;
	bool				fMorphOpening;
	// Fades the page and header too; not when only the size changes.
	bool				fMorphFade;

	AppIndex			fApps;
	History				fHistory;
	FileSearch*			fFileSearch;
	BMessageRunner*		fFileSearchRunner;
	int32				fGeneration;
	int32				fFileGeneration;
	std::vector<Result>	fFileResults;
	BString				fFileQuery;
};

#endif // SEARCH_WINDOW_H
