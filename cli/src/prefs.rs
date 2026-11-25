use std::ffi::{c_char, CString};

use anyhow::{bail, Result};
use core_foundation::{
    array::CFArray,
    base::{CFType, CFTypeRef, TCFType},
    boolean::CFBoolean,
    dictionary::CFDictionary,
    number::CFNumber,
    string::CFString,
};
use core_foundation_sys::preferences::{
    kCFPreferencesAnyHost, kCFPreferencesCurrentUser, CFPreferencesAppSynchronize,
    CFPreferencesCopyAppValue, CFPreferencesCopyMultiple, CFPreferencesSetAppValue,
};

extern "C" {
    fn notify_post(name: *const c_char) -> u32;
}

pub struct Prefs {
    name: String,
    domain: CFString,
}

impl Prefs {
    pub fn new(domain: &str) -> Self {
        let cf_domain = CFString::new(domain);
        unsafe {
            CFPreferencesAppSynchronize(cf_domain.as_concrete_TypeRef());
        }
        Self {
            name: domain.to_string(),
            domain: cf_domain,
        }
    }

    pub fn raw(&self, key: &str) -> Option<CFType> {
        let key = CFString::new(key);
        let value = unsafe {
            CFPreferencesCopyAppValue(key.as_concrete_TypeRef(), self.domain.as_concrete_TypeRef())
        };
        (!value.is_null()).then(|| unsafe { CFType::wrap_under_create_rule(value) })
    }

    /// Reads many keys in one cfprefsd round trip; `Manifest::state` asks for every tweak at once.
    pub fn bools(&self, keys: &[&str]) -> Vec<Option<bool>> {
        let wanted: Vec<CFString> = keys.iter().map(|key| CFString::new(key)).collect();
        let array = CFArray::from_CFTypes(&wanted);
        let found = unsafe {
            CFPreferencesCopyMultiple(
                array.as_concrete_TypeRef(),
                self.domain.as_concrete_TypeRef(),
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost,
            )
        };
        if found.is_null() {
            return keys.iter().map(|_| None).collect();
        }
        let found = unsafe { CFDictionary::<CFString, CFType>::wrap_under_create_rule(found) };
        wanted
            .iter()
            .map(|key| found.find(key).and_then(|value| as_bool(&value)))
            .collect()
    }

    pub fn set(&self, key: &str, on: bool) {
        self.set_value(key, &CFBoolean::from(on).as_CFType());
    }

    pub fn set_value(&self, key: &str, value: &CFType) {
        self.write(key, value.as_CFTypeRef());
    }

    pub fn clear(&self, key: &str) {
        self.write(key, std::ptr::null());
    }

    fn write(&self, key: &str, value: CFTypeRef) {
        let key = CFString::new(key);
        unsafe {
            CFPreferencesSetAppValue(
                key.as_concrete_TypeRef(),
                value,
                self.domain.as_concrete_TypeRef(),
            );
        }
    }

    pub fn save(&self) -> Result<()> {
        if unsafe { CFPreferencesAppSynchronize(self.domain.as_concrete_TypeRef()) } == 0 {
            bail!("Couldn't save the settings in {}.", self.name);
        }
        notify(&self.name)
    }
}

pub fn notify(domain: &str) -> Result<()> {
    let notification = CString::new(format!("{domain}.changed"))?;
    let status = unsafe { notify_post(notification.as_ptr()) };
    if status != 0 {
        bail!("Saved, but couldn't tell Dia (notify_post returned {status}). Restart Dia to see the changes.");
    }
    Ok(())
}

pub fn as_bool(value: &CFType) -> Option<bool> {
    if let Some(flag) = value.downcast::<CFBoolean>() {
        return Some(flag.into());
    }
    if let Some(number) = value.downcast::<CFNumber>() {
        return number.to_f64().map(|number| number != 0.0);
    }
    value
        .downcast::<CFString>()
        .map(|text| is_true_string(&text.to_string()))
}

