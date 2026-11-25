use std::{
    collections::BTreeMap,
    ffi::c_void,
    fs::{self, File, Permissions},
    io::{self, Read, Write},
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
};

use anyhow::{anyhow, bail, Result};
use core_foundation::{
    array::CFArray,
    base::{CFType, TCFType},
    boolean::CFBoolean,
    dictionary::CFDictionary,
    number::CFNumber,
    string::CFString,
};
use serde::Serialize;
use serde_json::{json, Map, Number, Value};

use crate::{
    dia,
    env::Env,
    lock,
    manifest::{Manifest, Patch, SettingKind},
    prefs::{as_bool, Prefs},
    tweaks::{self, on_off},
    ui::{self, Ui},
};

pub const FILE: &str = "diatweaks-config.json";
const MAX_BYTES: u64 = 1 << 20;
const MODIFIERS: u64 = 0x1E_0000;
const NOT_SHIFT: u64 = 0x1C_0000;

enum Kind<'a> {
    Bool,
    Number(Option<f64>, Option<f64>),
    Text,
    Choice(&'a [String]),
    Shortcut,
}

struct Setting<'a> {
    index: usize,
    kind: Kind<'a>,
}

#[derive(Serialize)]
struct Config<'a> {
    version: u32,
    tweaks: BTreeMap<&'a str, bool>,
    settings: BTreeMap<&'a str, Value>,
}

#[derive(Default)]
struct Plan {
    tweaks: BTreeMap<usize, bool>,
    settings: BTreeMap<String, Value>,
    unknown: Vec<String>,
    warnings: Vec<String>,
}

/// What an import would change, worked out before anything is written.
#[derive(Default)]
struct Prepared {
    changes: Vec<usize>,
    wanted: Vec<bool>,
    sets: Vec<(usize, bool)>,
    clears: Vec<usize>,
    settings: Vec<(String, CFType)>,
    cleared_settings: Vec<String>,
    resets: Vec<String>,
    affected: Vec<usize>,
}

fn portable_patch(patch: &Patch) -> bool {
    !patch.local && patch.key != "localTweaks"
}

fn portable(manifest: &Manifest) -> BTreeMap<&str, Setting<'_>> {
    let mut found = BTreeMap::new();
    for (index, patch) in manifest.patches.iter().enumerate() {
        if !portable_patch(patch) {
            continue;
        }
        if let Some(choice) = &patch.choice {
            found.insert(
                choice.key.as_str(),
                Setting {
                    index,
                    kind: Kind::Choice(&choice.values),
                },
            );
        }
        if let Some(shortcut) = &patch.shortcut {
            found.insert(
                shortcut.key.as_str(),
                Setting {
                    index,
                    kind: Kind::Shortcut,
                },
            );
        }
        for spec in &patch.settings {
            let kind = match spec.kind {
                SettingKind::Bool => Kind::Bool,
                SettingKind::Number => Kind::Number(spec.min, spec.max),
                SettingKind::String => Kind::Text,
                SettingKind::Unsupported => continue,
            };
            found.insert(spec.key.as_str(), Setting { index, kind });
        }
    }
    found
}

pub fn export(env: &Env, ui: &Ui, path: Option<PathBuf>) -> Result<()> {
    let manifest = Manifest::load(env)?;
    let prefs = Prefs::new(&env.domain);
    let state = manifest.state(&prefs);
    let mut settings = BTreeMap::new();
    for (key, setting) in portable(&manifest) {
        let Some(value) = read(&prefs, key, &setting.kind) else {
            continue;
        };
        match check(&manifest, &setting, key, &value, &mut Vec::new()) {
            Ok(_) => {
                settings.insert(key, value);
            }
            Err(problem) => ui.warn(format!("Left out {key}: it {problem}")),
        }
    }
    let config = Config {
        version: 1,
        tweaks: manifest
            .patches
            .iter()
            .zip(&state)
            .filter(|(patch, _)| portable_patch(patch))
            .map(|(patch, &on)| (patch.key.as_str(), on))
            .collect(),
        settings,
    };
    let json = serde_json::to_string_pretty(&config)?;
    let path = path.unwrap_or_else(|| FILE.into());
    if path == Path::new("-") {
        ui::say(json);
        return Ok(());
    }
    let path = if path.is_dir() { path.join(FILE) } else { path };
    write_atomically(&path, &format!("{json}\n"))?;
    ui.done(format!(
        "Saved {} and {} to {}.",
        count(config.tweaks.len(), "tweak"),
        count(config.settings.len(), "setting"),
        path.display()
    ));
    Ok(())
}

