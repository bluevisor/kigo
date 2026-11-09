# Kigo

A Spotlight and Raycast style launcher for [Haiku](https://www.haiku-os.org).
Press **Alt+Space** (Option+Space on a Mac keyboard in UTM), type, and hit
Enter.

In haiku poetry, the *kigo* is the season word: the one word that sets the
scene. Kigo the launcher is the one shortcut that gets you anywhere.

## What it finds

| Type                     | Example            | Enter does                        |
|--------------------------|--------------------|-----------------------------------|
| Applications, preferences | `term`, `network`  | opens it, or brings it forward if it's running |
| Files and folders        | `invoice`          | opens it (live query on the BFS name index, no crawler) |
| Arithmetic               | `sqrt(2)*10^3`     | copies the answer                 |
| Links                    | `haiku-os.org`     | opens it in your browser          |
| Shell commands           | `> ls -la`         | runs it in Terminal               |
| Commands                 | `restart`, `workspace 2`, `empty trash` | runs it (Restart, Shut Down and Empty Trash ask twice) |
| Anything else            | `haiku vulkan`     | searches the web                  |

The best match across all kinds is the **Top Hit**. Results rank by how well
they match and by how often and how recently you opened them; with nothing
typed, Kigo suggests what you use most.

## Keys

| Key                         | Action                                    |
|-----------------------------|-------------------------------------------|
| Up / Down, Ctrl+P / Ctrl+N  | move through results                      |
| Enter                       | open the selected result                  |
| Shift+Enter                 | open a new instance of the app           |
| Alt+Enter                   | show it in Tracker                        |
| Alt+Shift+C                 | copy its path (or the answer, or the URL) |
| Alt+1 … Alt+9               | open the Nth result                       |
| Tab                         | complete the selected name                |
| Alt+Left / Right            | move by word (Option+arrows on a Mac)     |
| Option+Left / Right         | to the start / end (Cmd+arrows on a Mac)  |
| Esc                         | clear the query, then close               |
| Alt+,                       | settings (Option+, or Cmd+, on a Mac)     |

Kigo follows your Appearance colors and font size, so it works with dark
themes too.

## Settings

**Alt+,**, the **Kigo Settings** command or `Kigo --settings` grows the
launcher into its settings page, in the same window; Esc shrinks it back.
There you pick what Kigo searches (applications, files, commands, the
calculator), which web search it offers last (DuckDuckGo, Google, Bing or
none), whether it suggests what you use most, its size, whether it opens at
login and checks for updates. Up/Down move, Space or Enter changes,
Left/Right pick a choice. Settings live in `~/config/settings/Kigo/settings`.
At the bottom, **About** shows Kigo's mark, 季 (*ki*, season, the first half
of 季語 *kigo*) brushed in your accent color, with the version and Check Now.

## Install

Download the `.hpkg` for your system from the
[releases](https://github.com/bluevisor/kigo/releases) (`arm64`, `x86_64`,
or `x86_gcc2` for 32-bit Haiku) and copy it into
`~/config/packages`. Open Kigo once from Deskbar: it installs its Alt+Space
hotkey (an input_server filter in `~/config/non-packaged/add-ons`) and starts
itself hidden at every login (a line in `~/config/settings/boot/UserBootscript`).

The same filter makes **Win+Space** (⌘+Space on a Mac keyboard) switch input
methods, as on macOS: Haiku hardcodes that switch to Alt+Space, which Kigo
takes.

Kigo checks GitHub for a newer release once a day, and on demand with the
**Check for Updates** command. An update is downloaded, swapped into
`~/config/packages`, and Kigo restarts itself in the background.

## Build

On Haiku, with the development tools installed:

```sh
make            # build/Kigo and build/KigoHotkey
make run        # start the built copy
make package    # dist/kigo-<version>-<rev>-<arch>.hpkg
make install    # install that package
```

From a Mac, `haiku/deploy.sh [--install]` copies the tree to a Haiku VM over
ssh (`HOST`, default `haiku-dbg`), builds it there and starts it.
`haiku/cross.sh x86_64` and `haiku/cross.sh x86` cross-compile for Intel in
Haiku's own cross-compiler images
(`ghcr.io/haiku/cross-compiler:x86_64-r1beta5` / `x86_gcc2h-r1beta5`, gcc 13)
and package on that Haiku box, since `rc`, `xres` and `package` only run on
Haiku. 32-bit Haiku gets an `x86_gcc2` package built for its gcc 13 `x86`
secondary architecture.
`haiku/mkicon.py` regenerates the vector icon and `haiku/Kigo.rdef`.

