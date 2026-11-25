use std::{
    fs,
    io::Write,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
};

use serde_json::{json, Value};

const PATCHES: &str = r#"{"version": 1, "patches": [
    {"key": "hideToolbar", "title": "Hide Toolbar", "detail": "H", "defaultOn": false, "requires": null, "disabledBy": null, "experimental": true},
    {"key": "localTweaks", "title": "Local Tweaks", "detail": "T", "defaultOn": true, "requires": null, "disabledBy": null},
    {"key": "showAddressField", "title": "Show Address Field", "detail": "S", "defaultOn": false, "requires": null, "disabledBy": null},
    {"key": "windowMaterial", "title": "Window Material", "detail": "W", "defaultOn": true, "requires": null, "disabledBy": null,
     "choice": {"key": "windowMaterialChoice", "default": "glass.17", "values": ["glass.17", "material.1"]},
     "settings": [
        {"key": "windowCornerRadius", "type": "number", "default": 26, "min": 0, "max": 26},
        {"key": "windowShadow", "type": "bool", "default": true},
        {"key": "futureSetting", "type": "dial", "default": 1}
     ]},
    {"key": "pinTab", "title": "Pin Tab Shortcut", "detail": "P", "defaultOn": false, "requires": null, "disabledBy": null,
     "shortcut": {"key": "pinTabShortcutKey", "default": {"keyCode": 2, "modifiers": 1048576, "key": "D"}}},
    {"key": "launchFlags", "title": "Launch Flags", "detail": "L", "defaultOn": false, "requires": null, "disabledBy": null, "relaunch": true,
     "settings": [{"key": "launchFlagsArgs", "type": "string", "default": ""}]}
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
            domain: format!("com.diapatches.test.config.{name}.{}", std::process::id()),
        }
    }

    fn path(&self) -> &Path {
        self.dir.path()
    }

    fn command(&self, args: &[&str]) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_diatweaks"));
        command
            .args(args)
            .current_dir(self.path())
            .env("HOME", self.path())
            .env("DIAPATCH_HOME", self.path())
            .env("DIAPATCH_APP", self.path().join("Dia.app"))
            .env("DIATWEAKS_DOMAIN", &self.domain)
            .env_remove("DIATWEAKS_ALLOW_ROOT");
        command
    }

    fn run(&self, args: &[&str]) -> Output {
        self.command(args).output().unwrap()
    }

    fn run_with_stdin(&self, args: &[&str], input: &str) -> Output {
        let mut child = self
            .command(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(input.as_bytes())
            .unwrap();
        child.wait_with_output().unwrap()
    }

    fn defaults(&self, args: &[&str]) -> Output {
        Command::new("/usr/bin/defaults")
            .args([args[0], &self.domain])
            .args(&args[1..])
            .output()
            .unwrap()
    }

    fn saved(&self, key: &str) -> Option<String> {
        let output = self.defaults(&["read", key]);
        output
            .status
            .success()
            .then(|| out(&output).trim().to_string())
    }

    fn snapshot(&self) -> String {
        out(&self.defaults(&["export", "-"]))
    }

    fn exported(&self) -> Value {
        let output = self.run(&["export", "-"]);
        assert!(output.status.success(), "{}", err(&output));
        serde_json::from_slice(&output.stdout).unwrap()
    }

    fn write(&self, name: &str, content: &Value) -> PathBuf {
        let path = self.path().join(name);
        fs::write(&path, content.to_string()).unwrap();
        path
    }

    fn import(&self, content: &Value, extra: &[&str]) -> Output {
        let path = self.write("in.json", content);
        let mut args = vec!["import", path.to_str().unwrap()];
        args.extend_from_slice(extra);
        self.run(&args)
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = Command::new("/usr/bin/defaults")
            .args(["delete", &self.domain])
            .output();
        let plist = format!("Library/Preferences/{}.plist", self.domain);
        let _ = fs::remove_file(Path::new(&std::env::var("HOME").unwrap()).join(plist));
        let _ = Command::new("/bin/chmod")
            .args(["-R", "u+w"])
            .arg(self.path())
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
fn export_is_sorted_deterministic_and_leaves_no_temp_files() {
    let sandbox = Sandbox::new("deterministic");
    sandbox.run(&["on", "showAddressField"]);
    let first = sandbox.run(&["export"]);
    assert!(first.status.success(), "{}", err(&first));
    assert!(out(&first).contains("Saved 5 tweaks and 0 settings to"));

    let file = sandbox.path().join("diatweaks-config.json");
    let bytes = fs::read(&file).unwrap();
    assert_eq!(
        String::from_utf8(bytes.clone()).unwrap(),
        "{\n  \"version\": 1,\n  \"tweaks\": {\n    \"hideToolbar\": false,\n    \"launchFlags\": false,\n    \"pinTab\": false,\n    \"showAddressField\": true,\n    \"windowMaterial\": true\n  },\n  \"settings\": {}\n}\n"
    );
    assert_eq!(
        fs::metadata(&file).unwrap().permissions().mode() & 0o777,
        0o644
    );

    assert!(sandbox.run(&["export"]).status.success());
    assert_eq!(fs::read(&file).unwrap(), bytes);
    let names: Vec<_> = fs::read_dir(sandbox.path())
        .unwrap()
        .map(|entry| entry.unwrap().file_name().into_string().unwrap())
        .filter(|name| name.starts_with('.') && name != ".diatweaks.lock")
        .collect();
    assert!(names.is_empty(), "{names:?}");
}

#[test]
fn export_dash_prints_only_json_and_writes_no_file() {
    let sandbox = Sandbox::new("stdout");
    let output = sandbox.run(&["export", "-"]);
    assert!(output.status.success());
    assert_eq!(err(&output), "");
    let text = out(&output);
    assert!(text.ends_with("}\n"));
    let parsed: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(parsed["version"], 1);
    assert!(!sandbox.path().join("diatweaks-config.json").exists());

    let file = sandbox.path().join("saved.json");
    assert!(sandbox
        .run(&["backup", file.to_str().unwrap()])
        .status
        .success());
    assert_eq!(fs::read_to_string(file).unwrap(), text);
}

#[test]
fn export_into_a_folder_and_through_a_symlink() {
    let sandbox = Sandbox::new("targets");
    fs::create_dir(sandbox.path().join("dotfiles")).unwrap();
    assert!(sandbox.run(&["export", "dotfiles"]).status.success());
    let real = sandbox.path().join("dotfiles/diatweaks-config.json");
    assert!(real.is_file());

    let link = sandbox.path().join("link.json");
    std::os::unix::fs::symlink(&real, &link).unwrap();
    sandbox.run(&["on", "showAddressField"]);
    assert!(sandbox.run(&["export", "link.json"]).status.success());
    assert!(fs::symlink_metadata(&link)
        .unwrap()
        .file_type()
        .is_symlink());
    assert!(fs::read_to_string(real)
        .unwrap()
        .contains("\"showAddressField\": true"));
}

#[test]
fn export_explains_missing_and_locked_folders() {
    let sandbox = Sandbox::new("unwritable");
    let missing = sandbox.run(&["export", "nowhere/config.json"]);
    assert_eq!(missing.status.code(), Some(1));
    assert!(err(&missing).contains("doesn't exist. Make it first, or pick another path."));

    let locked = sandbox.path().join("locked");
    fs::create_dir(&locked).unwrap();
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o555)).unwrap();
    let denied = sandbox.run(&["export", "locked/config.json"]);
    assert_eq!(denied.status.code(), Some(1));
    assert!(err(&denied).contains("can't write to"), "{}", err(&denied));
    assert!(!err(&denied).contains("sudo chown"));
}

