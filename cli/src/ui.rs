use std::{
    cell::Cell,
    fmt::Display,
    io::{self, IsTerminal, Write},
};

use anyhow::{Error, Result};
use cliclack::{Theme, ThemeState};

use crate::signals::{self, Cancelled};

pub struct Ui {
    pub interactive: bool,
    pub yes: bool,
    framed: Cell<bool>,
    in_menu: Cell<bool>,
}

impl Ui {
    pub fn new(yes: bool) -> Self {
        Self {
            interactive: io::stdin().is_terminal() && io::stderr().is_terminal(),
            yes,
            framed: Cell::new(false),
            in_menu: Cell::new(false),
        }
    }

    #[cfg(test)]
    pub fn headless(yes: bool) -> Self {
        Self {
            interactive: false,
            yes,
            framed: Cell::new(false),
            in_menu: Cell::new(false),
        }
    }

    pub fn intro(&self) {
        self.framed.set(true);
        cliclack::set_theme(Frame);
        let _ = cliclack::intro(console::style(" DiaTweaks ").reverse());
    }

    pub fn enter_menu(&self, in_menu: bool) {
        self.in_menu.set(in_menu);
    }

    pub fn info(&self, message: impl Display) {
        if self.framed.get() {
            let _ = cliclack::log::info(message);
        } else {
            say(message);
        }
    }

    pub fn remark(&self, message: impl Display) {
        if self.framed.get() {
            let _ = cliclack::log::remark(message);
        } else {
            say(message);
        }
    }

    pub fn success(&self, message: impl Display) {
        if self.framed.get() {
            let _ = cliclack::log::success(message);
        } else {
            say(message);
        }
    }

    pub fn warn(&self, message: impl Display) {
        if self.framed.get() {
            let _ = cliclack::log::warning(message);
        } else {
            complain(format_args!("warning: {message}"));
        }
    }

    pub fn error(&self, err: &Error) {
        if self.framed.get() {
            let _ = cliclack::log::error(describe(err));
        } else {
            complain(format_args!("diatweaks: {}", describe(err)));
        }
    }

    pub fn note(&self, title: impl Display, body: impl Display) {
        if self.framed.get() {
            let _ = cliclack::note(title, body);
        } else {
            say(body);
        }
    }

    pub fn done(&self, message: impl Display) {
        match (self.framed.get(), self.in_menu.get()) {
            (true, true) => drop(cliclack::log::success(message)),
            (true, false) => drop(cliclack::outro(message)),
            (false, _) => say(message),
        }
    }

    pub fn cancelled(&self, cancelled: &Cancelled) {
        if self.framed.get() {
            let _ = cliclack::outro_cancel(cancelled);
        } else {
            complain(cancelled);
        }
    }

    pub fn failed(&self, err: &Error) {
        if self.framed.get() {
            let _ = cliclack::outro_cancel(describe(err));
        } else {
            complain(format_args!("diatweaks: {}", describe(err)));
        }
    }

    pub fn spinner(&self, label: impl Display) -> Spinner {
        let label = label.to_string();
        let bar = self.framed.get().then(|| {
            let bar = cliclack::spinner();
            bar.start(&label);
            bar
        });
        Spinner { bar, label }
    }

    pub fn proceed(&self, question: impl Display) -> Result<bool> {
        if self.yes || !self.interactive {
            return Ok(true);
        }
        prompt(cliclack::confirm(question).initial_value(true).interact())
    }

    pub fn ask(&self, question: impl Display) -> Result<bool> {
        if self.yes || !self.interactive {
            return Ok(false);
        }
        prompt(cliclack::confirm(question).initial_value(true).interact())
    }

    pub fn choose(&self, question: impl Display, default: bool) -> Result<bool> {
        if self.yes {
            return Ok(true);
        }
        if !self.interactive {
            return Ok(false);
        }
        prompt(
            cliclack::confirm(question)
                .initial_value(default)
                .interact(),
        )
    }
}

