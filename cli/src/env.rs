use std::{
    env,
    ffi::{CString, OsString},
    fs,
    os::unix::{ffi::OsStrExt, fs::MetadataExt},
    path::{Path, PathBuf},
};

use anyhow::{anyhow, Context, Error, Result};

pub const DEFAULT_APP: &str = "/Applications/Dia.app";

pub struct Env {
    pub home: PathBuf,
    pub support: PathBuf,
    pub app: PathBuf,
    pub domain: String,
}

impl Env {
    pub fn load() -> Result<Self> {
        let home = var_os("HOME")
            .map(PathBuf::from)
            .context("HOME isn't set")?;
        let support = var_os("DIAPATCH_HOME").map_or_else(
            || home.join("Library/Application Support/DiaPatches"),
            PathBuf::from,
        );
        let app = var_os("DIAPATCH_APP").map_or_else(
            || {
                find_app(
                    &support,
                    Path::new(DEFAULT_APP),
                    &home.join("Applications/Dia.app"),
                )
            },
            PathBuf::from,
        );
        Ok(Self {
            support,
            app,
            domain: var("DIATWEAKS_DOMAIN").unwrap_or_else(|| "com.diapatches".into()),
            home,
        })
    }

    pub fn diapatch(&self) -> PathBuf {
        self.support.join("bin/diapatch")
    }

    pub fn manifest(&self) -> PathBuf {
        self.support.join("patches.json")
    }

    pub fn staged(&self) -> PathBuf {
        self.support.join("staged/Dia.app")
    }

    pub fn local(&self) -> PathBuf {
        self.support.join("local")
    }

    pub fn local_state(&self) -> PathBuf {
        self.support.join("local-state.json")
    }

    pub fn install_hint(&self) -> String {
        let recorded = fs::read_to_string(self.support.join("source-dir"))
            .ok()
            .map(|dir| PathBuf::from(dir.trim_end_matches('\n')).join("install.sh"));
        recorded
            .into_iter()
            .chain([self.home.join("DiaTweaks/install.sh")])
            .find(|script| script.is_file())
            .map_or_else(
                || "./install.sh".into(),
                |script| script.display().to_string(),
            )
    }

    pub fn not_yours(&self, path: &Path) -> Error {
        anyhow!(
            "{} belongs to another user, usually from running DiaTweaks with sudo, so diatweaks can't change it. Make it yours again, then try once more:\n  sudo chown -R \"$USER\" \"{}\"",
            path.display(),
            self.support.display()
        )
    }

    pub fn check_yours(&self, path: &Path) -> Result<()> {
        match fs::symlink_metadata(path) {
            Ok(meta) if !is_mine(&meta) || !writable(path) => Err(self.not_yours(path)),
            _ => Ok(()),
        }
    }

    #[cfg(test)]
    pub fn at(dir: &Path) -> Self {
        Self {
            home: dir.into(),
            support: dir.into(),
            app: dir.join("Dia.app"),
            domain: "com.diapatches.test".into(),
        }
    }
}

pub fn writable(path: &Path) -> bool {
    CString::new(path.as_os_str().as_bytes())
        .is_ok_and(|path| unsafe { libc::access(path.as_ptr(), libc::W_OK) } == 0)
}

pub fn is_mine(meta: &fs::Metadata) -> bool {
    meta.uid() == unsafe { libc::geteuid() }
}

// diapatch's findDia order; its last resort, Launch Services, only matters before `diapatch install` writes dia-app.
fn find_app(support: &Path, system: &Path, user: &Path) -> PathBuf {
    let remembered = fs::read_to_string(support.join("dia-app"))
        .ok()
        .map(|path| PathBuf::from(path.trim()));
    remembered
        .into_iter()
        .chain([system.into(), user.into()])
        .find(|app| app.is_absolute() && app.is_dir())
        .unwrap_or_else(|| system.into())
}

fn var_os(name: &str) -> Option<OsString> {
    env::var_os(name).filter(|value| !value.is_empty())
}

fn var(name: &str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn install_hint_prefers_the_recorded_source_folder() {
        let dir = tempfile::tempdir().unwrap();
        let env = Env::at(dir.path());
        assert_eq!(env.install_hint(), "./install.sh");

        let home = dir.path().join("DiaTweaks");
        fs::create_dir_all(&home).unwrap();
        fs::write(home.join("install.sh"), "").unwrap();
        assert_eq!(
            env.install_hint(),
            home.join("install.sh").display().to_string()
        );

        let source = dir.path().join("src tree");
        fs::create_dir_all(&source).unwrap();
        fs::write(source.join("install.sh"), "").unwrap();
        fs::write(
            dir.path().join("source-dir"),
            format!("{}\n", source.display()),
        )
        .unwrap();
        assert_eq!(
            env.install_hint(),
            source.join("install.sh").display().to_string()
        );
    }

    #[test]
    fn finds_dia_where_diapatch_does() {
        let dir = tempfile::tempdir().unwrap();
        let (system, user) = (
            dir.path().join("system/Dia.app"),
            dir.path().join("user/Dia.app"),
        );
        let remembered = dir.path().join("Elsewhere/Dia.app");
        let find = || find_app(dir.path(), &system, &user);

        assert_eq!(find(), system);
        fs::create_dir_all(&user).unwrap();
        assert_eq!(find(), user);
        fs::create_dir_all(&system).unwrap();
        assert_eq!(find(), system);

        fs::write(
            dir.path().join("dia-app"),
            format!("  {}\n", remembered.display()),
        )
        .unwrap();
        assert_eq!(find(), system, "a remembered Dia that's gone is skipped");
        fs::create_dir_all(&remembered).unwrap();
        assert_eq!(find(), remembered);

        for junk in ["", "\n", "Dia.app"] {
            fs::write(dir.path().join("dia-app"), junk).unwrap();
            assert_eq!(find(), system, "{junk:?}");
        }
    }

    #[test]
    fn writable_uses_access_not_the_mode_bits() {
        let dir = tempfile::tempdir().unwrap();
        let locked = dir.path().join("locked");
        fs::create_dir(&locked).unwrap();
        assert!(writable(&locked));
        assert!(!writable(&locked.join("missing")));
        fs::set_permissions(&locked, fs::Permissions::from_mode(0o555)).unwrap();
        assert!(!writable(&locked));
        let env = Env::at(dir.path());
        assert!(env.check_yours(&locked.join("missing")).is_ok());
        let err = env.check_yours(&locked).unwrap_err().to_string();
        assert!(err.contains(&format!(
            "sudo chown -R \"$USER\" \"{}\"",
            dir.path().display()
        )));
        fs::set_permissions(&locked, fs::Permissions::from_mode(0o755)).unwrap();
    }
}
