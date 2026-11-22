use std::fmt::Write;

use anyhow::Result;

use crate::{
    dia::{self, SafeMode},
    env::Env,
    lock,
    manifest::Manifest,
    prefs::Prefs,
    signals::Cancelled,
    ui::{self, Ui},
};

pub fn list(env: &Env) -> Result<()> {
    let manifest = Manifest::load(&env.manifest())?;
    let state = manifest.state(&Prefs::new(&env.domain));
    if dia::is_paused(&env.support) {
        ui::say("Tweaks are paused: every one is off until `diatweaks resume`. The settings below are kept.");
    }
    let width = manifest
        .patches
        .iter()
        .map(|patch| patch.key.len())
        .max()
        .unwrap_or(0);
    for (index, (patch, &on)) in manifest.patches.iter().zip(&state).enumerate() {
        let mut line = format!("{:<4} {:<width$}  {}", on_off(on), patch.key, patch.title);
        if let Some(cover) = manifest.covered_by(index, &state) {
            let _ = write!(line, " ({} hides this too)", manifest.title(cover));
        }
        ui::say(line);
    }
    Ok(())
}

pub fn set(env: &Env, ui: &Ui, names: &[String], on: bool) -> Result<()> {
    let manifest = Manifest::load(&env.manifest())?;
    let targets = manifest.resolve(names)?;
    let current = manifest.state(&Prefs::new(&env.domain));
    let mut wanted = current.clone();
    for &index in &targets {
        if current[index] == on {
            ui.info(format_args!(
                "{} is already {}.",
                manifest.title(index),
                on_off(on)
            ));
        }
        wanted[index] = on;
    }
    add_requirements(ui, &manifest, &current, &mut wanted)?;
    let changes = save(env, &manifest, &current, &wanted)?;
    if changes.is_empty() {
        ui.done("Nothing to change.");
        return Ok(());
    }
    for &index in &changes {
        ui.success(format_args!(
            "Turned {} {}.",
            on_off(wanted[index]),
            manifest.title(index)
        ));
    }
    for note in notes(&manifest, &current, &wanted) {
        ui.warn(note);
    }
    finish_changes(env, ui, &manifest, &changes, &wanted, false);
    Ok(())
}

fn is_live_dia(env: &Env) -> bool {
    !dia::is_paused(&env.support)
        && dia::is_running(&env.app)
        && dia::is_patched(&env.app)
        && dia::safe_mode(&env.support) == SafeMode::Off
}

fn needs_relaunch(
    manifest: &Manifest,
    index: usize,
    wanted_on: bool,
    icon_linked: bool,
    brief_patched: bool,
) -> bool {
    let patch = &manifest.patches[index];
    patch.relaunch
        || (patch.key == "appIcon" && wanted_on != icon_linked)
        || (patch.key == "briefLanguage" && wanted_on != brief_patched)
}

fn finish_changes(
    env: &Env,
    ui: &Ui,
    manifest: &Manifest,
    changes: &[usize],
    wanted: &[bool],
    saved_prefix: bool,
) {
    let icon_linked = dia::has_linked_icon_catalog(&env.app);
    let brief_patched = dia::has_brief_language(&env.app);
    let live = is_live_dia(env);
    let relaunching: Vec<&str> = if live {
        changes
            .iter()
            .filter(|&&index| {
                needs_relaunch(manifest, index, wanted[index], icon_linked, brief_patched)
            })
            .map(|&index| manifest.title(index))
            .collect()
    } else {
        Vec::new()
    };
    if !live
        && !dia::is_paused(&env.support)
        && dia::is_patched(&env.app)
        && dia::safe_mode(&env.support) == SafeMode::Off
    {
        if let Some(&index) = changes
            .iter()
            .find(|&&index| manifest.patches[index].key == "appIcon")
        {
            if wanted[index] && !icon_linked {
                ui.warn(
                    "App Icon needs a rebuild to link Dia's asset catalog. Run `diatweaks update` to apply it.",
                );
            } else if !wanted[index] && icon_linked {
                ui.warn(
                    "Dia's default icon is restored; run `diatweaks update` to restore its sealed asset catalog.",
                );
            }
        }
        if let Some(&index) = changes
            .iter()
            .find(|&&index| manifest.patches[index].key == "briefLanguage")
        {
            if wanted[index] != brief_patched {
                ui.warn(
                    "Morning Brief Language needs a rebuild to update Dia's prompt. Run `diatweaks update` to apply it.",
                );
            }
        }
    }
    let tail = if !relaunching.is_empty() {
        ui.warn(format_args!(
            "Relaunch Dia to apply: {}.",
            relaunching.join(", ")
        ));
        if relaunching.len() == changes.len() {
            "Relaunch Dia to see the changes.".into()
        } else {
            "Dia shows the rest now.".into()
        }
    } else {
        where_it_applies(env)
    };
    if saved_prefix {
        ui.done(format_args!("Saved. {tail}"));
    } else {
        ui.done(tail);
    }
}

