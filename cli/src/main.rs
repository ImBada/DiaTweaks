mod child;
mod config;
mod dia;
mod doctor;
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

use std::{
    io, panic,
    path::{Path, PathBuf},
    process::ExitCode,
};

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
    #[command(visible_alias = "ls")]
    List,
    /// Turn tweaks on, by key or title
    #[command(visible_aliases = ["on", "turn-on"])]
    Enable {
        #[arg(value_name = "TWEAK")]
        tweaks: Vec<String>,
    },
    /// Turn tweaks off, by key or title
    #[command(visible_aliases = ["off", "turn-off"])]
    Disable {
        #[arg(value_name = "TWEAK")]
        tweaks: Vec<String>,
    },
    /// Turn each tweak on if it's off, and off if it's on
    Toggle {
        #[arg(value_name = "TWEAK")]
        tweaks: Vec<String>,
    },
    /// Turn every tweak off, keeping their settings, until `diatweaks resume`
    Pause,
    /// Turn the tweaks back on as they were before `diatweaks pause`
    #[command(visible_alias = "unpause")]
    Resume,
    /// Show Dia's versions, safe mode and which tweaks are on
    #[command(visible_alias = "info")]
    Status,
    /// Check Dia and DiaTweaks, tidy up stopped updates, and say how to fix the rest
    #[command(visible_alias = "repair")]
    Doctor,
    /// Save your tweaks and settings to a file (`-` prints them instead)
    #[command(visible_alias = "backup")]
    Export {
        #[arg(value_name = "PATH")]
        path: Option<PathBuf>,
    },
    /// Load tweaks and settings from a file made by `diatweaks export`
    Import {
        #[arg(value_name = "PATH")]
        path: Option<PathBuf>,
        /// Also reset every tweak and setting the file doesn't mention
        #[arg(long)]
        replace: bool,
    },
    /// Install the latest DiaTweaks release, then patch Dia again
    Update,
    /// Download and patch a newer Dia
    UpdateDia,
    /// Put the original Dia back
    #[command(visible_alias = "uninstall")]
    Restore {
        /// Also delete DiaTweaks' files
        #[arg(long)]
        purge: bool,
    },
    /// Add, build, install and list tweaks you keep in your own folder
    Local {
        #[command(subcommand)]
        command: Option<LocalCommand>,
    },
    #[command(hide = true)]
    Add {
        #[arg(value_name = "PATH")]
        path: PathBuf,
    },
    #[command(hide = true)]
    Install {
        #[arg(required = true, value_name = "TWEAK")]
        names: Vec<String>,
    },
}

#[derive(Subcommand)]
enum LocalCommand {
    /// List the local tweaks and whether each built
    #[command(visible_alias = "ls")]
    List,
    /// List optional tweaks you can download from DiaTweaks
    #[command(visible_alias = "catalog")]
    Available,
    /// Download and build an optional tweak from DiaTweaks
    Install {
        #[arg(required = true, value_name = "TWEAK")]
        names: Vec<String>,
    },
    /// Copy a .m file, tweak folder, PR .patch, .zip, .dylib or GitHub link into the local folder
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
    #[command(visible_aliases = ["rm", "delete", "uninstall"])]
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
    let default_hook = panic::take_hook();
    panic::set_hook(Box::new(move |info| {
        let _ = console::Term::stderr().show_cursor();
        default_hook(info);
    }));
    let ui = Ui::new(cli.yes && cli.command.is_some());
    if let Err(err) = preflight() {
        ui.failed(&err);
        return ExitCode::FAILURE;
    }
    if cli.command.is_none() && !ui.interactive {
        let _ = Cli::command().write_help(&mut io::stderr());
        return ExitCode::from(2);
    }
    if !prints_plainly(&cli.command) && ui.interactive {
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

fn prints_plainly(command: &Option<Command>) -> bool {
    match command {
        Some(Command::List | Command::Status) | None => true,
        Some(Command::Export { path: Some(path) }) => path == Path::new("-"),
        _ => false,
    }
}

fn preflight() -> Result<()> {
    if unsafe { libc::geteuid() } == 0
        && std::env::var_os("DIATWEAKS_ALLOW_ROOT").is_none_or(|value| value != "1")
    {
        bail!("Don't run diatweaks with sudo or as root. It manages your own Dia and settings, so run it as yourself.");
    }
    signals::install()?;
    Ok(())
}

fn run(command: Option<Command>, ui: &Ui) -> Result<()> {
    let env = Env::load()?;
    let Some(command) = command else {
        return menu::run(&env, ui);
    };
    match command {
        Command::List => tweaks::list(&env),
        Command::Enable { tweaks } => tweaks::set(&env, ui, &tweaks, Some(true)),
        Command::Disable { tweaks } => tweaks::set(&env, ui, &tweaks, Some(false)),
        Command::Toggle { tweaks } => tweaks::set(&env, ui, &tweaks, None),
        Command::Pause => pause::set(&env, ui, true),
        Command::Resume => pause::set(&env, ui, false),
        Command::Status => status::print(&env, ui),
        Command::Doctor => doctor::run(&env, ui),
        Command::Export { path } => config::export(&env, ui, path),
        Command::Import { path, replace } => config::import(&env, ui, path, replace),
        Command::Update => update::run(&env, ui),
        Command::UpdateDia => update_dia::run(&env, ui),
        Command::Restore { purge } => restore::run(&env, ui, purge),
        Command::Add { path } => local::add(&env, ui, &path),
        Command::Install { names } => local::install_unless_built_in(&env, ui, &names),
        Command::Local { command } => match command.unwrap_or(LocalCommand::List) {
            LocalCommand::List => local::list(&env),
            LocalCommand::Available => local::available(&env, ui),
            LocalCommand::Install { names } => local::install(&env, ui, &names),
            LocalCommand::Add { path } => local::add(&env, ui, &path),
            LocalCommand::Build { names } => local::build(&env, ui, &names),
            LocalCommand::Remove { name } => local::remove(&env, ui, &name),
            LocalCommand::Open => local::open(&env),
            LocalCommand::Export { name } => local::export(&env, ui, &name),
            LocalCommand::Doctor => local::doctor(&env, ui),
        },
    }
}
