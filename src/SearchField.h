// The big single-line query field. Navigation keys go to the window; every
// edit posts kMsgQueryChanged.
#ifndef SEARCH_FIELD_H
#define SEARCH_FIELD_H

#include <TextView.h>

class SearchWindow;

class SearchField : public BTextView {
public:
	SearchField(BRect frame, SearchWindow* window);

	void Draw(BRect updateRect) override;
	void KeyDown(const char* bytes, int32 numBytes) override;
	void FrameResized(float width, float height) override;

	void SetPlaceholder(const char* text);

protected:
	void InsertText(const char* text, int32 length, int32 offset,
		const text_run_array* runs) override;
	void DeleteText(int32 fromOffset, int32 toOffset) override;

private:
	void _Changed();
	bool _MacEditingKey(char key, int32 modifiers);
	void _UpdateTextRect();

	SearchWindow*	fSearchWindow;
	BString			fPlaceholder;
};

#endif // SEARCH_FIELD_H
