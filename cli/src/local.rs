use std::{
    fs, io,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

use anyhow::{anyhow, bail, Context, Result};
use serde::Deserialize;
use tempfile::TempDir;

use crate::{
    dia::Diapatch,
    env::{self, Env},
    manifest::{Manifest, Patch},
    signals::{self, Cancelled},
    ui::{self, Ui},
};

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
        match fs::read(path) {
            Ok(data) => Ok(serde_json::from_slice(&data).unwrap_or_default()),
            Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(Self::default()),
            Err(err) => Err(err).with_context(|| format!("Couldn't read {}", path.display())),
        }
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
    if let Some(url) = path.to_str().filter(|text| text.contains("://")) {
        let (_download, file) = download(ui, url)?;
        return add(env, ui, &file);
    }
    if !path.exists() {
        let name = path.to_string_lossy();
        if !name.contains('/') && path.extension().is_none() {
            bail!(
                "There's nothing at {name}. To download an optional DiaTweaks tweak, run `diatweaks local install {name}`."
            );
        }
        bail!("There's nothing at {}.", path.display());
    }
    let folder = env.local();
    env.check_yours(&folder)?;
    fs::create_dir_all(&folder).with_context(|| format!("Couldn't create {}", folder.display()))?;
    let stem = path.file_stem().context("That path has no name.")?;
    let extension = path.extension().map(|value| value.to_string_lossy());
    let destination = first_free(&folder, &stem.to_string_lossy(), extension.as_deref());
    copy(path, &destination)?;
    let added = destination
        .file_name()
        .unwrap_or_default()
        .to_string_lossy();
    ui.success(format_args!("Added {added}."));
    let id = destination
        .file_stem()
        .unwrap_or_default()
        .to_string_lossy();
    build(env, ui, &[id.into_owned()])
}

fn download(ui: &Ui, url: &str) -> Result<(TempDir, PathBuf)> {
    let Some((source, name)) = github_download(url) else {
        bail!("Download that link first (curl -LO {url}), then run: diatweaks local add <file>");
    };
    let dir = tempfile::Builder::new().prefix("diatweaks-").tempdir()?;
    let file = dir.path().join(&name);
    let spinner = ui.spinner(format_args!("Downloading {name}"));
    let output = Command::new("/usr/bin/curl")
        .args(["-fsSL", "--max-time", "60", "-o"])
        .arg(&file)
        .arg(&source)
        .stdin(Stdio::null())
        .output()
        .context("Couldn't run curl.");
    let output = spinner.check(output)?;
    if signals::interrupted() {
        return Err(spinner.fail(Cancelled::nothing_changed().into()));
    }
    if !output.status.success() {
        let why = output_text(&output.stderr);
        let why = why.trim_start_matches("curl: ");
        let why = why
            .split_once(") ")
            .filter(|(code, _)| code.starts_with('('))
            .map_or(why, |(_, message)| message);
        return Err(spinner.fail(anyhow!(
            "Couldn't download {source}: {why}. Check the link and your internet connection."
        )));
    }
    spinner.stop(format_args!("Downloaded {name}"));
    Ok((dir, file))
}

fn github_download(url: &str) -> Option<(String, String)> {
    let rest = url.strip_prefix("https://")?;
    let (host, path) = rest.split_once('/')?;
    let path = path.split(['?', '#']).next()?.trim_end_matches('/');
    let parts: Vec<&str> = path.split('/').collect();
    match (host, parts.as_slice()) {
        ("github.com" | "www.github.com", [owner, repo, "pull", number, ..]) => {
            let number = number.trim_end_matches(".patch").trim_end_matches(".diff");
            (!number.is_empty() && number.bytes().all(|byte| byte.is_ascii_digit())).then(|| {
                (
                    format!("https://github.com/{owner}/{repo}/pull/{number}.patch"),
                    format!("pr-{number}.patch"),
                )
            })
        }
        ("github.com" | "www.github.com", [owner, repo, "blob" | "raw", rest @ ..])
            if rest.len() >= 2 =>
        {
            Some((
                format!("https://github.com/{owner}/{repo}/raw/{}", rest.join("/")),
                (*rest.last()?).to_owned(),
            ))
        }
        ("raw.githubusercontent.com", [_, _, _, .., name]) => {
            Some((url.to_owned(), (*name).to_owned()))
        }
        _ => None,
    }
}

pub fn build(env: &Env, ui: &Ui, names: &[String]) -> Result<()> {
    delegate(env, ui, "build", names)
}

