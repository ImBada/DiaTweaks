use std::{
    fs,
    path::{Path, PathBuf},
};

use anyhow::{bail, Result};

use crate::{
    child::OnInterrupt,
    dia::{self, Diapatch},
    env::Env,
    lock,
    signals::Cancelled,
    ui::{self, Ui},
};

// Stash staged-update markers while quitting Dia so DPInstallOnQuit doesn't spawn a racing `diapatch apply`.
struct StagedMarkers(Vec<(PathBuf, PathBuf)>);

impl StagedMarkers {
    fn stash(support: &Path) -> Self {
        let mut stashed = Vec::new();
        for (rel, tmp) in [
            ("staged/ready", "staged/.ready.restore"),
            (
                "staged/DiaTweaks/release.plist",
                "staged/DiaTweaks/.release.plist.restore",
            ),
        ] {
            let src = support.join(rel);
            let dst = support.join(tmp);
            if fs::rename(&src, &dst).is_ok() {
                stashed.push((src, dst));
            }
        }
        Self(stashed)
    }

    fn restore(self) {
        for (src, dst) in self.0 {
            let _ = fs::rename(dst, src);
        }
    }

    fn discard(self) {
        for (_, dst) in self.0 {
            let _ = fs::remove_file(dst);
        }
    }
}

pub fn run(env: &Env, ui: &Ui, mut purge: bool) -> Result<()> {
    let diapatch = Diapatch::find(env)?;
    if !ui.interactive && !ui.yes {
        bail!("Restoring asks for confirmation. Run it in a terminal, or add --yes.");
    }
    if !ui.yes {
        let restore = ui::prompt(
            cliclack::confirm(
                "Restore the original Dia? It goes back to updating itself, without tweaks.",
            )
            .initial_value(false)
            .interact(),
        )?;
        if !restore {
            return Err(Cancelled::nothing_changed().into());
        }
        if !purge {
            purge = ui::prompt(
                cliclack::confirm(
                    "Also delete DiaTweaks' files? You'd need install.sh to patch Dia again.",
                )
                .initial_value(false)
                .interact(),
            )?;
        }
        let what = if purge {
            "Dia quits, reopens as the original app, and DiaTweaks' files are deleted."
        } else {
            "Dia quits and reopens as the original app."
        };
        let sure = ui::prompt(
            cliclack::confirm(format!("Are you sure? {what}"))
                .initial_value(false)
                .interact(),
        )?;
        if !sure {
            return Err(Cancelled::nothing_changed().into());
        }
    }
    let _lock = lock::acquire(env, ui)?;

    let spinner = ui.spinner("Restoring the original Dia");
    let was_running = dia::is_running(&env.app);
    if was_running {
        let markers = StagedMarkers::stash(&env.support);
        if let Err(err) = dia::quit(&env.app) {
            markers.restore();
            return Err(spinner.fail(err));
        }
        markers.discard();
    }
    let mut args = vec!["uninstall"];
    if was_running {
        args.push("--relaunch");
    }
    if purge {
        args.push("--purge");
    }
    let done = spinner.check(diapatch.run(
        &args,
        OnInterrupt::Finish("Finishing so Dia isn't left half-restored…"),
        &spinner,
    ))?;
    if !done.status.success() {
        return Err(spinner.fail(done.failure("Couldn't restore Dia:", 5, &env.support)));
    }
    let label = match dia::version_of(&env.app) {
        Some(version) => format!("the original Dia {version}"),
        None => "the original Dia".into(),
    };
    spinner.stop(if was_running {
        format!("Restored {label} and reopened it")
    } else {
        format!("Restored {label}")
    });
    ui.done(if purge {
        "DiaTweaks is removed. Your tweak settings stay in case you install it again."
    } else {
        "Dia is the original app again. Run `diatweaks update` to patch it again."
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn staged_markers_stash_restores_on_cancel_and_discards_on_quit() {
        let dir = tempfile::tempdir().unwrap();
        let ready = dir.path().join("staged/ready");
        let tweaks = dir.path().join("staged/DiaTweaks/release.plist");
        fs::create_dir_all(tweaks.parent().unwrap()).unwrap();
        fs::write(&ready, "12345").unwrap();
        fs::write(&tweaks, "plist").unwrap();

        let stashed = StagedMarkers::stash(dir.path());
        assert!(!ready.exists());
        assert!(!tweaks.exists());
        stashed.restore();
        assert_eq!(fs::read_to_string(&ready).unwrap(), "12345");
        assert_eq!(fs::read_to_string(&tweaks).unwrap(), "plist");

        let stashed = StagedMarkers::stash(dir.path());
        stashed.discard();
        assert!(!ready.exists());
        assert!(!tweaks.exists());
        assert!(!dir.path().join("staged/.ready.restore").exists());
        assert!(!dir
            .path()
            .join("staged/DiaTweaks/.release.plist.restore")
            .exists());
    }
}
