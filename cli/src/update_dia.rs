use anyhow::{anyhow, bail, Result};

use crate::{
    child::{Finished, OnInterrupt},
    dia::{self, Diapatch},
    env::Env,
    lock,
    signals::{self, Cancelled},
    ui::Ui,
};

const FINISHING: &str = "Finishing so Dia isn't left half-installed…";
const UNFINISHED: &str = "cleaned up an unfinished staged Dia update";

pub fn run(env: &Env, ui: &Ui) -> Result<()> {
    let diapatch = Diapatch::find(env)?;
    if !env.app.exists() {
        bail!(
            "Dia isn't installed at {}. Get it from https://www.diabrowser.com, then run {}.",
            env.app.display(),
            env.install_hint()
        );
    }
    let _lock = lock::acquire(env, ui)?;

    let spinner = ui.spinner("Checking for a newer Dia");
    let status = spinner.check(diapatch.status(&spinner))?;
    let ready = match status.staged {
        Some(staged) => {
            spinner.stop(format_args!("Dia {staged} is downloaded and ready"));
            staged
        }
        None => {
            let Some(official) = status.official else {
                return Err(spinner.fail(anyhow!(
                    "DiaTweaks has no copy of the official Dia. Run {} to set it up again.",
                    env.install_hint()
                )));
            };
            let Some(latest) = status.feed else {
                return Err(spinner.fail(anyhow!(
                    "Couldn't reach Dia's update feed. Check your internet connection, then try again."
                )));
            };
            if !dia::is_newer(&latest, &official) {
                spinner.stop(format_args!("Dia {official} is up to date"));
                if !status.patched {
                    ui.warn(
                        "Dia isn't patched right now. Run `diatweaks update` to patch it again.",
                    );
                }
                ui.done("Nothing to update.");
                return Ok(());
            }
            spinner.stop(format_args!("Dia {latest} is out (you have {official})"));
            if !ui.proceed(format_args!("Download Dia {latest} and patch it?"))? {
                return Err(Cancelled::nothing_changed().into());
            }
            download(env, ui, &diapatch, &latest)?
        }
    };
    install(env, ui, &diapatch, &ready)
}

fn download(env: &Env, ui: &Ui, diapatch: &Diapatch, latest: &str) -> Result<String> {
    let spinner = ui.spinner(format_args!(
        "Downloading and patching Dia {latest}. This can take a few minutes"
    ));
    let done = spinner.check(diapatch.run(&["update"], OnInterrupt::StopDownloads, &spinner))?;
    let staged = (done.status.success() || signals::interrupted())
        .then(|| {
            dia::staged_ready(&env.support)
                .then(|| dia::version_of(&env.staged()))
                .flatten()
        })
        .flatten();
    match (staged, signals::interrupted()) {
        (Some(staged), true) => Err(spinner.fail(
            Cancelled(format!(
                "Stopped after Dia {staged} was ready. It installs the next time you quit Dia."
            ))
            .into(),
        )),
        (None, true) => Err(spinner.fail(Cancelled::nothing_changed().into())),
        (Some(staged), false) => {
            spinner.stop(format_args!("Dia {staged} is ready"));
            Ok(staged)
        }
        (None, false) => Err(spinner.fail(done.failure("Couldn't update Dia:", 5, &env.support))),
    }
}

