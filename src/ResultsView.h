// Sectioned result rows (icon, title, subtitle, kind), drawn by hand so it
// looks like Raycast's list rather than a BListView.
#ifndef RESULTS_VIEW_H
#define RESULTS_VIEW_H

#include <vector>

#include <View.h>

#include "Result.h"

class SearchWindow;

class ResultsView : public BView {
public:
	ResultsView(BRect frame, SearchWindow* window);

	void Draw(BRect updateRect) override;
	void MouseDown(BPoint where) override;
	void MouseMoved(BPoint where, uint32 transit,
		const BMessage* dragMessage) override;
	void MessageReceived(BMessage* message) override;

	// Results must already be grouped by section, in display order.
	void SetResults(const std::vector<Result>& results, int32 selection);
	const std::vector<Result>& Results() const { return fResults; }
	int32 CountResults() const { return (int32)fResults.size(); }

	int32 Selection() const { return fSelection; }
	const Result* SelectedResult() const;
	void Select(int32 index);
	void MoveSelection(int32 delta);

	void SetConfirming(const char* id);
	const BString& Confirming() const { return fConfirming; }

	// Height the list wants for its current results (capped).
	float PreferredHeight() const;

private:
	struct Line {
		bool	header;
		int32	index;		// result index, or -1 for headers
		float	top;
		float	height;
		BString	label;
	};

	void _BuildLines();
	void _DrawHeader(const Line& line);
	void _DrawRow(const Line& line);
	void _ScrollToSelection();
	void _ScrollBy(float delta);
	int32 _IndexAt(BPoint where) const;
	float _ContentHeight() const;

	SearchWindow*		fSearchWindow;
	std::vector<Result>	fResults;
	std::vector<Line>	fLines;
	int32				fSelection;
	float				fScroll;
	BString				fConfirming;
	BPoint				fLastMouse;
};

#endif // RESULTS_VIEW_H