The hotkey filter is never overwritten in place: the input_server keeps it
mapped, and rewriting a mapped add-on crashes the input_server (no keyboard or
mouse until it restarts). Kigo copies a new filter beside the old one and
renames it over.

## macOS

`mac/` holds a native Mac version: the same ranking, calculator, history and
settings, as a Swift app with no Dock icon. **Option+Space** opens it (Control
or Command+Space in Settings), **Option+,** or **Cmd+,** opens its settings.
It finds applications and System Settings panes, files through Spotlight's
index of your home folder, commands (Sleep, Lock Screen, Restart, Empty Trash,
Toggle Dark Mode, common folders), arithmetic, links, `> shell` commands, and
falls back to a web search.

With [Saddle Island](https://github.com/bluevisor/SaddleIsland) running, Kigo
plugs into it: with Saddle Island's Settings › Plugins › Kigo switch on (the
default), **F4** and **Option+Space** both open Saddle Island's search, answered
by Kigo. The search keeps Saddle
Island's look, in the notch; the rows are Kigo's (ranked by what you use, with
its commands, links and `> shell`) and Kigo opens what you pick. Saddle Island
recognises Kigo by its code signature and talks to it over its local IslandKit
socket; when Kigo isn't running, Saddle Island searches by itself. Turn off
Kigo's Settings › General › Search in Saddle Island to have both keys open
Kigo's own panel instead. Without Saddle Island, Option+Space opens Kigo's panel.

On the Mac, Cmd+Enter (or Option+Enter) shows the result in Finder,
Cmd+Shift+C copies its path, Cmd+1 … Cmd+9 open the Nth result. Backspace
with nothing typed puts the suggestions away; Down brings them back. While
an app showing another computer is in front (Beam, UTM, Screen Sharing,
Parallels, VMware, Remote Desktop) Kigo lets go of Option+Space, so it opens
the Kigo on that machine instead.

    mac/build.sh             # mac/dist/Kigo.app, signed with your Developer ID
    mac/build.sh --install   # replace /Applications/Kigo.app and start it
    mac/build.sh --release   # notarized mac/dist/kigo-<version>-macos.zip
    cd mac && swift test     # matcher, calculator, links, commands

The panel is a rounded, blurred charcoal surface (near white in light mode)
with a hairline border and a shadow; the gear in the search bar opens
settings, where you also pick a theme color. Like the Haiku app it updates
itself from GitHub releases once a day (`kigo-<version>-macos.zip`, checked
against this copy's Developer ID team before it's swapped in), or from
**Check for Updates**. It registers itself as a login item once it runs from
/Applications. For layout checks without Screen Recording permission,
`KIGO_SNAPSHOT=/tmp/k.png KIGO_QUERY=term .build/debug/Kigo` saves the
panel, and its settings page, as PNGs (it takes keyboard focus while it runs).

## Linux

`linux/` holds the Linux version: Python 3 and GTK 3, so the same archive
runs on any architecture (tested on a Jetson AGX Orin, Ubuntu 22.04, GNOME
on Xorg). **Alt+Space** opens it, **Alt+,** (or Ctrl+,, or the gear) its
settings. It finds applications (.desktop files), GNOME Settings panels,
files by name in your home folder, and commands (Sleep, Lock Screen,
Restart, Empty Trash, Toggle Dark Mode, folders), plus the calculator,
links, `> shell` commands and web search. Alt+Enter shows a file in Files,
Alt+Shift+C copies its path, Alt+1 … Alt+9 open the Nth result.

    tar xzf kigo-<version>-linux.tar.gz && sh kigo-<version>/install.sh

It installs for your user only (`~/.local/share/kigo`, `~/.local/bin/kigo`)
and needs `python3-gi` and `gir1.2-gtk-3.0`. On GNOME it binds Alt+Space as
a custom shortcut, moving GNOME's window menu off it (Kigo puts it back if
you pick another shortcut, and on `kigo --uninstall`). Where that shortcut
doesn't reach it, such as a second GNOME session like Beam's virtual
desktop (its own settings daemons may never hear of the binding), Kigo grabs
the key from the X server itself. Each session runs its own Kigo; one
installs an update and the others restart onto it. It updates itself
from these releases once a day, checking each download against the SHA-256
GitHub publishes for it.

    linux/build.sh --test    # core tests, then linux/dist/kigo-<version>-linux.tar.gz

## License

MIT, see [LICENSE](LICENSE).

The 季 mark is the glyph from [Yuji Boku](https://fonts.google.com/specimen/Yuji+Boku)
(SIL Open Font License 1.1), baked into the sources by `tools/mkki.py` so no
port needs the font installed.