#[test]
fn export_reports_only_what_was_saved_and_rounds_floats() {
    let sandbox = Sandbox::new("saved");
    for args in [
        &["write", "windowMaterialChoice", "material.1"][..],
        &["write", "windowCornerRadius", "-float", "0.24"],
        &["write", "windowShadow", "-bool", "NO"],
        &["write", "launchFlagsArgs", "--disable-gpu"],
        &[
            "write",
            "pinTabShortcutKey",
            "-dict",
            "key",
            "D",
            "keyCode",
            "-int",
            "2",
            "modifiers",
            "-int",
            "1048576",
        ],
        &["write", "profileColors", "-dict", "a", "#112233"],
    ] {
        assert!(sandbox.defaults(args).status.success());
    }
    assert_eq!(
        sandbox.exported()["settings"],
        json!({
            "launchFlagsArgs": "--disable-gpu",
            "pinTabShortcutKey": {"key": "D", "keyCode": 2, "modifiers": 1048576},
            "windowCornerRadius": 0.24,
            "windowMaterialChoice": "material.1",
            "windowShadow": false,
        })
    );
}

#[test]
fn export_leaves_out_settings_an_import_would_refuse() {
    let sandbox = Sandbox::new("leftout");
    sandbox.defaults(&["write", "launchFlagsArgs", "--ok broken"]);
    sandbox.defaults(&[
        "write",
        "pinTabShortcutKey",
        "-dict",
        "key",
        "D",
        "keyCode",
        "-int",
        "99999",
        "modifiers",
        "-int",
        "1048576",
    ]);
    sandbox.defaults(&["write", "windowShadow", "-dict", "key", "D"]);
    let output = sandbox.run(&["export", "-"]);
    assert!(output.status.success());
    assert!(err(&output).contains("Left out launchFlagsArgs"));
    assert!(err(&output).contains("Left out pinTabShortcutKey"));
    let parsed: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(parsed["settings"], json!({}));
}