fn write_atomically(path: &Path, text: &str) -> Result<()> {
    let path = fs::canonicalize(path).unwrap_or_else(|_| path.into());
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let saved = (|| {
        let mut file = tempfile::NamedTempFile::new_in(parent)?;
        file.write_all(text.as_bytes())?;
        file.as_file()
            .set_permissions(Permissions::from_mode(0o644))?;
        file.persist(&path).map_err(|failed| failed.error)?;
        Ok::<_, io::Error>(())
    })();
    saved.map_err(|err| match err.kind() {
        io::ErrorKind::NotFound => anyhow!(
            "The folder {} doesn't exist. Make it first, or pick another path.",
            parent.display()
        ),
        io::ErrorKind::PermissionDenied => anyhow!(
            "diatweaks can't write to {}. Pick a folder that's yours, like `diatweaks export ~/{FILE}`.",
            parent.display()
        ),
        _ => anyhow!(err).context(format!("Couldn't write {}", path.display())),
    })
}

pub fn import(env: &Env, ui: &Ui, path: Option<PathBuf>, replace: bool) -> Result<()> {
    let (manifest, name, plan) = load(env, ui, path)?;
    let _lock = lock::acquire(env, ui)?;
    let prefs = Prefs::new(&env.domain);
    announce(ui, &manifest, &plan);
    let prepared = Prepared::new(&manifest, &prefs, &plan, replace);
    if prepared.is_empty() {
        ui.done(format!("Already matches {name}: nothing to change."));
        return Ok(());
    }
    commit(env, ui, &manifest, &prefs, &prepared, &name)
}

fn load(env: &Env, ui: &Ui, path: Option<PathBuf>) -> Result<(Manifest, String, Plan)> {
    let manifest = Manifest::load(env)?;
    let path = match path {
        Some(path) => path,
        None if ui.interactive => ask_path(env, "Settings file to import")?,
        None => bail!("Pass a settings file to import, such as: diatweaks import {FILE}"),
    };
    let name = if path == Path::new("-") {
        "standard input".into()
    } else {
        path.display().to_string()
    };
    let plan = Plan::parse(&manifest, &read_text(&path, &name)?, &name)?;
    Ok((manifest, name, plan))
}

fn announce(ui: &Ui, manifest: &Manifest, plan: &Plan) {
    for warning in &plan.warnings {
        ui.warn(warning);
    }
    if !plan.unknown.is_empty() {
        ui.warn(format!("Skipped unknown keys: {}", plan.unknown.join(", ")));
    }
    if plan.sets_launch_flags(manifest) {
        ui.warn("This file sets Launch Flags, which open Dia with extra options. Only import launch flags from someone you trust.");
    }
}

impl Prepared {
    fn new(manifest: &Manifest, prefs: &Prefs, plan: &Plan, replace: bool) -> Self {
        let before = manifest.state(prefs);
        let mut wanted = before.clone();
        let mut prepared = Self {
            wanted: wanted.clone(),
            ..Self::default()
        };
        for (index, patch) in manifest.patches.iter().enumerate() {
            if let Some(&on) = plan.tweaks.get(&index) {
                if on != before[index] {
                    prepared.sets.push((index, on));
                }
                wanted[index] = on;
            } else if replace && portable_patch(patch) && prefs.raw(&patch.key).is_some() {
                prepared.clears.push(index);
                prepared.resets.push(patch.key.clone());
                wanted[index] = patch.default_on;
            }
        }
        prepared.changes = (0..wanted.len())
            .filter(|&index| wanted[index] != before[index])
            .collect();
        prepared.wanted = wanted;

        let mut tuned = Vec::new();
        for (key, setting) in portable(manifest) {
            match plan.settings.get(key) {
                Some(value) if read(prefs, key, &setting.kind).as_ref() != Some(value) => {
                    if let Some(value) = cf(value) {
                        prepared.settings.push((key.to_string(), value));
                        tuned.push(setting.index);
                    }
                }
                None if replace && prefs.raw(key).is_some() => {
                    prepared.cleared_settings.push(key.to_string());
                    prepared.resets.push(key.to_string());
                }
                _ => {}
            }
        }
        prepared.affected = prepared.changes.clone();
        for index in tuned {
            if prepared.wanted[index] && !prepared.affected.contains(&index) {
                prepared.affected.push(index);
            }
        }
        prepared
    }

