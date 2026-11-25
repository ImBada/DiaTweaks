use std::{collections::HashSet, fmt::Write, fs, io};

use anyhow::{anyhow, bail, Context, Result};
use serde::Deserialize;

use crate::{env::Env, local::LocalState, prefs::Prefs};

#[derive(Deserialize)]
pub struct Manifest {
    version: u32,
    pub patches: Vec<Patch>,
}

#[derive(Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Patch {
    pub key: String,
    pub title: String,
    pub detail: String,
    pub default_on: bool,
    pub requires: Option<String>,
    pub disabled_by: Option<String>,
    #[serde(default)]
    pub covered_by: Option<String>,
    #[serde(default)]
    pub relaunch: bool,
    #[serde(default)]
    pub local: bool,
    #[serde(default)]
    pub experimental: bool,
    #[serde(default)]
    pub choice: Option<ChoiceSpec>,
    #[serde(default)]
    pub shortcut: Option<ShortcutSpec>,
    #[serde(default)]
    pub settings: Vec<SettingSpec>,
}

#[derive(Deserialize, Clone)]
pub struct ChoiceSpec {
    pub key: String,
    #[serde(default)]
    pub values: Vec<String>,
}

#[derive(Deserialize, Clone)]
pub struct ShortcutSpec {
    pub key: String,
}

#[derive(Deserialize, Clone)]
pub struct SettingSpec {
    pub key: String,
    #[serde(rename = "type")]
    pub kind: SettingKind,
    pub min: Option<f64>,
    pub max: Option<f64>,
}

#[derive(Deserialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum SettingKind {
    Bool,
    Number,
    String,
    #[serde(other)]
    Unsupported,
}

impl Manifest {
    pub fn load(env: &Env) -> Result<Self> {
        let path = env.manifest();
        let data = match fs::read(&path) {
            Ok(data) => data,
            Err(err) if err.kind() == io::ErrorKind::NotFound => bail!(
                "DiaTweaks isn't installed: {} is missing. Run {} first.",
                path.display(),
                env.install_hint()
            ),
            Err(err) if err.kind() == io::ErrorKind::PermissionDenied => {
                return Err(env.not_yours(&path))
            }
            Err(err) => {
                return Err(err).with_context(|| format!("Couldn't read {}", path.display()));
            }
        };
        let broken = |problem: String| anyhow!("{problem} Run {} again.", env.install_hint());
        let manifest: Self = serde_json::from_slice(&data)
            .map_err(|err| broken(format!("{} is damaged ({err}).", path.display())))?;
        if !matches!(manifest.version, 1 | 2) {
            return Err(broken(format!(
                "{} is format {}, which this diatweaks can't read.",
                path.display(),
                manifest.version
            )));
        }
        if manifest.patches.is_empty() {
            return Err(broken(format!("{} lists no tweaks.", path.display())));
        }
        let links = manifest
            .patches
            .iter()
            .flat_map(|patch| [&patch.requires, &patch.disabled_by, &patch.covered_by])
            .flatten();
        for key in links {
            if manifest.index(key).is_none() {
                return Err(broken(format!(
                    "{} names a tweak it doesn't list: {key}.",
                    path.display()
                )));
            }
        }
        if let Some(index) =
            (0..manifest.patches.len()).find(|&index| manifest.requires_cycle(index))
        {
            return Err(broken(format!(
                "{} has a requirement cycle at {}.",
                path.display(),
                manifest.patches[index].key
            )));
        }
        Ok(manifest)
    }

    pub fn load_with_local(env: &Env) -> Result<Self> {
        let mut manifest = Self::load(env)?;
        if let Ok(state) = LocalState::load(&env.local_state()) {
            manifest.merge_local(state.patches());
        }
        Ok(manifest)
    }

    /// Links from a local tweak that dangle or loop are dropped, so one broken local file can't hide the official tweaks.
    pub fn merge_local(&mut self, local: Vec<Patch>) {
        let mut keys: HashSet<String> =
            self.patches.iter().map(|patch| patch.key.clone()).collect();
        let mut accepted = Vec::new();
        for mut patch in local {
            if keys.insert(patch.key.clone()) {
                patch.local = true;
                accepted.push(patch);
            }
        }
        for patch in &mut accepted {
            for link in [
                &mut patch.requires,
                &mut patch.disabled_by,
                &mut patch.covered_by,
            ] {
                if link.as_ref().is_some_and(|key| !keys.contains(key)) {
                    *link = None;
                }
            }
        }
        let base = self.patches.len();
        self.patches.extend(accepted);
        for index in base..self.patches.len() {
            if self.requires_cycle(index) {
                self.patches[index].requires = None;
            }
        }
    }

    fn requires_cycle(&self, index: usize) -> bool {
        let mut cursor = index;
        for _ in 0..self.patches.len() {
            match self.requirement(cursor) {
                Some(required) => cursor = required,
                None => return false,
            }
        }
        true
    }

    pub fn index(&self, key: &str) -> Option<usize> {
        self.patches.iter().position(|patch| patch.key == key)
    }

