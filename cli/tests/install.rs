use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output},
};

const INSTALL: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../install.sh");

struct Installer {
    dir: tempfile::TempDir,
}

impl Installer {
    fn new() -> Self {
        let installer = Self {
            dir: tempfile::tempdir().unwrap(),
        };
        installer.stub("make", "echo make-ran; exit 97");
        installer
    }

    fn stub(&self, name: &str, script: &str) {
        let path = self.dir.path().join("stubs").join(name);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, format!("#!/bin/sh\n{script}\n")).unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    }

    fn support(&self) -> PathBuf {
        self.dir.path().join("support")
    }

    fn app(&self) -> PathBuf {
        self.dir.path().join("Dia.app")
    }

    fn fake_dia(&self) {
        let binary = self.app().join("Contents/MacOS/Dia");
        fs::create_dir_all(binary.parent().unwrap()).unwrap();
        fs::write(binary, "").unwrap();
    }

    fn run(&self, args: &[&str]) -> Output {
        self.command(args).output().unwrap()
    }

    fn command(&self, args: &[&str]) -> Command {
        let mut command = Command::new("/bin/sh");
        command
            .arg(INSTALL)
            .args(args)
            .env(
                "PATH",
                format!(
                    "{}:/usr/bin:/bin:/usr/sbin:/sbin",
                    self.dir.path().join("stubs").display()
                ),
            )
            .env("HOME", self.dir.path())
            .env("TMPDIR", "/tmp")
            .env("DIAPATCH_HOME", self.support())
            .env("DIAPATCH_APP", self.app())
            .env("DIAPATCH_NO_RELAUNCH", "1")
            .env("DIATWEAKS_DOMAIN", "com.diapatches.test.install")
            .env("DIATWEAKS_LINK_DIR", self.dir.path().join("links"))
            .env("DEVELOPER_DIR", "/Library/Developer/CommandLineTools")
            .env_remove("DIATWEAKS_ALLOW_ROOT")
            .env_remove("DIAPATCH_SKIP_APP_CHECK");
        command
    }
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

fn never_built(output: &Output) {
    assert!(!String::from_utf8_lossy(&output.stdout).contains("make-ran"));
}

#[test]
fn help_and_unknown_flags() {
    let installer = Installer::new();
    for flag in ["-h", "--help"] {
        let output = installer.run(&[flag]);
        assert_eq!(output.status.code(), Some(0));
        assert!(
            String::from_utf8_lossy(&output.stdout).starts_with("Usage: ./install.sh [-y|--yes]")
        );
    }
    let output = installer.run(&["--bogus"]);
    assert_eq!(output.status.code(), Some(2));
    assert!(stderr(&output).starts_with("Usage: ./install.sh"));
}

#[test]
fn refuses_to_run_as_root() {
    let installer = Installer::new();
    installer.stub("id", r#"case $1 in -u) echo 0 ;; *) echo root ;; esac"#);
    let output = installer.run(&["--yes"]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(
        stderr(&output),
        "Don't run install.sh with sudo — it installs into your own home folder. Run ./install.sh as yourself.\n"
    );
    never_built(&output);
}

#[test]
fn needs_macos_14() {
    let installer = Installer::new();
    installer.stub("sw_vers", "echo 13.6.1");
    let output = installer.run(&[]);
    assert_eq!(output.status.code(), Some(1));
    assert!(stderr(&output)
        .contains("DiaTweaks needs macOS 14 or later (this Mac is on macOS 13.6.1)."));
    never_built(&output);
}

#[test]
fn needs_the_command_line_tools() {
    let installer = Installer::new();
    installer.stub("xcode-select", "exit 2");
    let output = installer
        .command(&[])
        .env_remove("DEVELOPER_DIR")
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(
        stderr(&output),
        "DiaTweaks needs Apple's Command Line Tools. Run: xcode-select --install — then run ./install.sh again.\n"
    );
    never_built(&output);
}

#[test]
fn names_the_chown_for_folders_it_cannot_write() {
    let installer = Installer::new();
    let support = installer.support();
    fs::create_dir_all(support.join("bin")).unwrap();
    fs::set_permissions(support.join("bin"), fs::Permissions::from_mode(0o555)).unwrap();
    let output = installer.run(&[]);
    fs::set_permissions(support.join("bin"), fs::Permissions::from_mode(0o755)).unwrap();
    assert_eq!(output.status.code(), Some(1));
    let user = String::from_utf8(
        Command::new("/usr/bin/id")
            .arg("-un")
            .output()
            .unwrap()
            .stdout,
    )
    .unwrap();
    assert!(stderr(&output).contains(&format!(
        "  sudo chown -R \"{}\" \"{}\"\n",
        user.trim(),
        support.join("bin").display()
    )));
    never_built(&output);
}

#[test]
fn stops_before_building_without_dia() {
    let installer = Installer::new();
    let output = installer.run(&[]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(
        stderr(&output),
        "Dia isn't installed yet. Download it from https://www.diabrowser.com, move Dia.app to /Applications, and run ./install.sh again.\n"
    );
    never_built(&output);
}

#[test]
fn needs_an_apple_silicon_dia() {
    let installer = Installer::new();
    installer.fake_dia();
    installer.stub("lipo", "echo x86_64");
    let output = installer.run(&[]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(
        stderr(&output),
        "DiaTweaks requires Apple Silicon (arm64 Dia.app).\n"
    );
    never_built(&output);

    installer.stub("lipo", "echo x86_64 arm64");
    let output = installer.run(&[]);
    assert_eq!(output.status.code(), Some(97), "{}", stderr(&output));
    assert!(String::from_utf8_lossy(&output.stdout).ends_with("Building DiaTweaks...\nmake-ran\n"));
}

#[test]
fn ctrl_c_during_the_build_says_how_to_continue() {
    use std::{os::unix::process::CommandExt, thread, time::Duration};

    let installer = Installer::new();
    installer.fake_dia();
    installer.stub("lipo", "echo arm64");
    let started = installer.dir.path().join("make-started");
    installer.stub("make", &format!("touch '{}'; sleep 10", started.display()));
    let child = installer
        .command(&[])
        .process_group(0)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    for _ in 0..200 {
        if started.exists() {
            break;
        }
        thread::sleep(Duration::from_millis(25));
    }
    assert!(started.exists());
    unsafe { libc::kill(-(child.id() as libc::pid_t), libc::SIGINT) };
    let output = child.wait_with_output().unwrap();
    assert_eq!(output.status.code(), Some(130));
    let repo = std::fs::canonicalize(concat!(env!("CARGO_MANIFEST_DIR"), "/..")).unwrap();
    assert_eq!(
        stderr(&output),
        format!(
            "\nStopped. Nothing changed — run {}/install.sh whenever you want to continue.\n",
            repo.display()
        )
    );
}
