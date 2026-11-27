CFLAGS := -arch arm64 -mmacosx-version-min=14.0 -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -Itweaks
DYLIB_M := $(shell find src/dylib -name '*.m')
DYLIB_OBJS := $(patsubst src/dylib/%.m,build/obj/%.o,$(DYLIB_M))
DYLIB_SWIFT := $(shell find src/dylib -name '*.swift')
SDK := $(shell xcrun --show-sdk-path)
SWIFT_LIB := $(SDK)/usr/lib/swift
# FoundationModels is macOS 26+ only: weak-link it, stop Swift auto-linking it, and skip it when the SDK lacks it.
FOUNDATION_MODELS := $(if $(wildcard $(SDK)/System/Library/Frameworks/FoundationModels.framework),-weak_framework FoundationModels)
SWIFTFLAGS := -target arm64-apple-macos14.0 -O -parse-as-library -wmo -module-name DiaPatchesSwift \
	-Xfrontend -disable-autolink-framework -Xfrontend FoundationModels
PASSKEYS := src/dylib/Patches/Passkeys/extension
EXTENSION := $(foreach file,manifest.json page.js bridge.js worker.js,-Wl,-sectcreate,__TEXT,__pk_$(basename $(file)),$(PASSKEYS)/$(file))

DYLIB_HEADERS := $(shell find src/dylib -name '*.h')
HEADERS_BIN := build/dp_headers.bin
LOCAL_CORE := src/dylib/Local/Local.m src/dylib/Local/Catalog.m src/dylib/Local/Build.m src/dylib/Local/Extract.m src/dylib/Local/State.m

COMMIT := $(shell git rev-parse HEAD 2>/dev/null)

TWEAK_FILES := $(shell find tweaks -type f ! -name index.json ! -name README.md ! -name '.*' 2>/dev/null)

all: build/diapatch build/DiaPatches.dylib build/patches.json build/tweaks.stamp

build/tweaks.stamp: build/diapatch build/DiaPatches.dylib $(HEADERS_BIN) scripts/build-tweaks $(TWEAK_FILES) | build
	scripts/build-tweaks
	@touch $@

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

build/obj/Patches/PiPSyphon/PiPSyphon.o: CFLAGS += -Isrc/vendor

$(HEADERS_BIN): $(DYLIB_HEADERS) scripts/pack-headers | build
	scripts/pack-headers src/dylib $@

build/obj/%.o: src/dylib/%.m
	@mkdir -p $(dir $@)
	clang $(CFLAGS) -MMD -MP -Isrc/dylib -c -o $@ $<

# Shared sources compile once per flavour (plain in build/obj, ASan+UBSan in build/objsan) instead of once per test binary.
SANITIZE := -fsanitize=address,undefined -fno-sanitize-recover=all
OBJ = $(patsubst tweaks/%.m,build/obj-tweaks/%.o,$(patsubst src/dylib/%.m,build/obj/%.o,$(1)))
OBJSAN = $(patsubst tweaks/%.m,build/objsan-tweaks/%.o,$(patsubst src/dylib/%.m,build/objsan/%.o,$(1)))
O_HOOK := $(call OBJ,src/dylib/StdPatch/Hook.m)
O_VIEWS := $(call OBJ,src/dylib/StdPatch/Views.m)
O_APP := $(call OBJ,src/dylib/StdPatch/App.m)
O_MESSAGES := $(call OBJ,src/dylib/Commands/GroupTabs/Messages.m)
O_BARTABS := $(call OBJ,src/dylib/Patches/CommandBar/Tabs.m)
O_CONFIG := $(call OBJ,src/dylib/Settings/Config.m)
S_HOOK := $(call OBJSAN,src/dylib/StdPatch/Hook.m)
S_VIEWS := $(call OBJSAN,src/dylib/StdPatch/Views.m)
S_APP := $(call OBJSAN,src/dylib/StdPatch/App.m)
S_MESSAGES := $(call OBJSAN,src/dylib/Commands/GroupTabs/Messages.m)
S_BARTABS := $(call OBJSAN,src/dylib/Patches/CommandBar/Tabs.m)
CLEAN_PLIST = $(2) & pid=$$!; trap 's=$$?; for d in $(1); do case "$$d" in *%s*) d=$$(printf "$$d" "$$pid");; esac; defaults delete "$$d" 2>/dev/null; rm -f "$$HOME/Library/Preferences/$$d.plist"; done; exit $$s' EXIT; wait $$pid

build/obj-tweaks/%.o: tweaks/%.m
	@mkdir -p $(dir $@)
	clang $(CFLAGS) -MMD -MP -Isrc/dylib -c -o $@ $<

build/objsan/%.o: src/dylib/%.m
	@mkdir -p $(dir $@)
	clang $(CFLAGS) $(SANITIZE) -MMD -MP -Isrc/dylib -c -o $@ $<

build/objsan-tweaks/%.o: tweaks/%.m
	@mkdir -p $(dir $@)
	clang $(CFLAGS) $(SANITIZE) -MMD -MP -Isrc/dylib -c -o $@ $<

-include $(DYLIB_OBJS:.o=.d) $(wildcard build/*.d build/objsan/*.d build/objsan/*/*.d build/objsan/*/*/*.d build/obj-tweaks/*/*.d build/objsan-tweaks/*/*.d)