// Matches NSString.boolValue.
fn is_true_string(text: &str) -> bool {
    let trimmed = text.trim_start();
    if matches!(trimmed.chars().next(), Some('Y' | 'y' | 'T' | 't')) {
        return true;
    }
    let unsigned = trimmed.strip_prefix(['+', '-']).unwrap_or(trimmed);
    matches!(
        unsigned.trim_start_matches('0').chars().next(),
        Some('1'..='9')
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn clear(prefs: &Prefs, keys: &[&str]) {
        for key in keys {
            prefs.clear(key);
        }
        unsafe {
            CFPreferencesAppSynchronize(prefs.domain.as_concrete_TypeRef());
        }
        let _ = std::process::Command::new("/usr/bin/defaults")
            .args(["delete", &prefs.name])
            .output();
        if let Ok(home) = std::env::var("HOME") {
            let _ = std::fs::remove_file(
                std::path::Path::new(&home).join(format!("Library/Preferences/{}.plist", prefs.name)),
            );
        }
    }

    #[test]
    fn string_bool_matches_foundation() {
        for truthy in [
            "YES", "yes", "true", "T", "1", " 1", "+1", "-1", "001", "+001", "-001", "2",
        ] {
            assert!(is_true_string(truthy), "expected true for {truthy:?}");
        }
        for falsy in [
            "", "0", "NO", "false", "+YES", "-YES", "0YES", "++1", "+-1", "-true", " 000T", "0.5",
        ] {
            assert!(!is_true_string(falsy), "expected false for {falsy:?}");
        }
    }

    #[test]
    fn bools_reads_many_keys_in_one_go() {
        let domain = format!("com.diapatches.test.batch.{}", std::process::id());
        let prefs = Prefs::new(&domain);
        prefs.set("on", true);
        prefs.set("off", false);
        assert!(prefs.save().is_ok());

        let reloaded = Prefs::new(&domain);
        assert_eq!(
            reloaded.bools(&["on", "off", "missing"]),
            vec![Some(true), Some(false), None]
        );
        assert_eq!(reloaded.bools(&["on", "on"]), vec![Some(true), Some(true)]);
        assert!(reloaded.bools(&[]).is_empty());

        clear(&reloaded, &["on", "off"]);
    }

    #[test]
    fn prefs_round_trips_booleans_and_numbers() {
        let domain = format!("com.diapatches.test.prefs.{}", std::process::id());
        let prefs = Prefs::new(&domain);
        prefs.set("flagOn", true);
        prefs.set("flagOff", false);
        assert!(prefs.save().is_ok());

        let reloaded = Prefs::new(&domain);
        assert_eq!(
            reloaded.bools(&["flagOn", "flagOff", "missing"]),
            vec![Some(true), Some(false), None]
        );

        clear(&reloaded, &["flagOn", "flagOff"]);
    }

    #[test]
    fn prefs_preserves_dictionaries_and_arrays_and_ignores_non_bools() {
        use core_foundation::{array::CFArray, dictionary::CFDictionary};

        let domain = format!("com.diapatches.test.containers.{}", std::process::id());
        let prefs = Prefs::new(&domain);

        let dict = CFDictionary::from_CFType_pairs(&[(
            CFString::new("space-1"),
            CFString::new("#112233"),
        )]);
        let array = CFArray::from_CFTypes(&[CFString::new("--disable-gpu")]);
        let dict_key = CFString::new("profileColors");
        let array_key = CFString::new("launchFlagsArgs");
        unsafe {
            CFPreferencesSetAppValue(
                dict_key.as_concrete_TypeRef(),
                dict.as_CFTypeRef(),
                prefs.domain.as_concrete_TypeRef(),
            );
            CFPreferencesSetAppValue(
                array_key.as_concrete_TypeRef(),
                array.as_CFTypeRef(),
                prefs.domain.as_concrete_TypeRef(),
            );
        }
        prefs.set("profileColorPicker", true);
        prefs.set("launchFlags", true);
        assert!(prefs.save().is_ok());

        let reloaded = Prefs::new(&domain);
        assert_eq!(
            reloaded.bools(&[
                "profileColorPicker",
                "launchFlags",
                "profileColors",
                "launchFlagsArgs"
            ]),
            vec![Some(true), Some(true), None, None]
        );

        let raw_dict = unsafe {
            CFPreferencesCopyAppValue(
                dict_key.as_concrete_TypeRef(),
                reloaded.domain.as_concrete_TypeRef(),
            )
        };
        assert!(!raw_dict.is_null());
        let raw_dict = unsafe { CFType::wrap_under_create_rule(raw_dict) };
        assert!(raw_dict.downcast::<CFDictionary>().is_some());

        let raw_array = unsafe {
            CFPreferencesCopyAppValue(
                array_key.as_concrete_TypeRef(),
                reloaded.domain.as_concrete_TypeRef(),
            )
        };
        assert!(!raw_array.is_null());
        let raw_array = unsafe { CFType::wrap_under_create_rule(raw_array) };
        assert!(raw_array.downcast::<CFArray>().is_some());

        clear(
            &reloaded,
            &[
                "profileColorPicker",
                "launchFlags",
                "profileColors",
                "launchFlagsArgs",
            ],
        );
    }
}
