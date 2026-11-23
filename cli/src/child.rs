use std::{
    ffi::OsStr,
    io::{Read, Seek, SeekFrom},
    mem,
    os::unix::{ffi::OsStrExt, process::CommandExt},
    path::{Path, PathBuf},
    process::{Command, ExitStatus, Stdio},
    thread,
    time::Duration,
};

use anyhow::{Context, Result};

use crate::{signals, ui::Spinner};

pub enum OnInterrupt {
    // Only curl is stopped; diapatch moves whole bundles that must finish.
    StopDownloads,
    Finish(&'static str),
}

pub struct Finished {
    pub status: ExitStatus,
    pub output: String,
}

impl Finished {
    pub fn tail(&self, count: usize) -> String {
        let lines: Vec<&str> = self
            .output
            .lines()
            .filter(|line| !line.trim().is_empty())
            .collect();
        if lines.is_empty() {
            return format!("It stopped with {} and printed nothing.", self.status);
        }
        lines[lines.len().saturating_sub(count)..].join("\n")
    }
}

// Unlinked file instead of a pipe so the child never dies of SIGPIPE if diatweaks is killed.
pub fn run(
    command: &mut Command,
    on_interrupt: OnInterrupt,
    spinner: &Spinner,
) -> Result<Finished> {
    let mut log = tempfile::tempfile().context("Couldn't create a temporary file")?;
    let mut child = command
        .process_group(0)
        .stdin(Stdio::null())
        .stdout(log.try_clone()?)
        .stderr(log.try_clone()?)
        .spawn()
        .with_context(|| {
            format!(
                "Couldn't run {}",
                Path::new(command.get_program()).display()
            )
        })?;
    let pid = child.id() as libc::pid_t;
    let mut stopping = false;
    let status = loop {
        if let Some(status) = child.try_wait()? {
            break status;
        }
        if signals::interrupted() {
            let (message, stop) = match on_interrupt {
                OnInterrupt::StopDownloads => ("Stopping after the current step…", true),
                OnInterrupt::Finish(why) => (why, false),
            };
            if !stopping {
                spinner.set_message(message);
                stopping = true;
            }
            if stop {
                stop_downloads(pid);
            }
        }
        thread::sleep(Duration::from_millis(50));
    };
    let mut bytes = Vec::new();
    log.seek(SeekFrom::Start(0))?;
    log.read_to_end(&mut bytes)?;
    Ok(Finished {
        status,
        output: String::from_utf8_lossy(&bytes).into_owned(),
    })
}

fn stop_downloads(parent: libc::pid_t) {
    let curl = Path::new("/usr/bin/curl");
    for pid in child_pids(parent) {
        if pid_path(pid).is_some_and(|path| path == curl) {
            unsafe { libc::kill(pid, libc::SIGTERM) };
        }
    }
}

fn child_pids(parent: libc::pid_t) -> Vec<libc::pid_t> {
    let mut pids = vec![0 as libc::pid_t; 256];
    let size = mem::size_of_val(pids.as_slice()) as libc::c_int;
    let count = unsafe { libc::proc_listchildpids(parent, pids.as_mut_ptr().cast(), size) };
    pids.truncate(count.max(0) as usize);
    pids
}

pub fn all_pids() -> Vec<libc::pid_t> {
    let capacity = unsafe { libc::proc_listallpids(std::ptr::null_mut(), 0) }.max(0) as usize + 64;
    let mut pids = vec![0 as libc::pid_t; capacity];
    let size = mem::size_of_val(pids.as_slice()) as libc::c_int;
    let count = unsafe { libc::proc_listallpids(pids.as_mut_ptr().cast(), size) };
    pids.truncate(count.max(0) as usize);
    pids
}

pub fn pid_path(pid: libc::pid_t) -> Option<PathBuf> {
    let mut buffer = [0u8; libc::PROC_PIDPATHINFO_MAXSIZE as usize];
    let length =
        unsafe { libc::proc_pidpath(pid, buffer.as_mut_ptr().cast(), buffer.len() as u32) };
    (length > 0).then(|| PathBuf::from(OsStr::from_bytes(&buffer[..length as usize])))
}

pub fn quick(command: &mut Command) -> Option<String> {
    let output = command
        .process_group(0)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).trim().to_string())
}