build/DiaPatches.dylib: $(DYLIB_OBJS) build/DiaPatchesSwift.o $(SYPHON_OBJECTS) $(HEADERS_BIN) $(wildcard $(PASSKEYS)/*) | build
	clang $(CFLAGS) -Isrc/dylib -dynamiclib $(EXTENSION) -Wl,-sectcreate,__TEXT,__dp_headers,$(HEADERS_BIN) -framework AppKit -framework QuartzCore -framework Metal -framework AVFoundation -framework VideoToolbox -framework CoreMedia -framework CoreVideo -framework UniformTypeIdentifiers -framework IOSurface \
		-L$(SWIFT_LIB) -Wl,-rpath,/usr/lib/swift $(FOUNDATION_MODELS) -o $@ $(filter %.o,$^)

# With DIAPATCH_MANIFEST set, the dylib writes the patch list and exits as it loads, so diapatch never runs.
build/patches.json: build/DiaPatches.dylib build/diapatch
	DIAPATCH_MANIFEST=$@ DYLD_INSERT_LIBRARIES=$< build/diapatch

build:
	mkdir -p $@

GROUP_TABS := $(call OBJ,$(addprefix src/dylib/Commands/GroupTabs/,Plan.m Title.m Registrable.m))

build/group-tabs: tests/group-tabs.m $(GROUP_TABS) $(O_MESSAGES) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ $^

build/mouse-back-forward: tests/mouse-back-forward.m src/dylib/Patches/MouseBackForward/MouseBackForward.m $(O_HOOK) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ tests/mouse-back-forward.m $(O_HOOK)

SPLIT := src/dylib/Patches/SplitClientHello

build/split-client-hello: tests/split-client-hello.m $(wildcard $(SPLIT)/Split.[hm] $(SPLIT)/Write.[hm]) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework Foundation -o $@ \
		tests/split-client-hello.m $(SPLIT)/Split.m $(SPLIT)/Write.m

build/vertical-tab-glow: tests/vertical-tab-glow.m $(wildcard src/dylib/Patches/HideVerticalTabGlow/*.[hm]) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ $<

build/peek-cursor: tests/peek-cursor.m src/dylib/Patches/Peek/Cursor.m src/dylib/Patches/Peek/Peek.h src/dylib/StdPatch/Hook.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ $<

build/link-key: tests/link-key.m src/dylib/Patches/LittleDia/LinkKey.m src/dylib/Patches/LittleDia/LittleDia.h $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/link-key.m src/dylib/Patches/LittleDia/LinkKey.m

build/safe-mode: tests/safe-mode.m src/dylib/SafeMode/SafeMode.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ $<

build/pause: tests/pause.m src/dylib/SafeMode/SafeMode.m src/dylib/StdPatch/Patch.m src/dylib/StdPatch/Shortcut.m $(O_VIEWS) $(O_CONFIG) src/dylib/Settings/Controls.m src/dylib/Settings/Items.m src/dylib/Settings/Overview.m src/dylib/Settings/Folder.m src/dylib/Settings/Home.m src/dylib/Settings/Page.m $(LOCAL_CORE) src/dylib/Local/UI.m | build
	clang $(CFLAGS) -MMD -MP -Isrc/dylib -framework AppKit -framework QuartzCore -framework UniformTypeIdentifiers -o $@ tests/pause.m $(O_VIEWS) $(O_CONFIG)

build/hook-table: tests/hook-table.m src/dylib/StdPatch/Hook.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ $<

build/updates-runtime: tests/updates-runtime.m src/dylib/Updates/Updates.m src/dylib/Updates/Updates.h src/dylib/Settings/Controls.m src/dylib/Settings/SoftwareUpdate.m src/dylib/Settings/Settings.h $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/updates-runtime.m $(S_VIEWS)

build/settings-preview: tests/settings-preview.m tests/runloop.h src/dylib/Settings/Preview.m src/dylib/Settings/Controls.m src/dylib/Settings/Settings.h $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -framework AVFoundation -framework VideoToolbox -framework CoreMedia -framework CoreVideo -o $@ tests/settings-preview.m

GROUP_TABS_SAN := $(call OBJSAN,$(addprefix src/dylib/Commands/GroupTabs/,Plan.m Title.m Registrable.m))

build/runtime-guards: tests/runtime-guards.m src/dylib/StdPatch/Patch.m src/dylib/Local/Local.h src/dylib/StdPatch/TypedURL.m src/dylib/StdPatch/Hide.m src/dylib/StdPatch/HideHosts.m src/dylib/StdPatch/Hide.h src/dylib/Settings/Settings.m src/dylib/Settings/Settings.h src/dylib/Commands/GroupTabs/Order.m src/dylib/Commands/GroupTabs/Grouping.m src/dylib/Commands/GroupTabs/Menu.m src/dylib/Commands/GroupTabs/GroupTabs.h $(S_HOOK) $(S_VIEWS) $(S_APP) $(GROUP_TABS_SAN) $(S_MESSAGES) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/runtime-guards.m $(S_HOOK) $(S_VIEWS) $(S_APP) $(GROUP_TABS_SAN) $(S_MESSAGES)

TIDY := $(call OBJSAN,src/dylib/Patches/TidyTabs/Tabs.m) $(S_BARTABS) $(S_MESSAGES)

build/tidy-tabs: tests/tidy-tabs.m $(TIDY) $(wildcard src/dylib/Patches/TidyTabs/*.[hm] src/dylib/Patches/NewTabNextToCurrent/*.m src/dylib/Patches/CommandBar/*.h src/dylib/StdPatch/*.[hm]) | build
	clang $(CFLAGS) $(SANITIZE) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/tidy-tabs.m $(TIDY)

build/drag-offset: tests/drag-offset.m src/dylib/Patches/CompactTabRows/CompactTabRows.m $(O_HOOK) $(O_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/drag-offset.m $(O_HOOK) $(O_VIEWS)

build/small-tab-shape: tests/small-tab-shape.m src/dylib/Patches/CompactTabRows/CompactTabRows.m $(O_HOOK) $(O_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/small-tab-shape.m $(O_HOOK) $(O_VIEWS)

build/little-dia-stack: tests/little-dia-stack.m src/dylib/Patches/LittleDia/Stack.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ $<

build/little-dia-profile: tests/little-dia-profile.m src/dylib/Patches/LittleDia/Profile.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ $<

build/little-dia-launcher: tests/little-dia-launcher.m tests/runloop.h src/dylib/Patches/LittleDia/Launcher.m src/dylib/Patches/LittleDia/NewWindow.m src/dylib/Patches/LittleDia/LittleDia.h $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/little-dia-launcher.m

build/tracking: tests/tracking.m tests/runloop.h src/dylib/Commands/GroupTabs/Tracking.m $(O_MESSAGES) $(O_HOOK) $(O_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ tests/tracking.m $(O_HOOK) $(O_VIEWS) $(O_MESSAGES)

build/little-dia-tab-links: tests/little-dia-tab-links.m src/dylib/Patches/LittleDia/TabLinks.m src/dylib/Patches/LittleDia/LinkKey.m src/dylib/Patches/LittleDia/LittleDia.h $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/little-dia-tab-links.m src/dylib/Patches/LittleDia/LinkKey.m $(S_HOOK) $(S_VIEWS)

build/little-dia-over: tests/little-dia-over.m src/dylib/Patches/LittleDia/Route.m $(O_HOOK) $(O_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ tests/little-dia-over.m $(O_HOOK) $(O_VIEWS)

build/little-dia-route: tests/little-dia-route.m src/dylib/Patches/LittleDia/Route.m src/dylib/Patches/LittleDia/Stack.m src/dylib/Patches/LittleDia/Extension.m src/dylib/Patches/LittleDia/LittleDia.h $(O_MESSAGES) $(O_HOOK) $(O_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ tests/little-dia-route.m $(O_MESSAGES) $(O_HOOK) $(O_VIEWS)
build/chat-card: tests/chat-card.m src/dylib/Patches/EdgeToEdge/ChatCard.m src/dylib/Patches/EdgeToEdge/EdgeToEdge.h $(O_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/chat-card.m $(O_VIEWS)

EDGE_TO_EDGE_SAN := $(call OBJSAN,$(wildcard src/dylib/Patches/EdgeToEdge/*.m))

build/edge-to-edge-fullscreen: tests/edge-to-edge-fullscreen.m $(EDGE_TO_EDGE_SAN) $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/edge-to-edge-fullscreen.m $(EDGE_TO_EDGE_SAN) $(S_HOOK) $(S_VIEWS)

check-edge-to-edge-fullscreen: build/edge-to-edge-fullscreen
	build/edge-to-edge-fullscreen

check: check-edge-to-edge-fullscreen
.PHONY: check-edge-to-edge-fullscreen

build/little-dia-focus: tests/little-dia-focus.m tests/runloop.h src/dylib/Patches/LittleDia/Window.m $(S_MESSAGES) $(S_HOOK) $(S_VIEWS) | build
	clang $(CFLAGS) $(SANITIZE) -MMD -MP -Isrc/dylib -framework AppKit -o $@ tests/little-dia-focus.m $(S_MESSAGES) $(S_HOOK) $(S_VIEWS)

HIDE_TOOLBAR_DIR := src/dylib/Patches/HideToolbar
HIDE_TOOLBAR_LAYOUT := $(addprefix $(HIDE_TOOLBAR_DIR)/,HideToolbar.m Layout.m Hover.m Permission.m KeepBookmarks.m)
HIDE_TOOLBAR := $(HIDE_TOOLBAR_LAYOUT) $(addprefix $(HIDE_TOOLBAR_DIR)/,RevealOnHover.m ShowOnNewTab.m ShowWithSidebar.m ShowWithTopTabs.m)
SETTLE := $(call OBJ,src/dylib/Test/Scenarios.m src/dylib/StdPatch/Patch.m $(HIDE_TOOLBAR)) $(O_VIEWS) $(O_HOOK)

build/toolbar-permission: tests/toolbar-permission.m $(call OBJ,$(HIDE_TOOLBAR_LAYOUT)) $(O_HOOK) $(O_VIEWS) | build
	clang $(CFLAGS) -MMD -MP -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ $(filter %.m %.o,$^)

build/toolbar-performance: tests/toolbar-performance.m $(call OBJSAN,$(addprefix $(HIDE_TOOLBAR_DIR)/,Layout.m Hover.m KeepBookmarks.m)) $(S_HOOK) $(S_VIEWS) | build
	clang $(CFLAGS) $(SANITIZE) -MMD -MP -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ $(filter %.m %.o,$^)

check-toolbar-performance: build/toolbar-performance
	build/toolbar-performance

check: check-toolbar-performance
.PHONY: check-toolbar-performance

build/hide-toolbar-settle: tests/hide-toolbar-settle.m src/dylib/Test/Test.m $(call OBJ,$(LOCAL_CORE)) $(SETTLE) | build
	clang $(CFLAGS) -MMD -MP -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/hide-toolbar-settle.m $(call OBJ,$(LOCAL_CORE)) $(SETTLE)

build/show-address-field: tests/show-address-field.m src/dylib/Patches/ShowAddressField/ShowAddressField.m $(S_HOOK) $(S_VIEWS) | build
	clang $(CFLAGS) $(SANITIZE) -MMD -MP -Isrc/dylib -framework AppKit -o $@ tests/show-address-field.m $(S_HOOK) $(S_VIEWS)

build/destination-toggle-engine-name: tests/destination-toggle-engine-name.m src/dylib/Patches/DestinationToggleEngineName/DestinationToggleEngineName.m src/dylib/Patches/DestinationToggleEngineName/DestinationToggleEngineName.h $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/destination-toggle-engine-name.m $(S_HOOK) $(S_VIEWS)

build/turn-off-ai-rows: tests/turn-off-ai-rows.m src/dylib/Patches/TurnOffAI/Rows.m $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h src/dylib/Patches/TurnOffAI/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ $(filter %.m %.o,$^)

check-turn-off-ai-rows: build/turn-off-ai-rows
	build/turn-off-ai-rows

check: check-turn-off-ai-rows
.PHONY: check-turn-off-ai-rows

build/hide-chat-button: tests/hide-chat-button.m src/dylib/Patches/HideChatButton/HideChatButton.m src/dylib/Patches/TurnOffAI/TurnOffAI.m src/dylib/Patches/TurnOffAI/TurnOffAI.h src/dylib/StdPatch/Hide.m src/dylib/StdPatch/HideHosts.m $(O_HOOK) $(O_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ tests/hide-chat-button.m $(O_HOOK) $(O_VIEWS)

CHAT_MODEL := src/dylib/Patches/DiaChatModel
AGENT_TRANSPORT := $(addprefix src/dylib/Patches/AgentTransport/,AgentRelay.m AgentSocket.m AgentFilters.m AgentFrames.m AgentWriter.m)
CHAT_MODEL_OBJS := $(call OBJSAN,$(CHAT_MODEL)/DiaChatModel.m $(CHAT_MODEL)/Fallback.m $(CHAT_MODEL)/AgentRequest.m $(AGENT_TRANSPORT)) $(S_HOOK)

build/dia-chat-model: tests/dia-chat-model.m $(CHAT_MODEL_OBJS) $(wildcard src/dylib/StdPatch/*.h src/dylib/Patches/AgentTransport/*.h) | build
	clang $(CFLAGS) $(SANITIZE) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/dia-chat-model.m $(CHAT_MODEL_OBJS)

check-dia-chat-model: build/dia-chat-model
	build/dia-chat-model

check: check-dia-chat-model
.PHONY: check-dia-chat-model

check-agent-transport:
	tests/agent-transport

check: check-agent-transport
.PHONY: check-agent-transport

check-chat-models:
	tests/chat-models

check: check-chat-models
.PHONY: check-chat-models

build/hide-connect-app-prompt: tests/hide-connect-app-prompt.m tests/runloop.h src/dylib/Patches/HideConnectAppPrompts/HideConnectAppPrompts.m src/dylib/Patches/HideConnectAppPrompts/HideConnectAppPrompts.h src/dylib/Patches/TurnOffAI/TurnOffAI.m src/dylib/Patches/TurnOffAI/TurnOffAI.h src/dylib/StdPatch/Hide.m src/dylib/StdPatch/HideHosts.m $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/hide-connect-app-prompt.m $(S_HOOK) $(S_VIEWS)

NTP_PROMPTS := src/dylib/Patches/HideTrialButton/HideTrialButton.m \
	src/dylib/Patches/HideSetupSuggestions/HideSetupSuggestions.m \
	src/dylib/Patches/HideDefaultBrowserBanner/HideDefaultBrowserBanner.m

build/hide-ntp-prompts: tests/hide-ntp-prompts.m $(NTP_PROMPTS) src/dylib/StdPatch/Hide.m src/dylib/StdPatch/HideHosts.m $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/hide-ntp-prompts.m $(S_HOOK) $(S_VIEWS)

LAUNCH_FLAGS := src/dylib/Patches/LaunchFlags/Parse.m src/dylib/Patches/LaunchFlags/LaunchFlags.m src/dylib/Patches/LaunchFlags/Rows.m

build/launch-flags: tests/launch-flags.m src/dylib/StdPatch/Extensions.m $(LAUNCH_FLAGS) src/dylib/Patches/LaunchFlags/LaunchFlags.h src/dylib/Settings/Controls.m src/dylib/Settings/Settings.h $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/launch-flags.m $(S_HOOK) $(S_VIEWS)

build/command-bar-swap: tests/command-bar-swap.m src/dylib/Patches/CommandBar/CommandBarSwap.m src/dylib/Patches/CommandBar/HideTabButton.m src/dylib/Patches/CommandBar/HideTabRows.m src/dylib/Patches/CommandBar/CommandBarOverlay.h src/dylib/Patches/CommandBar/HideTab.h $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/command-bar-swap.m $(S_HOOK) $(S_VIEWS)

build/command-bar-spare: tests/command-bar-spare.m tests/runloop.h src/dylib/Patches/CommandBar/CommandBarSpare.m src/dylib/Patches/CommandBar/CommandBarSpareMaker.m src/dylib/Patches/CommandBar/HideTab.m src/dylib/Patches/CommandBar/HideTabButton.m $(S_BARTABS) src/dylib/Patches/CommandBar/CommandBarOverlay.h src/dylib/Patches/CommandBar/HideTab.h src/dylib/Patches/CommandBar/Tabs.h $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/command-bar-spare.m $(S_BARTABS) $(S_HOOK) $(S_VIEWS)

build/command-bar-lifecycle: tests/command-bar-lifecycle.m src/dylib/Patches/CommandBar/CommandBar.m $(S_BARTABS) src/dylib/Patches/CommandBar/CommandBarOverlay.h src/dylib/Patches/CommandBar/HideTab.h src/dylib/Patches/CommandBar/Tabs.h src/dylib/Patches/CommandBar/AutoPip.h src/dylib/Patches/CompactCommandBar/CompactCommandBar.h $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/command-bar-lifecycle.m $(S_BARTABS) $(S_HOOK) $(S_VIEWS)

SIDEBAR_GRAIN_DIR := src/dylib/Patches/SidebarGrain
SIDEBAR_GRAIN := $(call OBJ,$(addprefix $(SIDEBAR_GRAIN_DIR)/,GrainView.m GrainAppearance.m GrainMaterial.m TextureMaterial.m TexturePatterns.m GrainSettings.m GrainControls.m GrainHosts.m GrainMenu.m) \
	src/dylib/Patches/KeepWindowsActive/KeepWindowsActive.m)
SIDEBAR_GRAIN_TESTS := $(addprefix tests/,sidebar-grain.m sidebar-grain-render.m sidebar-grain-hosts.m sidebar-grain-menu.m)

build/sidebar-grain: $(SIDEBAR_GRAIN_TESTS) tests/sidebar-grain-render.h $(SIDEBAR_GRAIN) $(O_HOOK) $(O_VIEWS) $(wildcard $(SIDEBAR_GRAIN_DIR)/*.h src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ $(SIDEBAR_GRAIN_TESTS) $(SIDEBAR_GRAIN) $(O_HOOK) $(O_VIEWS)

check-sidebar-grain: build/sidebar-grain
	build/sidebar-grain

check: check-sidebar-grain
.PHONY: check-sidebar-grain

build/tab-titles: tests/tab-titles.m src/dylib/Patches/TabTitles/Title.m src/dylib/Patches/TabTitles/Title.h | build
	clang $(CFLAGS) -Isrc/dylib -framework Foundation -o $@ tests/tab-titles.m src/dylib/Patches/TabTitles/Title.m

DIAPATCH_PARTS := $(filter-out src/diapatch/main.m,$(wildcard src/diapatch/*.m))

build/diapatch-tests: tests/diapatch.m $(wildcard src/diapatch/*.[hm]) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/diapatch -framework AppKit -framework CoreGraphics -framework Security -o $@ tests/diapatch.m $(DIAPATCH_PARTS)

build/ai-history-search: tests/ai-history-search.m src/dylib/Patches/AIHistorySearch/AIHistorySearch.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/ai-history-search.m

build/open-sidebar-instantly: tests/open-sidebar-instantly.m src/dylib/Patches/OpenSidebarInstantly/OpenSidebarInstantly.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/open-sidebar-instantly.m

build/native-messaging: tests/native-messaging.m src/dylib/StdPatch/Hosts.m src/dylib/Patches/Passkeys/Passkeys.m src/dylib/Patches/ICloudPasswords/ICloudPasswords.m src/dylib/Patches/Bitwarden/Bitwarden.m src/dylib/Patches/ProtonPass/ProtonPass.m src/dylib/Patches/OnePassword/OnePassword.m src/diapatch/PasswordsHost.m $(wildcard src/dylib/StdPatch/*.h src/diapatch/Passwords*.h $(PASSKEYS)/*) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -D_mh_dylib_header=_mh_execute_header -Isrc/dylib -Isrc/diapatch $(EXTENSION) -framework AppKit -o $@ \
		tests/native-messaging.m src/dylib/StdPatch/Hosts.m src/dylib/Patches/Passkeys/Passkeys.m src/dylib/Patches/OnePassword/OnePassword.m

build/diapatch-passkeys: tests/diapatch-passkeys.m src/diapatch/Disclaim.m src/diapatch/PasswordsLaunch.m src/diapatch/PasswordsHandoff.m src/diapatch/Passkeys.m $(wildcard src/diapatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/diapatch -framework Foundation -framework CoreGraphics -framework Security -o $@ tests/diapatch-passkeys.m

build/passkeys-origin: tests/passkeys-origin.m src/diapatch/Passkeys.m src/diapatch/Disclaim.m $(addprefix src/diapatch/,Passkeys.h LaunchServices.h Disclaim.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc -framework Foundation -framework CoreGraphics -o $@ tests/passkeys-origin.m src/diapatch/Disclaim.m

build/passkeys-managers: tests/passkeys-managers.m tests/passkeys-managers.js $(PASSKEYS)/page.js | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -framework Foundation -framework JavaScriptCore -o $@ tests/passkeys-managers.m

check-passkeys-managers: build/passkeys-managers
	build/passkeys-managers

check: check-passkeys-managers
.PHONY: check-passkeys-managers

build/app-icon-signing: tests/app-icon-signing.m $(addprefix src/diapatch/,AppIcon.m IconCatalog.m TweakPrefs.m AppIcon.h IconCatalog.h TweakPrefs.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc -framework Foundation -framework CoreGraphics -framework Security -o $@ tests/app-icon-signing.m $(addprefix src/diapatch/,AppIcon.m IconCatalog.m TweakPrefs.m)

PEEK_LIFE := $(addprefix src/dylib/Patches/Peek/,Peek.h Glow.m Tab.m Selection.m Motion.m Keys.m Visibility.m Chat.m ChatContext.m Card.m Pages.m Handoff.m Zoom.m DragLinks.m)
build/peek-lifecycle: tests/peek-lifecycle.m $(PEEK_LIFE) $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/peek-lifecycle.m $(S_HOOK) $(S_VIEWS)

PEEK_TABS := $(addprefix src/dylib/Patches/Peek/,Peek.h Controls.m Address.m Find.m Tab.m Selection.m Motion.m Keys.m Visibility.m Chat.m ChatContext.m Card.m Pages.m Handoff.m Zoom.m)
build/peek-tabs: tests/peek-tabs.m $(PEEK_TABS) $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/peek-tabs.m $(S_HOOK) $(S_VIEWS)

PEEK_CHAT := $(addprefix src/dylib/Patches/Peek/,Peek.h Chat.m ChatContext.m Keys.m Visibility.m Selection.m Card.m Pages.m Handoff.m Motion.m Tab.m)
build/peek-chat: tests/peek-chat.m $(PEEK_CHAT) $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/peek-chat.m $(S_HOOK) $(S_VIEWS)

HIDE_TOOLBAR_OFF := $(addprefix $(HIDE_TOOLBAR_DIR)/,HideToolbar.h HideToolbar.m Layout.m Hover.m Permission.m KeepBookmarks.m PlainTab.m ProgressLine.m ProgressColors.m LoadingProgress.m)
build/hide-toolbar-off: tests/hide-toolbar-off.m $(HIDE_TOOLBAR_OFF) $(O_HOOK) $(O_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -framework Metal -o $@ tests/hide-toolbar-off.m $(O_HOOK) $(O_VIEWS)

HIDE_TOOLBAR_FOCUS := $(addprefix $(HIDE_TOOLBAR_DIR)/,HideToolbar.h HideToolbar.m Layout.m Hover.m Permission.m RevealOnHover.m KeepBookmarks.m ShowWithSidebar.m ShowOnNewTab.m ShowWithTopTabs.m)
build/hide-toolbar-focus-bookmarks: tests/hide-toolbar-focus-bookmarks.m $(HIDE_TOOLBAR_FOCUS) $(O_HOOK) $(O_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/hide-toolbar-focus-bookmarks.m $(O_HOOK) $(O_VIEWS)

WINDOW_PATCHES := $(call OBJSAN,src/dylib/Patches/WindowCorners/WindowCorners.m src/dylib/Patches/WindowMaterial/WindowMaterial.m src/dylib/Patches/PrivateWindowTheme/PrivateWindowTheme.m src/dylib/Patches/HideTrafficLights/HideTrafficLights.m src/dylib/Patches/CompactCommandBar/CompactCommandBar.m src/dylib/Patches/CompactCommandBar/Layout.m src/dylib/Patches/CompactCommandBar/NewTab.m src/dylib/Patches/CommandBar/HideTabParked.m src/dylib/Patches/CommandBar/HideTabLayout.m)
build/window-patches: tests/window-patches.m $(WINDOW_PATCHES) src/dylib/Patches/DragWindowFromPage/DragWindowFromPage.m $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h src/dylib/Patches/CompactCommandBar/*.h src/dylib/Patches/CommandBar/HideTab.h src/dylib/Patches/EdgeToEdge/EdgeToEdge.h) | build
	clang $(CFLAGS) $(SANITIZE) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/window-patches.m $(WINDOW_PATCHES) $(S_HOOK) $(S_VIEWS)

build/zoom-on-double-click: tests/zoom-on-double-click.m src/dylib/Patches/ZoomOnDoubleClick/ZoomOnDoubleClick.m $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/zoom-on-double-click.m $(S_HOOK) $(S_VIEWS)

check-zoom-on-double-click: build/zoom-on-double-click
	build/zoom-on-double-click

check: check-zoom-on-double-click
.PHONY: check-zoom-on-double-click

build/pinned-tab-close-button: tests/pinned-tab-close-button.m src/dylib/Patches/PinnedTabCloseButton/PinnedTabCloseButton.m src/dylib/Patches/PinnedTabCloseButton/PinnedTabs.h src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ $<

build/pinned-split-close: tests/pinned-split-close.m src/dylib/Patches/PinnedSplitClose/PinnedSplitClose.m src/dylib/Patches/PinnedTabCloseButton/PinnedTabs.h src/dylib/Patches/CommandBar/Tabs.h src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ $<

build/pinned-cmd-click: tests/pinned-cmd-click.m src/dylib/Patches/PinnedCmdClick/PinnedCmdClick.m src/dylib/Commands/GroupTabs/GroupTabs.h $(S_HOOK) $(S_VIEWS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/pinned-cmd-click.m $(S_HOOK) $(S_VIEWS)

SIDEBAR_TAB_BUGS := $(call OBJSAN,src/dylib/Patches/HideSleepingTabs/HideSleepingTabs.m src/dylib/Patches/HideTabGroupBackground/HideTabGroupBackground.m \
	src/dylib/Patches/KeepFoldersOpen/KeepFoldersOpen.m src/dylib/Patches/CollapsePinned/CollapsePinned.m \
	src/dylib/Patches/CompactTabRows/CompactTabRows.m src/dylib/Patches/UndoCloseTab/UndoCloseTab.m \
	src/dylib/Patches/SavePageAs/SavePageAs.m src/dylib/Patches/ProfileEmoji/ProfileEmoji.m \
	src/dylib/Patches/PullRequestRepo/PullRequestRepo.m src/dylib/Patches/PullRequestRepo/Subtitle.m src/dylib/Patches/PullRequestRepo/Rows.m \
	src/dylib/Patches/UnloadTab/UnloadTab.m src/dylib/Patches/UnloadTab/Pages.m src/dylib/Patches/UnloadTab/Recent.m \
	src/dylib/Patches/PinnedTabCloseButton/PinnedTabs.m src/dylib/Patches/CompactSidebarHeader/CompactSidebarHeader.m \
	src/dylib/Patches/TidyTabs/TidyTabs.m src/dylib/Patches/TidyTabs/Layout.m src/dylib/Patches/TidyTabs/Hover.m \
	src/dylib/Patches/TidyTabs/Row.m src/dylib/Patches/TidyTabs/Separator.m src/dylib/Patches/TidyTabs/Brush.m src/dylib/Patches/TidyTabs/Wave.m \
	src/dylib/Patches/CommandBar/HideTab.m src/dylib/Patches/CommandBar/HideTabRows.m \
	src/dylib/Patches/CommandBar/HideTabLayout.m src/dylib/Patches/CommandBar/HideTabParked.m) \
	$(S_BARTABS) $(S_MESSAGES) $(S_HOOK) $(S_VIEWS)

build/sidebar-tab-bugs: tests/sidebar-tab-bugs.m $(SIDEBAR_TAB_BUGS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) $(SANITIZE) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/sidebar-tab-bugs.m $(SIDEBAR_TAB_BUGS)

UNLOAD_TAB := $(call OBJSAN,src/dylib/Patches/UnloadTab/UnloadTab.m src/dylib/Patches/UnloadTab/Pages.m src/dylib/Patches/UnloadTab/Recent.m \
	src/dylib/Patches/PinnedTabCloseButton/PinnedTabs.m) $(S_BARTABS) $(S_MESSAGES) $(S_HOOK) $(S_VIEWS)

build/unload-tab: tests/unload-tab.m tests/watchdog.h $(UNLOAD_TAB) $(wildcard src/dylib/Patches/UnloadTab/*.h src/dylib/Patches/PinnedTabCloseButton/PinnedTabs.h src/dylib/Patches/CommandBar/Tabs.h src/dylib/Commands/GroupTabs/GroupTabs.h src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) $(SANITIZE) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/unload-tab.m $(UNLOAD_TAB)

PROFILE_COLOR_PICKER := $(call OBJSAN,$(wildcard src/dylib/Patches/ProfileColorPicker/*.m)) $(S_HOOK) $(S_VIEWS)

build/profile-color-picker: tests/profile-color-picker.m $(PROFILE_COLOR_PICKER) src/dylib/Patches/ProfileColorPicker/ProfileColorPicker.h $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) $(SANITIZE) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/profile-color-picker.m $(PROFILE_COLOR_PICKER)

HISTORICAL_REGRESSIONS := $(call OBJSAN,src/dylib/Patches/CompactTabRows/CompactTabRows.m src/dylib/Patches/CollapsePinned/CollapsePinned.m \
	src/dylib/Patches/PullRequestRepo/PullRequestRepo.m src/dylib/Patches/PullRequestRepo/Subtitle.m src/dylib/Patches/PullRequestRepo/Rows.m) \
	$(S_HOOK) $(S_VIEWS)

build/historical-regressions: tests/historical-regressions.m tests/watchdog.h tests/runloop.h src/dylib/Patches/Peek/Toolbar.m src/dylib/Patches/Peek/ToolbarRules.m src/dylib/Patches/LittleDia/Over.m src/dylib/Patches/LittleDia/Stack.m $(HISTORICAL_REGRESSIONS) $(wildcard src/dylib/StdPatch/*.h src/dylib/Patches/Peek/Peek.h src/dylib/Patches/LittleDia/LittleDia.h src/dylib/Patches/HideToolbar/HideToolbar.h src/dylib/Patches/CompactTabRows/CompactTabRows.h src/dylib/Patches/PullRequestRepo/PullRequestRepo.h) | build
	clang $(CFLAGS) $(SANITIZE) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/historical-regressions.m $(HISTORICAL_REGRESSIONS)

# DiaPatches' constructor skips helper processes, so the suite runs as one and loads the patch table itself.
build/settings-cleanup: tests/settings-cleanup.m build/DiaPatches.dylib $(wildcard src/dylib/StdPatch/*.h src/dylib/Settings/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/settings-cleanup.m build/DiaPatches.dylib -Wl,-rpath,@loader_path/..

check-settings-cleanup: build/settings-cleanup
	$(call CLEAN_PLIST,com.diapatches.settings-test.%s,build/settings-cleanup --type=settings-cleanup)

check: check-settings-cleanup
.PHONY: check-settings-cleanup

build/abi-kvc-kvo-swift.o: src/dylib/Commands/GroupTabs/Selection.swift tests/abi-kvc-kvo-swift.swift | build
	swiftc $(SWIFTFLAGS) -emit-object -o $@ $^

ABI_KVC_KVO := $(S_HOOK) $(S_VIEWS) $(S_BARTABS) \
	$(call OBJSAN,src/dylib/Patches/LittleDia/Profile.m src/dylib/Patches/SkipAccount/Code.m \
	src/dylib/Patches/Peek/Address.m src/dylib/Patches/Peek/CopyURL.m src/dylib/Patches/Peek/Toolbar.m \
	src/dylib/Patches/Peek/ToolbarRules.m src/dylib/Patches/Peek/ChatContext.m src/dylib/Patches/Peek/Peek.m src/dylib/Patches/Peek/PinnedLinks.m \
	src/dylib/Settings/Preview.m)

build/abi-kvc-kvo: tests/abi-kvc-kvo.m tests/watchdog.h tests/runloop.h build/abi-kvc-kvo-swift.o $(ABI_KVC_KVO) src/dylib/Patches/ExtensionsShortcut/ExtensionsShortcut.m src/dylib/Patches/HideHistorySuggestions/HideHistorySuggestions.m $(wildcard src/dylib/StdPatch/*.h src/dylib/Patches/Peek/*.h src/dylib/Patches/LittleDia/*.h src/dylib/Patches/CommandBar/*.h src/dylib/Patches/SkipAccount/*.h src/dylib/Settings/*.h) | build
	clang $(CFLAGS) $(SANITIZE) -Isrc/dylib -framework AppKit -framework QuartzCore -framework AVFoundation -framework VideoToolbox -framework CoreMedia -framework CoreVideo \
		-L$(SWIFT_LIB) -Wl,-rpath,/usr/lib/swift -o $@ tests/abi-kvc-kvo.m $(ABI_KVC_KVO) build/abi-kvc-kvo-swift.o

VIEW_REUSE_LAYOUT := $(call OBJSAN,$(wildcard src/dylib/Patches/EdgeToEdge/*.m) src/dylib/Patches/WindowCorners/WindowCorners.m \
	src/dylib/Patches/WindowMaterial/WindowMaterial.m src/dylib/Patches/PullRequestRepo/PullRequestRepo.m \
	src/dylib/Patches/PullRequestRepo/Subtitle.m src/dylib/Patches/PullRequestRepo/Rows.m \
	src/dylib/Patches/CompactTabRows/CompactTabRows.m src/dylib/Patches/CollapsePinned/CollapsePinned.m \
	src/dylib/Patches/HideTabGroupBackground/HideTabGroupBackground.m src/dylib/Patches/ProfileEmoji/ProfileEmoji.m \
	src/dylib/Patches/TidyTabs/TidyTabs.m src/dylib/Patches/TidyTabs/Layout.m src/dylib/Patches/TidyTabs/Hover.m \
	src/dylib/Patches/TidyTabs/Row.m src/dylib/Patches/TidyTabs/Separator.m src/dylib/Patches/TidyTabs/Brush.m \
	src/dylib/Patches/TidyTabs/Wave.m src/dylib/Patches/SidebarGrain/SidebarGrain.m \
	src/dylib/Patches/CompactCommandBar/CompactCommandBar.m src/dylib/Patches/CompactCommandBar/Layout.m \
	src/dylib/Patches/CompactCommandBar/NewTab.m src/dylib/Patches/LittleDia/Window.m \
	src/dylib/Patches/LittleDia/Over.m src/dylib/Patches/LittleDia/Bar.m src/dylib/Patches/LittleDia/Address.m \
	src/dylib/Patches/TurnOffAI/TurnOffAI.m src/dylib/Patches/TurnOffAI/Rows.m \
	src/dylib/Patches/HideToolbar/PlainTab.m src/dylib/Patches/HideToolbar/ProgressLine.m \
	$(wildcard src/dylib/Patches/HideVerticalTabGlow/*.m)) \
	$(S_HOOK) $(S_VIEWS)

build/view-reuse-layout: tests/view-reuse-layout.m tests/watchdog.h $(VIEW_REUSE_LAYOUT) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) $(SANITIZE) -Isrc/dylib -framework AppKit -framework QuartzCore -framework Metal -o $@ tests/view-reuse-layout.m $(VIEW_REUSE_LAYOUT)

COMBINATORIAL := $(S_HOOK) $(S_VIEWS) $(S_APP) $(S_MESSAGES) $(S_BARTABS) \
	$(call OBJSAN,src/dylib/StdPatch/Hide.m src/dylib/StdPatch/HideHosts.m src/dylib/StdPatch/Patch.m \
	src/dylib/StdPatch/Shortcut.m src/dylib/StdPatch/Extensions.m src/dylib/StdPatch/Zoom.m \
	src/dylib/Settings/Controls.m src/dylib/Settings/Items.m src/dylib/Settings/Overview.m \
	src/dylib/Settings/Folder.m src/dylib/Settings/Home.m src/dylib/Settings/Page.m src/dylib/Settings/Config.m \
	src/dylib/Commands/GroupTabs/Tracking.m src/dylib/Commands/GroupTabs/Menu.m \
	$(HIDE_TOOLBAR) src/dylib/Patches/ShowAddressField/ShowAddressField.m \
	src/dylib/Patches/DestinationToggleEngineName/DestinationToggleEngineName.m \
	src/dylib/Patches/HideChatButton/HideChatButton.m src/dylib/Patches/HideChatsButton/HideChatsButton.m \
	src/dylib/Patches/HideUpgradeBanner/HideUpgradeBanner.m src/dylib/Patches/HidePersonalizeButton/HidePersonalizeButton.m \
	src/dylib/Patches/HideSkillsSuggestions/HideSkillsSuggestions.m src/dylib/Patches/HideConnectAppPrompts/HideConnectAppPrompts.m \
	src/dylib/Patches/HideTrialButton/HideTrialButton.m src/dylib/Patches/HideSetupSuggestions/HideSetupSuggestions.m \
	src/dylib/Patches/HideDefaultBrowserBanner/HideDefaultBrowserBanner.m \
	src/dylib/Patches/TurnOffAI/TurnOffAI.m src/dylib/Patches/TurnOffAI/Rows.m \
	src/dylib/Patches/HideTrafficLights/HideTrafficLights.m src/dylib/Patches/CompactSidebarHeader/CompactSidebarHeader.m \
	src/dylib/Patches/WindowCorners/WindowCorners.m \
	$(wildcard src/dylib/Patches/EdgeToEdge/*.m) \
	$(wildcard src/dylib/Patches/ProfileColorPicker/*.m) \
	src/dylib/Patches/PrivateWindowTheme/PrivateWindowTheme.m \
	src/dylib/Patches/WindowMaterial/WindowMaterial.m src/dylib/Patches/TranslucentSidebar/TranslucentSidebar.m \
	src/dylib/Patches/HidePinnedTabBorder/HidePinnedTabBorder.m src/dylib/Patches/HideTabGroupBackground/HideTabGroupBackground.m \
	src/dylib/Patches/UnloadTab/UnloadTab.m src/dylib/Patches/UnloadTab/Pages.m src/dylib/Patches/UnloadTab/Recent.m \
	src/dylib/Patches/PinnedTabCloseButton/PinnedTabs.m \
	src/dylib/Patches/CollapsePinned/CollapsePinned.m src/dylib/Patches/CompactTabRows/CompactTabRows.m \
	src/dylib/Patches/CommandBar/CommandBar.m src/dylib/Patches/CommandBar/AutoPip.m \
	src/dylib/Patches/CommandBar/HideTabLayout.m \
	src/dylib/Patches/LittleDia/LinkMenu.m src/dylib/Patches/LittleDia/Options.m src/dylib/Patches/LittleDia/Launcher.m \
	src/dylib/Patches/PinnedCmdClick/PinnedCmdClick.m \
	src/dylib/Patches/Peek/Peek.m src/dylib/Patches/Peek/Card.m src/dylib/Patches/Peek/Pages.m \
	src/dylib/Patches/Peek/Keys.m src/dylib/Patches/Peek/Chat.m src/dylib/Patches/Peek/ChatContext.m \
	src/dylib/Patches/Peek/Visibility.m src/dylib/Patches/Peek/Motion.m src/dylib/Patches/Peek/Selection.m \
	src/dylib/Patches/Peek/Handoff.m \
	src/dylib/Patches/Peek/Tab.m src/dylib/Patches/Peek/Zoom.m \
	$(LAUNCH_FLAGS) src/dylib/Patches/SplitClientHello/SplitClientHello.m \
	src/dylib/Patches/SplitClientHello/Split.m src/dylib/Patches/SplitClientHello/Write.m src/dylib/Patches/SplitClientHello/Send.m \
	$(LOCAL_CORE))

build/combinatorial-stability: tests/combinatorial-stability.m tests/watchdog.h tests/runloop.h $(COMBINATORIAL) src/dylib/SafeMode/SafeMode.m $(wildcard src/dylib/StdPatch/*.h src/dylib/Local/*.h) | build
	clang $(CFLAGS) $(SANITIZE) -Isrc/dylib -framework AppKit -framework QuartzCore -framework UniformTypeIdentifiers -o $@ tests/combinatorial-stability.m $(COMBINATORIAL)

build/local-tweaks: tests/local-tweaks.m build/DiaPatches.dylib $(wildcard src/dylib/Local/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/local-tweaks.m build/DiaPatches.dylib -Wl,-rpath,@loader_path/..

check-local-tweaks: build/local-tweaks
	$(call CLEAN_PLIST,com.diapatches.local-test.%s com.diapatches.local-test.%s.other,build/local-tweaks --type=local-tweaks)

check: check-local-tweaks
.PHONY: check-local-tweaks

build/settings-sidebar-fallback: tests/settings-sidebar-fallback.m build/DiaPatches.dylib $(wildcard src/dylib/StdPatch/*.h src/dylib/Settings/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/settings-sidebar-fallback.m build/DiaPatches.dylib -Wl,-rpath,@loader_path/..

check-settings-sidebar-fallback: build/settings-sidebar-fallback
	home="$$(mktemp -d /tmp/dp-sidebar-fallback.XXXXXX)"; domain="$$home/com.diapatches"; \
	trap 's=$$?; defaults delete "$$domain" 2>/dev/null; rm -rf "$$home"; exit $$s' EXIT; \
	DIAPATCH_HOME="$$home" DIATWEAKS_DOMAIN="$$domain" build/settings-sidebar-fallback --type=renderer

check: check-settings-sidebar-fallback
.PHONY: check-settings-sidebar-fallback

build/config-portability: tests/config-portability.m build/DiaPatches.dylib $(wildcard src/dylib/StdPatch/*.h src/dylib/Settings/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/config-portability.m build/DiaPatches.dylib -Wl,-rpath,@loader_path/..

check-config-portability: build/config-portability
	build/config-portability --type=config-portability

check: check-config-portability
.PHONY: check-config-portability

DELETE_PROFILE_OBJS := $(call OBJSAN,$(wildcard src/dylib/Patches/DeleteProfileMenu/*.m)) $(S_HOOK) $(S_VIEWS) $(S_APP)

build/delete-profile-menu: tests/delete-profile-menu.m $(DELETE_PROFILE_OBJS) $(wildcard src/dylib/Patches/DeleteProfileMenu/*.h src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) $(SANITIZE) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/delete-profile-menu.m $(DELETE_PROFILE_OBJS)

check-delete-profile-menu: build/delete-profile-menu
	build/delete-profile-menu --type=renderer

check: check-delete-profile-menu
.PHONY: check-delete-profile-menu

check: build/diapatch build/diapatch-tests build/group-tabs build/mouse-back-forward build/vertical-tab-glow build/split-client-hello build/peek-cursor build/link-key build/peek-tabs build/peek-chat build/safe-mode build/pause build/hook-table build/updates-runtime build/settings-preview build/runtime-guards build/tidy-tabs build/drag-offset build/small-tab-shape build/toolbar-permission build/launch-flags build/little-dia-stack build/little-dia-profile build/little-dia-over build/little-dia-focus build/tracking build/hide-toolbar-settle build/command-bar-swap build/command-bar-spare build/tab-titles build/show-address-field build/destination-toggle-engine-name build/hide-chat-button build/hide-connect-app-prompt build/hide-ntp-prompts build/open-sidebar-instantly build/ai-history-search build/native-messaging build/diapatch-passkeys build/passkeys-origin build/app-icon-signing build/little-dia-route build/little-dia-tab-links build/chat-card build/peek-lifecycle build/hide-toolbar-off build/hide-toolbar-focus-bookmarks build/little-dia-launcher build/pinned-cmd-click build/command-bar-lifecycle build/window-patches build/pinned-tab-close-button build/pinned-split-close build/sidebar-tab-bugs build/unload-tab build/profile-color-picker build/historical-regressions build/abi-kvc-kvo build/view-reuse-layout build/combinatorial-stability build/local-tweaks build/patches.json
	tests/tweaks-update
	build/diapatch-tests
	build/group-tabs
	build/tidy-tabs
	build/mouse-back-forward
	build/vertical-tab-glow
	build/split-client-hello
	build/peek-cursor
	build/link-key
	build/peek-lifecycle
	build/peek-tabs
	build/peek-chat
	build/safe-mode
	build/pause
	build/hook-table
	$(call CLEAN_PLIST,com.diapatches.updates-test.%s,build/updates-runtime)
	build/settings-preview
	build/runtime-guards
	build/drag-offset
	build/small-tab-shape
	build/toolbar-permission
	build/hide-toolbar-off
	build/hide-toolbar-focus-bookmarks
	build/little-dia-launcher
	build/pinned-cmd-click
	build/launch-flags
	build/little-dia-stack
	build/little-dia-profile
	build/tracking
	build/little-dia-over
	build/little-dia-route
	build/little-dia-tab-links
	build/little-dia-focus
	build/chat-card
	build/hide-toolbar-settle
	build/command-bar-swap
	build/command-bar-spare
	$(call CLEAN_PLIST,com.diapatches.command-bar-lifecycle.%s com.diapatches.lifecycle-domain,build/command-bar-lifecycle)
	build/tab-titles
	build/show-address-field
	build/destination-toggle-engine-name
	build/hide-chat-button
	build/hide-connect-app-prompt
	build/hide-ntp-prompts
	build/open-sidebar-instantly
	build/ai-history-search
	build/native-messaging
	build/diapatch-passkeys
	build/passkeys-origin
	build/app-icon-signing
	build/window-patches
	build/pinned-tab-close-button
	build/pinned-split-close
	build/sidebar-tab-bugs
	build/unload-tab
	$(call CLEAN_PLIST,com.diapatches.profile-color-picker.%s,build/profile-color-picker)
	build/historical-regressions
	build/abi-kvc-kvo
	$(call CLEAN_PLIST,com.diapatches.view-reuse-layout.%s,build/view-reuse-layout)
	build/combinatorial-stability
	scripts/build-tweaks --check
	scripts/check-patches

test: build/DiaPatches.dylib
	./test.sh

patch:
	@scripts/new-patch "$(NAME)"

clean:
	rm -rf build cli/target

.PHONY: all check clean test patch