    fn is_empty(&self) -> bool {
        self.tweaks() == 0 && self.settings.is_empty() && self.cleared_settings.is_empty()
    }

    fn tweaks(&self) -> usize {
        self.changes.len()
    }

    fn apply(&self, manifest: &Manifest, prefs: &Prefs) {
        for &index in &self.clears {
            prefs.clear(&manifest.patches[index].key);
        }
        for &(index, on) in &self.sets {
            prefs.set(&manifest.patches[index].key, on);
        }
        for (key, value) in &self.settings {
            prefs.set_value(key, value);
        }
        for key in &self.cleared_settings {
            prefs.clear(key);
        }
    }
}

fn commit(
    env: &Env,
    ui: &Ui,
    manifest: &Manifest,
    prefs: &Prefs,
    prepared: &Prepared,
    name: &str,
) -> Result<()> {
    prepared.apply(manifest, prefs);
    prefs.save()?;
    for &index in &prepared.changes {
        ui.success(format!(
            "Turned {} {}.",
            on_off(prepared.wanted[index]),
            manifest.title(index)
        ));
    }
    if !prepared.settings.is_empty() {
        let updated: Vec<&str> = prepared
            .settings
            .iter()
            .map(|(key, _)| key.as_str())
            .collect();
        ui.success(format!("Updated {}.", updated.join(", ")));
    }
    if !prepared.resets.is_empty() {
        ui.info(format!(
            "Reset to defaults ({}): {}.",
            prepared.resets.len(),
            prepared.resets.join(", ")
        ));
    }
    if prepared
        .affected
        .iter()
        .any(|&index| manifest.patches[index].key == "appIcon")
    {
        dia::sync_icon(env);
    }
    ui.success(format!(
        "Imported {name}: {} and {} changed.",
        count(prepared.tweaks(), "tweak"),
        count(prepared.settings.len(), "setting")
    ));
    tweaks::finish_changes(
        env,
        ui,
        manifest,
        &prepared.affected,
        &prepared.wanted,
        false,
    );
    Ok(())
}

pub fn menu(env: &Env, ui: &Ui) -> Result<()> {
    #[derive(Clone, Copy, PartialEq, Eq)]
    enum Choice {
        Export,
        Merge,
        Replace,
    }
    let choice = ui::prompt(
        cliclack::select("Back up or import settings")
            .item(
                Choice::Export,
                "Back up",
                "save your tweaks and settings to a file",
            )
            .item(
                Choice::Merge,
                "Import and merge",
                "keep anything the file doesn't mention",
            )
            .item(
                Choice::Replace,
                "Import and replace",
                "reset anything the file doesn't mention",
            )
            .interact(),
    )?;
    match choice {
        Choice::Export => export(env, ui, Some(ask_path(env, "Save to")?)),
        Choice::Merge | Choice::Replace => {
            let path = ask_path(env, "Settings file to import")?;
            preview(env, ui, path, choice == Choice::Replace)
        }
    }
}

/// The menu's import: show what would change, then apply it once the person agrees.
fn preview(env: &Env, ui: &Ui, path: PathBuf, replace: bool) -> Result<()> {
    let (manifest, name, plan) = load(env, ui, Some(path))?;
    let _lock = lock::acquire(env, ui)?;
    let prefs = Prefs::new(&env.domain);
    announce(ui, &manifest, &plan);
    let prepared = Prepared::new(&manifest, &prefs, &plan, replace);
    if prepared.is_empty() {
        ui.done(format!("Already matches {name}: nothing to change."));
        return Ok(());
    }
    let mut summary = vec![count(prepared.tweaks(), "tweak")];
    let settings = prepared.settings.len() + prepared.cleared_settings.len();
    if settings > 0 {
        summary.push(count(settings, "setting"));
    }
    ui.info(format!("{name} changes {}.", summary.join(" and ")));
    if !ui.proceed(format!("Import these changes from {name}?"))? {
        ui.info("Nothing changed.");
        return Ok(());
    }
    commit(env, ui, &manifest, &prefs, &prepared, &name)
}

