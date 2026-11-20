CFLAGS := -arch arm64 -mmacosx-version-min=14.0 -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter
DYLIB_SOURCES := $(shell find src/dylib -name '*.[hm]')
DYLIB_SWIFT := $(shell find src/dylib -name '*.swift')
SDK := $(shell xcrun --show-sdk-path)
SWIFT_LIB := $(SDK)/usr/lib/swift
# FoundationModels is macOS 26+ only: weak-link it, stop Swift auto-linking it, and skip it when the SDK lacks it.
FOUNDATION_MODELS := $(if $(wildcard $(SDK)/System/Library/Frameworks/FoundationModels.framework),-weak_framework FoundationModels)
SWIFTFLAGS := -target arm64-apple-macos14.0 -O -parse-as-library -wmo -module-name DiaPatchesSwift \
	-Xfrontend -disable-autolink-framework -Xfrontend FoundationModels
PASSKEYS := src/dylib/Patches/Passkeys/extension
EXTENSION := $(foreach file,manifest.json page.js bridge.js worker.js,-Wl,-sectcreate,__TEXT,__pk_$(basename $(file)),$(PASSKEYS)/$(file))

COMMIT := $(shell git rev-parse HEAD 2>/dev/null)

all: build/diapatch build/DiaPatches.dylib build/patches.json

build/commit: FORCE | build
	@echo '$(COMMIT)' | cmp -s - $@ || echo '$(COMMIT)' > $@

FORCE:

