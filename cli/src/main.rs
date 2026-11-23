mod child;
mod dia;
mod env;
mod local;
mod lock;
mod manifest;
mod menu;
mod pause;
mod prefs;
mod restore;
mod signals;
mod status;
mod tweaks;
mod ui;
mod update;
mod update_dia;

use std::{io, path::PathBuf, process::ExitCode};

use anyhow::{bail, Result};
use clap::{CommandFactory, Parser, Subcommand};

use crate::{env::Env, signals::Cancelled, ui::Ui};

/// Turn Dia tweaks on and off, and keep Dia and DiaTweaks up to date.
///
/// Run it without a command in a terminal for a menu.
#[derive(Parser)]
#[command(name = "diatweaks", version = env!("DIATWEAKS_VERSION"))]
struct Cli {
    /// Answer yes to every question
    #[arg(short, long, global = true)]
    yes: bool,

    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand)]
enum Command {
    /// List the tweaks and whether each is on
    List,
    /// Turn tweaks on, by key or title
    Enable {
        #[arg(required = true, value_name = "TWEAK")]
        tweaks: Vec<String>,
    },
    /// Turn tweaks off, by key or title
    Disable {
        #[arg(required = true, value_name = "TWEAK")]
        tweaks: Vec<String>,
    },
    /// Turn every tweak off, keeping their settings, until `diatweaks resume`
    Pause,
    /// Turn the tweaks back on as they were before `diatweaks pause`
    Resume,
    /// Show Dia's versions, safe mode and which tweaks are on
    Status,
    /// Install the latest DiaTweaks release, then patch Dia again
    Update,
    /// Download and patch a newer Dia
    UpdateDia,
    /// Put the original Dia back
    Restore {
        /// Also delete DiaTweaks' files
        #[arg(long)]
        purge: bool,
    },
    /// Add, build and list tweaks you keep in your own folder
    Local {
        #[command(subcommand)]
        command: Option<LocalCommand>,
    },
}

#[derive(Subcommand)]
enum LocalCommand {
    /// List the local tweaks and whether each built
    List,
    /// Copy a .m file, tweak folder, PR .patch, .zip or .dylib into the local folder
    Add {
        #[arg(value_name = "PATH")]
        path: PathBuf,
    },
    /// Compile the local tweaks now
    Build {
        #[arg(value_name = "NAME")]
        names: Vec<String>,
    },
    /// Move a local tweak to the Trash
    Remove {
        #[arg(value_name = "NAME")]
        name: String,
    },
    /// Show the local folder in Finder
    Open,
    /// Zip a local tweak so you can share it
    Export {
        #[arg(value_name = "NAME")]
        name: String,
    },
    /// Check the compiler, the SDK and every local tweak
    Doctor,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let ui = Ui::new(cli.yes && cli.command.is_some());
    if cli.command.is_none() && !ui.interactive {
        let _ = Cli::command().write_help(&mut io::stderr());
        return ExitCode::from(2);
    }
    if !matches!(cli.command, Some(Command::List | Command::Status) | None) && ui.interactive {
        ui.intro();
    }
    match run(cli.command, &ui) {
        Ok(()) if signals::interrupted() => ExitCode::from(130),
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => match err.downcast_ref::<Cancelled>() {
            Some(cancelled) => {
                ui.cancelled(cancelled);
                ExitCode::from(130)
            }
            None => {
                ui.failed(&err);
                ExitCode::FAILURE
            }
        },
    }
}

fn run(command: Option<Command>, ui: &Ui) -> Result<()> {
    if unsafe { libc::geteuid() } == 0 {
        bail!("Don't run diatweaks with sudo or as root. It manages your own Dia and settings.");
    }
    signals::install()?;
    let env = Env::load()?;
    let Some(command) = command else {
        return menu::run(&env, ui);
    };
    match command {
        Command::List => tweaks::list(&env),
        Command::Enable { tweaks } => tweaks::set(&env, ui, &tweaks, true),
        Command::Disable { tweaks } => tweaks::set(&env, ui, &tweaks, false),
        Command::Pause => pause::set(&env, ui, true),
        Command::Resume => pause::set(&env, ui, false),
        Command::Status => status::print(&env, ui),
        Command::Update => update::run(&env, ui),
        Command::UpdateDia => update_dia::run(&env, ui),
        Command::Restore { purge } => restore::run(&env, ui, purge),
        Command::Local { command } => match command.unwrap_or(LocalCommand::List) {
            LocalCommand::List => local::list(&env),
            LocalCommand::Add { path } => local::add(&env, ui, &path),
            LocalCommand::Build { names } => local::build(&env, ui, &names),
            LocalCommand::Remove { name } => local::remove(&env, ui, &name),
            LocalCommand::Open => local::open(&env),
            LocalCommand::Export { name } => local::export(&env, ui, &name),
            LocalCommand::Doctor => local::doctor(&env, ui),
        },
    }
}
