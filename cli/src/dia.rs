use std::{
    cmp::Ordering,
    fs::{self, File},
    io::Read,
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
    process::Command,
    thread,
    time::{Duration, Instant},
};

use anyhow::{bail, Context, Result};
use serde::Deserialize;

use crate::{
    child::{self, Finished, OnInterrupt},
    env::{Env, DEFAULT_APP},
    signals::{self, Cancelled},
    ui::Spinner,
};

pub struct Diapatch {
    path: PathBuf,
    app: Option<PathBuf>,
}

#[derive(Deserialize)]
pub struct Status {
    pub official: Option<String>,
    pub installed: Option<String>,
    pub patched: bool,
    pub staged: Option<String>,
    pub feed: Option<String>,
    pub channel: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SafeMode {
    Off,
    TweaksOff,
    Disabled,
    Parked,
}

impl Diapatch {
    pub fn find(env: &Env) -> Result<Self> {
        let path = env.diapatch();
        if !path.is_file() {
            bail!(
                "DiaTweaks isn't installed: {} is missing. Run {} first.",
                path.display(),
                env.install_hint()
            );
        }
        let app = (env.app != Path::new(DEFAULT_APP)).then(|| env.app.clone());
        Ok(Self { path, app })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn command(&self) -> Command {
        let mut command = Command::new(&self.path);
        if let Some(app) = &self.app {
            command.env("DIAPATCH_APP", app);
        }
        command
    }

    pub fn run(
        &self,
        args: &[&str],
        on_interrupt: OnInterrupt,
        spinner: &Spinner,
    ) -> Result<Finished> {
        child::run(self.command().args(args), on_interrupt, spinner)
    }

    pub fn status(&self, spinner: &Spinner) -> Result<Status> {
        let done = self.run(&["status", "--json"], OnInterrupt::StopDownloads, spinner)?;
        if signals::interrupted() {
            bail!(Cancelled::nothing_changed());
        }
        let json = done.output.lines().rev().find(|line| line.starts_with('{'));
        match (done.status.success(), json) {
            (true, Some(json)) => serde_json::from_str(json).context(
                "diatweaks and diapatch don't match. Run `diatweaks update` to bring both up to date.",
            ),
            _ => bail!(
                "Couldn't check Dia's status:\n{}\nRun `diatweaks doctor` to see what needs fixing.",
                done.tail(5)
            ),
        }
    }
}

pub fn is_newer(version: &str, than: &str) -> bool {
    let (a, b) = match (parenthesized_build(version), parenthesized_build(than)) {
        (Some(a), Some(b)) => (a, b),
        _ => (strip_build(version), strip_build(than)),
    };
    if a.trim().is_empty() {
        return false;
    }
    if b.trim().is_empty() {
        return true;
    }
    compare_versions(a, b) == Ordering::Greater
}

fn parenthesized_build(version: &str) -> Option<&str> {
    version
        .rsplit_once(" (")
        .and_then(|(_, build)| build.strip_suffix(')'))
        .filter(|build| !build.is_empty())
}

fn strip_build(version: &str) -> &str {
    version
        .rsplit_once(" (")
        .filter(|(_, build)| build.ends_with(')'))
        .map_or(version, |(short, _)| short)
}

fn compare_versions(a: &str, b: &str) -> Ordering {
    let (a_core, a_pre) = split_version(a);
    let (b_core, b_pre) = split_version(b);
    let core = compare_core(a_core, b_core);
    if core != Ordering::Equal {
        return core;
    }
    match (a_pre, b_pre) {
        (None, None) => Ordering::Equal,
        (None, Some(_)) => Ordering::Greater,
        (Some(_), None) => Ordering::Less,
        (Some(a), Some(b)) => compare_prerelease(a, b),
    }
}

fn split_version(version: &str) -> (&str, Option<&str>) {
    let trimmed = version.trim();
    let no_v = trimmed
        .strip_prefix(['v', 'V'])
        .filter(|rest| rest.as_bytes().first().is_some_and(u8::is_ascii_digit))
        .unwrap_or(trimmed);
    let no_meta = no_v.split_once('+').map_or(no_v, |(base, _)| base);
    match no_meta.split_once('-') {
        Some((core, pre)) if !pre.is_empty() => (core, Some(pre)),
        _ => (no_meta, None),
    }
}

fn compare_core(a: &str, b: &str) -> Ordering {
    let a_parts: Vec<&str> = a.split('.').collect();
    let b_parts: Vec<&str> = b.split('.').collect();
    let len = a_parts.len().max(b_parts.len());
    for i in 0..len {
        let pa = a_parts.get(i).copied().unwrap_or("0");
        let pb = b_parts.get(i).copied().unwrap_or("0");
        let cmp = match (pa.parse::<u128>(), pb.parse::<u128>()) {
            (Ok(na), Ok(nb)) => na.cmp(&nb),
            _ => pa.cmp(pb),
        };
        if cmp != Ordering::Equal {
            return cmp;
        }
    }
    Ordering::Equal
}

fn compare_prerelease(a: &str, b: &str) -> Ordering {
    let mut a_parts = a.split('.');
    let mut b_parts = b.split('.');
    loop {
        match (a_parts.next(), b_parts.next()) {
            (None, None) => return Ordering::Equal,
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (Some(pa), Some(pb)) => {
                let cmp = match (pa.parse::<u128>(), pb.parse::<u128>()) {
                    (Ok(na), Ok(nb)) => na.cmp(&nb),
                    (Ok(_), Err(_)) => Ordering::Less,
                    (Err(_), Ok(_)) => Ordering::Greater,
                    (Err(_), Err(_)) => pa.cmp(pb),
                };
                if cmp != Ordering::Equal {
                    return cmp;
                }
            }
        }
    }
}

fn dictionary(path: PathBuf) -> Option<plist::Dictionary> {
    plist::Value::from_file(path).ok()?.into_dictionary()
}

pub fn version_of(app: &Path) -> Option<String> {
    let info = dictionary(app.join("Contents/Info.plist"))?;
    let short = info.get("CFBundleShortVersionString")?.as_string()?;
    let build = info.get("CFBundleVersion")?.as_string()?;
    Some(format!("{short} ({build})"))
}

pub fn is_arm64(app: &Path) -> Option<bool> {
    const ARM64: u32 = 0x0100_000c;
    let info = dictionary(app.join("Contents/Info.plist"))?;
    let executable = info.get("CFBundleExecutable")?.as_string()?;
    let mut header = [0u8; 4096];
    let length = File::open(app.join("Contents/MacOS").join(executable))
        .ok()?
        .read(&mut header)
        .ok()?;
    let word = |at: usize| {
        let bytes: [u8; 4] = header[..length].get(at..at + 4)?.try_into().ok()?;
        Some(u32::from_be_bytes(bytes))
    };
    let stride = match word(0)? {
        0xcafe_babe => 20,
        0xcafe_babf => 32,
        0xcffa_edfe => return Some(word(4)?.swap_bytes() == ARM64),
        _ => return Some(false),
    };
    let count = word(4)? as usize;
    Some((0..count).any(|index| word(8 + index * stride) == Some(ARM64)))
}

pub fn is_patched(app: &Path) -> bool {
    dictionary(app.join("Contents/Info.plist"))
        .and_then(|info| info.get("DiaPatches")?.as_boolean())
        .unwrap_or(false)
}

pub fn tweaks_active(env: &Env) -> bool {
    is_patched(&env.app) && safe_mode(&env.support) == SafeMode::Off
}

pub fn is_live(env: &Env) -> bool {
    tweaks_active(env) && is_running(&env.app)
}

pub fn safe_mode(support: &Path) -> SafeMode {
    let Some(state) = dictionary(support.join("safe-mode.plist")) else {
        return SafeMode::Off;
    };
    let level = state
        .get("level")
        .and_then(plist::Value::as_signed_integer)
        .unwrap_or(0);
    match level {
        ..=0 => SafeMode::Off,
        1 => SafeMode::TweaksOff,
        _ if state.get("steppedDown").and_then(plist::Value::as_boolean) == Some(true) => {
            SafeMode::Parked
        }
        _ => SafeMode::Disabled,
    }
}

pub fn is_paused(support: &Path) -> bool {
    support.join("paused").is_file()
}

pub fn staged_ready(support: &Path) -> bool {
    let Ok(ready) = fs::read_to_string(support.join("staged/ready")) else {
        return false;
    };
    let Ok(meta) = fs::symlink_metadata(support.join("staged/Dia.app")) else {
        return false;
    };
    ready.trim() == meta.ino().to_string()
}

pub fn has_linked_icon_catalog(app: &Path) -> bool {
    let is_symlink = fs::symlink_metadata(app.join("Contents/Resources/Assets.car"))
        .is_ok_and(|meta| meta.file_type().is_symlink());
    is_symlink
        && dictionary(app.join("Contents/Info.plist")).is_some_and(|info| {
            info.get("CFBundleIconName")
                .and_then(plist::Value::as_string)
                == Some("DiaChosenIcon")
        })
}

pub fn has_brief_language(app: &Path) -> bool {
    fs::read_to_string(app.join(
        "Contents/Resources/agent-server-resources/dist/prompts/skills/morning-brief/SKILL.md",
    ))
    .is_ok_and(|text| text.contains("## Output language: "))
}

pub fn sync_icon(env: &Env) {
    if !has_linked_icon_catalog(&env.app) {
        return;
    }
    if let Ok(diapatch) = Diapatch::find(env) {
        child::quick(diapatch.command().arg("set-icon"));
    }
}

fn has_running_process(root: &Path) -> bool {
    child::all_pids()
        .into_iter()
        .filter_map(child::pid_path)
        .any(|path| path.starts_with(root))
}

pub fn is_running(app: &Path) -> bool {
    app.canonicalize()
        .is_ok_and(|root| has_running_process(&root))
}

// Terminate by PID like ⌘Q: SIGTERM triggers safe mode and another Dia may be open.
pub fn quit(app: &Path) -> Result<()> {
    let root = app.canonicalize()?;
    let macos = root.join("Contents/MacOS");
    let pids: Vec<String> = child::all_pids()
        .into_iter()
        .filter(|&pid| child::pid_path(pid).is_some_and(|path| path.parent() == Some(&macos)))
        .map(|pid| pid.to_string())
        .collect();
    let sent_terminate = !pids.is_empty();
    if sent_terminate {
        child::quick(Command::new("/usr/bin/osascript").args([
            "-l",
            "JavaScript",
            "-e",
            &terminate_script(&pids),
        ]));
    }
    let timeout = if sent_terminate { 60 } else { 5 };
    let deadline = Instant::now() + Duration::from_secs(timeout);
    while has_running_process(&root) {
        if signals::interrupted() {
            bail!(Cancelled("Stopped while waiting for Dia to quit.".into()));
        }
        if Instant::now() > deadline {
            if sent_terminate {
                bail!(
                    "Dia didn't quit. If it's showing a dialog, answer it, quit Dia, then try again."
                );
            }
            bail!(
                "A Dia background process is still running. Wait a moment or quit it, then try again."
            );
        }
        thread::sleep(Duration::from_millis(250));
    }
    Ok(())
}

fn terminate_script(pids: &[String]) -> String {
    format!(
        "ObjC.import('AppKit'); [{}].forEach(pid => {{ const app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(pid); if (!app.isNil()) app.terminate; }})",
        pids.join(",")
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_script_quits_every_dia_process() {
        let script = terminate_script(&["1".into(), "999999".into()]);
        assert!(script.contains("[1,999999].forEach"));
        let ran = Command::new("/usr/bin/osascript")
            .args(["-l", "JavaScript", "-e"])
            .arg(script.replace("app.terminate", "app.processIdentifier"))
            .output()
            .unwrap();
        assert!(
            ran.status.success(),
            "{}",
            String::from_utf8_lossy(&ran.stderr)
        );
    }

    #[test]
    fn compares_versions_and_builds() {
        assert!(is_newer("1.58.1", "1.58.0"));
        assert!(!is_newer("1.58.0", "1.58.1"));
        assert!(is_newer("1.1.10", "1.1.9"));
        assert!(!is_newer("1.1.9", "1.1.10"));
        assert!(is_newer("v1.1.10", "v1.1.9"));
        assert!(!is_newer("1.58.0", "1.58"));
        assert!(!is_newer("1.58", "1.58.0"));
        assert!(is_newer("1.58.1", "1.58.1-beta.1"));
        assert!(!is_newer("1.58.1-beta.1", "1.58.1"));
        assert!(is_newer("1.58.1-rc.1", "1.58.1-beta.10"));
        assert!(is_newer("1.58.1-beta.10", "1.58.1-beta.2"));
        assert!(!is_newer("1.58.1+build.2", "1.58.1+build.1"));
        assert!(is_newer("1.59.0 (91402)", "1.58.0 (91177)"));
        assert!(!is_newer("1.58.0 (91177)", "1.58.0 (91177)"));
        assert!(is_newer("1.58.1 (91200)", "1.58.0"));
        assert!(!is_newer("", "1.0.0"));
        assert!(is_newer("1.0.0", ""));
    }

    #[test]
    fn staged_ready_checks_inode() {
        let dir = tempfile::tempdir().unwrap();
        let staged = dir.path().join("staged/Dia.app");
        fs::create_dir_all(&staged).unwrap();
        assert!(!staged_ready(dir.path()));

        let ino = fs::symlink_metadata(&staged).unwrap().ino();
        fs::write(dir.path().join("staged/ready"), format!("{ino}\n")).unwrap();
        assert!(staged_ready(dir.path()));

        let swapped = dir.path().join("staged/other.app");
        fs::create_dir_all(&swapped).unwrap();
        fs::remove_dir(&staged).unwrap();
        fs::rename(&swapped, &staged).unwrap();
        assert!(!staged_ready(dir.path()));
    }

    #[test]
    fn linked_icon_catalog_requires_symlink_and_alias_name() {
        use std::os::unix::fs::symlink;

        let dir = tempfile::tempdir().unwrap();
        let app = dir.path().join("Dia.app");
        let resources = app.join("Contents/Resources");
        fs::create_dir_all(&resources).unwrap();
        let info = app.join("Contents/Info.plist");
        let car = resources.join("Assets.car");
        let target = dir.path().join("current.car");
        fs::write(&target, b"car").unwrap();

        let write_icon = |name: &str| {
            fs::write(
                &info,
                format!(
                    "<plist version=\"1.0\"><dict><key>CFBundleIconName</key><string>{name}</string></dict></plist>"
                ),
            )
            .unwrap();
        };

        fs::write(&car, b"car").unwrap();
        write_icon("AppIcon");
        assert!(!has_linked_icon_catalog(&app));
        write_icon("DiaChosenIcon");
        assert!(!has_linked_icon_catalog(&app));

        fs::remove_file(&car).unwrap();
        symlink(&target, &car).unwrap();
        assert!(has_linked_icon_catalog(&app));
        write_icon("AppIcon");
        assert!(!has_linked_icon_catalog(&app));
    }

    #[test]
    fn arm64_reads_thin_and_universal_headers() {
        let dir = tempfile::tempdir().unwrap();
        let app = dir.path().join("Dia.app");
        fs::create_dir_all(app.join("Contents/MacOS")).unwrap();
        fs::write(
            app.join("Contents/Info.plist"),
            "<plist version=\"1.0\"><dict><key>CFBundleExecutable</key><string>Dia</string></dict></plist>",
        )
        .unwrap();
        let binary = app.join("Contents/MacOS/Dia");
        let fat = |arches: &[u32]| {
            let mut bytes = 0xcafe_babe_u32.to_be_bytes().to_vec();
            bytes.extend((arches.len() as u32).to_be_bytes());
            for arch in arches {
                bytes.extend(arch.to_be_bytes());
                bytes.extend([0; 16]);
            }
            bytes
        };
        let thin = |arch: u32| [0xfeed_facf_u32.to_le_bytes(), arch.to_le_bytes()].concat();

        assert_eq!(is_arm64(&app), None);
        for (bytes, arm64) in [
            (thin(0x0100_000c), true),
            (thin(0x0100_0007), false),
            (fat(&[0x0100_0007, 0x0100_000c]), true),
            (fat(&[0x0100_0007]), false),
            (b"#!/bin/sh".to_vec(), false),
        ] {
            fs::write(&binary, bytes).unwrap();
            assert_eq!(is_arm64(&app), Some(arm64));
        }
    }

    #[test]
    fn brief_language_and_safe_mode_bounds() {
        let dir = tempfile::tempdir().unwrap();
        let app = dir.path().join("Dia.app");
        let skill = app.join(
            "Contents/Resources/agent-server-resources/dist/prompts/skills/morning-brief/SKILL.md",
        );
        fs::create_dir_all(skill.parent().unwrap()).unwrap();
        fs::write(&skill, "base prompt").unwrap();
        assert!(!has_brief_language(&app));
        fs::write(&skill, "base prompt\n\n## Output language: Japanese\n").unwrap();
        assert!(has_brief_language(&app));

        fs::write(
            dir.path().join("safe-mode.plist"),
            "<plist version=\"1.0\"><dict><key>level</key><integer>-1</integer></dict></plist>",
        )
        .unwrap();
        assert_eq!(safe_mode(dir.path()), SafeMode::Off);
    }
}
