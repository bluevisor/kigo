// Built-in commands (Raycast's "System" extension, Haiku edition) and the
// actions Kigo can perform on any result.
#ifndef COMMANDS_H
#define COMMANDS_H

#include <vector>

#include "Result.h"

class BMessenger;

// Appends matching built-in commands, scored, to `results`.
void SearchCommands(const char* query, std::vector<Result>& results);

// Rebuilds a command result from its id ("cmd:restart") for history.
bool CommandForId(const char* id, Result& result);

// Primary action (Enter). Returns false when it couldn't be done.
bool OpenResult(const Result& result, bool newInstance, const BMessenger& app);
// Alt+Enter: select the item in a Tracker window.
bool RevealResult(const Result& result);
// Alt+Shift+C: the path, URL, value or command line.
void CopyResult(const Result& result);

void CopyToClipboard(const char* text);
bool OpenURL(const char* url);
bool RunInTerminal(const char* command);

// URL-looking input: "https://…", "www.…", "haiku-os.org".
bool LooksLikeURL(const char* text, BString& url);

#endif // COMMANDS_H