#[test]
fn merge_import_keeps_everything_the_file_does_not_mention() {
    let sandbox = Sandbox::new("merge");
    sandbox.run(&["on", "showAddressField"]);
    sandbox.defaults(&["write", "windowCornerRadius", "-int", "10"]);
    sandbox.defaults(&["write", "profileColors", "-dict", "a", "#112233"]);

    let output = sandbox.import(&json!({"version": 1, "tweaks": {"hideToolbar": true}}), &[]);
    assert!(output.status.success(), "{}", err(&output));
    assert!(out(&output).contains("Turned on Hide Toolbar."));
    assert!(out(&output).contains("Imported"));

    let now = sandbox.exported();
    assert_eq!(now["tweaks"]["hideToolbar"], true);
    assert_eq!(now["tweaks"]["showAddressField"], true);
    assert_eq!(now["settings"]["windowCornerRadius"], 10);
    assert!(sandbox.saved("profileColors").is_some());
}

#[test]
fn replace_import_resets_portable_keys_and_nothing_else() {
    let sandbox = Sandbox::new("replace");
    sandbox.run(&["on", "showAddressField", "hideToolbar"]);
    sandbox.run(&["off", "windowMaterial"]);
    for args in [
        &["write", "windowCornerRadius", "-int", "10"][..],
        &["write", "windowMaterialChoice", "material.1"],
        &["write", "pinTabShortcutKey", "-dict"],
        &["write", "profileColors", "-dict", "a", "#112233"],
        &["write", "profileEmojis", "-dict", "a", "x"],
        &["write", "sidebarGrainProfiles", "-array", "a"],
        &["write", "collapsedPinned", "-array", "a"],
        &["write", "localTweaks", "-dict", "a", "b"],
        &["write", "someLocalTweak", "-bool", "YES"],
        &["write", "launchFlagsApplied", "-string", "--x"],
        &["write", "commandBarChatLocked", "-bool", "YES"],
        &["write", "littleDiaFrame", "-string", "1 2 3 4"],
        &["write", "autoUpdateDia", "-bool", "YES"],
        &["write", "autoUpdateTweaks", "-bool", "YES"],
        &["write", "showExperimentalTweaks", "-bool", "YES"],
    ] {
        assert!(sandbox.defaults(args).status.success());
    }
    let kept: Vec<_> = [
        "profileColors",
        "profileEmojis",
        "sidebarGrainProfiles",
        "collapsedPinned",
        "localTweaks",
        "someLocalTweak",
        "launchFlagsApplied",
        "commandBarChatLocked",
        "littleDiaFrame",
        "autoUpdateDia",
        "autoUpdateTweaks",
        "showExperimentalTweaks",
    ]
    .iter()
    .map(|key| (*key, sandbox.saved(key).unwrap()))
    .collect();

    let output = sandbox.import(
        &json!({"version": 1, "tweaks": {"hideToolbar": false}, "settings": {"windowShadow": false}}),
        &["--replace"],
    );
    assert!(output.status.success(), "{}", err(&output));
    assert!(out(&output).contains("Reset to defaults ("));

    let now = sandbox.exported();
    assert_eq!(
        now["tweaks"],
        json!({"hideToolbar": false, "launchFlags": false, "pinTab": false, "showAddressField": false, "windowMaterial": true})
    );
    assert_eq!(now["settings"], json!({"windowShadow": false}));
    for key in [
        "showAddressField",
        "windowMaterial",
        "windowCornerRadius",
        "windowMaterialChoice",
        "pinTabShortcutKey",
    ] {
        assert_eq!(sandbox.saved(key), None, "{key}");
    }
    for (key, before) in kept {
        assert_eq!(sandbox.saved(key), Some(before), "{key}");
    }
}

