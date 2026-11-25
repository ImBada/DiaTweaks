use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Output},
};

fn diatweaks(support: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_diatweaks"))
        .args(args)
        .env("HOME", support)
        .env("DIAPATCH_HOME", support)
        .output()
        .unwrap()
}

fn install_diapatch(support: &Path, script: &str) {
    let path = support.join("bin/diapatch");
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(&path, format!("#!/bin/sh\n{script}\n")).unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
}

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

#[test]
fn available_asks_diapatch_for_the_catalog() {
    let dir = tempfile::tempdir().unwrap();
    install_diapatch(dir.path(), r#"echo "diapatch $*""#);
    let output = diatweaks(dir.path(), &["local", "available"]);
    assert!(output.status.success());
    assert_eq!(text(&output.stdout).trim(), "diapatch local available");
}

#[test]
fn catalog_is_another_name_for_available() {
    let dir = tempfile::tempdir().unwrap();
    install_diapatch(dir.path(), r#"echo "diapatch $*""#);
    let output = diatweaks(dir.path(), &["local", "catalog"]);
    assert!(output.status.success());
    assert_eq!(text(&output.stdout).trim(), "diapatch local available");
}

#[test]
fn install_passes_every_name_through() {
    let dir = tempfile::tempdir().unwrap();
    install_diapatch(dir.path(), r#"echo "diapatch $*""#);
    let output = diatweaks(
        dir.path(),
        &["local", "install", "mouseBackForward", "Hide Foo"],
    );
    assert!(output.status.success());
    assert_eq!(
        text(&output.stdout).trim(),
        "diapatch local install mouseBackForward Hide Foo"
    );
}

#[test]
fn install_needs_a_name() {
    let dir = tempfile::tempdir().unwrap();
    install_diapatch(dir.path(), "exit 0");
    let output = diatweaks(dir.path(), &["local", "install"]);
    assert_eq!(output.status.code(), Some(2));
    assert!(text(&output.stderr).contains("<TWEAK>"));
}

#[test]
fn install_reports_what_diapatch_said() {
    let dir = tempfile::tempdir().unwrap();
    install_diapatch(
        dir.path(),
        r#"echo "No optional tweak matching “$3”." >&2; exit 1"#,
    );
    let output = diatweaks(dir.path(), &["local", "install", "nothing"]);
    assert_eq!(output.status.code(), Some(1));
    assert!(text(&output.stderr).contains("No optional tweak matching “nothing”."));
}

#[test]
fn available_without_diatweaks_installed_says_so() {
    let dir = tempfile::tempdir().unwrap();
    let output = diatweaks(dir.path(), &["local", "available"]);
    assert_eq!(output.status.code(), Some(1));
    assert!(text(&output.stderr).contains("isn't installed"));
}

#[test]
fn add_points_a_bare_name_at_install() {
    let dir = tempfile::tempdir().unwrap();
    let output = diatweaks(dir.path(), &["local", "add", "NonExistentName"]);
    assert_eq!(output.status.code(), Some(1));
    let error = text(&output.stderr);
    assert!(error.contains("There's nothing at NonExistentName."));
    assert!(error.contains("run `diatweaks local install NonExistentName`"));
}

#[test]
fn add_keeps_the_plain_message_for_a_path() {
    let dir = tempfile::tempdir().unwrap();
    for path in ["Missing.m", "folder/Missing"] {
        let output = diatweaks(dir.path(), &["local", "add", path]);
        assert_eq!(output.status.code(), Some(1));
        let error = text(&output.stderr);
        assert!(error.contains(&format!("There's nothing at {path}.")));
        assert!(!error.contains("local install"));
    }
}

#[test]
fn add_builds_just_the_added_tweak() {
    let dir = tempfile::tempdir().unwrap();
    install_diapatch(dir.path(), r#"printf '[%s]' "$@""#);
    let source = dir.path().join("MyTweak.m");
    fs::write(&source, "").unwrap();
    for (added, built) in [("MyTweak.m", "MyTweak"), ("MyTweak 2.m", "MyTweak 2")] {
        let output = diatweaks(dir.path(), &["local", "add", source.to_str().unwrap()]);
        assert!(output.status.success());
        assert!(dir.path().join("local").join(added).is_file());
        assert_eq!(
            text(&output.stdout),
            format!("Added {added}.\n[local][build][{built}]\n")
        );
    }
}

#[test]
fn remove_finds_a_tweak_by_name_with_or_without_its_extension() {
    let dir = tempfile::tempdir().unwrap();
    let local = dir.path().join("local");
    fs::create_dir_all(local.join("Folder")).unwrap();
    fs::write(local.join("Single.dylib"), "").unwrap();
    for (name, removed) in [("Single.m", "Single.dylib"), ("Folder.diatweak", "Folder")] {
        let output = diatweaks(dir.path(), &["local", "remove", name]);
        assert!(output.status.success());
        assert!(!local.join(removed).exists());
        assert!(dir.path().join(".Trash").join(removed).exists());
    }
}
