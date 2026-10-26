#include "FileSearch.h"

#include <algorithm>
#include <atomic>
#include <ctype.h>
#include <vector>

#include <Entry.h>
#include <Message.h>
#include <Path.h>
#include <Query.h>
#include <Volume.h>
#include <VolumeRoster.h>

#include "Fuzzy.h"
#include "Kigo.h"


static std::atomic<int32> sCurrentGeneration(0);

static const int32 kMaxResults = 24;
static const int32 kMaxScanned = 3000;
static const bigtime_t kTimeLimit = 400000;

namespace {

struct Job {
	BMessenger	target;
	BString		query;
	int32		generation;
};

struct Hit {
	entry_ref	ref;
	float		score;
};

} // namespace


// BFS name queries are case-sensitive glob matches, so "term" becomes
// "*[tT][eE][rR][mM]*". Glob characters are escaped.
static BString
CaseInsensitivePattern(const char* query)
{
	BString pattern("*");
	for (const char* c = query; *c != '\0'; c++) {
		unsigned char ch = *c;
		if (isalpha(ch)) {
			pattern << '[' << (char)tolower(ch) << (char)toupper(ch) << ']';
		} else if (strchr("*?[]\\\"'", ch) != NULL) {
			pattern << '\\' << (char)ch;
		} else
			pattern << (char)ch;
	}
	pattern << '*';
	return pattern;
}


static bool
IsNoise(const char* path)
{
	// Hidden folders, build output and caches drown real documents.
	static const char* kSkip[] = {
		"/.", "/node_modules/", "/target/", "/build/", "/__pycache__/",
		"/boot/home/config/cache/", "/boot/home/config/packages/",
		"/boot/home/config/settings/", "/boot/home/config/var/",
		"/boot/system/",
		"/boot/home/config/non-packaged/lib/",
		"/boot/home/config/non-packaged/develop/",
	};
	for (const char* skip : kSkip) {
		if (strstr(path, skip) != NULL)
			return true;
	}
	return false;
}


static float
ScoreHit(const char* query, const char* name, const char* path)
{
	float score = FuzzyScore(query, name);
	if (score <= 0)
		return 0;
	// Below apps and commands, and documents near home beat deep paths.
	score *= 0.75f;
	if (strncmp(path, "/boot/home/", 11) == 0)
		score += 15;
	if (strncmp(path, "/boot/home/Desktop/", 19) == 0)
		score += 10;
	int depth = 0;
	for (const char* c = path; *c != '\0'; c++) {
		if (*c == '/')
			depth++;
	}
	return score - depth * 2;
}


FileSearch::FileSearch(const BMessenger& target)
	:
	fTarget(target),
	fThread(-1)
{
}


FileSearch::~FileSearch()
{
	Cancel();
}


void
FileSearch::Cancel()
{
	sCurrentGeneration++;
	if (fThread >= 0) {
		status_t result;
		wait_for_thread(fThread, &result);
		fThread = -1;
	}
}


void
FileSearch::Start(const char* query, int32 generation)
{
	// Bump the generation first so a running query notices and stops.
	sCurrentGeneration = generation;
	if (fThread >= 0) {
		status_t result;
		wait_for_thread(fThread, &result);
		fThread = -1;
	}

	Job* job = new Job{fTarget, query, generation};
	fThread = spawn_thread(_Run, "kigo file search", B_LOW_PRIORITY, job);
	if (fThread < 0) {
		delete job;
		return;
	}
	resume_thread(fThread);
}


status_t
FileSearch::_Run(void* data)
{
	Job* job = (Job*)data;
	BString query(job->query);
	query.Trim();

	std::vector<Hit> hits;
	BVolume volume;
	if (BVolumeRoster().GetBootVolume(&volume) == B_OK
		&& volume.KnowsQuery() && query.Length() >= 2) {
		// Search the longest word; the fuzzy scorer checks the rest.
		BString word;
		int32 start = 0;
		while (start < query.Length()) {
			int32 end = query.FindFirst(' ', start);
			if (end < 0)
				end = query.Length();
			if (end - start > word.Length())
				query.CopyInto(word, start, end - start);
			start = end + 1;
		}

		BString predicate("name==\"");
		predicate << CaseInsensitivePattern(word.String()) << "\"";

		BQuery fsQuery;
		fsQuery.SetVolume(&volume);
		fsQuery.SetPredicate(predicate.String());
		if (fsQuery.Fetch() == B_OK) {
			bigtime_t deadline = system_time() + kTimeLimit;
			entry_ref ref;
			int32 scanned = 0;
			while (fsQuery.GetNextRef(&ref) == B_OK) {
				if (sCurrentGeneration != job->generation
					|| ++scanned > kMaxScanned || system_time() > deadline) {
					break;
				}
				BPath path(&ref);
				if (path.InitCheck() != B_OK || IsNoise(path.Path()))
					continue;
				float score = ScoreHit(query.String(), ref.name, path.Path());
				if (score > 0)
					hits.push_back(Hit{ref, score});
			}
		}
	}

	if (sCurrentGeneration == job->generation) {
		std::sort(hits.begin(), hits.end(),
			[](const Hit& a, const Hit& b) { return a.score > b.score; });
		BMessage reply(kMsgFileResults);
		reply.AddInt32("generation", job->generation);
		for (size_t i = 0; i < hits.size() && (int32)i < kMaxResults; i++) {
			reply.AddRef("ref", &hits[i].ref);
			reply.AddFloat("score", hits[i].score);
		}
		job->target.SendMessage(&reply);
	}

	delete job;
	return B_OK;
}
