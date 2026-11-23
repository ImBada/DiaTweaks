use std::{
    fs, io,
    path::{Path, PathBuf},
    process::Command,
};

use anyhow::{bail, Context, Result};
use serde::Deserialize;

use crate::{
    dia::Diapatch,
    env::Env,
    manifest::Patch,
    ui::{self, Ui},
};

/// `local-state.json`, written by the dylib and by `diapatch local build`.
#[derive(Deserialize, Default)]
pub struct LocalState {
    #[serde(default)]
    items: Vec<LocalItem>,
}

#[derive(Deserialize, Clone)]
pub struct LocalItem {
    pub id: String,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub error: Option<String>,
    #[serde(default)]
    pub patches: Vec<Patch>,
}

impl LocalState {
    pub fn load(path: &Path) -> Result<Self> {
        let data = match fs::read(path) {
            Ok(data) => data,
            Err(err) if err.kind() == io::ErrorKind::NotFound => return Ok(Self::default()),
            Err(err) => {
                return Err(err).with_context(|| format!("Couldn't read {}", path.display()));
            }
        };
        // A damaged state file must not break `diatweaks list`: the tweaks still load, they just aren't listed.
        Ok(serde_json::from_slice(&data).unwrap_or_default())
    }

    pub fn items(&self) -> &[LocalItem] {
        &self.items
    }

    pub fn patches(&self) -> Vec<Patch> {
        self.items
            .iter()
            .flat_map(|item| item.patches.iter().cloned())
            .collect()
    }
}

fn status_text(status: &str) -> &'static str {
    match status {
        "loaded" => "loaded",
        "ready" => "ready — relaunch Dia",
        "incompatible" => "incompatible",
        _ => "build failed",
    }
}

pub fn list(env: &Env) -> Result<()> {
    let state = LocalState::load(&env.local_state())?;
    if state.items().is_empty() {
        ui::say("There are no local tweaks. Add one with `diatweaks local add <path>`.");
        return Ok(());
    }
    for item in state.items() {
        let keys: Vec<&str> = item
            .patches
            .iter()
            .map(|patch| patch.key.as_str())
            .collect();
        let mut line = format!(
            "{:<12} {:<8} {}",
            item.id,
            item.kind,
            status_text(&item.status)
        );
        if !keys.is_empty() {
            line.push_str(&format!("  ({})", keys.join(", ")));
        }
        ui::say(line);
        if let Some(error) = &item.error {
            ui::say(format!("             {error}"));
        }
    }
    Ok(())
}

pub fn add(env: &Env, ui: &Ui, path: &Path) -> Result<()> {
    if !path.exists() {
        bail!("There's nothing at {}.", path.display());
    }
    let folder = env.local();
    fs::create_dir_all(&folder).with_context(|| format!("Couldn't create {}", folder.display()))?;
    let name = path.file_name().context("That path has no name.")?;
    let mut destination = folder.join(name);
    if destination.exists() {
        let stem = path.file_stem().unwrap_or_default().to_string_lossy();
        let extension = path.extension().map(|value| value.to_string_lossy());
        destination = first_free(&folder, &stem, extension.as_deref());
    }
    copy(path, &destination)?;
    ui.success(format_args!(
        "Added {}.",
        destination
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
    ));
    build(env, ui, &[])
}

pub fn build(env: &Env, ui: &Ui, names: &[String]) -> Result<()> {
    let diapatch = Diapatch::find(env)?;
    match run_local(ui, &diapatch, "build", names)? {
        Some(error) => bail!("{error}"),
        None => Ok(()),
    }
}

