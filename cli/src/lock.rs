use std::{
    fs::{File, OpenOptions},
    io,
    os::fd::AsRawFd,
    thread,
    time::{Duration, Instant},
};

use anyhow::{bail, Context, Result};

use crate::{
    env::Env,
    signals::{self, Cancelled},
    ui::Ui,
};

pub struct Lock {
    _file: File,
}

pub fn acquire(env: &Env, ui: &Ui) -> Result<Lock> {
    acquire_within(env, ui, Duration::from_secs(5))
}

fn acquire_within(env: &Env, ui: &Ui, patience: Duration) -> Result<Lock> {
    let path = env.support.join(".diatweaks.lock");
    env.check_yours(&env.support)?;
    env.check_yours(&path)?;
    let file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(&path)
        .with_context(|| format!("Couldn't open {}", path.display()))?;
    let deadline = Instant::now() + patience;
    let mut waiting = false;
    loop {
        if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } == 0 {
            return Ok(Lock { _file: file });
        }
        let err = io::Error::last_os_error();
        match err.kind() {
            io::ErrorKind::Interrupted => continue,
            io::ErrorKind::WouldBlock => {}
            _ => return Err(err).with_context(|| format!("Couldn't lock {}", path.display())),
        }
        if signals::interrupted() {
            bail!(Cancelled::nothing_changed());
        }
        if Instant::now() >= deadline {
            bail!("Another DiaTweaks command is still running. Wait for it to finish, then try again.");
        }
        if !waiting {
            ui.info("Waiting for another DiaTweaks command to finish…");
            waiting = true;
        }
        thread::sleep(Duration::from_millis(100));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lock_waits_gives_up_and_is_released_on_drop() {
        let dir = tempfile::tempdir().unwrap();
        let env = Env::at(dir.path());
        let ui = Ui::headless(false);
        let first = acquire_within(&env, &ui, Duration::ZERO).unwrap();
        let started = Instant::now();
        let Err(err) = acquire_within(&env, &ui, Duration::from_millis(300)) else {
            panic!("a held lock was taken twice");
        };
        assert!(started.elapsed() >= Duration::from_millis(300));
        assert!(err.to_string().contains("still running"));
        drop(first);
        assert!(acquire_within(&env, &ui, Duration::ZERO).is_ok());
    }

    #[test]
    fn lock_waits_for_a_short_holder() {
        let dir = tempfile::tempdir().unwrap();
        let env = Env::at(dir.path());
        let ui = Ui::headless(false);
        let held = acquire_within(&env, &ui, Duration::ZERO).unwrap();
        let release = thread::spawn(move || {
            thread::sleep(Duration::from_millis(200));
            drop(held);
        });
        assert!(acquire_within(&env, &ui, Duration::from_secs(5)).is_ok());
        release.join().unwrap();
    }
}