#[test]
fn local_tweaks_stay_on_this_mac_through_export_and_import() {
    let sandbox = Sandbox::new("localtweaks");
    assert!(sandbox.run(&["off", "localTweaks"]).status.success());
    assert_eq!(sandbox.exported()["tweaks"].get("localTweaks"), None);

    let replaced = sandbox.import(&json!({"version": 1}), &["--replace"]);
    assert!(replaced.status.success(), "{}", err(&replaced));
    assert_eq!(sandbox.saved("localTweaks").as_deref(), Some("0"));

    let named = sandbox.import(
        &json!({"version": 1, "tweaks": {"localTweaks": true, "showAddressField": true}}),
        &[],
    );
    assert!(named.status.success(), "{}", err(&named));
    assert!(
        err(&named).contains("Skipped unknown keys: localTweaks"),
        "{}",
        err(&named)
    );
    assert_eq!(sandbox.saved("localTweaks").as_deref(), Some("0"));
    assert_eq!(sandbox.exported()["tweaks"]["showAddressField"], true);
}

#[test]
fn shortcuts_round_trip_including_a_cleared_one() {
    let sandbox = Sandbox::new("shortcut");
    let shortcut = json!({"key": "F5", "keyCode": 96, "modifiers": 0});
    for value in [
        shortcut,
        json!({}),
        json!({"key": "D", "keyCode": 2, "modifiers": 1048576}),
    ] {
        let wanted = json!({"version": 1, "settings": {"pinTabShortcutKey": value}});
        let output = sandbox.import(&wanted, &[]);
        assert!(output.status.success(), "{}", err(&output));
        assert_eq!(sandbox.exported()["settings"], wanted["settings"]);
    }
    let again = sandbox.import(
        &json!({"version": 1, "settings": {"pinTabShortcutKey": {}}}),
        &[],
    );
    assert!(again.status.success());
    assert_eq!(
        sandbox.exported()["settings"]["pinTabShortcutKey"],
        json!({})
    );

    let saved = sandbox.run(&["export", "-"]);
    let rerun = sandbox.run_with_stdin(&["import", "-"], &out(&saved));
    assert!(rerun.status.success(), "{}", err(&rerun));
    assert!(out(&rerun).contains("Already matches standard input"));
}

#[test]
fn numbers_are_clamped_and_unknown_choices_kept_with_a_warning() {
    let sandbox = Sandbox::new("warnings");
    let output = sandbox.import(
        &json!({"version": 1, "settings": {"windowCornerRadius": 99, "windowMaterialChoice": "glass.99"}}),
        &[],
    );
    assert!(output.status.success(), "{}", err(&output));
    assert!(err(&output)
        .contains("Window Material: windowCornerRadius 99 is out of range, so it was set to 26"));
    assert!(err(&output).contains("Window Material: 'glass.99' isn't in this Mac's options; kept so DiaTweaks can fall back if needed"));
    assert_eq!(sandbox.saved("windowCornerRadius").as_deref(), Some("26"));
    assert_eq!(
        sandbox.saved("windowMaterialChoice").as_deref(),
        Some("glass.99")
    );

    let low = sandbox.import(
        &json!({"version": 1, "settings": {"windowCornerRadius": -3.5}}),
        &[],
    );
    assert!(low.status.success());
    assert_eq!(sandbox.saved("windowCornerRadius").as_deref(), Some("0"));
}