struct Frame;

impl Theme for Frame {
    fn format_footer_with_message(&self, state: &ThemeState, message: &str) -> String {
        let line = match state {
            ThemeState::Active => format!("└  {message}"),
            ThemeState::Cancel | ThemeState::Submit => "│".into(),
            ThemeState::Error(err) => format!("└  {err}"),
        };
        format!("{}\n", self.bar_color(state).apply_to(line))
    }
}

pub fn prompt<T>(result: io::Result<T>) -> Result<T> {
    let cancelled = matches!(
        &result,
        Err(err) if matches!(err.kind(), io::ErrorKind::Interrupted | io::ErrorKind::UnexpectedEof)
    );
    if cancelled || signals::interrupted() {
        return Err(Cancelled::nothing_changed().into());
    }
    Ok(result?)
}

fn describe(err: &Error) -> String {
    let mut text = without_os_errors(&format!("{err:#}"));
    let denied = err.chain().any(|cause| {
        cause
            .downcast_ref::<io::Error>()
            .is_some_and(|io| io.kind() == io::ErrorKind::PermissionDenied)
    });
    if denied && !text.contains("sudo chown") {
        text.push_str("\nRun `diatweaks doctor` to see what's in the way.");
    }
    text
}

fn without_os_errors(text: &str) -> String {
    const MARK: &str = " (os error ";
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find(MARK) {
        out.push_str(&rest[..start]);
        let tail = &rest[start + MARK.len()..];
        let digits = tail.bytes().take_while(u8::is_ascii_digit).count();
        if digits > 0 && tail[digits..].starts_with(')') {
            rest = &tail[digits + 1..];
        } else {
            out.push_str(MARK);
            rest = tail;
        }
    }
    out.push_str(rest);
    out
}

// Output errors are ignored so a closed pipe never aborts a step mid-way.
pub fn say(message: impl Display) {
    let _ = writeln!(io::stdout().lock(), "{message}");
}

fn complain(message: impl Display) {
    let _ = writeln!(io::stderr().lock(), "{message}");
}

pub struct Spinner {
    bar: Option<cliclack::ProgressBar>,
    label: String,
}

impl Spinner {
    pub fn set_message(&self, message: impl Display) {
        if let Some(bar) = &self.bar {
            bar.set_message(message);
        }
    }

    pub fn stop(&self, message: impl Display) {
        match &self.bar {
            Some(bar) => bar.stop(message),
            None => say(message),
        }
    }

    pub fn check<T>(&self, result: Result<T>) -> Result<T> {
        result.map_err(|err| self.fail(err))
    }

    pub fn fail(&self, err: Error) -> Error {
        if let Some(bar) = &self.bar {
            if err.is::<Cancelled>() {
                bar.cancel(&self.label);
            } else {
                bar.error(&self.label);
            }
        }
        err
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use anyhow::Context;

    #[test]
    fn errors_read_without_os_error_codes() {
        let err = Err::<(), _>(io::Error::from_raw_os_error(libc::ENOENT))
            .context("Couldn't read /x")
            .unwrap_err();
        assert_eq!(
            describe(&err),
            "Couldn't read /x: No such file or directory"
        );
        assert_eq!(
            without_os_errors("a (os error x) b (os error 1)"),
            "a (os error x) b"
        );
    }

    #[test]
    fn permission_errors_point_at_doctor() {
        let err = Err::<(), _>(io::Error::from_raw_os_error(libc::EACCES))
            .context("Couldn't write /x")
            .unwrap_err();
        assert_eq!(
            describe(&err),
            "Couldn't write /x: Permission denied\nRun `diatweaks doctor` to see what's in the way."
        );
    }

    #[test]
    fn ask_never_answers_for_the_user() {
        assert!(!Ui::headless(true).ask("Did you mean x?").unwrap());
        assert!(!Ui::headless(false).ask("Did you mean x?").unwrap());
    }
}