fn ask_path(env: &Env, question: &str) -> Result<PathBuf> {
    let typed: String = ui::prompt(cliclack::input(question).default_input(FILE).interact())?;
    Ok(match typed.trim().strip_prefix("~/") {
        Some(rest) => env.home.join(rest),
        None => typed.trim().into(),
    })
}

fn read_text(path: &Path, name: &str) -> Result<String> {
    let mut text = String::new();
    let read = if path == Path::new("-") {
        io::stdin().take(MAX_BYTES + 1).read_to_string(&mut text)
    } else {
        File::open(path).and_then(|file| file.take(MAX_BYTES + 1).read_to_string(&mut text))
    };
    read.map_err(|err| match err.kind() {
        io::ErrorKind::NotFound => anyhow!(
            "There's no file at {name}. Check the path, or run `diatweaks export` to make one."
        ),
        io::ErrorKind::PermissionDenied => anyhow!("diatweaks isn't allowed to read {name}."),
        io::ErrorKind::IsADirectory => {
            anyhow!("{name} is a folder. Name the settings file inside it.")
        }
        io::ErrorKind::InvalidData => {
            anyhow!("{name} isn't a text file, so it can't be a DiaTweaks settings file.")
        }
        _ => anyhow!(err).context(format!("Couldn't read {name}")),
    })?;
    if text.len() as u64 > MAX_BYTES {
        bail!("{name} is too big to be a DiaTweaks settings file.");
    }
    Ok(text)
}

impl Plan {
    /// Launch Flags run an arbitrary-args path, so an import that sets them needs a warning.
    fn sets_launch_flags(&self, manifest: &Manifest) -> bool {
        let on = manifest
            .index("launchFlags")
            .is_some_and(|index| self.tweaks.get(&index) == Some(&true));
        let args = self
            .settings
            .get("launchFlagsArgs")
            .and_then(Value::as_str)
            .is_some_and(|text| {
                text.lines().any(|line| {
                    let line = line.trim();
                    !line.is_empty() && !line.starts_with('#')
                })
            });
        on || args
    }

    fn parse(manifest: &Manifest, text: &str, name: &str) -> Result<Self> {
        let top = match serde_json::from_str(text) {
            Ok(Value::Object(top)) => top,
            Ok(_) => bail!("{name} isn't a DiaTweaks settings file: it should be a JSON object. Make one with `diatweaks export`."),
            Err(err) => bail!("{name} isn't valid JSON ({err}). Make a fresh one with `diatweaks export`."),
        };
        match top.get("version").and_then(Value::as_u64) {
            Some(1) => {}
            Some(newer) if newer > 1 => bail!("{name} is version {newer}, which this diatweaks can't read. Run `diatweaks update`, then try again."),
            _ => bail!("{name} should start with \"version\": 1. Make a fresh one with `diatweaks export`."),
        }

        let mut plan = Self::default();
        let mut problems = Vec::new();
        for key in top
            .keys()
            .filter(|key| !matches!(key.as_str(), "version" | "tweaks" | "settings"))
        {
            problems.push(format!(
                "\"{key}\" isn't a section of a settings file (use tweaks and settings)"
            ));
        }
        let mut section = |label: &str| match top.get(label) {
            None => Map::new(),
            Some(Value::Object(section)) => section.clone(),
            Some(_) => {
                problems.push(format!("\"{label}\" must be an object"));
                Map::new()
            }
        };
        let (tweaks, settings) = (section("tweaks"), section("settings"));

        for (key, value) in &tweaks {
            let Some(index) = manifest
                .index(key)
                .filter(|&index| portable_patch(&manifest.patches[index]))
            else {
                plan.unknown.push(key.clone());
                continue;
            };
            match value {
                Value::Bool(on) => {
                    plan.tweaks.insert(index, *on);
                }
                _ => problems.push(format!("tweaks.{key} must be true or false")),
            }
        }
        let portable = portable(manifest);
        for (key, value) in &settings {
            let Some(setting) = portable.get(key.as_str()) else {
                plan.unknown.push(key.clone());
                continue;
            };
            match check(manifest, setting, key, value, &mut plan.warnings) {
                Ok(value) => {
                    plan.settings.insert(key.clone(), value);
                }
                Err(problem) => problems.push(format!("settings.{key} {problem}")),
            }
        }
        if !problems.is_empty() {
            bail!(
                "{name} can't be imported, so nothing was changed:\n  - {}",
                problems.join("\n  - ")
            );
        }
        Ok(plan)
    }
}

