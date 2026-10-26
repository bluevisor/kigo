// Live file search over the boot volume's BFS name index, on a worker thread.
// Like Spotlight, it's a query against the file system's own index, so it
// needs no crawler and is always current.
#ifndef FILE_SEARCH_H
#define FILE_SEARCH_H

#include <Messenger.h>
#include <String.h>

class FileSearch {
public:
	FileSearch(const BMessenger& target);
	~FileSearch();

	// Starts a search; results arrive at the target as kMsgFileResults with
	// "generation" (int32) and per-hit "ref", "score" (float). Starting a new
	// search cancels the previous one.
	void Start(const char* query, int32 generation);
	void Cancel();

private:
	static status_t _Run(void* data);

	BMessenger		fTarget;
	thread_id		fThread;
};

#endif // FILE_SEARCH_H
