#!/bin/sh
set -eu
cd "$(dirname "$0")"
repo=$(pwd)

usage() {
    cat <<'EOF'
Usage: ./install.sh [-y|--yes] [-h|--help]

Builds DiaTweaks from this folder, installs it and patches Dia.

  -y, --yes   Don't ask before installing or updating Rust
  -h, --help  Show this help
EOF
}

die() {
    printf '%s\n' "$@" >&2
    exit 1
}

yes=
for arg in "$@"; do
    case $arg in
        -y|--yes) yes=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

if [ "$(id -u)" -eq 0 ] && [ "${DIATWEAKS_ALLOW_ROOT:-}" != 1 ]; then
    die "Don't run install.sh with sudo — it installs into your own home folder. Run ./install.sh as yourself."
fi

support="${DIAPATCH_HOME:-$HOME/Library/Application Support/DiaPatches}"
support=${support%/}
incoming="$support/.incoming"

stopped() {
    printf '\nStopped. Nothing changed — run %s/install.sh whenever you want to continue.\n' "$repo" >&2
    exit 130
}
trap 'rm -rf "$incoming"' EXIT
trap stopped INT TERM HUP

macos=$(sw_vers -productVersion 2>/dev/null) || macos=
case ${macos%%.*} in
    ''|*[!0-9]*) ;;
    *) [ "${macos%%.*}" -ge 14 ] || die "DiaTweaks needs macOS 14 or later (this Mac is on macOS $macos)." ;;
esac

[ -n "${DEVELOPER_DIR:-}" ] || xcode-select -p >/dev/null 2>&1 \
    || die "DiaTweaks needs Apple's Command Line Tools. Run: xcode-select --install — then run ./install.sh again."

locked=
for path in "$support" "$support/bin" "$support/pristine" "$support/staged" "$support/diapatch.log" "$incoming" \
    "$repo/build" "${CARGO_TARGET_DIR:-$repo/cli/target}"; do
    [ ! -e "$path" ] || [ -w "$path" ] || locked="$locked \"$path\""
done
[ -z "$locked" ] || die \
    "Some DiaTweaks folders belong to another user, usually from an earlier \`sudo ./install.sh\`, so this install can't update them." \
    "Make them yours again, then run ./install.sh again:" \
    "  sudo chown -R \"$(id -un)\"$locked"

