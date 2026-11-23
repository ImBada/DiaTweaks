use anyhow::{anyhow, bail, Result};

use crate::{
    child::OnInterrupt,
    dia::Diapatch,
    env::Env,
    lock,
    signals::{self, Cancelled},
    ui::Ui,
};

const FINISHING: &str = "Finishing the install so Dia isn't left half-patched…";

pub fn run(env: &Env, ui: &Ui) -> Result<()> {
    let diapatch = Diapatch::find(env)?;
    if !env.app.exists() {
        bail!(
            "Dia isn't installed at {}. Get it from https://www.diabrowser.com first.",
            env.app.display()
        );
    }
    let _lock = lock::acquire(&env.support)?;
    if !ui.proceed("Update DiaTweaks? It installs the latest release, then reopens Dia.")? {
        return Err(Cancelled::nothing_changed().into());
    }

    let spinner = ui.spinner("Downloading the latest DiaTweaks");
    let download =
        spinner.check(diapatch.run(&["self-update"], OnInterrupt::StopDownloads, &spinner))?;
    if signals::interrupted() {
        return Err(spinner.fail(Cancelled::nothing_changed().into()));
    }
    if !download.status.success() {
        return Err(spinner.fail(anyhow!(
            "Couldn't update DiaTweaks. Check your internet connection, then try again.\n{}",
            download.tail(3)
        )));
    }
    let download_note = download.output.trim().lines().last().map(str::to_owned);
    let done = spinner.check(diapatch.run(
        &["apply", "--tweaks"],
        OnInterrupt::Finish(FINISHING),
        &spinner,
    ))?;
    if !done.status.success() {
        return Err(spinner.fail(anyhow!("Couldn't install DiaTweaks:\n{}", done.tail(3))));
    }
    spinner.stop(
        done.output
            .trim()
            .lines()
            .last()
            .or(download_note.as_deref())
            .unwrap_or("DiaTweaks is up to date"),
    );
    if signals::interrupted() {
        bail!(Cancelled(
            "Stopped after updating DiaTweaks. Run `diatweaks update` to patch Dia.".into()
        ));
    }

    let spinner = ui.spinner("Patching Dia and reopening it");
    let done = spinner.check(diapatch.run(
        &["install", "--relaunch"],
        OnInterrupt::Finish(FINISHING),
        &spinner,
    ))?;
    if !done.status.success() {
        return Err(spinner.fail(anyhow!("Couldn't patch Dia:\n{}", done.tail(12))));
    }
    spinner.stop("Patched Dia");
    ui.done("DiaTweaks is up to date.");
    Ok(())
}