pub fn available(env: &Env, ui: &Ui) -> Result<()> {
    delegate(env, ui, "available", &[])
}

pub fn install(env: &Env, ui: &Ui, names: &[String]) -> Result<()> {
    delegate(env, ui, "install", names)
}

pub fn install_unless_built_in(env: &Env, ui: &Ui, names: &[String]) -> Result<()> {
    let built_in = Manifest::load(env).ok();
    let mut optional = Vec::new();
    for name in names {
        let found = built_in
            .as_ref()
            .and_then(|manifest| Some(&manifest.patches[manifest.find(name)?]));
        match found {
            Some(patch) => ui.info(format_args!(
                "{} is already built into DiaTweaks — turn it on with: diatweaks on {}",
                patch.title, patch.key
            )),
            None => optional.push(name.clone()),
        }
    }
    if optional.is_empty() {
        return Ok(());
    }
    install(env, ui, &optional)
}

fn delegate(env: &Env, ui: &Ui, subcommand: &str, names: &[String]) -> Result<()> {
    let Some(error) = run_local(ui, &Diapatch::find(env)?, subcommand, names)? else {
        return Ok(());
    };
    const TOOLCHAIN: [&str; 4] = ["clang", "xcrun", "SDK", "headers"];
    if TOOLCHAIN.iter().any(|sign| error.contains(sign)) {
        bail!("{error}\nRun `diatweaks local doctor` to check your Command Line Tools.");
    }
    bail!("{error}")
}

