use std::{fs, io};

use anyhow::{Context, Result};

use crate::{
    dia,
    env::Env,
    lock,
    manifest::Manifest,
    prefs::{self, Prefs},
    tweaks,
    ui::Ui,
};

pub fn set(env: &Env, ui: &Ui, paused: bool) -> Result<()> {
    let manifest = Manifest::load(env)?;
    let _lock = lock::acquire(env, ui)?;
    if dia::is_paused(&env.support) == paused {
        ui.done(if paused {
            "Tweaks are already paused."
        } else {
            "Tweaks aren't paused."
        });
        return Ok(());
    }

    let file = env.support.join("paused");
    if paused {
        fs::write(&file, b"").with_context(|| format!("Couldn't write {}", file.display()))?;
    } else {
        match fs::remove_file(&file) {
            Ok(()) => {}
            Err(err) if err.kind() == io::ErrorKind::NotFound => {}
            Err(err) => {
                return Err(err).with_context(|| format!("Couldn't delete {}", file.display()));
            }
        }
    }
    let state = manifest.state(&Prefs::new(&env.domain));
    let app_icon_on = manifest.index("appIcon").is_some_and(|index| state[index]);
    if app_icon_on {
        dia::sync_icon(env);
    }
    prefs::notify(&env.domain)?;

    if !paused {
        ui.success("Tweaks are back on.");
        if app_icon_on
            && !dia::is_live(env)
            && dia::tweaks_active(env)
            && !dia::has_linked_icon_catalog(&env.app)
        {
            ui.warn(
                "App Icon needs a rebuild to link Dia's asset catalog. Run `diatweaks update` to apply it.",
            );
        }
        ui.done(where_resumed(env));
        return Ok(());
    }

    let on: Vec<usize> = (0..state.len()).filter(|&index| state[index]).collect();
    match on.len() {
        0 => ui.success("Paused. No tweaks were on."),
        1 => ui.success("Paused 1 tweak. Its settings are kept."),
        count => ui.success(format_args!(
            "Paused {count} tweaks. Their settings are kept."
        )),
    }
    let waiting: Vec<&str> = if dia::is_live(env) {
        on.iter()
            .filter(|&&index| manifest.patches[index].relaunch)
            .map(|&index| manifest.title(index))
            .collect()
    } else {
        Vec::new()
    };
    if waiting.is_empty() {
        ui.done(tweaks::where_it_shows(env));
        return Ok(());
    }
    ui.warn(format_args!(
        "Relaunch Dia to finish: {}.",
        waiting.join(", ")
    ));
    ui.done("Dia shows the rest now.");
    Ok(())
}

// A Dia launched while paused has no hooks installed, so resuming always needs a relaunch.
fn where_resumed(env: &Env) -> String {
    if dia::is_live(env) {
        return "Relaunch Dia to finish.".into();
    }
    tweaks::where_it_shows(env)
}
