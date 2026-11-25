use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Output},
};

const PATCHES: &str = r#"{"version": 1, "patches": [
    {"key": "hideToolbar", "title": "Hide Toolbar", "detail": "H", "defaultOn": false, "requires": null, "disabledBy": null},
    {"key": "showAddressField", "title": "Show Address Field", "detail": "S", "defaultOn": false, "requires": null, "disabledBy": null}
]}"#;

struct Sandbox {
    dir: tempfile::TempDir,
    domain: String,
}

impl Sandbox {
    fn new(name: &str) -> Self {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("patches.json"), PATCHES).unwrap();
        Self {
            dir,
            domain: format!("com.diapatches.test.cli.{name}.{}", std::process::id()),
        }
    }

    fn path(&self) -> &Path {
        self.dir.path()
    }

    fn diapatch(&self, script: &str) {
        let path = self.path().join("bin/diapatch");
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, format!("#!/bin/sh\n{script}\n")).unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    }

    fn dia(&self, app: &Path, short: &str, build: &str) {
        fs::create_dir_all(app.join("Contents/MacOS")).unwrap();
        fs::write(
            app.join("Contents/Info.plist"),
            format!(
                "<plist version=\"1.0\"><dict><key>CFBundleExecutable</key><string>Dia</string><key>CFBundleShortVersionString</key><string>{short}</string><key>CFBundleVersion</key><string>{build}</string><key>DiaPatches</key><true/></dict></plist>"
            ),
        )
        .unwrap();
        let arm64 = [0xfeed_facf_u32.to_le_bytes(), 0x0100_000c_u32.to_le_bytes()].concat();
        fs::write(app.join("Contents/MacOS/Dia"), arm64).unwrap();
    }

    fn isolated(&self, mut command: Command) -> Command {
        command
            .current_dir(self.path())
            .env("HOME", self.path())
            .env("DIAPATCH_HOME", self.path())
            .env("DIATWEAKS_DOMAIN", &self.domain)
            .env_remove("DIATWEAKS_ALLOW_ROOT");
        command
    }

    fn command(&self, args: &[&str]) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_diatweaks"));
        command
            .args(args)
            .env("DIAPATCH_APP", self.path().join("Dia.app"));
        self.isolated(command)
    }

    fn run(&self, args: &[&str]) -> Output {
        self.command(args).output().unwrap()
    }

    // The real /Applications/Dia.app comes before ~/Applications, so it's hidden from the search.
    fn run_finding_dia(&self, args: &[&str]) -> Output {
        let mut command = Command::new("/usr/bin/sandbox-exec");
        command
            .args([
                "-p",
                r#"(version 1)(allow default)(deny file-read* file-write* (subpath "/Applications/Dia.app"))"#,
                env!("CARGO_BIN_EXE_diatweaks"),
            ])
            .args(args)
            .env_remove("DIAPATCH_APP");
        self.isolated(command).output().unwrap()
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = Command::new("/usr/bin/defaults")
            .args(["delete", &self.domain])
            .output();
        if let Ok(home) = std::env::var("HOME") {
            let _ = fs::remove_file(
                Path::new(&home).join(format!("Library/Preferences/{}.plist", self.domain)),
            );
        }
        let _ = Command::new("/bin/chmod")
            .args(["-R", "u+w"])
            .arg(self.dir.path())
            .output();
    }
}