fn check(
    manifest: &Manifest,
    setting: &Setting<'_>,
    key: &str,
    value: &Value,
    warnings: &mut Vec<String>,
) -> Result<Value, String> {
    let title = &manifest.patches[setting.index].title;
    match &setting.kind {
        Kind::Bool if value.is_boolean() => Ok(value.clone()),
        Kind::Bool => Err("must be true or false".into()),
        Kind::Number(min, max) => {
            let number = value
                .as_f64()
                .filter(|number| number.is_finite())
                .ok_or("must be a number")?;
            let clamped = number
                .max(min.unwrap_or(f64::NEG_INFINITY))
                .min(max.unwrap_or(f64::INFINITY));
            let clean = json_number(clamped).ok_or("must be a number")?;
            if clamped != number {
                warnings.push(format!(
                    "{title}: {key} {value} is out of range, so it was set to {clean}"
                ));
            }
            Ok(clean)
        }
        Kind::Text => {
            let text = value.as_str().ok_or("must be text")?;
            match launch_flags_problem(text).filter(|_| key == "launchFlagsArgs") {
                Some(problem) => Err(problem),
                None => Ok(value.clone()),
            }
        }
        Kind::Choice(values) => {
            let text = value.as_str().ok_or("must be text")?;
            if !values.is_empty() && !values.iter().any(|known| known == text) {
                warnings.push(format!("{title}: '{text}' isn't in this Mac's options; kept so DiaTweaks can fall back if needed"));
            }
            Ok(value.clone())
        }
        Kind::Shortcut => check_shortcut(value).map(|()| value.clone()),
    }
}

fn check_shortcut(value: &Value) -> Result<(), String> {
    let shape = "must be {} to clear it, or an object with exactly key, keyCode and modifiers";
    let object = value.as_object().ok_or(shape)?;
    if object.is_empty() {
        return Ok(());
    }
    let key = object
        .get("key")
        .and_then(Value::as_str)
        .filter(|key| !key.is_empty() && !key.chars().any(char::is_control));
    let key_code = object
        .get("keyCode")
        .and_then(Value::as_u64)
        .filter(|&code| code <= u64::from(u16::MAX));
    let modifiers = object
        .get("modifiers")
        .and_then(Value::as_u64)
        .filter(|&flags| flags & !MODIFIERS == 0);
    let (Some(key), Some(_), Some(modifiers), 3) = (key, key_code, modifiers, object.len()) else {
        return Err(shape.into());
    };
    let function_key = (1..=12).any(|number| key == format!("F{number}"));
    if modifiers & NOT_SHIFT == 0 && !function_key {
        return Err("needs ⌃, ⌥ or ⌘ held, unless the key is F1–F12".into());
    }
    Ok(())
}

