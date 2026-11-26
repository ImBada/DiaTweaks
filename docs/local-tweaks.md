# Local Tweaks

Local Tweaks runs tweaks you keep in a folder of your own. They are ordinary DiaTweaks tweaks: each one gets a switch in **Dia → Settings → Patches**, a key in `com.diapatches`, and a line in `diatweaks list`. They survive Dia updates, DiaTweaks updates, and `diapatch uninstall --purge`.

The folder is:

```
~/Library/Application Support/DiaPatches/local/
```

Open it from **Dia → Settings → Patches → App → Local Tweaks → Open Folder**, or with `diatweaks local open`.

## What you can drop in

| File | What happens |
|---|---|
| `MyTweak.m` | Compiled and loaded. The common case. |
| `MyTweak/` | A folder of `.m` and `.h` files that compile together. |
| `pr-123.patch` or `.diff` | A GitHub pull request diff. Its new `.m` and `.h` files are extracted and built. |
| `MyTweak.dylib` | A prebuilt tweak, loaded as-is. |
| `MyTweak.zip` | A folder of sources, unpacked and built. |

Add one with **Add Tweak…** in Settings, by dropping the file into the folder in Finder, or with:

```sh
diatweaks local add ~/Downloads/MyTweak.m
```

## Optional tweaks

**Dia → Settings → Patches → App → Local Tweaks → Available** lists tweaks DiaTweaks keeps in [`tweaks/`](../tweaks/) instead of building them in. **Install** downloads one into your local folder, builds it and switches it on for the next launch. A tweak you had on before it moved out of the built-in list comes first, marked *Previously on*.

```sh
diatweaks local available
diatweaks local install exampleTweak
```

`install` takes a tweak's name, key or title, and needs the network once; after that it's an ordinary local tweak. Nothing is listed when there are no optional tweaks yet, and a tweak your DiaTweaks already has built in is never offered.

## Writing one

A local tweak is the same file a pull request would contain:

```objc
#import "StdPatch/StdPatch.h"

DP_PATCH(MyTweak) {
    .key = @"myTweak",
    .defaultOn = NO,
    .title = @"My Tweak",
    .detail = @"What this tweak does, in one line.",
    .symbol = @"hammer",
    .tint = @"systemOrangeColor",
    .section = @"Local",
};
```

**New Starter Tweak…** writes a working file like that into the folder and shows it in Finder. Edit it, relaunch Dia, and the switch appears.

`section` is where the switch lives in Settings. Leave it out and the tweak goes in a **Local** section of its own.

## Why it keeps working

A local tweak compiles against the headers inside the installed `DiaPatches.dylib`, not against a copy on disk. When DiaTweaks updates, the headers change with it, and the next launch recompiles your tweak from source against the new ones. Nothing to reinstall, nothing to re-download.

A prebuilt `.dylib` can't be recompiled, so it records the layout it was built against. If a DiaTweaks update changes that layout, the dylib is refused with *"Built for an older DiaTweaks ABI — recompile from source"* instead of crashing Dia.

## Pull request diffs

`diatweaks local add ~/Downloads/pr-557.patch` extracts the new files a pull request adds and builds them. Two things come along automatically:

- New `.m` and `.h` files, keeping their folder structure.
- Any `#define` the pull request adds to `src/dylib/StdPatch/Dia.h`, so a tweak that needs a new Dia class name still compiles.

A pull request that **changes an existing tweak** can't run this way, because the installed dylib is already built. It's refused with *"Modifies built-in file EdgeToEdge.m — changes to existing tweaks need a full DiaTweaks build."* That kind of change needs a real pull request.

## When something goes wrong

A broken local tweak never stops Dia from opening. Its row under **Installed** in Settings says what went wrong, in red under its name:

- A compile error shows the compiler's message, with the file and line.
- A `.dylib` with a missing symbol, the wrong architecture, or an old ABI is skipped with the reason.
- A tweak that reuses a key DiaTweaks already has is dropped, and the rest of the file still loads.
- A `requires`, `disabledBy` or `coveredBy` that points at nothing, or loops, is dropped.

If Dia crashes at launch while local tweaks are loaded, the next launch turns **only** the local tweaks off and leaves the built-in tweaks alone. Settings then offers **Turn Local Tweaks Back On**.

## The command

| Command | Does |
|---|---|
| `diatweaks local` | Lists the local tweaks and whether each built |
| `diatweaks local available` | Lists the optional tweaks you can download |
| `diatweaks local install <name…>` | Downloads, builds and switches on an optional tweak |
| `diatweaks local add <path>` | Copies a `.m`, folder, `.patch`, `.zip` or `.dylib` into the folder and builds it |
| `diatweaks local build [name…]` | Compiles the local tweaks now |
| `diatweaks local remove <name>` | Moves a local tweak to the Trash |
| `diatweaks local open` | Shows the folder in Finder |
| `diatweaks local export <name>` | Zips a local tweak to your Desktop so you can share it |
| `diatweaks local doctor` | Checks the compiler, the SDK, the folder and every local tweak |

`diatweaks list` and `diatweaks status` include local tweaks, marked `(local)`, and `diatweaks enable` and `disable` work on them like any other tweak.

## Sharing one

`diatweaks local export MyTweak` zips the folder to your Desktop. Whoever receives it runs `diatweaks local add ~/Downloads/MyTweak.zip`. There is no separate file format: the bundle is just the folder.

## Turning it off

**Local Tweaks** in **Dia → Settings → Patches → App** is the master switch. Turn it off and no local code is loaded at all; your files stay where they are. **Pause Tweaks** and Safe Mode also stop local tweaks from loading.

## Requirements

Compiling `.m` files needs Apple's developer tools: `xcode-select --install`. A prebuilt `.dylib` needs nothing.
