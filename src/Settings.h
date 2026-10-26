// key=value settings in ~/config/settings/Kigo/settings.
#ifndef SETTINGS_H
#define SETTINGS_H

#include <String.h>

namespace Settings {

BString Get(const char* key);
void Set(const char* key, const char* value);

// ~/config/settings/Kigo, created if needed.
BString Folder();

}

#endif // SETTINGS_H
