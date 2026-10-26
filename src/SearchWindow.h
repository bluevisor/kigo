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
class ResultsView;
class SearchField;

class SearchWindow : public BWindow {
public:
	SearchWindow();
	~SearchWindow() override;

	void MessageReceived(BMessage* message) override;
	void WindowActivated(bool active) override;
	bool QuitRequested() override;

	// Called with the window locked.
	void ShowLauncher();
	void HideLauncher();
	void Toggle();

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
	BString _Query() const;

	SearchField*		fField;
	ResultsView*		fList;
	FooterView*			fFooter;
	BView*				fBackground;

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
