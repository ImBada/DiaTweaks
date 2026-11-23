use anyhow::Result;

use crate::{
    dia::{self, Diapatch, SafeMode},
    env::Env,
    manifest::Manifest,
    prefs::Prefs,
    tweaks::on_off,
    ui::{self, Spinner, Ui},
};

const COMMIT: &str = env!("DIATWEAKS_COMMIT");

pub fn print(env: &Env, ui: &Ui) -> Result<()> {
    let lines = report(env, &ui.spinner(""))?;
    ui::say(lines.join("\n"));
    Ok(())
}

pub fn show(env: &Env, ui: &Ui) -> Result<()> {
    let spinner = ui.spinner("Checking Dia");
    let lines = spinner.check(report(env, &spinner))?;
    spinner.stop("Checked Dia");
    ui.note("Status", lines.join("\n"));
    Ok(())
}

fn report(env: &Env, spinner: &Spinner) -> Result<Vec<String>> {
    let manifest = Manifest::load_with_local(&env.manifest(), &env.local_state())?;
    let status = Diapatch::find(env)?.status(spinner)?;
    let none = || "none".to_string();

    let installed = match &status.installed {
        Some(version) if status.patched => format!("{version}, patched"),
        Some(version) => format!("{version}, not patched"),
        None => format!("not installed at {}", env.app.display()),
    };
    let staged = status.staged.as_ref().map_or_else(none, |version| {
        format!("{version}, installs when Dia quits")
    });
    let latest = match &status.feed {
        Some(version) => format!("{version} on the {} channel", status.channel),
        None => "couldn't check (are you online?)".into(),
    };
    let safe_mode = match dia::safe_mode(&env.support) {
        SafeMode::Off => "off",
        SafeMode::TweaksOff => "on: tweaks are off because Dia quit unexpectedly right after opening",
        SafeMode::Parked => "on: DiaTweaks is off because Dia kept quitting right after opening, even after it was tried again; it stays off until the next DiaTweaks update",
        SafeMode::Disabled => "on: DiaTweaks is off because Dia kept quitting right after opening; it comes back with tweaks off after one launch where Dia stays open for three minutes or quits normally",
    };
    let paused = dia::is_paused(&env.support);
    let mut lines = vec![
        format!("Dia        {installed}"),
        format!("Official   {}", status.official.unwrap_or_else(none)),
        format!("Staged     {staged}"),
        format!("Latest     {latest}"),
        format!("Safe mode  {safe_mode}"),
        format!("DiaTweaks  {}", COMMIT.get(..7).unwrap_or(COMMIT)),
    ];
    if paused {
        lines.push("Paused     yes: every tweak is off and keeps its settings; run `diatweaks resume` to turn them back on".into());
    }
    lines.push(if paused {
        "Tweaks (paused: these settings come back with `diatweaks resume`)".into()
    } else {
        "Tweaks".into()
    });

    let state = manifest.state(&Prefs::new(&env.domain));
    for (index, &on) in state.iter().enumerate() {
        lines.push(format!(
            "  {:<4} {}",
            on_off(on),
            manifest.label(index, &state)
        ));
    }
    Ok(lines)
}