#[test]
fn invalid_launch_flags_reject_the_whole_file_before_writing_anything() {
    let sandbox = Sandbox::new("atomic");
    sandbox.run(&["on", "showAddressField"]);
    let before = sandbox.snapshot();
    for flags in [
        "--ok broken",
        "--disable-gpu \"unclosed",
        "-x",
        "--",
        "--bad name",
    ] {
        let output = sandbox.import(
            &json!({"version": 1, "tweaks": {"hideToolbar": true}, "settings": {"windowShadow": false, "launchFlagsArgs": flags}}),
            &["--replace"],
        );
        assert_eq!(output.status.code(), Some(1), "{flags}");
        assert!(
            err(&output).contains("nothing was changed"),
            "{}",
            err(&output)
        );
        assert!(
            err(&output).contains("settings.launchFlagsArgs has"),
            "{}",
            err(&output)
        );
        assert_eq!(sandbox.snapshot(), before, "{flags}");
    }
    let fine = sandbox.import(
        &json!({"version": 1, "settings": {"launchFlagsArgs": "# note\n--disable-gpu --foo=\"a b\" '--bar'"}}),
        &[],
    );
    assert!(fine.status.success(), "{}", err(&fine));
}

#[test]
fn every_problem_is_listed_and_nothing_is_written() {
    let sandbox = Sandbox::new("problems");
    let before = sandbox.snapshot();
    let output = sandbox.import(
        &json!({"version": 1, "tweaks": {"hideToolbar": "yes", "showAddressField": true},
                "settings": {"windowShadow": 1, "windowCornerRadius": "wide", "windowMaterialChoice": 3,
                             "pinTabShortcutKey": {"key": "D", "keyCode": 2, "modifiers": 131072},
                             "launchFlagsArgs": false}}),
        &[],
    );
    assert_eq!(output.status.code(), Some(1));
    let message = err(&output);
    for problem in [
        "tweaks.hideToolbar must be true or false",
        "settings.windowShadow must be true or false",
        "settings.windowCornerRadius must be a number",
        "settings.windowMaterialChoice must be text",
        "settings.pinTabShortcutKey needs ⌃, ⌥ or ⌘ held, unless the key is F1–F12",
        "settings.launchFlagsArgs must be text",
    ] {
        assert!(message.contains(problem), "{problem}\n{message}");
    }
    assert_eq!(sandbox.snapshot(), before);
    assert_eq!(sandbox.saved("showAddressField"), None);
}

#[test]
fn shortcut_shapes_are_checked_strictly() {
    let sandbox = Sandbox::new("shapes");
    for bad in [
        json!("D"),
        json!([]),
        json!({"key": "D"}),
        json!({"key": "", "keyCode": 2, "modifiers": 1048576}),
        json!({"key": "D", "keyCode": 65536, "modifiers": 1048576}),
        json!({"key": "D", "keyCode": -1, "modifiers": 1048576}),
        json!({"key": "D", "keyCode": 2.5, "modifiers": 1048576}),
        json!({"key": "D", "keyCode": 2, "modifiers": 1}),
        json!({"key": "D", "keyCode": 2, "modifiers": 1048576, "extra": 1}),
        json!({"key": "F13", "keyCode": 2, "modifiers": 0}),
        json!({"key": "D\u{7}", "keyCode": 2, "modifiers": 1048576}),
    ] {
        let output = sandbox.import(
            &json!({"version": 1, "settings": {"pinTabShortcutKey": bad}}),
            &[],
        );
        assert_eq!(output.status.code(), Some(1), "{bad}");
        assert!(err(&output).contains("settings.pinTabShortcutKey"), "{bad}");
    }
    assert_eq!(sandbox.saved("pinTabShortcutKey"), None);
}

#[test]
fn unknown_and_machine_specific_keys_are_skipped_not_fatal() {
    let sandbox = Sandbox::new("unknown");
    let output = sandbox.import(
        &json!({"version": 1,
                "tweaks": {"removedTweak": true, "showAddressField": true},
                "settings": {"profileColors": {"a": "b"}, "showExperimentalTweaks": true, "autoUpdateDia": true,
                             "futureSetting": 3, "showAddressField": true, "windowShadow": false}}),
        &[],
    );
    assert!(output.status.success(), "{}", err(&output));
    assert!(err(&output).contains(
        "Skipped unknown keys: removedTweak, autoUpdateDia, futureSetting, profileColors, showAddressField, showExperimentalTweaks"
    ), "{}", err(&output));
    assert_eq!(sandbox.saved("profileColors"), None);
    assert_eq!(sandbox.saved("showExperimentalTweaks"), None);
    assert_eq!(sandbox.saved("autoUpdateDia"), None);
    assert_eq!(sandbox.saved("futureSetting"), None);
    assert_eq!(sandbox.saved("removedTweak"), None);
    assert_eq!(sandbox.exported()["tweaks"]["showAddressField"], true);
}

