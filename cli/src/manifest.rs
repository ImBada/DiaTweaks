use std::{collections::HashSet, fmt::Write, fs, io, path::Path};

use anyhow::{anyhow, bail, Context, Result};
use serde::Deserialize;

use crate::{local::LocalState, prefs::Prefs};

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
}

impl Manifest {
    pub fn load(path: &Path) -> Result<Self> {
        let data = match fs::read(path) {
            Ok(data) => data,
            Err(err) if err.kind() == io::ErrorKind::NotFound => bail!(
                "DiaTweaks isn't installed: {} is missing. Run install.sh first.",
                path.display()
            ),
            Err(err) => {
                return Err(err).with_context(|| format!("Couldn't read {}", path.display()));
            }
        };
        let manifest: Self = serde_json::from_slice(&data).map_err(|err| {
            anyhow!(
                "{} is damaged ({err}). Run install.sh again.",
                path.display()
            )
        })?;
        if manifest.version != 1 {
            bail!(
                "{} is format {}, which this diatweaks can't read. Run install.sh again.",
                path.display(),
                manifest.version
            );
        }
        if manifest.patches.is_empty() {
            bail!("{} lists no tweaks. Run install.sh again.", path.display());
        }
        let links = manifest
            .patches
            .iter()
            .flat_map(|patch| [&patch.requires, &patch.disabled_by, &patch.covered_by])
            .flatten();
        for key in links {
            if manifest.index(key).is_none() {
                bail!(
                    "{} names a tweak it doesn't list: {key}. Run install.sh again.",
                    path.display()
                );
            }
        }
        if let Some(index) =
            (0..manifest.patches.len()).find(|&index| manifest.requires_cycle(index))
        {
            bail!(
                "{} has a requirement cycle at {}. Run install.sh again.",
                path.display(),
                manifest.patches[index].key
            );
        }
        Ok(manifest)
    }

    pub fn load_with_local(path: &Path, local: &Path) -> Result<Self> {
        let mut manifest = Self::load(path)?;
        if let Ok(state) = LocalState::load(local) {
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
        self.patches
            .iter()
            .map(|patch| prefs.get(&patch.key).unwrap_or(patch.default_on))
            .collect()
    }

    pub fn resolve(&self, names: &[String]) -> Result<Vec<usize>> {
        let mut found = Vec::new();
        let mut unknown = Vec::new();
        for name in names {
            let wanted = normalize(name);
            let index = self.patches.iter().position(|patch| {
                normalize(&patch.key) == wanted || normalize(&patch.title) == wanted
            });
            match index {
                Some(index) if !found.contains(&index) => found.push(index),
                Some(_) => {}
                None => unknown.push(self.suggest(name, &wanted)),
            }
        }
        if !unknown.is_empty() {
            bail!("{}", unknown.join("\n"));
        }
        Ok(found)
    }

    fn suggest(&self, name: &str, wanted: &str) -> String {
        let close: Vec<&str> = self
            .patches
            .iter()
            .filter(|patch| is_close(wanted, &patch.key) || is_close(wanted, &patch.title))
            .map(|patch| patch.key.as_str())
            .collect();
        match close.as_slice() {
            [] => format!("There's no tweak called \"{name}\". Run `diatweaks list` to see them."),
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
    let path = dir.path().join("patches.json");
    fs::write(&path, json).unwrap();
    Manifest::load(&path)
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
        assert_eq!(
            manifest
                .resolve(&["hide-toolbar".into(), "Show Address Field".into()])
                .unwrap(),
            vec![0, 1]
        );
        let err = manifest
            .resolve(&["hidetoolba".into()])
            .unwrap_err()
            .to_string();
        assert!(err.contains("hideToolbar"));
        assert_eq!(manifest.hidden_by(1, &[true, false]), Some(0));
        assert_eq!(manifest.hidden_by(1, &[false, true]), None);
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