fn install(env: &Env, ui: &Ui, diapatch: &Diapatch, ready: &str) -> Result<()> {
    if signals::interrupted() {
        bail!(Cancelled(format!(
            "Stopped before installing. Dia {ready} installs the next time you quit Dia, or run `diatweaks update-dia`."
        )));
    }
    if !dia::is_running(&env.app) {
        let spinner = ui.spinner(format_args!("Installing Dia {ready}"));
        let done =
            spinner.check(diapatch.run(&["apply"], OnInterrupt::Finish(FINISHING), &spinner))?;
        if !done.status.success() {
            return Err(spinner.fail(done.failure("Couldn't install Dia:", 5, &env.support)));
        }
        spinner.check(installed(env, ready, &done))?;
        spinner.stop(format_args!("Installed Dia {ready}"));
        ui.done(format_args!("Dia {ready} is installed."));
        return Ok(());
    }
    if !ui.choose("Relaunch Dia now to install it?", true)? {
        if dia::is_patched(&env.app) {
            ui.done(format_args!(
                "Dia {ready} installs the next time you quit Dia."
            ));
        } else {
            ui.done(format_args!(
                "Quit Dia, then run `diatweaks update-dia` to install Dia {ready}."
            ));
        }
        return Ok(());
    }
    let spinner = ui.spinner(format_args!("Relaunching Dia to install {ready}"));
    spinner.check(dia::quit(&env.app))?;
    let done = spinner.check(diapatch.run(
        &["apply", "--relaunch"],
        OnInterrupt::Finish(FINISHING),
        &spinner,
    ))?;
    if !done.status.success() {
        return Err(spinner.fail(done.failure("Couldn't install Dia:", 5, &env.support)));
    }
    spinner.check(installed(env, ready, &done))?;
    spinner.stop(format_args!("Installed Dia {ready} and reopened it"));
    ui.done(format_args!("Dia {ready} is installed."));
    Ok(())
}

// diapatch apply exits 0 when it drops the staged build: it was unfinished, or Dia was replaced by hand.
fn installed(env: &Env, ready: &str, done: &Finished) -> Result<()> {
    if done.output.contains(UNFINISHED) {
        bail!(
            "Dia {ready} wasn't installed: its download hadn't finished, so DiaTweaks cleared it away and left your Dia as it was. Run `diatweaks update-dia` to download it again."
        );
    }
    let Some(now) = dia::version_of(&env.app) else {
        bail!(
            "Dia {ready} wasn't installed, and there is no Dia at {}. Get Dia from https://www.diabrowser.com, then run `diatweaks update`.",
            env.app.display()
        );
    };
    match (dia::is_patched(&env.app), now == ready) {
        (true, true) => Ok(()),
        (true, false) => bail!(
            "Dia {ready} wasn't installed. Dia {now} is in place instead. Run `diatweaks update-dia` to try again."
        ),
        (false, _) => bail!(
            "Dia {ready} wasn't installed. Dia {now} is still in place, and it isn't patched. Run `diatweaks update` to patch it."
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{fs, os::unix::process::ExitStatusExt, process::ExitStatus};

    fn applied(output: &str) -> Finished {
        Finished {
            status: ExitStatus::from_raw(0),
            output: output.into(),
        }
    }

    #[test]
    fn unfinished_downloads_are_not_reported_as_installed() {
        assert!(include_str!("../../src/diapatch/main.m").contains(UNFINISHED));
        let dir = tempfile::tempdir().unwrap();
        let env = Env::at(dir.path());
        let plist = |version: &str| {
            fs::create_dir_all(env.app.join("Contents")).unwrap();
            fs::write(
                env.app.join("Contents/Info.plist"),
                format!("<plist version=\"1.0\"><dict><key>CFBundleShortVersionString</key><string>{version}</string><key>CFBundleVersion</key><string>1</string><key>DiaPatches</key><true/></dict></plist>"),
            )
            .unwrap();
        };

        plist("2.0");
        assert!(installed(&env, "2.0 (1)", &applied("installed patched Dia 2.0 (1)")).is_ok());
        let err = installed(
            &env,
            "2.0 (1)",
            &applied("cleaned up an unfinished staged Dia update; run `diatweaks update` to stage it again"),
        )
        .unwrap_err()
        .to_string();
        assert!(
            err.contains("wasn't installed") && err.contains("`diatweaks update-dia`"),
            "{err}"
        );

        plist("1.0");
        let err = installed(&env, "2.0 (1)", &applied(""))
            .unwrap_err()
            .to_string();
        assert!(err.starts_with("Dia 2.0 (1) wasn't installed. Dia 1.0 (1) is in place instead."));
    }
}