fn where_it_applies(env: &Env) -> String {
    if dia::is_paused(&env.support) {
        "Tweaks are paused, so nothing changes until you run `diatweaks resume`.".into()
    } else {
        where_it_shows(env)
    }
}

pub fn menu(env: &Env, ui: &Ui) -> Result<()> {
    let manifest = Manifest::load(&env.manifest())?;
    let current = manifest.state(&Prefs::new(&env.domain));
    let mut prompt = cliclack::multiselect("Turn tweaks on or off (space toggles, enter saves)")
        .required(false)
        .initial_values((0..current.len()).filter(|&index| current[index]).collect());
    for (index, patch) in manifest.patches.iter().enumerate() {
        prompt = prompt.item(index, &patch.title, hint(&manifest, &current, index));
    }
    let selected = ui::prompt(prompt.interact())?;
    let mut wanted = vec![false; current.len()];
    for index in selected {
        wanted[index] = true;
    }
    add_requirements(ui, &manifest, &current, &mut wanted)?;

    let summary: Vec<String> = (0..wanted.len())
        .filter(|&index| wanted[index] != current[index])
        .map(|index| {
            let verb = if wanted[index] {
                "Turn on "
            } else {
                "Turn off"
            };
            format!("{verb}  {}", manifest.title(index))
        })
        .collect();
    if summary.is_empty() {
        ui.done("Nothing changed.");
        return Ok(());
    }
    ui.note("Changes", summary.join("\n"));
    for note in notes(&manifest, &current, &wanted) {
        ui.warn(note);
    }
    if !ui.choose("Save these changes?", true)? {
        return Err(Cancelled::nothing_changed().into());
    }
    let changes = save(env, &manifest, &current, &wanted)?;
    finish_changes(env, ui, &manifest, &changes, &wanted, true);
    Ok(())
}

fn hint(manifest: &Manifest, current: &[bool], index: usize) -> String {
    let mut hint = manifest.patches[index].detail.clone();
    if let Some(required) = manifest.requirement(index) {
        let _ = write!(hint, " Needs {}.", manifest.title(required));
    }
    if let Some(cover) = manifest.covered_by(index, current) {
        let _ = write!(hint, " {} hides this too.", manifest.title(cover));
    } else if let Some(disabler) = manifest.hidden_by(index, current) {
        let _ = write!(
            hint,
            " No difference while {} is on.",
            manifest.title(disabler)
        );
    }
    hint
}

fn add_requirements(
    ui: &Ui,
    manifest: &Manifest,
    current: &[bool],
    wanted: &mut [bool],
) -> Result<()> {
    for index in 0..wanted.len() {
        if !wanted[index] || current[index] {
            continue;
        }
        let mut needer = index;
        while let Some(required) = manifest.requirement(needer) {
            if wanted[required] {
                break;
            }
            let question = format!(
                "{} needs {}, which is off. Turn that on too?",
                manifest.title(needer),
                manifest.title(required)
            );
            if !ui.choose(question, true)? {
                break;
            }
            wanted[required] = true;
            needer = required;
        }
    }
    Ok(())
}

fn notes(manifest: &Manifest, current: &[bool], wanted: &[bool]) -> Vec<String> {
    let changed = |index: usize| current[index] != wanted[index];
    let mut notes = Vec::new();
    for index in 0..wanted.len() {
        if let Some(required) = manifest.requirement(index) {
            if wanted[index] && !wanted[required] && (changed(index) || changed(required)) {
                notes.push(format!(
                    "{} does nothing while {} is off.",
                    manifest.title(index),
                    manifest.title(required)
                ));
            }
        }
        if let Some(cover) = manifest.covered_by(index, wanted) {
            if wanted[index] && changed(index) {
                notes.push(format!(
                    "{} hides {} too.",
                    manifest.title(cover),
                    manifest.title(index)
                ));
            }
        } else if let Some(disabler) = manifest.hidden_by(index, wanted) {
            if wanted[index] && changed(index) {
                notes.push(format!(
                    "{} makes no difference while {} is on.",
                    manifest.title(index),
                    manifest.title(disabler)
                ));
            }
        }
    }
    notes
}

// Write only changed keys so concurrent edits to other tweaks survive.
fn save(env: &Env, manifest: &Manifest, current: &[bool], wanted: &[bool]) -> Result<Vec<usize>> {
    let changes: Vec<usize> = (0..wanted.len())
        .filter(|&index| current[index] != wanted[index])
        .collect();
    if changes.is_empty() {
        return Ok(changes);
    }
    let _lock = lock::acquire(&env.support)?;
    let prefs = Prefs::new(&env.domain);
    for &index in &changes {
        prefs.set(&manifest.patches[index].key, wanted[index]);
    }
    prefs.save()?;
    if changes
        .iter()
        .any(|&index| manifest.patches[index].key == "appIcon")
    {
        dia::sync_icon(env);
    }
    Ok(changes)
}