#[test]
fn files_that_are_not_settings_files_are_refused_plainly() {
    let sandbox = Sandbox::new("refused");
    let before = sandbox.snapshot();
    for (content, message) in [
        (json!([1]), "should be a JSON object"),
        (json!({"tweaks": {}}), "should start with \"version\": 1"),
        (
            json!({"version": 2}),
            "is version 2, which this diatweaks can't read",
        ),
        (json!({"version": 1.5}), "should start with \"version\": 1"),
        (json!({"version": "1"}), "should start with \"version\": 1"),
        (
            json!({"version": 1, "extra": {}}),
            "\"extra\" isn't a section",
        ),
        (
            json!({"version": 1, "tweaks": []}),
            "\"tweaks\" must be an object",
        ),
        (
            json!({"version": 1, "settings": 3}),
            "\"settings\" must be an object",
        ),
    ] {
        let output = sandbox.import(&content, &[]);
        assert_eq!(output.status.code(), Some(1), "{content}");
        assert!(
            err(&output).contains(message),
            "{content}\n{}",
            err(&output)
        );
    }
    let broken = sandbox.run_with_stdin(&["import", "-"], "{not json");
    assert_eq!(broken.status.code(), Some(1));
    assert!(err(&broken).contains("standard input isn't valid JSON"));
    assert_eq!(sandbox.snapshot(), before);
}

#[test]
fn import_explains_a_missing_path_file_or_folder() {
    let sandbox = Sandbox::new("paths");
    let bare = sandbox.run(&["import"]);
    assert_eq!(bare.status.code(), Some(1));
    assert!(err(&bare).contains(
        "Pass a settings file to import, such as: diatweaks import diatweaks-config.json"
    ));

    let missing = sandbox.run(&["import", "nope.json"]);
    assert!(err(&missing).contains("There's no file at nope.json."));

    fs::create_dir(sandbox.path().join("folder")).unwrap();
    let folder = sandbox.run(&["import", "folder"]);
    assert!(
        err(&folder).contains("folder is a folder"),
        "{}",
        err(&folder)
    );

    fs::write(sandbox.path().join("binary.json"), [0xff, 0xfe, 0x00]).unwrap();
    assert!(err(&sandbox.run(&["import", "binary.json"])).contains("isn't a text file"));

    fs::write(sandbox.path().join("huge.json"), vec![b' '; 1 << 21]).unwrap();
    assert!(err(&sandbox.run(&["import", "huge.json"])).contains("too big"));
}

#[test]
fn import_reads_standard_input_and_is_idempotent() {
    let sandbox = Sandbox::new("stdin");
    let config = r#"{"version": 1, "tweaks": {"showAddressField": true}, "settings": {"windowShadow": false}}"#;
    let first = sandbox.run_with_stdin(&["import", "-"], config);
    assert!(first.status.success(), "{}", err(&first));
    assert!(out(&first).contains("Imported standard input: 1 tweak and 1 setting changed."));

    let second = sandbox.run_with_stdin(&["import", "-"], config);
    assert!(second.status.success());
    assert!(out(&second).contains("Already matches standard input: nothing to change."));
}

#[test]
fn import_does_not_pin_tweaks_that_already_follow_their_default() {
    let sandbox = Sandbox::new("pinning");
    let output = sandbox.import(
        &json!({"version": 1, "tweaks": {"windowMaterial": true, "hideToolbar": false}}),
        &[],
    );
    assert!(output.status.success());
    assert!(out(&output).contains("Already matches"));
    assert_eq!(sandbox.saved("windowMaterial"), None);
    assert_eq!(sandbox.saved("hideToolbar"), None);
}

#[test]
fn import_says_when_flags_or_relaunch_tweaks_need_dia_restarted() {
    let sandbox = Sandbox::new("relaunch");
    let output = sandbox.import(
        &json!({"version": 1, "tweaks": {"launchFlags": true}, "settings": {"launchFlagsArgs": "--disable-gpu"}}),
        &[],
    );
    assert!(output.status.success(), "{}", err(&output));
    assert!(out(&output).contains("Turned on Launch Flags."));
    assert!(out(&output).contains("Updated launchFlagsArgs."));
}

