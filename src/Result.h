// One row in Kigo's results list.
#ifndef RESULT_H
#define RESULT_H

#include <Entry.h>
#include <String.h>

class BBitmap;

enum ResultKind {
	kKindApp,
	kKindPreference,
	kKindFile,
	kKindFolder,
	kKindCommand,
	kKindCalculator,
	kKindURL,
	kKindWeb,
	kKindShell,
};

struct Result {
	ResultKind	kind = kKindFile;
	BString		title;
	BString		subtitle;
	// Stable key for history/frecency: "app:/path", "file:/path", "cmd:restart".
	BString		id;
	BString		section;
	// Command id, calculator value, URL, or shell command line.
	BString		payload;
	entry_ref	ref;
	bool		hasRef = false;
	bool		needsConfirm = false;
	// Shared with IconCache; never owned here.
	BBitmap*	icon = nullptr;
	float		score = 0;
};

const char* ResultKindLabel(ResultKind kind);
const char* PrimaryActionLabel(const Result& result);
bool CanReveal(const Result& result);

#endif // RESULT_H