build/diapatch: $(wildcard src/diapatch/*.[hm]) build/commit | build
	clang $(CFLAGS) -DDIATWEAKS_COMMIT='"$(COMMIT)"' -framework AppKit -framework CoreGraphics -framework Security -o $@ $(filter %.m,$^)

build/DiaPatchesSwift.o: $(DYLIB_SWIFT) | build
	swiftc $(SWIFTFLAGS) -emit-object -o $@ $^

# Syphon's server, vendored for Send PiP to Syphon. Its own code, so its warnings stay quiet.
SYPHON := src/vendor/Syphon
SYPHON_OBJECTS := $(patsubst $(SYPHON)/%,build/syphon/%.o,$(wildcard $(SYPHON)/*.m $(SYPHON)/*.c))

build/syphon/%.o: $(SYPHON)/% $(wildcard $(SYPHON)/*.h) | build
	@mkdir -p build/syphon
	clang $(CFLAGS) -w -include $(SYPHON)/Syphon_Prefix.pch -Isrc/vendor -c $< -o $@

build/DiaPatches.dylib: $(DYLIB_SOURCES) build/DiaPatchesSwift.o $(SYPHON_OBJECTS) $(wildcard $(PASSKEYS)/*) | build
	clang $(CFLAGS) -Isrc/dylib -Isrc/vendor -dynamiclib $(EXTENSION) -framework AppKit -framework QuartzCore -framework Metal -framework AVFoundation -framework VideoToolbox -framework CoreMedia -framework CoreVideo -framework IOSurface \
		-L$(SWIFT_LIB) -Wl,-rpath,/usr/lib/swift $(FOUNDATION_MODELS) -o $@ $(filter %.m %.o,$^)

# With DIAPATCH_MANIFEST set, the dylib writes the patch list and exits as it loads, so diapatch never runs.
build/patches.json: build/DiaPatches.dylib build/diapatch
	DIAPATCH_MANIFEST=$@ DYLD_INSERT_LIBRARIES=$< build/diapatch

build:
	mkdir -p $@

GROUP_TABS := $(addprefix src/dylib/Commands/GroupTabs/,Plan.m Title.m Registrable.m Messages.m)

build/group-tabs: tests/group-tabs.m $(GROUP_TABS) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ $^

build/mouse-back-forward: tests/mouse-back-forward.m src/dylib/Patches/MouseBackForward/MouseBackForward.m src/dylib/StdPatch/Hook.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ tests/mouse-back-forward.m src/dylib/StdPatch/Hook.m

SPLIT := src/dylib/Patches/SplitClientHello

build/split-client-hello: tests/split-client-hello.m $(wildcard $(SPLIT)/Split.[hm] $(SPLIT)/Write.[hm]) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework Foundation -o $@ \
		tests/split-client-hello.m $(SPLIT)/Split.m $(SPLIT)/Write.m

build/vertical-tab-glow: tests/vertical-tab-glow.m $(wildcard src/dylib/Patches/HideVerticalTabGlow/*.[hm]) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ $<

build/peek-cursor: tests/peek-cursor.m src/dylib/Patches/Peek/Cursor.m src/dylib/Patches/Peek/Peek.h src/dylib/StdPatch/Hook.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ $<

build/peek-link: tests/peek-link.m src/dylib/Patches/Peek/Link.m src/dylib/Patches/Peek/Peek.h $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ tests/peek-link.m src/dylib/Patches/Peek/Link.m

build/safe-mode: tests/safe-mode.m src/dylib/SafeMode/SafeMode.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ $<

build/hook-table: tests/hook-table.m src/dylib/StdPatch/Hook.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address -Isrc/dylib -framework AppKit -o $@ $<

TIDY := src/dylib/Patches/TidyTabs/Tabs.m src/dylib/Patches/CommandBar/Tabs.m src/dylib/Commands/GroupTabs/Messages.m

build/tidy-tabs: tests/tidy-tabs.m $(TIDY) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ $^

build/drag-offset: tests/drag-offset.m src/dylib/Patches/CompactTabRows/CompactTabRows.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ tests/drag-offset.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

build/little-dia-stack: tests/little-dia-stack.m src/dylib/Patches/LittleDia/Stack.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ $<

build/little-dia-profile: tests/little-dia-profile.m src/dylib/Patches/LittleDia/Profile.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ $<

build/tracking: tests/tracking.m src/dylib/Commands/GroupTabs/Tracking.m src/dylib/Commands/GroupTabs/Messages.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ tests/tracking.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m src/dylib/Commands/GroupTabs/Messages.m

build/little-dia-over: tests/little-dia-over.m src/dylib/Patches/LittleDia/Route.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ tests/little-dia-over.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

HIDE_TOOLBAR_DIR := src/dylib/Patches/HideToolbar
HIDE_TOOLBAR_LAYOUT := $(addprefix $(HIDE_TOOLBAR_DIR)/,HideToolbar.m Layout.m Hover.m Permission.m)
HIDE_TOOLBAR := $(HIDE_TOOLBAR_LAYOUT) $(addprefix $(HIDE_TOOLBAR_DIR)/,RevealOnHover.m ShowOnNewTab.m ShowWithSidebar.m ShowWithTopTabs.m)
SETTLE := src/dylib/Test/Scenarios.m src/dylib/StdPatch/Patch.m src/dylib/StdPatch/Views.m src/dylib/StdPatch/Hook.m $(HIDE_TOOLBAR)

build/toolbar-permission: tests/toolbar-permission.m $(HIDE_TOOLBAR_LAYOUT) $(HIDE_TOOLBAR_DIR)/HideToolbar.h src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ $(filter %.m,$^)

build/hide-toolbar-settle: tests/hide-toolbar-settle.m src/dylib/Test/Test.m $(SETTLE) $(wildcard src/dylib/StdPatch/*.h src/dylib/Patches/HideToolbar/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/hide-toolbar-settle.m $(SETTLE)

build/launch-flags: tests/launch-flags.m src/dylib/StdPatch/Extensions.m src/dylib/StdPatch/Hook.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ tests/launch-flags.m src/dylib/StdPatch/Hook.m

check: build/diapatch build/group-tabs build/mouse-back-forward build/vertical-tab-glow build/split-client-hello build/peek-cursor build/peek-link build/safe-mode build/hook-table build/tidy-tabs build/drag-offset build/toolbar-permission build/launch-flags build/little-dia-stack build/little-dia-profile build/little-dia-over build/tracking build/hide-toolbar-settle build/patches.json
	tests/tweaks-update
	build/group-tabs
	build/tidy-tabs
	build/mouse-back-forward
	build/vertical-tab-glow
	build/split-client-hello
	build/peek-cursor
	build/peek-link
	build/safe-mode
	build/hook-table
	build/drag-offset
	build/toolbar-permission
	build/launch-flags
	build/little-dia-stack
	build/little-dia-profile
	build/tracking
	build/little-dia-over
	build/hide-toolbar-settle
	tests/sidebar-grain
	scripts/check-patches

test: build/DiaPatches.dylib
	./test.sh

patch:
	@scripts/new-patch "$(NAME)"

clean:
	rm -rf build

.PHONY: all check clean test patch
