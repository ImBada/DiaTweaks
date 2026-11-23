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

# Local tweaks compile against the headers of the installed dylib, so every header rides inside it.
DYLIB_HEADERS := $(shell find src/dylib -name '*.h')
HEADERS_BIN := build/dp_headers.bin
LOCAL_CORE := src/dylib/Local/Local.m src/dylib/Local/Build.m src/dylib/Local/Extract.m src/dylib/Local/State.m

COMMIT := $(shell git rev-parse HEAD 2>/dev/null)

all: build/diapatch build/DiaPatches.dylib build/patches.json

build/commit: FORCE | build
	@echo '$(COMMIT)' | cmp -s - $@ || echo '$(COMMIT)' > $@

FORCE:

build/diapatch: $(wildcard src/diapatch/*.[hm]) build/commit | build
	clang $(CFLAGS) -DDIATWEAKS_COMMIT='"$(COMMIT)"' -framework AppKit -framework CoreGraphics -framework Security -o $@ $(filter %.m,$^)

build/DiaPatchesSwift.o: $(DYLIB_SWIFT) | build
	swiftc $(SWIFTFLAGS) -emit-object -o $@ $^

$(HEADERS_BIN): $(DYLIB_HEADERS) scripts/pack-headers | build
	scripts/pack-headers src/dylib $@

build/DiaPatches.dylib: $(DYLIB_SOURCES) build/DiaPatchesSwift.o $(HEADERS_BIN) $(wildcard $(PASSKEYS)/*) | build
	clang $(CFLAGS) -Isrc/dylib -dynamiclib $(EXTENSION) -Wl,-sectcreate,__TEXT,__dp_headers,$(HEADERS_BIN) -framework AppKit -framework QuartzCore -framework Metal -framework AVFoundation -framework VideoToolbox -framework CoreMedia -framework CoreVideo \
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
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ $<

build/peek-link: tests/peek-link.m src/dylib/Patches/Peek/Link.m src/dylib/Patches/Peek/Peek.h $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/peek-link.m src/dylib/Patches/Peek/Link.m

build/safe-mode: tests/safe-mode.m src/dylib/SafeMode/SafeMode.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ $<

build/pause: tests/pause.m src/dylib/SafeMode/SafeMode.m src/dylib/StdPatch/Patch.m src/dylib/StdPatch/Shortcut.m src/dylib/StdPatch/Views.m src/dylib/Settings/Controls.m src/dylib/Settings/Items.m src/dylib/Settings/Overview.m src/dylib/Settings/Folder.m src/dylib/Settings/Home.m src/dylib/Settings/Page.m src/dylib/Settings/Settings.h $(LOCAL_CORE) $(wildcard src/dylib/StdPatch/*.h src/dylib/Local/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/pause.m src/dylib/StdPatch/Views.m

build/hook-table: tests/hook-table.m src/dylib/StdPatch/Hook.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ $<

build/updates-runtime: tests/updates-runtime.m src/dylib/Updates/Updates.m src/dylib/Updates/Updates.h src/dylib/Settings/Controls.m src/dylib/Settings/SoftwareUpdate.m src/dylib/Settings/Settings.h src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/updates-runtime.m src/dylib/StdPatch/Views.m

build/settings-preview: tests/settings-preview.m tests/runloop.h src/dylib/Settings/Preview.m src/dylib/Settings/Controls.m src/dylib/Settings/Settings.h $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -framework AVFoundation -framework VideoToolbox -framework CoreMedia -framework CoreVideo -o $@ tests/settings-preview.m

build/runtime-guards: tests/runtime-guards.m src/dylib/StdPatch/TypedURL.m src/dylib/StdPatch/Hide.m src/dylib/StdPatch/HideHosts.m src/dylib/StdPatch/Hide.h src/dylib/Settings/Settings.m src/dylib/Settings/Settings.h src/dylib/Commands/GroupTabs/Order.m src/dylib/Commands/GroupTabs/Grouping.m src/dylib/Commands/GroupTabs/Menu.m src/dylib/Commands/GroupTabs/GroupTabs.h src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m src/dylib/StdPatch/App.m $(GROUP_TABS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/runtime-guards.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m src/dylib/StdPatch/App.m $(GROUP_TABS)

TIDY := src/dylib/Patches/TidyTabs/Tabs.m src/dylib/Patches/CommandBar/Tabs.m src/dylib/Commands/GroupTabs/Messages.m

build/tidy-tabs: tests/tidy-tabs.m $(TIDY) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ $^

build/drag-offset: tests/drag-offset.m src/dylib/Patches/CompactTabRows/CompactTabRows.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/drag-offset.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

build/small-tab-shape: tests/small-tab-shape.m src/dylib/Patches/CompactTabRows/CompactTabRows.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/small-tab-shape.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

build/little-dia-stack: tests/little-dia-stack.m src/dylib/Patches/LittleDia/Stack.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ $<

build/little-dia-profile: tests/little-dia-profile.m src/dylib/Patches/LittleDia/Profile.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ $<

build/little-dia-launcher: tests/little-dia-launcher.m src/dylib/Patches/LittleDia/Launcher.m src/dylib/Patches/LittleDia/NewWindow.m src/dylib/Patches/LittleDia/LittleDia.h $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/little-dia-launcher.m

build/tracking: tests/tracking.m src/dylib/Commands/GroupTabs/Tracking.m src/dylib/Commands/GroupTabs/Messages.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ tests/tracking.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m src/dylib/Commands/GroupTabs/Messages.m

build/little-dia-over: tests/little-dia-over.m src/dylib/Patches/LittleDia/Route.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ tests/little-dia-over.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

build/little-dia-route: tests/little-dia-route.m src/dylib/Patches/LittleDia/Route.m src/dylib/Patches/LittleDia/Stack.m src/dylib/Patches/LittleDia/Extension.m src/dylib/Patches/LittleDia/LittleDia.h src/dylib/Commands/GroupTabs/Messages.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ tests/little-dia-route.m src/dylib/Commands/GroupTabs/Messages.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m
build/chat-card: tests/chat-card.m src/dylib/Patches/EdgeToEdge/ChatCard.m src/dylib/Patches/EdgeToEdge/EdgeToEdge.h src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/chat-card.m src/dylib/StdPatch/Views.m

build/edge-to-edge-fullscreen: tests/edge-to-edge-fullscreen.m $(wildcard src/dylib/Patches/EdgeToEdge/*.m) src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/edge-to-edge-fullscreen.m $(wildcard src/dylib/Patches/EdgeToEdge/*.m) src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

check-edge-to-edge-fullscreen: build/edge-to-edge-fullscreen
	build/edge-to-edge-fullscreen

check: check-edge-to-edge-fullscreen
.PHONY: check-edge-to-edge-fullscreen

build/little-dia-focus: tests/little-dia-focus.m tests/runloop.h src/dylib/Patches/LittleDia/Window.m src/dylib/Patches/LittleDia/LittleDia.h src/dylib/Commands/GroupTabs/Messages.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/little-dia-focus.m src/dylib/Commands/GroupTabs/Messages.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

HIDE_TOOLBAR_DIR := src/dylib/Patches/HideToolbar
HIDE_TOOLBAR_LAYOUT := $(addprefix $(HIDE_TOOLBAR_DIR)/,HideToolbar.m Layout.m Hover.m Permission.m KeepBookmarks.m)
HIDE_TOOLBAR := $(HIDE_TOOLBAR_LAYOUT) $(addprefix $(HIDE_TOOLBAR_DIR)/,RevealOnHover.m ShowOnNewTab.m ShowWithSidebar.m ShowWithTopTabs.m)
SETTLE := src/dylib/Test/Scenarios.m src/dylib/StdPatch/Patch.m src/dylib/StdPatch/Views.m src/dylib/StdPatch/Hook.m $(HIDE_TOOLBAR)

build/toolbar-permission: tests/toolbar-permission.m $(HIDE_TOOLBAR_LAYOUT) $(HIDE_TOOLBAR_DIR)/HideToolbar.h src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ $(filter %.m,$^)

build/hide-toolbar-settle: tests/hide-toolbar-settle.m src/dylib/Test/Test.m $(SETTLE) $(LOCAL_CORE) $(wildcard src/dylib/StdPatch/*.h src/dylib/Patches/HideToolbar/*.h src/dylib/Local/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/hide-toolbar-settle.m $(SETTLE) $(LOCAL_CORE)

build/show-address-field: tests/show-address-field.m src/dylib/Patches/ShowAddressField/ShowAddressField.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/show-address-field.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

build/destination-toggle-engine-name: tests/destination-toggle-engine-name.m src/dylib/Patches/DestinationToggleEngineName/DestinationToggleEngineName.m src/dylib/Patches/DestinationToggleEngineName/DestinationToggleEngineName.h src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/destination-toggle-engine-name.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

build/hide-chat-button: tests/hide-chat-button.m src/dylib/Patches/HideChatButton/HideChatButton.m src/dylib/Patches/TurnOffAI/TurnOffAI.m src/dylib/Patches/TurnOffAI/TurnOffAI.h src/dylib/StdPatch/Hide.m src/dylib/StdPatch/HideHosts.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -o $@ tests/hide-chat-button.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

CHAT_MODEL := src/dylib/Patches/DiaChatModel
AGENT_TRANSPORT := $(addprefix src/dylib/Patches/AgentTransport/,AgentRelay.m AgentSocket.m AgentFilters.m AgentFrames.m AgentWriter.m)

build/dia-chat-model: tests/dia-chat-model.m $(CHAT_MODEL)/DiaChatModel.m $(CHAT_MODEL)/Fallback.m $(CHAT_MODEL)/AgentRequest.m $(AGENT_TRANSPORT) src/dylib/StdPatch/Hook.m $(wildcard src/dylib/StdPatch/*.h src/dylib/Patches/AgentTransport/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/dia-chat-model.m $(CHAT_MODEL)/DiaChatModel.m $(CHAT_MODEL)/Fallback.m $(CHAT_MODEL)/AgentRequest.m $(AGENT_TRANSPORT) src/dylib/StdPatch/Hook.m

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

build/hide-connect-app-prompt: tests/hide-connect-app-prompt.m tests/runloop.h src/dylib/Patches/HideConnectAppPrompts/HideConnectAppPrompts.m src/dylib/Patches/HideConnectAppPrompts/HideConnectAppPrompts.h src/dylib/Patches/TurnOffAI/TurnOffAI.m src/dylib/Patches/TurnOffAI/TurnOffAI.h src/dylib/StdPatch/Hide.m src/dylib/StdPatch/HideHosts.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/hide-connect-app-prompt.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

NTP_PROMPTS := src/dylib/Patches/HideTrialButton/HideTrialButton.m \
	src/dylib/Patches/HideSetupSuggestions/HideSetupSuggestions.m \
	src/dylib/Patches/HideDefaultBrowserBanner/HideDefaultBrowserBanner.m

build/hide-ntp-prompts: tests/hide-ntp-prompts.m $(NTP_PROMPTS) src/dylib/StdPatch/Hide.m src/dylib/StdPatch/HideHosts.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/hide-ntp-prompts.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

LAUNCH_FLAGS := src/dylib/Patches/LaunchFlags/Parse.m src/dylib/Patches/LaunchFlags/LaunchFlags.m src/dylib/Patches/LaunchFlags/Rows.m

build/launch-flags: tests/launch-flags.m src/dylib/StdPatch/Extensions.m $(LAUNCH_FLAGS) src/dylib/Patches/LaunchFlags/LaunchFlags.h src/dylib/Settings/Controls.m src/dylib/Settings/Settings.h src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/launch-flags.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

build/command-bar-swap: tests/command-bar-swap.m src/dylib/Patches/CommandBar/CommandBarSwap.m src/dylib/Patches/CommandBar/HideTabButton.m src/dylib/Patches/CommandBar/HideTabRows.m src/dylib/Patches/CommandBar/CommandBarOverlay.h src/dylib/Patches/CommandBar/HideTab.h src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/command-bar-swap.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

build/command-bar-spare: tests/command-bar-spare.m tests/runloop.h src/dylib/Patches/CommandBar/CommandBarSpare.m src/dylib/Patches/CommandBar/CommandBarSpareMaker.m src/dylib/Patches/CommandBar/HideTab.m src/dylib/Patches/CommandBar/HideTabButton.m src/dylib/Patches/CommandBar/Tabs.m src/dylib/Patches/CommandBar/CommandBarOverlay.h src/dylib/Patches/CommandBar/HideTab.h src/dylib/Patches/CommandBar/Tabs.h src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/command-bar-spare.m src/dylib/Patches/CommandBar/Tabs.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

build/command-bar-lifecycle: tests/command-bar-lifecycle.m src/dylib/Patches/CommandBar/CommandBar.m src/dylib/Patches/CommandBar/Tabs.m src/dylib/Patches/CommandBar/CommandBarOverlay.h src/dylib/Patches/CommandBar/HideTab.h src/dylib/Patches/CommandBar/Tabs.h src/dylib/Patches/CommandBar/AutoPip.h src/dylib/Patches/CompactCommandBar/CompactCommandBar.h src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/command-bar-lifecycle.m src/dylib/Patches/CommandBar/Tabs.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

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

build/diapatch-passkeys: tests/diapatch-passkeys.m src/diapatch/PasswordsLaunch.m src/diapatch/PasswordsHandoff.m src/diapatch/Passkeys.m $(wildcard src/diapatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/diapatch -framework Foundation -framework CoreGraphics -framework Security -o $@ tests/diapatch-passkeys.m

build/passkeys-origin: tests/passkeys-origin.m src/diapatch/Passkeys.m src/diapatch/Passkeys.h src/diapatch/LaunchServices.h | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc -framework Foundation -framework CoreGraphics -o $@ tests/passkeys-origin.m

build/passkeys-managers: tests/passkeys-managers.m tests/passkeys-managers.js $(PASSKEYS)/page.js | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -framework Foundation -framework JavaScriptCore -o $@ tests/passkeys-managers.m

check-passkeys-managers: build/passkeys-managers
	build/passkeys-managers

check: check-passkeys-managers
.PHONY: check-passkeys-managers

build/app-icon-signing: tests/app-icon-signing.m src/diapatch/AppIcon.m src/diapatch/IconCatalog.m src/diapatch/AppIcon.h src/diapatch/IconCatalog.h | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc -framework Foundation -framework CoreGraphics -framework Security -o $@ tests/app-icon-signing.m src/diapatch/AppIcon.m src/diapatch/IconCatalog.m

PEEK_LIFE := $(addprefix src/dylib/Patches/Peek/,Peek.h Glow.m Tab.m Selection.m Motion.m Keys.m Visibility.m Chat.m ChatContext.m Card.m Pages.m Handoff.m Zoom.m DragLinks.m)
build/peek-lifecycle: tests/peek-lifecycle.m $(PEEK_LIFE) src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/peek-lifecycle.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

PEEK_TABS := $(addprefix src/dylib/Patches/Peek/,Peek.h Controls.m Address.m Find.m Tab.m Selection.m Motion.m Keys.m Visibility.m Chat.m ChatContext.m Card.m Pages.m Handoff.m Zoom.m)
build/peek-tabs: tests/peek-tabs.m $(PEEK_TABS) src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/peek-tabs.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

PEEK_CHAT := $(addprefix src/dylib/Patches/Peek/,Peek.h Chat.m ChatContext.m Keys.m Visibility.m Selection.m Card.m Pages.m Handoff.m Motion.m Tab.m)
build/peek-chat: tests/peek-chat.m $(PEEK_CHAT) src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/peek-chat.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

HIDE_TOOLBAR_OFF := $(addprefix $(HIDE_TOOLBAR_DIR)/,HideToolbar.h HideToolbar.m Layout.m Hover.m Permission.m KeepBookmarks.m PlainTab.m ProgressLine.m ProgressColors.m LoadingProgress.m)
build/hide-toolbar-off: tests/hide-toolbar-off.m $(HIDE_TOOLBAR_OFF) src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -framework Metal -o $@ tests/hide-toolbar-off.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

HIDE_TOOLBAR_FOCUS := $(addprefix $(HIDE_TOOLBAR_DIR)/,HideToolbar.h HideToolbar.m Layout.m Hover.m Permission.m RevealOnHover.m KeepBookmarks.m ShowWithSidebar.m ShowOnNewTab.m ShowWithTopTabs.m)
build/hide-toolbar-focus-bookmarks: tests/hide-toolbar-focus-bookmarks.m $(HIDE_TOOLBAR_FOCUS) src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/hide-toolbar-focus-bookmarks.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

WINDOW_PATCHES := src/dylib/Patches/WindowCorners/WindowCorners.m src/dylib/Patches/WindowMaterial/WindowMaterial.m src/dylib/Patches/PrivateWindowTheme/PrivateWindowTheme.m src/dylib/Patches/HideTrafficLights/HideTrafficLights.m src/dylib/Patches/CompactCommandBar/CompactCommandBar.m src/dylib/Patches/CompactCommandBar/Layout.m src/dylib/Patches/CompactCommandBar/NewTab.m src/dylib/Patches/CommandBar/HideTabParked.m src/dylib/Patches/CommandBar/HideTabLayout.m
build/window-patches: tests/window-patches.m $(WINDOW_PATCHES) src/dylib/Patches/DragWindowFromPage/DragWindowFromPage.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h src/dylib/Patches/CompactCommandBar/*.h src/dylib/Patches/CommandBar/HideTab.h src/dylib/Patches/EdgeToEdge/EdgeToEdge.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/window-patches.m $(WINDOW_PATCHES) src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

build/zoom-on-double-click: tests/zoom-on-double-click.m src/dylib/Patches/ZoomOnDoubleClick/ZoomOnDoubleClick.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/zoom-on-double-click.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

check-zoom-on-double-click: build/zoom-on-double-click
	build/zoom-on-double-click

check: check-zoom-on-double-click
.PHONY: check-zoom-on-double-click

build/pinned-tab-close-button: tests/pinned-tab-close-button.m src/dylib/Patches/PinnedTabCloseButton/PinnedTabCloseButton.m src/dylib/Patches/PinnedTabCloseButton/PinnedTabs.h src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ $<

build/pinned-split-close: tests/pinned-split-close.m src/dylib/Patches/PinnedSplitClose/PinnedSplitClose.m src/dylib/Patches/PinnedTabCloseButton/PinnedTabs.h src/dylib/Patches/CommandBar/Tabs.h src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ $<

build/pinned-cmd-click: tests/pinned-cmd-click.m src/dylib/Patches/PinnedCmdClick/PinnedCmdClick.m src/dylib/Patches/Peek/Peek.h src/dylib/Commands/GroupTabs/GroupTabs.h src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -o $@ tests/pinned-cmd-click.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

SIDEBAR_TAB_BUGS := src/dylib/Patches/HideSleepingTabs/HideSleepingTabs.m src/dylib/Patches/HideTabGroupBackground/HideTabGroupBackground.m \
	src/dylib/Patches/KeepFoldersOpen/KeepFoldersOpen.m src/dylib/Patches/CollapsePinned/CollapsePinned.m \
	src/dylib/Patches/CompactTabRows/CompactTabRows.m src/dylib/Patches/UndoCloseTab/UndoCloseTab.m \
	src/dylib/Patches/SavePageAs/SavePageAs.m src/dylib/Patches/ProfileEmoji/ProfileEmoji.m \
	src/dylib/Patches/PullRequestRepo/PullRequestRepo.m src/dylib/Patches/PullRequestRepo/Subtitle.m src/dylib/Patches/PullRequestRepo/Rows.m \
	src/dylib/Patches/UnloadTab/UnloadTab.m src/dylib/Patches/UnloadTab/Pages.m src/dylib/Patches/UnloadTab/Recent.m \
	src/dylib/Patches/PinnedTabCloseButton/PinnedTabs.m src/dylib/Patches/CompactSidebarHeader/CompactSidebarHeader.m \
	src/dylib/Patches/TidyTabs/TidyTabs.m src/dylib/Patches/TidyTabs/Layout.m src/dylib/Patches/TidyTabs/Hover.m \
	src/dylib/Patches/TidyTabs/Row.m src/dylib/Patches/TidyTabs/Separator.m src/dylib/Patches/TidyTabs/Brush.m src/dylib/Patches/TidyTabs/Wave.m \
	src/dylib/Patches/CommandBar/Tabs.m src/dylib/Patches/CommandBar/HideTab.m src/dylib/Patches/CommandBar/HideTabRows.m \
	src/dylib/Patches/CommandBar/HideTabLayout.m src/dylib/Patches/CommandBar/HideTabParked.m src/dylib/Commands/GroupTabs/Messages.m \
	src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

build/sidebar-tab-bugs: tests/sidebar-tab-bugs.m $(SIDEBAR_TAB_BUGS) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/sidebar-tab-bugs.m $(SIDEBAR_TAB_BUGS)

UNLOAD_TAB := src/dylib/Patches/UnloadTab/UnloadTab.m src/dylib/Patches/UnloadTab/Pages.m src/dylib/Patches/UnloadTab/Recent.m \
	src/dylib/Patches/PinnedTabCloseButton/PinnedTabs.m src/dylib/Patches/CommandBar/Tabs.m \
	src/dylib/Commands/GroupTabs/Messages.m src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

build/unload-tab: tests/unload-tab.m tests/watchdog.h $(UNLOAD_TAB) $(wildcard src/dylib/Patches/UnloadTab/*.h src/dylib/Patches/PinnedTabCloseButton/PinnedTabs.h src/dylib/Patches/CommandBar/Tabs.h src/dylib/Commands/GroupTabs/GroupTabs.h src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/unload-tab.m $(UNLOAD_TAB)

PROFILE_COLOR_PICKER := $(wildcard src/dylib/Patches/ProfileColorPicker/*.m) src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

build/profile-color-picker: tests/profile-color-picker.m $(PROFILE_COLOR_PICKER) src/dylib/Patches/ProfileColorPicker/ProfileColorPicker.h $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/profile-color-picker.m $(PROFILE_COLOR_PICKER)

HISTORICAL_REGRESSIONS := src/dylib/Patches/CompactTabRows/CompactTabRows.m src/dylib/Patches/CollapsePinned/CollapsePinned.m \
	src/dylib/Patches/PullRequestRepo/PullRequestRepo.m src/dylib/Patches/PullRequestRepo/Subtitle.m src/dylib/Patches/PullRequestRepo/Rows.m \
	src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

build/historical-regressions: tests/historical-regressions.m tests/watchdog.h tests/runloop.h src/dylib/Patches/Peek/Toolbar.m src/dylib/Patches/Peek/ToolbarRules.m src/dylib/Patches/LittleDia/Over.m src/dylib/Patches/LittleDia/Stack.m $(HISTORICAL_REGRESSIONS) $(wildcard src/dylib/StdPatch/*.h src/dylib/Patches/Peek/Peek.h src/dylib/Patches/LittleDia/LittleDia.h src/dylib/Patches/HideToolbar/HideToolbar.h src/dylib/Patches/CompactTabRows/CompactTabRows.h src/dylib/Patches/PullRequestRepo/PullRequestRepo.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/historical-regressions.m $(HISTORICAL_REGRESSIONS)

# DiaPatches' constructor skips helper processes, so the suite runs as one and loads the patch table itself.
build/settings-cleanup: tests/settings-cleanup.m build/DiaPatches.dylib $(wildcard src/dylib/StdPatch/*.h src/dylib/Settings/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/settings-cleanup.m build/DiaPatches.dylib -Wl,-rpath,@loader_path/..

check-settings-cleanup: build/settings-cleanup
	build/settings-cleanup --type=settings-cleanup

check: check-settings-cleanup
.PHONY: check-settings-cleanup

build/abi-kvc-kvo-swift.o: src/dylib/Commands/GroupTabs/Selection.swift tests/abi-kvc-kvo-swift.swift | build
	swiftc $(SWIFTFLAGS) -emit-object -o $@ $^

ABI_KVC_KVO := src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m src/dylib/Patches/CommandBar/Tabs.m \
	src/dylib/Patches/LittleDia/Profile.m src/dylib/Patches/SkipAccount/Code.m \
	src/dylib/Patches/Peek/Address.m src/dylib/Patches/Peek/CopyURL.m src/dylib/Patches/Peek/Toolbar.m \
	src/dylib/Patches/Peek/ToolbarRules.m src/dylib/Patches/Peek/ChatContext.m src/dylib/Patches/Peek/Peek.m \
	src/dylib/Settings/Preview.m

build/abi-kvc-kvo: tests/abi-kvc-kvo.m tests/watchdog.h tests/runloop.h build/abi-kvc-kvo-swift.o $(ABI_KVC_KVO) src/dylib/Patches/ExtensionsShortcut/ExtensionsShortcut.m src/dylib/Patches/HideHistorySuggestions/HideHistorySuggestions.m $(wildcard src/dylib/StdPatch/*.h src/dylib/Patches/Peek/*.h src/dylib/Patches/LittleDia/*.h src/dylib/Patches/CommandBar/*.h src/dylib/Patches/SkipAccount/*.h src/dylib/Settings/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -framework AVFoundation -framework VideoToolbox -framework CoreMedia -framework CoreVideo \
		-L$(SWIFT_LIB) -Wl,-rpath,/usr/lib/swift -o $@ tests/abi-kvc-kvo.m $(ABI_KVC_KVO) build/abi-kvc-kvo-swift.o

VIEW_REUSE_LAYOUT := $(wildcard src/dylib/Patches/EdgeToEdge/*.m) src/dylib/Patches/WindowCorners/WindowCorners.m \
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
	$(wildcard src/dylib/Patches/HideVerticalTabGlow/*.m) \
	src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m

build/view-reuse-layout: tests/view-reuse-layout.m tests/watchdog.h $(VIEW_REUSE_LAYOUT) $(wildcard src/dylib/StdPatch/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -framework Metal -o $@ tests/view-reuse-layout.m $(VIEW_REUSE_LAYOUT)

COMBINATORIAL := src/dylib/StdPatch/Hook.m src/dylib/StdPatch/Views.m src/dylib/StdPatch/App.m \
	src/dylib/StdPatch/Hide.m src/dylib/StdPatch/HideHosts.m src/dylib/StdPatch/Patch.m \
	src/dylib/StdPatch/Shortcut.m src/dylib/StdPatch/Extensions.m src/dylib/StdPatch/Zoom.m \
	src/dylib/Settings/Controls.m src/dylib/Settings/Items.m src/dylib/Settings/Overview.m \
	src/dylib/Settings/Folder.m src/dylib/Settings/Home.m src/dylib/Settings/Page.m \
	src/dylib/Commands/GroupTabs/Messages.m src/dylib/Commands/GroupTabs/Tracking.m src/dylib/Commands/GroupTabs/Menu.m \
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
	src/dylib/Patches/CommandBar/HideTabLayout.m src/dylib/Patches/CommandBar/Tabs.m \
	src/dylib/Patches/LittleDia/LinkMenu.m src/dylib/Patches/LittleDia/Options.m src/dylib/Patches/LittleDia/Launcher.m \
	src/dylib/Patches/PinnedCmdClick/PinnedCmdClick.m \
	src/dylib/Patches/Peek/Peek.m src/dylib/Patches/Peek/Card.m src/dylib/Patches/Peek/Pages.m \
	src/dylib/Patches/Peek/Keys.m src/dylib/Patches/Peek/Chat.m src/dylib/Patches/Peek/ChatContext.m \
	src/dylib/Patches/Peek/Visibility.m src/dylib/Patches/Peek/Motion.m src/dylib/Patches/Peek/Selection.m \
	src/dylib/Patches/Peek/Handoff.m \
	src/dylib/Patches/Peek/Tab.m src/dylib/Patches/Peek/Zoom.m \
	$(LAUNCH_FLAGS) src/dylib/Patches/SplitClientHello/SplitClientHello.m \
	src/dylib/Patches/SplitClientHello/Split.m src/dylib/Patches/SplitClientHello/Write.m src/dylib/Patches/SplitClientHello/Send.m

build/combinatorial-stability: tests/combinatorial-stability.m tests/watchdog.h tests/runloop.h $(COMBINATORIAL) src/dylib/SafeMode/SafeMode.m $(LOCAL_CORE) $(wildcard src/dylib/StdPatch/*.h src/dylib/Local/*.h) | build
	clang $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/combinatorial-stability.m $(COMBINATORIAL) $(LOCAL_CORE)

build/local-tweaks: tests/local-tweaks.m build/DiaPatches.dylib $(wildcard src/dylib/Local/*.h) | build
	clang $(CFLAGS) -Isrc/dylib -framework AppKit -framework QuartzCore -o $@ tests/local-tweaks.m build/DiaPatches.dylib -Wl,-rpath,@loader_path/..

check-local-tweaks: build/local-tweaks
	build/local-tweaks --type=local-tweaks

check: check-local-tweaks
.PHONY: check-local-tweaks

check: build/diapatch build/diapatch-tests build/group-tabs build/mouse-back-forward build/vertical-tab-glow build/split-client-hello build/peek-cursor build/peek-link build/peek-tabs build/peek-chat build/safe-mode build/pause build/hook-table build/updates-runtime build/settings-preview build/runtime-guards build/tidy-tabs build/drag-offset build/small-tab-shape build/toolbar-permission build/launch-flags build/little-dia-stack build/little-dia-profile build/little-dia-over build/little-dia-focus build/tracking build/hide-toolbar-settle build/command-bar-swap build/command-bar-spare build/tab-titles build/show-address-field build/destination-toggle-engine-name build/hide-chat-button build/hide-connect-app-prompt build/hide-ntp-prompts build/open-sidebar-instantly build/ai-history-search build/native-messaging build/diapatch-passkeys build/passkeys-origin build/app-icon-signing build/little-dia-route build/chat-card build/peek-lifecycle build/hide-toolbar-off build/hide-toolbar-focus-bookmarks build/little-dia-launcher build/pinned-cmd-click build/command-bar-lifecycle build/window-patches build/pinned-tab-close-button build/pinned-split-close build/sidebar-tab-bugs build/unload-tab build/profile-color-picker build/historical-regressions build/abi-kvc-kvo build/view-reuse-layout build/combinatorial-stability build/local-tweaks build/patches.json
	tests/tweaks-update
	build/diapatch-tests
	build/group-tabs
	build/tidy-tabs
	build/mouse-back-forward
	build/vertical-tab-glow
	build/split-client-hello
	build/peek-cursor
	build/peek-link
	build/peek-lifecycle
	build/peek-tabs
	build/peek-chat
	build/safe-mode
	build/pause
	build/hook-table
	build/updates-runtime
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
	build/little-dia-focus
	build/chat-card
	build/hide-toolbar-settle
	build/command-bar-swap
	build/command-bar-spare
	build/command-bar-lifecycle
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
	build/profile-color-picker
	build/historical-regressions
	build/abi-kvc-kvo
	build/view-reuse-layout
	build/combinatorial-stability
	build/local-tweaks --type=local-tweaks
	tests/sidebar-grain
	scripts/check-patches

test: build/DiaPatches.dylib
	./test.sh

patch:
	@scripts/new-patch "$(NAME)"

clean:
	rm -rf build

.PHONY: all check clean test patch