// Mirrors LaunchFlags/Parse.m so an import never saves flags Dia would drop.
fn launch_flags_problem(text: &str) -> Option<String> {
    let chars: Vec<char> = text.chars().collect();
    let space = |c: char| matches!(c, ' ' | '\t' | '\r' | '\n');
    let escapable = |c: char| space(c) || matches!(c, '\'' | '"' | '\\');
    let mut at = 0;
    while at < chars.len() {
        if space(chars[at]) {
            at += 1;
            continue;
        }
        if chars[at] == '#' {
            while at < chars.len() && chars[at] != '\n' {
                at += 1;
            }
            continue;
        }
        let mut token = String::new();
        let mut quote = None;
        while at < chars.len() {
            let c = chars[at];
            let next = chars.get(at + 1).copied();
            at += 1;
            match (quote, c, next) {
                (Some(open), c, _) if c == open => quote = None,
                (Some('"'), '\\', Some(n @ ('"' | '\\'))) => {
                    token.push(n);
                    at += 1;
                }
                (None, c, _) if space(c) => break,
                (None, '\'' | '"', _) => quote = Some(c),
                (None, '\\', Some(n)) if escapable(n) => {
                    if !matches!(n, '\r' | '\n') {
                        token.push(n);
                    }
                    at += 1;
                }
                (_, '\0', _) => {}
                (_, c, _) => token.push(c),
            }
        }
        if quote.is_some() {
            return Some("has a quote that never closes".into());
        }
        if !token.is_empty() && !is_launch_flag(&token) {
            return Some(format!(
                "has \"{token}\", which isn't a launch flag (flags look like --disable-gpu)"
            ));
        }
    }
    None
}

fn is_launch_flag(token: &str) -> bool {
    let Some(rest) = token.strip_prefix("--") else {
        return false;
    };
    let (name, value) = rest.split_once('=').unwrap_or((rest, ""));
    name.starts_with(|c: char| c.is_ascii_alphanumeric())
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
        && !value.contains(['\0', '\r', '\n'])
}

fn json_number(value: f64) -> Option<Value> {
    if !value.is_finite() {
        return None;
    }
    if value.fract() == 0.0 && value.abs() < (1_i64 << 53) as f64 {
        return Some(Value::from(value as i64));
    }
    let rounded = (value * 1e6).round() / 1e6;
    Number::from_f64(if rounded.is_finite() { rounded } else { value }).map(Value::Number)
}

fn read(prefs: &Prefs, key: &str, kind: &Kind<'_>) -> Option<Value> {
    let value = prefs.raw(key)?;
    match kind {
        Kind::Bool => as_bool(&value).map(Value::Bool),
        Kind::Number(..) => json_number(value.downcast::<CFNumber>()?.to_f64()?),
        Kind::Text if key == "launchFlagsArgs" => Some(Value::String(launch_flags_text(&value)?)),
        Kind::Text | Kind::Choice(_) => {
            Some(Value::String(value.downcast::<CFString>()?.to_string()))
        }
        Kind::Shortcut => read_shortcut(&value),
    }
}

// Older versions saved launch flags as an array of flags, which Launch Flags still reads.
fn launch_flags_text(value: &CFType) -> Option<String> {
    if let Some(text) = value.downcast::<CFString>() {
        return Some(text.to_string());
    }
    let mut flags = Vec::new();
    for item in value.downcast::<CFArray>()?.iter() {
        let item = unsafe { CFType::wrap_under_get_rule(*item) };
        let Some(text) = item.downcast::<CFString>() else {
            continue;
        };
        let text = text.to_string();
        if !text.is_empty() {
            flags.push(quote_flag(&text));
        }
    }
    Some(flags.join("\n"))
}

// Mirrors DPFormatLaunchFlagsArray, so a legacy array exports the text the tweak reads.
fn quote_flag(text: &str) -> String {
    let quote = text.starts_with('#')
        || text
            .chars()
            .any(|c| c.is_whitespace() || matches!(c, '"' | '\'' | '\\'));
    if !quote {
        return text.to_string();
    }
    let escaped = text.replace('\\', "\\\\").replace('"', "\\\"");
    format!("\"{escaped}\"")
}

fn read_shortcut(value: &CFType) -> Option<Value> {
    let dictionary = value.downcast::<CFDictionary>()?;
    if dictionary.is_empty() {
        return Some(json!({}));
    }
    let entry = |name: &str| {
        let key = CFString::new(name);
        dictionary
            .find(key.as_concrete_TypeRef().cast::<c_void>())
            .map(|item| unsafe { CFType::wrap_under_get_rule(*item) })
    };
    Some(json!({
        "key": entry("key")?.downcast::<CFString>()?.to_string(),
        "keyCode": entry("keyCode")?.downcast::<CFNumber>()?.to_i64()?,
        "modifiers": entry("modifiers")?.downcast::<CFNumber>()?.to_i64()?,
    }))
}