fn run_local(
    ui: &Ui,
    diapatch: &Diapatch,
    subcommand: &str,
    names: &[String],
) -> Result<Option<String>> {
    let path = diapatch.path();
    let output = Command::new(path)
        .arg("local")
        .arg(subcommand)
        .args(names)
        .output()
        .with_context(|| format!("Couldn't run {}", path.display()))?;
    let text = output_text(&output.stdout);
    if !text.is_empty() {
        ui.info(text);
    }
    if output.status.success() {
        return Ok(None);
    }
    let error = output_text(&output.stderr);
    Ok(Some(if error.is_empty() {
        "Some local tweaks didn't build.".into()
    } else {
        error
    }))
}

fn output_text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).trim().to_string()
}

pub fn remove(env: &Env, ui: &Ui, name: &str) -> Result<()> {
    let path = find(env, name)?;
    trash(&path)?;
    ui.success(format_args!(
        "Moved {} to the Trash.",
        path.file_name().unwrap_or_default().to_string_lossy()
    ));
    Ok(())
}

pub fn open(env: &Env) -> Result<()> {
    let folder = env.local();
    fs::create_dir_all(&folder).with_context(|| format!("Couldn't create {}", folder.display()))?;
    Command::new("/usr/bin/open")
        .arg(&folder)
        .status()
        .context("Couldn't open Finder.")?;
    Ok(())
}

pub fn export(env: &Env, ui: &Ui, name: &str) -> Result<()> {
    let source = find(env, name)?;
    let desktop = std::env::var_os("HOME")
        .map(PathBuf::from)
        .map(|home| home.join("Desktop"))
        .filter(|path| path.is_dir())
        .unwrap_or_else(|| PathBuf::from("."));
    let destination = desktop.join(format!("{name}.zip"));
    let status = Command::new("/usr/bin/ditto")
        .args(["-c", "-k", "--sequesterRsrc", "--keepParent"])
        .arg(&source)
        .arg(&destination)
        .status()
        .context("Couldn't run ditto.")?;
    if !status.success() {
        bail!("Couldn't zip {}.", source.display());
    }
    ui.success(format_args!("Exported {}.", destination.display()));
    Ok(())
}

pub fn doctor(env: &Env, ui: &Ui) -> Result<()> {
    let mut problems = Vec::new();
    let xcrun = |args: &[&str]| {
        Command::new("/usr/bin/xcrun")
            .args(args)
            .output()
            .is_ok_and(|output| output.status.success())
    };
    if xcrun(&["--find", "clang"]) {
        ui.success("clang is available.");
    } else {
        problems.push(
            "Install Xcode Command Line Tools (xcode-select --install) to compile .m tweaks, or use a prebuilt .dylib."
                .to_string(),
        );
    }
    if xcrun(&["--show-sdk-path"]) {
        ui.success("The macOS SDK is available.");
    } else {
        problems.push("The macOS SDK is missing. Install Xcode Command Line Tools.".to_string());
    }
    let folder = env.local();
    if folder.exists() {
        match fs::metadata(&folder) {
            Ok(meta) if meta.permissions().readonly() => {
                problems.push(format!("{} isn't writable.", folder.display()));
            }
            Ok(_) => ui.success(format_args!("{} is writable.", folder.display())),
            Err(err) => problems.push(format!("Couldn't read {}: {err}", folder.display())),
        }
    } else {
        ui.info(format_args!(
            "{} doesn't exist yet; it's created when you add a tweak.",
            folder.display()
        ));
    }
    // The dylib knows whether it carries headers and how every tweak builds, so ask it rather than guess.
    match Diapatch::find(env).and_then(|diapatch| run_local(ui, &diapatch, "doctor", &[])) {
        Ok(Some(error)) => problems.push(error),
        Ok(None) => {}
        Err(err) => problems.push(format!("{err:#}")),
    }
    if problems.is_empty() {
        ui.done("Local tweaks are ready to build.");
        return Ok(());
    }
    for problem in &problems {
        ui.warn(problem);
    }
    bail!("{} local tweak problem(s) to fix.", problems.len())
}

