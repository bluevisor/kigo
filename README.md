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

Kigo follows your Appearance colors and font size, so it works with dark
themes too.

## Install

Download the `.hpkg` for your architecture from the
[releases](https://github.com/bluevisor/kigo/releases) and copy it into
`~/config/packages`. Open Kigo once from Deskbar: it installs its Alt+Space
hotkey (an input_server filter in `~/config/non-packaged/add-ons`) and starts
itself hidden at every login (a line in `~/config/settings/boot/UserBootscript`).

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
`haiku/mkicon.py` regenerates the vector icon and `haiku/Kigo.rdef`.

The hotkey filter is never overwritten in place: the input_server keeps it
mapped, and rewriting a mapped add-on crashes the input_server (no keyboard or
mouse until it restarts). Kigo copies a new filter beside the old one and
renames it over.

## License

MIT, see [LICENSE](LICENSE).
