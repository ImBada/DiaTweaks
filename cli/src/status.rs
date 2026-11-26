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
    let manifest = Manifest::load_with_local(env)?;
    let status = Diapatch::find(env)?.status(spinner)?;
    let none = || "none".to_string();

    let installed = match &status.installed {
        Some(version) if status.patched => format!("{version}, patched"),
        Some(version) => format!("{version}, not patched"),
        None => format!("not installed at {}", env.app.display()),
    };
    let staged = match &status.staged {
        Some(version) => format!("{version}, installs when Dia quits"),
        None if env.staged().exists() => "incomplete — run `diatweaks update`".into(),
        None => none(),
    };
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
        format!(
            "DiaTweaks  {}",
            tweaks_version(status.release.as_deref(), COMMIT)
        ),
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

fn tweaks_version(release: Option<&str>, commit: &str) -> String {
    let short = commit.get(..7).unwrap_or(commit);
    match release.map(|tag| tag.trim().trim_start_matches('v')) {
        Some(version) if !version.is_empty() => format!("{version} ({short})"),
        _ => short.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SHA: &str = "abc1234def5678abc1234def5678abc1234def56";

    #[test]
    fn release_builds_show_their_version_and_commit() {
        assert_eq!(tweaks_version(Some("v1.2.0"), SHA), "1.2.0 (abc1234)");
        assert_eq!(tweaks_version(Some("1.2.0"), SHA), "1.2.0 (abc1234)");
    }

    #[test]
    fn dev_builds_show_only_the_commit() {
        assert_eq!(tweaks_version(None, SHA), "abc1234");
        assert_eq!(tweaks_version(Some(""), SHA), "abc1234");
        assert_eq!(tweaks_version(Some("v"), SHA), "abc1234");
        assert_eq!(tweaks_version(None, "unknown"), "unknown");
    }
}
