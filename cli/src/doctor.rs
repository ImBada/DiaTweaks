use std::{
    fmt::Display,
    fs::{self, File, OpenOptions},
    io,
    os::fd::AsRawFd,
    path::Path,
};

use anyhow::{bail, Result};

use crate::{
    dia::{self, Diapatch, SafeMode},
    env::Env,
    local,
    manifest::Manifest,
    tweaks,
    ui::Ui,
};

struct Report<'a> {
    ui: &'a Ui,
    problems: Vec<String>,
}

impl Report<'_> {
    fn fine(&self, message: impl Display) {
        self.ui.success(message);
    }

    fn note(&self, message: impl Display) {
        self.ui.warn(message);
    }

    fn problem(&mut self, message: impl Display) {
        self.problems.push(message.to_string());
    }
}

pub fn run(env: &Env, ui: &Ui) -> Result<()> {
    let mut report = Report {
        ui,
        problems: Vec::new(),
    };
    check_app(env, &mut report);
    if check_folder(env, &mut report) {
        check_install(env, &mut report);
        check_staged(env, &mut report);
        check_state(env, &report);
    }
    report.problems.extend(local::problems(env, ui));
    if report.problems.is_empty() {
        ui.done("Nothing to fix.");
        return Ok(());
    }
    for problem in &report.problems {
        ui.warn(problem);
    }
    match report.problems.len() {
        1 => bail!("Found 1 thing to fix."),
        count => bail!("Found {count} things to fix."),
    }
}

fn check_app(env: &Env, report: &mut Report) {
    let app = &env.app;
    if !app.exists() {
        return report.problem(format_args!(
            "There's no Dia at {}. Download it from https://www.diabrowser.com and move it to /Applications.",
            app.display()
        ));
    }
    if app.starts_with("/Volumes") {
        return report.problem(format_args!(
            "Dia is running from a disk image ({}). Drag Dia.app to /Applications first.",
            app.display()
        ));
    }
    if dia::is_arm64(app) == Some(false) {
        return report
            .problem("This Dia isn't built for Apple Silicon (arm64), which DiaTweaks needs.");
    }
    let version = dia::version_of(app).unwrap_or_else(|| "Dia".into());
    if !dia::is_patched(app) {
        return report.problem(format_args!(
            "Dia {version} at {} isn't patched. Run `diatweaks update` to patch it.",
            app.display()
        ));
    }
    report.fine(format_args!(
        "Dia {version} at {} is patched.",
        app.display()
    ));
}

fn check_folder(env: &Env, report: &mut Report) -> bool {
    let support = &env.support;
    if !support.is_dir() {
        report.problem(format_args!(
            "DiaTweaks isn't installed: {} is missing. Run {}.",
            support.display(),
            env.install_hint()
        ));
        return false;
    }
    let entries = fs::read_dir(support)
        .into_iter()
        .flatten()
        .flatten()
        .map(|entry| entry.path());
    let theirs = [support.clone(), support.join("bin")]
        .into_iter()
        .chain(entries)
        .find(|path| env.check_yours(path).is_err());
    match theirs {
        Some(path) => report.problem(env.not_yours(&path)),
        None => report.fine(format_args!("{} is yours and writable.", support.display())),
    }
    true
}

fn check_install(env: &Env, report: &mut Report) {
    if let Err(err) = Diapatch::find(env) {
        return report.problem(format_args!("{err:#}"));
    }
    match Manifest::load(env) {
        Ok(manifest) => report.fine(format_args!(
            "DiaTweaks is installed, with {} tweaks.",
            manifest.patches.len()
        )),
        Err(err) => report.problem(format_args!("{err:#}")),
    }
}

fn check_staged(env: &Env, report: &mut Report) {
    if env.staged().exists() && !dia::staged_ready(&env.support) {
        report
            .problem("A Dia update stopped before it finished. Run `diatweaks update` to redo it.");
    }
    let tweaks = env.support.join("staged/DiaTweaks");
    if !tweaks.join(".applying").exists() {
        return;
    }
    if tweaks.join("release.plist").exists() {
        return report
            .problem("A DiaTweaks update stopped partway. Run `diatweaks update` to finish it.");
    }
    let log = env.support.join("diapatch.log");
    let _idle = match diapatch_idle(&log) {
        DiapatchLock::Idle(idle) => idle,
        DiapatchLock::Busy => return report.note(
            "A DiaTweaks update is running right now. Run `diatweaks doctor` again once it's done.",
        ),
        DiapatchLock::Unavailable(err) => {
            return report.problem(format_args!(
                "Couldn't tidy up {} because {} can't be opened: {err}",
                tweaks.display(),
                log.display()
            ))
        }
    };
    match fs::remove_dir_all(&tweaks) {
        Ok(()) => report.fine("Cleaned up what a finished DiaTweaks update left behind."),
        Err(err) => report.problem(format_args!(
            "Couldn't clean up {}: {err}",
            tweaks.display()
        )),
    }
}