fn find(env: &Env, name: &str) -> Result<PathBuf> {
    let folder = env.local();
    let wanted = name
        .trim_end_matches(".m")
        .trim_end_matches(".dylib")
        .trim_end_matches(".patch")
        .trim_end_matches(".diff")
        .trim_end_matches(".zip");
    let entries =
        fs::read_dir(&folder).with_context(|| format!("Couldn't read {}", folder.display()))?;
    for entry in entries {
        let entry = entry?;
        let file = entry.file_name().to_string_lossy().into_owned();
        if file == name
            || Path::new(&file)
                .file_stem()
                .is_some_and(|stem| stem == wanted)
        {
            return Ok(entry.path());
        }
    }
    bail!("There's no local tweak called \"{name}\". Run `diatweaks local` to see them.")
}

fn first_free(folder: &Path, stem: &str, extension: Option<&str>) -> PathBuf {
    let named = |suffix: &str| match extension {
        Some(extension) => folder.join(format!("{stem}{suffix}.{extension}")),
        None => folder.join(format!("{stem}{suffix}")),
    };
    let mut path = named("");
    for number in 2..1000 {
        if !path.exists() {
            break;
        }
        path = named(&format!(" {number}"));
    }
    path
}

fn copy(from: &Path, to: &Path) -> Result<()> {
    if from.is_dir() {
        fs::create_dir_all(to)?;
        for entry in fs::read_dir(from)? {
            let entry = entry?;
            copy(&entry.path(), &to.join(entry.file_name()))?;
        }
        Ok(())
    } else {
        fs::copy(from, to)
            .map(|_| ())
            .with_context(|| format!("Couldn't copy {} to {}", from.display(), to.display()))
    }
}