pub fn where_it_shows(env: &Env) -> String {
    match dia::safe_mode(&env.support) {
        SafeMode::Off => {}
        SafeMode::TweaksOff => return "Tweaks are off because Dia quit unexpectedly right after opening. Turn them back on in Dia → Settings → Patches.".into(),
        SafeMode::Parked => return "DiaTweaks is off because Dia kept quitting right after opening, even after it was tried again. It stays off until the next DiaTweaks update.".into(),
        SafeMode::Disabled => return "DiaTweaks is off because Dia kept quitting right after opening. After one launch where Dia stays open for three minutes or quits normally, the next launch brings Settings back with tweaks still off. Turn them back on in Dia → Settings → Patches.".into(),
    }
    if !dia::is_patched(&env.app) {
        return "Dia isn't patched right now, so they won't show. Run `diatweaks update` to patch it again.".into();
    }
    if dia::is_running(&env.app) {
        return "Dia shows the changes now.".into();
    }
    "Dia uses them the next time it opens.".into()
}

fn on_off(on: bool) -> &'static str {
    if on {
        "on"
    } else {
        "off"
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn notes_does_not_warn_when_disabling_hidden_tweak() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("patches.json");
        fs::write(
            &path,
            r#"{
                "version": 1,
                "patches": [
                    {"key": "turnOffAI", "title": "Turn Off AI", "detail": "A", "defaultOn": false, "requires": null, "disabledBy": null, "relaunch": true},
                    {"key": "briefLanguage", "title": "Morning Brief Language", "detail": "B", "defaultOn": false, "requires": null, "disabledBy": "turnOffAI"}
                ]
            }"#,
        )
        .unwrap();
        let manifest = Manifest::load(&path).unwrap();

        // Turning briefLanguage OFF while turnOffAI is ON should NOT warn.
        assert!(notes(&manifest, &[true, true], &[true, false]).is_empty());
        // Turning briefLanguage ON while turnOffAI is ON SHOULD warn.
        let warnings = notes(&manifest, &[true, false], &[true, true]);
        assert_eq!(warnings.len(), 1);
        assert!(warnings[0].contains("Morning Brief Language"));
    }

    #[test]
    fn needs_relaunch_tracks_relaunch_app_icon_and_brief_language() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("patches.json");
        fs::write(
            &path,
            r#"{
                "version": 1,
                "patches": [
                    {"key": "turnOffAI", "title": "Turn Off AI", "detail": "A", "defaultOn": false, "requires": null, "disabledBy": null, "relaunch": true},
                    {"key": "appIcon", "title": "App Icon", "detail": "I", "defaultOn": false, "requires": null, "disabledBy": null},
                    {"key": "hideToolbar", "title": "Hide Toolbar", "detail": "H", "defaultOn": false, "requires": null, "disabledBy": null},
                    {"key": "briefLanguage", "title": "Morning Brief Language", "detail": "B", "defaultOn": false, "requires": null, "disabledBy": "turnOffAI"},
                    {"key": "hideChatButton", "title": "Hide Chat Button", "detail": "C", "defaultOn": false, "requires": null, "disabledBy": "hideToolbar", "coveredBy": "turnOffAI"}
                ]
            }"#,
        )
        .unwrap();
        let manifest = Manifest::load(&path).unwrap();

        assert!(needs_relaunch(&manifest, 0, true, false, false));
        assert!(needs_relaunch(&manifest, 0, false, true, true));
        assert!(needs_relaunch(&manifest, 1, true, false, false));
        assert!(!needs_relaunch(&manifest, 1, true, true, false));
        assert!(needs_relaunch(&manifest, 1, false, true, false));
        assert!(!needs_relaunch(&manifest, 1, false, false, false));
        assert!(!needs_relaunch(&manifest, 2, true, false, false));
        assert!(needs_relaunch(&manifest, 3, true, false, false));
        assert!(!needs_relaunch(&manifest, 3, true, false, true));
        assert!(needs_relaunch(&manifest, 3, false, false, true));
        assert!(!needs_relaunch(&manifest, 3, false, false, false));

        // coveredBy warns when enabling a tweak already covered by Turn Off AI (without duplicate disabledBy warning).
        let covered_notes = notes(
            &manifest,
            &[true, false, true, false, false],
            &[true, false, true, false, true],
        );
        assert_eq!(covered_notes, vec!["Turn Off AI hides Hide Chat Button too."]);
    }
}
