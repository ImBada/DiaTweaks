# Optional tweaks

Tweaks in this folder aren't built into `DiaPatches.dylib`. **Settings → Patches → Local Tweaks → Available** lists them and installs one in a click, and `diatweaks local available` and `diatweaks local install <name>` do the same from a terminal. An installed tweak is an ordinary [local tweak](../docs/local-tweaks.md): it compiles on the user's Mac and survives DiaTweaks updates.

A tweak is `tweaks/<Name>.m`, or a `tweaks/<Name>/` folder of `.m` and `.h` files. It's written like any other tweak, with `DP_PATCH`, and imports headers as `"StdPatch/StdPatch.h"`, never as `"Patches/<Name>/…"`.

`index.json` is what Settings reads. `make` compiles every tweak here the way Dia will and rewrites it, and `make check` fails when it's stale. Don't edit it by hand.

## Moving a built-in tweak here

```sh
scripts/make-local <Name>
```

moves `src/dylib/Patches/<Name>` to `tweaks/<Name>`, points the Makefile and tests at the new path, then runs `make` and `scripts/check-patches`. It refuses a tweak that other built-in code imports or links to, a tweak in a Settings folder, one with Swift files, and Passkeys.

`scripts/make-local --builtin <Name>` moves it back.

A user whose DiaTweaks still has the tweak built in never sees it listed here, and one who had it on sees it first, marked *Previously on*, with a switch that's already on once they install it.