fn cf(value: &Value) -> Option<CFType> {
    Some(match value {
        Value::Bool(on) => CFBoolean::from(*on).as_CFType(),
        Value::Number(number) => match number.as_i64() {
            Some(whole) => CFNumber::from(whole),
            None => CFNumber::from(number.as_f64()?),
        }
        .as_CFType(),
        Value::String(text) => CFString::new(text).as_CFType(),
        Value::Object(entries) => {
            let pairs: Vec<(CFString, CFType)> = entries
                .iter()
                .filter_map(|(key, value)| Some((CFString::new(key), cf(value)?)))
                .collect();
            CFDictionary::from_CFType_pairs(&pairs).as_CFType()
        }
        _ => return None,
    })
}

fn count(number: usize, noun: &str) -> String {
    format!("{number} {noun}{}", if number == 1 { "" } else { "s" })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn launch_flags_follow_the_dylib_parser() {
        for fine in [
            "",
            "  \n",
            "--disable-gpu",
            "--a.b_c-d=1 --x",
            "--foo=\"a b\" '--bar' --baz=\\ q",
            "# a note --not-parsed\n--ok",
            "\"\" --ok",
            "\"--quoted=flag \\\"x\\\"\"",
        ] {
            assert_eq!(launch_flags_problem(fine), None, "{fine:?}");
        }
        for bad in [
            "bad", "-x", "--", "---x", "--=1", "--a b", "--a\"b", "'--x", "--x \"y", "--x=\"\\",
        ] {
            assert!(launch_flags_problem(bad).is_some(), "{bad:?}");
        }
    }

    #[test]
    fn numbers_export_cleanly() {
        assert_eq!(json_number(20.0), Some(json!(20)));
        assert_eq!(json_number(-0.0), Some(json!(0)));
        assert_eq!(json_number(0.240_000_000_000_000_02), Some(json!(0.24)));
        assert_eq!(json_number(f64::NAN), None);
        assert_eq!(json_number(f64::INFINITY), None);
        assert_eq!(json_number(1e300), Some(json!(1e300)));
        assert_eq!(
            json_number(9_007_199_254_740_992.0),
            Some(json!(9_007_199_254_740_992.0))
        );
    }

    #[test]
    fn shortcuts_need_a_real_modifier_unless_they_are_function_keys() {
        let shortcut =
            |key: &str, modifiers: u64| json!({"key": key, "keyCode": 1, "modifiers": modifiers});
        for fine in [
            json!({}),
            shortcut("D", 0x10_0000),
            shortcut("D", 0x1E_0000),
            shortcut("F1", 0),
            shortcut("F12", 0x2_0000),
        ] {
            assert_eq!(check_shortcut(&fine), Ok(()), "{fine}");
        }
        for bad in [
            shortcut("D", 0),
            shortcut("D", 0x2_0000),
            shortcut("F13", 0),
            shortcut("D", 0x10_0001),
            shortcut("f1", 0),
        ] {
            assert!(check_shortcut(&bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn values_become_the_matching_core_foundation_types() {
        let shortcut = cf(&json!({"key": "D", "keyCode": 2, "modifiers": 1048576})).unwrap();
        assert!(shortcut.downcast::<CFDictionary>().is_some());
        assert_eq!(
            read_shortcut(&shortcut),
            Some(json!({"key": "D", "keyCode": 2, "modifiers": 1048576}))
        );
        assert_eq!(read_shortcut(&cf(&json!({})).unwrap()), Some(json!({})));
        assert_eq!(read_shortcut(&cf(&json!({"key": "D"})).unwrap()), None);
        assert_eq!(
            cf(&json!(1.5))
                .unwrap()
                .downcast::<CFNumber>()
                .unwrap()
                .to_f64(),
            Some(1.5)
        );
        assert!(
            cf(&json!(7))
                .unwrap()
                .downcast::<CFNumber>()
                .unwrap()
                .to_i64()
                == Some(7)
        );
        assert!(cf(&json!(true)).unwrap().downcast::<CFBoolean>().is_some());
        assert!(cf(&json!(null)).is_none());
    }
}