#[test]
fn legacy_launch_flag_arrays_export_as_the_text_the_tweak_reads() {
    let sandbox = Sandbox::new("legacy-flags");
    let written = sandbox.defaults(&[
        "write",
        "launchFlagsArgs",
        "-array",
        "--disable-gpu",
        "--foo=a b",
        "--bar=1",
    ]);
    assert!(written.status.success(), "{}", err(&written));

    let exported = sandbox.exported();
    assert_eq!(
        exported["settings"]["launchFlagsArgs"],
        json!("--disable-gpu\n\"--foo=a b\"\n--bar=1")
    );

    let file = sandbox.write("legacy.json", &exported);
    let imported = sandbox.run(&["import", file.to_str().unwrap()]);
    assert!(imported.status.success(), "{}", err(&imported));
    assert!(
        out(&imported).contains("Already matches"),
        "{}",
        out(&imported)
    );
    assert_eq!(
        sandbox.exported()["settings"]["launchFlagsArgs"],
        exported["settings"]["launchFlagsArgs"]
    );

    let broken = Sandbox::new("legacy-flags-broken");
    assert!(broken
        .defaults(&["write", "launchFlagsArgs", "-array", "--ok", "broken"])
        .status
        .success());
    let refused = broken.run(&["export", "-"]);
    assert!(refused.status.success());
    assert!(
        err(&refused).contains("Left out launchFlagsArgs"),
        "{}",
        err(&refused)
    );
}

#[test]
fn imports_that_set_launch_flags_warn_about_trust() {
    let sandbox = Sandbox::new("trust");
    let on = sandbox.import(&json!({"version": 1, "tweaks": {"launchFlags": true}}), &[]);
    assert!(on.status.success(), "{}", err(&on));
    assert!(
        err(&on).contains("Only import launch flags from someone you trust"),
        "{}",
        err(&on)
    );

    let args = sandbox.import(
        &json!({"version": 1, "settings": {"launchFlagsArgs": "--disable-gpu"}}),
        &[],
    );
    assert!(args.status.success(), "{}", err(&args));
    assert!(err(&args).contains("Only import launch flags from someone you trust"));

    let note = sandbox.import(
        &json!({"version": 1, "settings": {"launchFlagsArgs": "# only a note"}}),
        &[],
    );
    assert!(note.status.success(), "{}", err(&note));
    assert!(!err(&note).contains("trust"), "{}", err(&note));

    let off = sandbox.import(
        &json!({"version": 1, "tweaks": {"launchFlags": false}}),
        &[],
    );
    assert!(off.status.success(), "{}", err(&off));
    assert!(!err(&off).contains("trust"), "{}", err(&off));
}

#[test]
fn odd_saved_values_never_block_export_or_import() {
    let sandbox = Sandbox::new("odd-values");
    for args in [
        &["write", "windowCornerRadius", "-dict", "a", "b"][..],
        &["write", "pinTabShortcutKey", "-string", "D"],
        &["write", "hideToolbar", "-dict", "a", "b"],
    ] {
        assert!(sandbox.defaults(args).status.success());
    }
    let output = sandbox.run(&["export", "-"]);
    assert!(output.status.success(), "{}", err(&output));
    let exported: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(exported["settings"], json!({}));
    assert_eq!(exported["tweaks"]["hideToolbar"], false);

    let fixed = sandbox.import(
        &json!({"version": 1, "tweaks": {"hideToolbar": true}, "settings": {"windowCornerRadius": 8, "windowShadow": true}}),
        &[],
    );
    assert!(fixed.status.success(), "{}", err(&fixed));
    assert_eq!(sandbox.saved("windowCornerRadius").as_deref(), Some("8"));
    assert_eq!(sandbox.saved("hideToolbar").as_deref(), Some("1"));
}

#[test]
fn list_marks_experimental_tweaks() {
    let sandbox = Sandbox::new("experimental");
    let output = sandbox.run(&["list"]);
    assert!(output.status.success());
    let text = out(&output);
    assert!(text.contains("Hide Toolbar [experimental]\n"), "{text}");
    assert!(!text.contains("Window Material ["));
}
