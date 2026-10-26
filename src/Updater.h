// Over-the-air updates from the GitHub releases, like Temino's: a check at
// launch (once a day) and from the "Check for Updates" command. A newer
// release's package for this architecture is downloaded with curl and
// swapped into the packages folder by a shell that outlives Kigo (replacing
// the package stops the running app), which then starts the new Kigo.
#ifndef UPDATER_H
#define UPDATER_H

namespace Updater {

// Runs in the background. `manual` skips the once-a-day limit and also
// reports "up to date" and failures.
void Check(bool manual);

// Shows "Kigo X is installed" after an update restarted Kigo.
void AnnounceUpdated();

}

#endif // UPDATER_H