    fn linked(&self, key: &Option<String>) -> Option<usize> {
        key.as_deref().and_then(|key| self.index(key))
    }

    pub fn requirement(&self, index: usize) -> Option<usize> {
        self.linked(&self.patches[index].requires)
    }

    fn disabler(&self, index: usize) -> Option<usize> {
        self.linked(&self.patches[index].disabled_by)
    }

    pub fn covered_by(&self, index: usize, state: &[bool]) -> Option<usize> {
        self.linked(&self.patches[index].covered_by)
            .filter(|&cover| state[cover])
    }

    pub fn hidden_by(&self, index: usize, state: &[bool]) -> Option<usize> {
        let disabler = self.disabler(index).filter(|&disabler| state[disabler])?;
        let disabler_key = self.patches[disabler].key.as_str();
        let has_option_on = self.patches.iter().enumerate().any(|(option, patch)| {
            state[option] && patch.requires.as_deref() == Some(disabler_key)
        });
        (!has_option_on).then_some(disabler)
    }

    pub fn title(&self, index: usize) -> &str {
        &self.patches[index].title
    }

    pub fn label(&self, index: usize, state: &[bool]) -> String {
        let patch = &self.patches[index];
        let mut label = patch.title.clone();
        if patch.local {
            label.push_str(" (local)");
        }
        if patch.experimental {
            label.push_str(" [experimental]");
        }
        for note in self.annotations(index, state) {
            let _ = write!(label, " ({note})");
        }
        label
    }

    pub fn annotations(&self, index: usize, state: &[bool]) -> Vec<String> {
        let mut notes = Vec::new();
        if let Some(required) = self
            .requirement(index)
            .filter(|&required| state[index] && !state[required])
        {
            notes.push(format!(
                "does nothing while {} is off",
                self.title(required)
            ));
        }
        if let Some(cover) = self.covered_by(index, state) {
            notes.push(format!("{} hides this too", self.title(cover)));
        } else if let Some(disabler) = self.hidden_by(index, state) {
            notes.push(format!(
                "no difference while {} is on",
                self.title(disabler)
            ));
        }
        notes
    }

    pub fn state(&self, prefs: &Prefs) -> Vec<bool> {
        let keys: Vec<&str> = self
            .patches
            .iter()
            .map(|patch| patch.key.as_str())
            .collect();
        prefs
            .bools(&keys)
            .into_iter()
            .zip(&self.patches)
            .map(|(on, patch)| on.unwrap_or(patch.default_on))
            .collect()
    }

    pub fn find(&self, name: &str) -> Option<usize> {
        let wanted = normalize(name);
        self.patches
            .iter()
            .position(|patch| normalize(&patch.key) == wanted || normalize(&patch.title) == wanted)
    }

    pub fn resolve(
        &self,
        names: &[String],
        mut confirm: impl FnMut(&str, &Patch) -> Result<bool>,
    ) -> Result<Vec<usize>> {
        let mut found = Vec::new();
        let mut unknown = Vec::new();
        for name in names {
            let index = match self.find(name) {
                Some(index) => index,
                None => match self.close_to(name).as_slice() {
                    &[one] if confirm(name, &self.patches[one])? => one,
                    close => {
                        unknown.push(self.not_found(name, close));
                        continue;
                    }
                },
            };
            if !found.contains(&index) {
                found.push(index);
            }
        }
        if !unknown.is_empty() {
            bail!(
                "{}\nRun `diatweaks list` to see all tweaks.",
                unknown.join("\n")
            );
        }
        Ok(found)
    }

    fn close_to(&self, name: &str) -> Vec<usize> {
        let wanted = normalize(name);
        (0..self.patches.len())
            .filter(|&index| {
                let patch = &self.patches[index];
                is_close(&wanted, &patch.key) || is_close(&wanted, &patch.title)
            })
            .collect()
    }

    fn not_found(&self, name: &str, close: &[usize]) -> String {
        let keys: Vec<&str> = close
            .iter()
            .map(|&index| self.patches[index].key.as_str())
            .collect();
        match keys.as_slice() {
            [] => format!("There's no tweak called \"{name}\"."),
            [one] => format!("There's no tweak called \"{name}\". Did you mean {one}?"),
            many => format!(
                "There's no tweak called \"{name}\". Did you mean one of {}?",
                many.join(", ")
            ),
        }
    }
}

fn normalize(name: &str) -> String {
    name.chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .map(|c| c.to_ascii_lowercase())
        .collect()
}

fn is_close(wanted: &str, candidate: &str) -> bool {
    let candidate = normalize(candidate);
    (wanted.len() >= 3 && candidate.contains(wanted))
        || strsim::normalized_damerau_levenshtein(wanted, &candidate) >= 0.7
}