// diapatch holds an exclusive flock on its log for the whole run, so holding that lock means no run is underway.
enum DiapatchLock {
    // None: there's no log yet, so no run has ever started. A read-only check must not create one.
    Idle(Option<File>),
    Busy,
    Unavailable(io::Error),
}

fn diapatch_idle(log: &Path) -> DiapatchLock {
    let log = match OpenOptions::new().append(true).open(log) {
        Ok(log) => log,
        Err(err) if err.kind() == io::ErrorKind::NotFound => return DiapatchLock::Idle(None),
        Err(err) => return DiapatchLock::Unavailable(err),
    };
    if unsafe { libc::flock(log.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } == 0 {
        return DiapatchLock::Idle(Some(log));
    }
    let err = io::Error::last_os_error();
    if err.kind() == io::ErrorKind::WouldBlock {
        DiapatchLock::Busy
    } else {
        DiapatchLock::Unavailable(err)
    }
}

fn check_state(env: &Env, report: &Report) {
    if dia::is_paused(&env.support) {
        report.note("Tweaks are paused. Run `diatweaks resume` to turn them back on.");
    }
    if dia::safe_mode(&env.support) != SafeMode::Off {
        report.note(tweaks::where_it_shows(env));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn staged_leftovers_are_reported_or_cleaned() {
        let dir = tempfile::tempdir().unwrap();
        let env = Env::at(dir.path());
        let ui = Ui::headless(false);
        let mut report = Report {
            ui: &ui,
            problems: Vec::new(),
        };

        fs::create_dir_all(env.staged()).unwrap();
        let tweaks = dir.path().join("staged/DiaTweaks");
        fs::create_dir_all(&tweaks).unwrap();
        fs::write(tweaks.join(".applying"), "").unwrap();
        fs::write(tweaks.join("release.plist"), "").unwrap();
        check_staged(&env, &mut report);
        assert_eq!(report.problems.len(), 2);
        assert!(report
            .problems
            .iter()
            .all(|problem| problem.contains("diatweaks update")));

        report.problems.clear();
        fs::remove_dir(env.staged()).unwrap();
        fs::remove_file(tweaks.join("release.plist")).unwrap();
        // A live exclusive flock on the log means an update is running, so the leftovers stay for now.
        let log = dir.path().join("diapatch.log");
        fs::write(&log, "").unwrap();
        let busy = OpenOptions::new().append(true).open(&log).unwrap();
        assert_eq!(
            unsafe { libc::flock(busy.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) },
            0
        );
        check_staged(&env, &mut report);
        assert!(tweaks.exists());
        drop(busy);
        check_staged(&env, &mut report);
        assert!(!tweaks.exists());
        assert!(report.problems.is_empty());
    }

    #[test]
    fn an_unreadable_log_is_a_permission_problem_not_a_running_update() {
        use std::os::unix::fs::PermissionsExt;

        let dir = tempfile::tempdir().unwrap();
        let env = Env::at(dir.path());
        let ui = Ui::headless(false);
        let mut report = Report {
            ui: &ui,
            problems: Vec::new(),
        };
        let tweaks = dir.path().join("staged/DiaTweaks");
        fs::create_dir_all(&tweaks).unwrap();
        fs::write(tweaks.join(".applying"), "").unwrap();
        let log = dir.path().join("diapatch.log");
        fs::write(&log, "").unwrap();
        fs::set_permissions(&log, fs::Permissions::from_mode(0o000)).unwrap();

        check_staged(&env, &mut report);
        fs::set_permissions(&log, fs::Permissions::from_mode(0o644)).unwrap();
        assert!(
            tweaks.exists(),
            "leftovers stay while the log can't be read"
        );
        assert_eq!(report.problems.len(), 1, "{:?}", report.problems);
        assert!(report.problems[0].contains("can't be opened"));
        assert!(report.problems[0].contains("diapatch.log"));
    }

    #[test]
    fn a_folder_that_is_not_yours_names_the_fix() {
        use std::os::unix::fs::PermissionsExt;

        let dir = tempfile::tempdir().unwrap();
        let env = Env::at(dir.path());
        let ui = Ui::headless(false);
        let mut report = Report {
            ui: &ui,
            problems: Vec::new(),
        };
        let bin = dir.path().join("bin");
        fs::create_dir(&bin).unwrap();
        fs::set_permissions(&bin, fs::Permissions::from_mode(0o555)).unwrap();
        assert!(check_folder(&env, &mut report));
        fs::set_permissions(&bin, fs::Permissions::from_mode(0o755)).unwrap();
        assert_eq!(report.problems.len(), 1);
        assert!(report.problems[0].contains(&format!(
            "sudo chown -R \"$USER\" \"{}\"",
            dir.path().display()
        )));
    }
}