// Never `rm -rf`: a local tweak is the user's own work, so it goes to the Trash where it can come back.
fn trash(path: &Path) -> Result<()> {
    let home = std::env::var_os("HOME").context("HOME isn't set")?;
    let folder = PathBuf::from(home).join(".Trash");
    fs::create_dir_all(&folder)?;
    let name = path
        .file_name()
        .context("That path has no name.")?
        .to_string_lossy();
    let destination = first_free(&folder, &name, None);
    if fs::rename(path, &destination).is_ok() {
        return Ok(());
    }
    copy(path, &destination)?;
    if path.is_dir() {
        fs::remove_dir_all(path)
    } else {
        fs::remove_file(path)
    }
    .with_context(|| format!("Couldn't remove {}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::Manifest;

    fn write(path: &Path, text: &str) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, text).unwrap();
    }

    fn manifest(dir: &Path) -> Manifest {
        let path = dir.join("patches.json");
        write(
            &path,
            r#"{
                "version": 1,
                "patches": [
                    {"key": "hideToolbar", "title": "Hide Toolbar", "detail": "H", "defaultOn": false, "requires": null, "disabledBy": null},
                    {"key": "localTweaks", "title": "Local Tweaks", "detail": "L", "defaultOn": true, "requires": null, "disabledBy": null}
                ]
            }"#,
        );
        Manifest::load(&path).unwrap()
    }

    fn state(dir: &Path, items: &str) {
        write(
            &dir.join("local-state.json"),
            &format!(r#"{{"version": 1, "dylibUUID": "x", "items": {items}}}"#),
        );
    }

    #[test]
    fn merges_local_patches_and_marks_them() {
        let dir = tempfile::tempdir().unwrap();
        let mut manifest = manifest(dir.path());
        state(
            dir.path(),
            r#"[{"id": "MyTweak", "kind": "source", "status": "loaded", "patches": [
                {"key": "myTweak", "title": "My Tweak", "detail": "M", "defaultOn": false,
                 "requires": null, "disabledBy": null, "coveredBy": null, "relaunch": false}
            ]}]"#,
        );
        let local = LocalState::load(&dir.path().join("local-state.json")).unwrap();
        manifest.merge_local(local.patches());
        assert_eq!(manifest.patches.len(), 3);
        assert!(manifest.patches[2].local);
        assert!(!manifest.patches[0].local);
        assert_eq!(manifest.resolve(&["my-tweak".into()]).unwrap(), vec![2]);
    }

    #[test]
    fn drops_dangling_links_and_duplicate_keys() {
        let dir = tempfile::tempdir().unwrap();
        let mut manifest = manifest(dir.path());
        state(
            dir.path(),
            r#"[{"id": "Broken", "kind": "source", "status": "loaded", "patches": [
                {"key": "needsGhost", "title": "Needs Ghost", "detail": "N", "defaultOn": false,
                 "requires": "ghost", "disabledBy": "ghost", "coveredBy": "ghost", "relaunch": false},
                {"key": "hideToolbar", "title": "Impostor", "detail": "I", "defaultOn": false,
                 "requires": null, "disabledBy": null, "coveredBy": null, "relaunch": false}
            ]}]"#,
        );
        let local = LocalState::load(&dir.path().join("local-state.json")).unwrap();
        manifest.merge_local(local.patches());
        assert_eq!(manifest.patches.len(), 3);
        assert_eq!(manifest.title(0), "Hide Toolbar");
        let merged = &manifest.patches[2];
        assert_eq!(merged.key, "needsGhost");
        assert!(
            merged.requires.is_none()
                && merged.disabled_by.is_none()
                && merged.covered_by.is_none()
        );
    }

    #[test]
    fn breaks_a_requirement_cycle() {
        let dir = tempfile::tempdir().unwrap();
        let mut manifest = manifest(dir.path());
        state(
            dir.path(),
            r#"[{"id": "Cycle", "kind": "source", "status": "loaded", "patches": [
                {"key": "cycleA", "title": "Cycle A", "detail": "A", "defaultOn": false,
                 "requires": "cycleB", "disabledBy": null, "coveredBy": null, "relaunch": false},
                {"key": "cycleB", "title": "Cycle B", "detail": "B", "defaultOn": false,
                 "requires": "cycleA", "disabledBy": null, "coveredBy": null, "relaunch": false}
            ]}]"#,
        );
        let local = LocalState::load(&dir.path().join("local-state.json")).unwrap();
        manifest.merge_local(local.patches());
        assert_eq!(manifest.patches.len(), 4);
        for index in 2..4 {
            let mut seen = std::collections::HashSet::new();
            let mut cursor = index;
            while let Some(required) = manifest.requirement(cursor) {
                assert!(seen.insert(cursor), "the chain loops at {cursor}");
                cursor = required;
            }
        }
    }

    #[test]
    fn a_missing_or_damaged_state_file_is_not_an_error() {
        let dir = tempfile::tempdir().unwrap();
        assert!(LocalState::load(&dir.path().join("local-state.json"))
            .unwrap()
            .items()
            .is_empty());
        write(&dir.path().join("local-state.json"), "{ not json");
        assert!(LocalState::load(&dir.path().join("local-state.json"))
            .unwrap()
            .items()
            .is_empty());
    }

    #[test]
    fn load_with_local_reads_both_files() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("patches.json");
        write(
            &path,
            r#"{"version": 1, "patches": [
                {"key": "hideToolbar", "title": "Hide Toolbar", "detail": "H", "defaultOn": false, "requires": null, "disabledBy": null}
            ]}"#,
        );
        state(
            dir.path(),
            r#"[{"id": "MyTweak", "kind": "source", "status": "loaded", "patches": [
                {"key": "myTweak", "title": "My Tweak", "detail": "M", "defaultOn": false,
                 "requires": null, "disabledBy": null, "coveredBy": null, "relaunch": false}
            ]}]"#,
        );
        let manifest =
            Manifest::load_with_local(&path, &dir.path().join("local-state.json")).unwrap();
        assert_eq!(manifest.patches.len(), 2);
        assert!(manifest.patches[1].local);
    }
}