#[cfg(test)]
pub fn load_json(json: &str) -> Result<Manifest> {
    let dir = tempfile::tempdir().unwrap();
    fs::write(dir.path().join("patches.json"), json).unwrap();
    Manifest::load(&Env::at(dir.path()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_requirement_cycles() {
        let loaded = load_json(
            r#"{
                "version": 1,
                "patches": [
                    {"key": "a", "title": "A", "detail": "A", "defaultOn": false, "requires": "b", "disabledBy": null},
                    {"key": "b", "title": "B", "detail": "B", "defaultOn": false, "requires": "a", "disabledBy": null}
                ]
            }"#,
        );
        assert!(loaded.is_err());
    }

    #[test]
    fn resolves_by_key_and_title_and_suggests() {
        let manifest = load_json(
            r#"{
                "version": 1,
                "patches": [
                    {"key": "hideToolbar", "title": "Hide Toolbar", "detail": "H", "defaultOn": false, "requires": null, "disabledBy": null},
                    {"key": "showAddressField", "title": "Show Address Field", "detail": "S", "defaultOn": false, "requires": null, "disabledBy": "hideToolbar"}
                ]
            }"#,
        )
        .unwrap();
        let never = |_: &str, _: &Patch| Ok(false);
        assert_eq!(
            manifest
                .resolve(&["hide-toolbar".into(), "Show Address Field".into()], never)
                .unwrap(),
            vec![0, 1]
        );
        let err = manifest
            .resolve(&["hidetoolba".into(), "zzz".into()], never)
            .unwrap_err()
            .to_string();
        assert_eq!(
            err,
            "There's no tweak called \"hidetoolba\". Did you mean hideToolbar?\nThere's no tweak called \"zzz\".\nRun `diatweaks list` to see all tweaks."
        );
        let mut asked = Vec::new();
        let accepted = manifest
            .resolve(&["hidetoolba".into()], |name, patch| {
                asked.push(format!("{name}->{}", patch.key));
                Ok(true)
            })
            .unwrap();
        assert_eq!(accepted, vec![0]);
        assert_eq!(asked, vec!["hidetoolba->hideToolbar"]);
        assert_eq!(manifest.hidden_by(1, &[true, false]), Some(0));
        assert_eq!(manifest.hidden_by(1, &[false, true]), None);
    }

    #[test]
    fn reads_version_1_and_2_manifests_and_their_portable_settings() {
        let old = load_json(
            r#"{"version": 1, "patches": [{"key": "a", "title": "A", "detail": "A", "defaultOn": false, "requires": null, "disabledBy": null}]}"#,
        )
        .unwrap();
        let patch = &old.patches[0];
        assert!(
            !patch.experimental
                && patch.choice.is_none()
                && patch.shortcut.is_none()
                && patch.settings.is_empty()
        );

        let new = load_json(
            r#"{"version": 2, "patches": [{"key": "a", "title": "A", "detail": "A", "defaultOn": false, "requires": null, "disabledBy": null,
                "experimental": true,
                "choice": {"key": "aChoice", "default": "x", "values": ["x", "y"]},
                "shortcut": {"key": "aShortcut", "default": {"keyCode": 2, "modifiers": 1048576, "key": "D"}},
                "settings": [{"key": "n", "type": "number", "default": 1, "min": 0, "max": 5}, {"key": "z", "type": "dial", "default": 1}]}]}"#,
        )
        .unwrap();
        let patch = &new.patches[0];
        assert!(patch.experimental);
        assert_eq!(patch.choice.as_ref().unwrap().values, ["x", "y"]);
        assert_eq!(patch.shortcut.as_ref().unwrap().key, "aShortcut");
        assert!(patch.settings[0].kind == SettingKind::Number);
        assert_eq!(
            (patch.settings[0].min, patch.settings[0].max),
            (Some(0.0), Some(5.0))
        );
        assert!(patch.settings[1].kind == SettingKind::Unsupported);
        assert_eq!(new.label(0, &[false]), "A [experimental]");

        let future = load_json(r#"{"version": 3, "patches": []}"#);
        assert!(future.err().unwrap().to_string().contains("format 3"));
    }

    #[test]
    fn loads_and_validates_covered_by() {
        let manifest = load_json(
            r#"{
                "version": 1,
                "patches": [
                    {"key": "turnOffAI", "title": "Turn Off AI", "detail": "A", "defaultOn": false, "requires": null, "disabledBy": null, "coveredBy": null},
                    {"key": "hideChatButton", "title": "Hide Chat Button", "detail": "C", "defaultOn": false, "requires": null, "disabledBy": null, "coveredBy": "turnOffAI"}
                ]
            }"#,
        )
        .unwrap();
        assert_eq!(manifest.covered_by(1, &[true, false]), Some(0));
        assert_eq!(manifest.covered_by(1, &[false, true]), None);

        let dangling = load_json(
            r#"{
                "version": 1,
                "patches": [
                    {"key": "hideChatButton", "title": "Hide Chat Button", "detail": "C", "defaultOn": false, "requires": null, "disabledBy": null, "coveredBy": "missing"}
                ]
            }"#,
        );
        assert!(dangling.is_err());
    }
}