fn out(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn err(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

#[test]
fn on_off_and_toggle_flip_tweaks() {
    let sandbox = Sandbox::new("flip");
    let on = sandbox.run(&["on", "hideToolbar", "Show Address Field"]);
    assert!(on.status.success(), "{}", err(&on));
    assert!(out(&on).contains("Turned on Hide Toolbar.\nTurned on Show Address Field.\n"));

    let toggled = sandbox.run(&["toggle", "hide-toolbar"]);
    assert!(toggled.status.success(), "{}", err(&toggled));
    assert!(out(&toggled).contains("Turned off Hide Toolbar."));

    let off = sandbox.run(&["turn-off", "hideToolbar"]);
    assert!(off.status.success());
    assert!(out(&off).contains("Hide Toolbar is already off.\nNothing to change."));

    let list = sandbox.run(&["ls"]);
    assert!(list.status.success());
    assert_eq!(
        out(&list),
        "off  hideToolbar       Hide Toolbar\non   showAddressField  Show Address Field\n"
    );
}

#[test]
fn naming_nothing_outside_a_terminal_explains_how() {
    let sandbox = Sandbox::new("nothing");
    for (args, example) in [(&["toggle"][..], "toggle"), (&["on"][..], "on")] {
        let output = sandbox.run(args);
        assert_eq!(output.status.code(), Some(1));
        assert!(err(&output).contains(&format!("like `diatweaks {example} hideToolbar`")));
        assert!(err(&output).contains("Run `diatweaks list` to see all tweaks."));
    }
}

#[test]
fn a_near_miss_is_never_accepted_for_the_user() {
    let sandbox = Sandbox::new("nearmiss");
    for args in [
        &["on", "hidetoolba"][..],
        &["--yes", "on", "hidetoolba"][..],
    ] {
        let output = sandbox.run(args);
        assert_eq!(output.status.code(), Some(1));
        assert_eq!(
            err(&output),
            "diatweaks: There's no tweak called \"hidetoolba\". Did you mean hideToolbar?\nRun `diatweaks list` to see all tweaks.\n"
        );
    }
    assert!(out(&sandbox.run(&["list"])).starts_with("off  hideToolbar"));
}

#[test]
fn changes_while_paused_point_at_resume_and_unpause_resumes() {
    let sandbox = Sandbox::new("paused");
    fs::write(sandbox.path().join("paused"), "").unwrap();
    let on = sandbox.run(&["on", "hideToolbar"]);
    assert!(on.status.success(), "{}", err(&on));
    assert!(out(&on).ends_with(
        "DiaTweaks is paused right now — run `diatweaks resume` so your changes take effect.\n"
    ));

    let resumed = sandbox.run(&["unpause"]);
    assert!(resumed.status.success(), "{}", err(&resumed));
    assert!(out(&resumed).starts_with("Tweaks are back on."));
    assert!(!sandbox.path().join("paused").exists());
}

#[test]
fn install_points_built_in_tweaks_at_on_and_forwards_the_rest() {
    let sandbox = Sandbox::new("install");
    sandbox.diapatch(r#"echo "diapatch $*""#);
    let output = sandbox.run(&["install", "Hide Toolbar", "mouseBackForward"]);
    assert!(output.status.success(), "{}", err(&output));
    assert_eq!(
        out(&output),
        "Hide Toolbar is already built into DiaTweaks — turn it on with: diatweaks on hideToolbar\ndiapatch local install mouseBackForward\n"
    );

    let only_built_in = sandbox.run(&["install", "hideToolbar"]);
    assert!(only_built_in.status.success());
    assert!(!out(&only_built_in).contains("diapatch"));
}

#[test]
fn add_at_the_top_level_is_local_add() {
    let sandbox = Sandbox::new("add");
    sandbox.diapatch(r#"printf '[%s]' "$@""#);
    let source = sandbox.path().join("Mine.m");
    fs::write(&source, "").unwrap();
    let output = sandbox.run(&["add", source.to_str().unwrap()]);
    assert!(output.status.success(), "{}", err(&output));
    assert_eq!(out(&output), "Added Mine.m.\n[local][build][Mine]\n");
}

#[test]
fn local_aliases_list_and_remove() {
    let sandbox = Sandbox::new("localalias");
    let local = sandbox.path().join("local");
    fs::create_dir_all(&local).unwrap();
    for name in ["A.m", "B.m", "C.m"] {
        fs::write(local.join(name), "").unwrap();
    }
    for (alias, name) in [("rm", "A"), ("delete", "B"), ("uninstall", "C")] {
        let output = sandbox.run(&["local", alias, name]);
        assert!(output.status.success(), "{alias}: {}", err(&output));
        assert!(!local.join(format!("{name}.m")).exists());
    }
    let listed = sandbox.run(&["local", "ls"]);
    assert!(listed.status.success());
    assert!(out(&listed).contains("There are no local tweaks."));
}

#[test]
fn status_reports_an_unfinished_staged_dia() {
    let sandbox = Sandbox::new("staged");
    sandbox.diapatch(
        r#"echo '{"official":"1.0 (1)","installed":"1.0 (1)","patched":true,"staged":null,"feed":null,"channel":"stable"}'"#,
    );
    let none = sandbox.run(&["info"]);
    assert!(none.status.success(), "{}", err(&none));
    assert!(out(&none).contains("Staged     none\n"));

    fs::create_dir_all(sandbox.path().join("staged/Dia.app")).unwrap();
    let incomplete = sandbox.run(&["status"]);
    assert!(out(&incomplete).contains("Staged     incomplete — run `diatweaks update`\n"));
}

#[test]
fn doctor_lists_what_to_fix() {
    let sandbox = Sandbox::new("doctor");
    sandbox.diapatch("exit 0");
    fs::write(sandbox.path().join("paused"), "").unwrap();
    let staged = sandbox.path().join("staged/DiaTweaks");
    fs::create_dir_all(&staged).unwrap();
    fs::write(staged.join(".applying"), "").unwrap();

    let output = sandbox.run(&["repair"]);
    assert_eq!(output.status.code(), Some(1));
    let (stdout, stderr) = (out(&output), err(&output));
    assert!(stdout.contains("DiaTweaks is installed, with 2 tweaks."));
    assert!(stdout.contains("Cleaned up what a finished DiaTweaks update left behind."));
    assert!(!staged.exists());
    assert!(stderr.contains("Run `diatweaks resume`"));
    assert!(stderr.contains(&format!(
        "There's no Dia at {}",
        sandbox.path().join("Dia.app").display()
    )));
    assert!(stderr.contains("diatweaks: Found "));
}

#[test]
fn a_folder_that_is_not_yours_names_the_chown() {
    let sandbox = Sandbox::new("chown");
    sandbox.diapatch("exit 0");
    fs::set_permissions(sandbox.path(), fs::Permissions::from_mode(0o555)).unwrap();
    let chown = format!("sudo chown -R \"$USER\" \"{}\"", sandbox.path().display());

    let on = sandbox.run(&["on", "hideToolbar"]);
    assert_eq!(on.status.code(), Some(1));
    assert!(err(&on).contains(&chown), "{}", err(&on));
    let doctor = sandbox.run(&["doctor"]);
    assert!(err(&doctor).contains(&chown), "{}", err(&doctor));

    fs::set_permissions(sandbox.path(), fs::Permissions::from_mode(0o755)).unwrap();
    assert!(out(&sandbox.run(&["list"])).starts_with("off  hideToolbar"));
}

#[test]
fn missing_files_name_the_install_script_that_was_used() {
    let sandbox = Sandbox::new("hint");
    fs::remove_file(sandbox.path().join("patches.json")).unwrap();
    let source = sandbox.path().join("checkout");
    fs::create_dir_all(&source).unwrap();
    fs::write(source.join("install.sh"), "").unwrap();
    fs::write(
        sandbox.path().join("source-dir"),
        format!("{}\n", source.display()),
    )
    .unwrap();
    let output = sandbox.run(&["list"]);
    assert_eq!(output.status.code(), Some(1));
    assert!(err(&output).contains(&format!(
        "is missing. Run {} first.",
        source.join("install.sh").display()
    )));
}

#[test]
fn errors_leave_out_os_error_codes() {
    let sandbox = Sandbox::new("oserror");
    let output = sandbox.run(&["local", "export", "Nothing"]);
    assert_eq!(output.status.code(), Some(1));
    assert!(err(&output).contains("No such file or directory"));
    assert!(!err(&output).contains("os error"));
}

#[test]
fn export_falls_back_to_the_current_folder() {
    let sandbox = Sandbox::new("export");
    let local = sandbox.path().join("local");
    fs::create_dir_all(&local).unwrap();
    fs::write(local.join("Mine.m"), "").unwrap();
    let desktop = sandbox.path().join("Desktop");
    fs::create_dir_all(&desktop).unwrap();
    fs::set_permissions(&desktop, fs::Permissions::from_mode(0o555)).unwrap();

    let output = sandbox.run(&["local", "export", "Mine"]);
    assert!(output.status.success(), "{}", err(&output));
    let saved: PathBuf = fs::canonicalize(sandbox.path()).unwrap().join("Mine.zip");
    assert!(saved.is_file());
    assert!(out(&output).contains(&format!("Exported {}.", saved.display())));
    assert!(err(&output).contains("Couldn't write to ~/Desktop"));
}

#[test]
fn local_add_only_downloads_github_links() {
    let sandbox = Sandbox::new("url");
    for url in [
        "https://example.com/Foo.m",
        "http://github.com/a/b/pull/1",
        "https://github.com/a/b/pull/latest",
    ] {
        let output = sandbox.run(&["local", "add", url]);
        assert_eq!(output.status.code(), Some(1));
        assert_eq!(
            err(&output),
            format!("diatweaks: Download that link first (curl -LO {url}), then run: diatweaks local add <file>\n")
        );
    }
}

#[test]
fn restore_answers_to_uninstall() {
    let sandbox = Sandbox::new("restore");
    sandbox.diapatch("echo should-not-run; exit 1");
    let output = sandbox.run(&["uninstall"]);
    assert_eq!(output.status.code(), Some(1));
    assert!(err(&output).contains("Restoring asks for confirmation"));
    assert!(!out(&output).contains("should-not-run"));
}

const RECORDING_DIAPATCH: &str = r#"echo "$DIAPATCH_APP" >> "$DIAPATCH_HOME/seen-app"
case "$1" in
status) echo '{"official":"1.0 (1)","installed":"1.0 (1)","patched":true,"staged":"2.0 (2)","feed":"2.0 (2)","channel":"stable"}' ;;
apply) /usr/bin/plutil -replace CFBundleShortVersionString -string 2.0 "$DIAPATCH_APP/Contents/Info.plist" &&
  /usr/bin/plutil -replace CFBundleVersion -string 2 "$DIAPATCH_APP/Contents/Info.plist" ;;
esac"#;

#[test]
fn status_doctor_and_update_dia_find_dia_where_diapatch_does() {
    for (name, place) in [
        ("remembered", "Elsewhere/Dia.app"),
        ("user", "Applications/Dia.app"),
    ] {
        let sandbox = Sandbox::new(name);
        sandbox.diapatch(RECORDING_DIAPATCH);
        let app = sandbox.path().join(place);
        sandbox.dia(&app, "1.0", "1");
        if name == "remembered" {
            fs::write(
                sandbox.path().join("dia-app"),
                format!("{}\n", app.display()),
            )
            .unwrap();
            sandbox.dia(&sandbox.path().join("Applications/Dia.app"), "0.9", "0");
        }

        let status = sandbox.run_finding_dia(&["status"]);
        assert!(status.status.success(), "{name}: {}", err(&status));
        assert!(out(&status).contains("Dia        1.0 (1), patched\n"));

        let doctor = sandbox.run_finding_dia(&["doctor"]);
        assert!(
            out(&doctor).contains(&format!("Dia 1.0 (1) at {} is patched.", app.display())),
            "{name}: {}{}",
            out(&doctor),
            err(&doctor)
        );

        let update = sandbox.run_finding_dia(&["update-dia"]);
        assert!(update.status.success(), "{name}: {}", err(&update));
        assert!(out(&update).contains("Dia 2.0 (2) is installed."));

        let seen = fs::read_to_string(sandbox.path().join("seen-app")).unwrap();
        assert!(seen.lines().count() >= 3, "{name}: {seen}");
        assert!(
            seen.lines().all(|line| Path::new(line) == app),
            "{name}: {seen}"
        );
    }
}

#[test]
fn update_dia_says_when_apply_dropped_an_unfinished_download() {
    let sandbox = Sandbox::new("unfinished");
    sandbox.dia(&sandbox.path().join("Dia.app"), "1.0", "1");
    sandbox.diapatch(
        r#"case "$1" in
status) echo '{"official":"1.0 (1)","installed":"1.0 (1)","patched":true,"staged":"2.0 (2)","feed":"2.0 (2)","channel":"stable"}' ;;
apply) echo 'cleaned up an unfinished staged Dia update; run `diatweaks update` to stage it again' ;;
esac"#,
    );
    let output = sandbox.run(&["update-dia"]);
    assert_eq!(output.status.code(), Some(1));
    assert!(!out(&output).contains("is installed"), "{}", out(&output));
    assert!(err(&output).contains("Dia 2.0 (2) wasn't installed: its download hadn't finished"));
    assert!(err(&output).contains("Run `diatweaks update-dia` to download it again."));
}