if [ -z "${DIAPATCH_APP:-}" ] && [ ! -d /Applications/Dia.app ]; then
    found="$HOME/Applications/Dia.app"
    [ -d "$found" ] || found=$(mdfind 'kMDItemCFBundleIdentifier == "company.thebrowser.dia"' 2>/dev/null \
        | grep -vF -e "$support/" -e /.Trash/ | head -n 1) || found=
    case $found in
        /Volumes/*) die "Dia is running from a disk image ($found). Drag Dia.app to /Applications first, then run ./install.sh again." ;;
        ?*) export DIAPATCH_APP="$found" ;;
    esac
fi
dia_app=${DIAPATCH_APP:-/Applications/Dia.app}
if [ "${DIAPATCH_SKIP_APP_CHECK:-}" != 1 ]; then
    [ -d "$dia_app" ] || die "Dia isn't installed yet. Download it from https://www.diabrowser.com, move Dia.app to /Applications, and run ./install.sh again."
    archs=$(lipo -archs "$dia_app/Contents/MacOS/Dia" 2>/dev/null) || archs=
    case " $archs " in
        *" arm64 "*|"  ") ;;
        *) die "DiaTweaks requires Apple Silicon (arm64 Dia.app)." ;;
    esac
fi

echo "Building DiaTweaks..."
make -s -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

rust_min=88

have_rust() { command -v cargo >/dev/null && command -v rustc >/dev/null; }

rust_ok() {
    why=
    have_rust || return 1
    ver=$(rustc --version 2>/dev/null | cut -d' ' -f2)
    major=${ver%%.*}
    minor=${ver#*.}
    minor=${minor%%.*}
    case $major$minor in ''|*[!0-9]*) why="Rust isn't working"; return 1 ;; esac
    why="Rust $ver is too old"
    [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge "$rust_min" ]; }
}

confirm() {
    printf '%s [y/N] ' "$1"
    read -r answer || answer=
    case $answer in [yY]*) ;; *) return 1 ;; esac
}

install_rustup() { curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal; }

cli=
if [ -f cli/Cargo.toml ]; then
    # First, so a fresh rustup cargo beats an older Homebrew or system one.
    PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
    if ! rust_ok && [ -z "$yes" ] && [ -t 0 ]; then
        old="$why for the diatweaks command (needs 1.$rust_min+)."
        if ! have_rust; then
            if confirm 'The diatweaks command needs Rust. Install it with rustup?'; then install_rustup || true; fi
        elif command -v rustup >/dev/null; then
            if confirm "$old Update it with rustup?" && rustup update stable; then
                # An older pinned default toolchain keeps winning over the stable that was just updated.
                rust_ok || export RUSTUP_TOOLCHAIN=stable
            fi
        elif command -v brew >/dev/null && brew list --versions rust >/dev/null 2>&1; then
            if confirm "$old Update it with Homebrew?"; then brew upgrade rust || true; fi
        else
            if confirm "$old Install current Rust with rustup?"; then install_rustup || true; fi
        fi
    fi
    hash -r 2>/dev/null || true
    if ! have_rust; then
        echo "Skipping the diatweaks command: it needs Rust (https://rustup.rs)."
    elif ! rust_ok; then
        echo "Skipping the diatweaks command: $why (needs 1.$rust_min+; run 'rustup update stable' or 'brew upgrade rust')."
    elif cargo build --release --manifest-path cli/Cargo.toml; then
        cli="${CARGO_TARGET_DIR:-cli/target}/release/diatweaks"
    else
        echo "Skipping the diatweaks command: it didn't build."
    fi
fi

rm -rf "$incoming"
mkdir -p "$incoming" "$support/bin"
cp build/diapatch build/DiaPatches.dylib build/patches.json ${cli:+"$cli"} "$incoming/"
cp -R assets/app-icons "$incoming/"
# Ctrl-C waits for the renames, so the installed files always come from one build.
trap 'interrupted=1' INT TERM HUP
(
    trap '' INT TERM HUP
    mv -f "$incoming/diapatch" ${cli:+"$incoming/diatweaks"} "$support/bin/"
    mv -f "$incoming/DiaPatches.dylib" "$incoming/patches.json" "$support/"
    rm -rf "$support/app-icons"
    rm -f "$support/release.plist"  # this is a source build now, not a release
    mv -f "$incoming/app-icons" "$support/"
    printf '%s\n' "$repo" > "$support/source-dir"
)
[ -z "${interrupted-}" ] || stopped
trap stopped INT TERM HUP

if [ -n "$cli" ]; then
    if [ -n "${DIATWEAKS_LINK_DIR-}" ]; then dir=$DIATWEAKS_LINK_DIR
    elif [ -w /opt/homebrew/bin ]; then dir=/opt/homebrew/bin
    elif [ -w /usr/local/bin ]; then dir=/usr/local/bin
    else dir="$HOME/.local/bin"
    fi
    link="$dir/diatweaks"
    case $(readlink "$link" 2>/dev/null || true) in
        "$support"/*) ;;
        *) if [ -L "$link" ] || [ -e "$link" ]; then echo "Left $link alone: it isn't DiaTweaks'."; link=; fi ;;
    esac
    if [ -n "$link" ]; then
        mkdir -p "$dir"
        ln -sfh "$support/bin/diatweaks" "$link"
        case ":$PATH:" in *":$dir:"*) ;; *) echo "Add $dir to your PATH to run diatweaks." ;; esac
    fi
fi

# diapatch inherits the ignored signals, so a Ctrl-C can't stop it halfway through swapping Dia.app.
trap '' INT TERM HUP
"$support/bin/diapatch" install --relaunch