fn run_local(
    ui: &Ui,
    diapatch: &Diapatch,
    subcommand: &str,
    names: &[String],
) -> Result<Option<String>> {
    let path = diapatch.path();
    let output = diapatch
        .command()
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
    trash(&env.home, &path)?;
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

const NO_DESKTOP: &str = "Couldn't write to ~/Desktop (Terminal may not have Desktop access in System Settings > Privacy & Security > Files and Folders).";

pub fn export(env: &Env, ui: &Ui, name: &str) -> Result<()> {
    let source = find(env, name)?;
    let zip = format!(
        "{}.zip",
        source.file_stem().unwrap_or_default().to_string_lossy()
    );
    let desktop = env.home.join("Desktop");
    let saved = match zip_to(&source, &desktop.join(&zip))? {
        None => desktop.join(&zip),
        Some(_) => {
            let here = std::env::current_dir().context(NO_DESKTOP)?;
            if let Some(why) = zip_to(&source, &here.join(&zip))? {
                bail!(
                    "{NO_DESKTOP}\nIt couldn't go in {} either: {why}",
                    here.display()
                );
            }
            ui.warn(NO_DESKTOP);
            here.join(&zip)
        }
    };
    ui.success(format_args!("Exported {}.", saved.display()));
    Ok(())
}

fn zip_to(source: &Path, destination: &Path) -> Result<Option<String>> {
    let output = Command::new("/usr/bin/ditto")
        .args(["-c", "-k", "--sequesterRsrc", "--keepParent"])
        .arg(source)
        .arg(destination)
        .stdin(Stdio::null())
        .output()
        .context("Couldn't run ditto.")?;
    Ok((!output.status.success()).then(|| {
        let why = output_text(&output.stderr);
        if why.is_empty() {
            format!("ditto stopped with {}", output.status)
        } else {
            why
        }
    }))
}

pub fn doctor(env: &Env, ui: &Ui) -> Result<()> {
    let problems = problems(env, ui);
    if problems.is_empty() {
        ui.done("Local tweaks are ready to build.");
        return Ok(());
    }
    for problem in &problems {
        ui.warn(problem);
    }
    bail!("{} local tweak problem(s) to fix.", problems.len())
}

pub fn problems(env: &Env, ui: &Ui) -> Vec<String> {
    let mut problems = Vec::new();
    let command_line_tools = std::env::var_os("DEVELOPER_DIR")
        .is_none()
        .then(|| Path::new("/Library/Developer/CommandLineTools"));
    let xcrun = |args: &[&str]| {
        Command::new("/usr/bin/xcrun")
            .args(args)
            .stdin(Stdio::null())
            .output()
            .is_ok_and(|output| output.status.success())
    };
    let clang = command_line_tools.is_some_and(|tools| {
        fs::metadata(tools.join("usr/bin/clang"))
            .is_ok_and(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0)
    }) || xcrun(&["--find", "clang"]);
    if clang {
        ui.success("clang is available.");
    } else {
        problems.push(
            "Install Xcode Command Line Tools (xcode-select --install) to compile .m tweaks, or use a prebuilt .dylib."
                .to_string(),
        );
    }
    let sdk = command_line_tools.is_some_and(|tools| tools.join("SDKs/MacOSX.sdk").exists())
        || xcrun(&["--show-sdk-path"]);
    if sdk {
        ui.success("The macOS SDK is available.");
    } else {
        problems.push("The macOS SDK is missing. Install Xcode Command Line Tools.".to_string());
    }
    let folder = env.local();
    match fs::symlink_metadata(&folder) {
        Err(_) => ui.info(format_args!(
            "{} doesn't exist yet; it's created when you add a tweak.",
            folder.display()
        )),
        Ok(meta) if env::is_mine(&meta) && env::writable(&folder) => {
            ui.success(format_args!("{} is writable.", folder.display()));
        }
        Ok(_) => problems.push(env.not_yours(&folder).to_string()),
    }
    match Diapatch::find(env).and_then(|diapatch| run_local(ui, &diapatch, "doctor", &[])) {
        Ok(Some(error)) => problems.push(error),
        Ok(None) => {}
        Err(err) => problems.push(format!("{err:#}")),
    }
    problems
}

const EXTENSIONS: [&str; 6] = ["m", "dylib", "patch", "diff", "zip", "diatweak"];

fn find(env: &Env, name: &str) -> Result<PathBuf> {
    let folder = env.local();
    let wanted = name
        .rsplit_once('.')
        .filter(|(_, extension)| EXTENSIONS.contains(extension))
        .map_or(name, |(stem, _)| stem);
    for entry in
        fs::read_dir(&folder).with_context(|| format!("Couldn't read {}", folder.display()))?
    {
        let entry = entry?;
        let file = entry.file_name();
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

fn trash(home: &Path, path: &Path) -> Result<()> {
    let folder = home.join(".Trash");
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
        write(
            &dir.join("patches.json"),
            r#"{
                "version": 1,
                "patches": [
                    {"key": "hideToolbar", "title": "Hide Toolbar", "detail": "H", "defaultOn": false, "requires": null, "disabledBy": null},
                    {"key": "localTweaks", "title": "Local Tweaks", "detail": "L", "defaultOn": true, "requires": null, "disabledBy": null}
                ]
            }"#,
        );
        Manifest::load(&Env::at(dir)).unwrap()
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
        assert_eq!(
            manifest
                .resolve(&["my-tweak".into()], |_, _| Ok(false))
                .unwrap(),
            vec![2]
        );
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
    fn github_links_become_downloads() {
        let pull =
            |url: &str| github_download(url).map(|(source, name)| format!("{source} {name}"));
        let expected = "https://github.com/JaceThings/DiaTweaks/pull/557.patch pr-557.patch";
        for url in [
            "https://github.com/JaceThings/DiaTweaks/pull/557",
            "https://github.com/JaceThings/DiaTweaks/pull/557/",
            "https://github.com/JaceThings/DiaTweaks/pull/557/files#diff-1",
            "https://github.com/JaceThings/DiaTweaks/pull/557.patch",
            "https://www.github.com/JaceThings/DiaTweaks/pull/557?w=1",
        ] {
            assert_eq!(pull(url).as_deref(), Some(expected), "{url}");
        }
        assert_eq!(
            pull("https://github.com/a/b/blob/main/tweaks/Foo/Foo.m").as_deref(),
            Some("https://github.com/a/b/raw/main/tweaks/Foo/Foo.m Foo.m")
        );
        assert_eq!(
            pull("https://raw.githubusercontent.com/a/b/main/Foo.m?token=x").as_deref(),
            Some("https://raw.githubusercontent.com/a/b/main/Foo.m?token=x Foo.m")
        );
        for url in [
            "http://github.com/a/b/pull/1",
            "https://github.com/a/b/pull/x",
            "https://github.com/a/b",
            "https://example.com/Foo.m",
            "ftp://github.com/a/b/pull/1",
        ] {
            assert_eq!(pull(url), None, "{url}");
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
        write(
            &dir.path().join("patches.json"),
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
        let manifest = Manifest::load_with_local(&Env::at(dir.path())).unwrap();
        assert_eq!(manifest.patches.len(), 2);
        assert!(manifest.patches[1].local);
    }
}
