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

On the Mac, Cmd+Enter (or Option+Enter) shows the result in Finder,
Cmd+Shift+C copies its path, Cmd+1 … Cmd+9 open the Nth result. Backspace
with nothing typed puts the suggestions away; Down brings them back.

    mac/build.sh             # mac/dist/Kigo.app, signed with your Developer ID
    mac/build.sh --install   # replace /Applications/Kigo.app and start it
    cd mac && swift test     # matcher, calculator, links, commands

The panel is a rounded, blurred charcoal surface (near white in light mode)
with a hairline border and a shadow; the gear in the search bar opens
settings. It registers itself as a login item once it runs from
/Applications. For layout checks without Screen Recording permission,
`KIGO_SNAPSHOT=/tmp/k.png KIGO_QUERY=term .build/debug/Kigo` saves the
panel, and its settings page, as PNGs (it takes keyboard focus while it runs).

## License

MIT, see [LICENSE](LICENSE).
