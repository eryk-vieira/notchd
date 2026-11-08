//! Custom modules on disk (docs/modules.md): `<modules dir>/<id>/module.json`.
//! Writing and removing the folders of the modules the user makes through
//! IPC or the settings, and the one-time move of the config's old
//! `terminals` into folders. The rules (which id is free, what a terminal's
//! `module.json` holds, what migrates) are `notchd_core::config`'s and
//! `notchd_core::custom`'s; this only does the file work, so a test runs it
//! on a temp dir.

use notchd_core::config;
use notchd_core::custom::{TerminalAdd, parse_terminal_add};
use serde_json::Value;
use std::fs;
use std::path::Path;

/// Every folder of `dir` with its `module.json` as JSON (`Null` when it has
/// none or it does not parse), by name.
pub fn existing(dir: &Path) -> Vec<(String, Value)> {
    let Ok(read) = fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut out: Vec<(String, Value)> = read
        .flatten()
        .filter(|e| e.path().is_dir())
        .map(|e| {
            let name = e.file_name().to_string_lossy().into_owned();
            let manifest = fs::read_to_string(e.path().join("module.json"))
                .ok()
                .and_then(|t| serde_json::from_str(&t).ok())
                .unwrap_or(Value::Null);
            (name, manifest)
        })
        .collect();
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out
}

/// Writes the folder `<dir>/<id>` with `manifest` as its `module.json`. It
/// must not exist: a module is never overwritten.
pub fn write_module(dir: &Path, id: &str, manifest: &Value) -> Result<(), String> {
    let folder = dir.join(id);
    fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    fs::create_dir(&folder).map_err(|e| format!("{}: {e}", folder.display()))?;
    let mut text = serde_json::to_string_pretty(manifest).map_err(|e| e.to_string())?;
    text.push('\n');
    fs::write(folder.join("module.json"), text)
        .map_err(|e| format!("{}: {e}", folder.join("module.json").display()))
}

/// What moving the config's `terminals` into folders did.
#[derive(Debug, Default, PartialEq)]
pub struct Migration {
    /// The config without the entries that are folders now, when that
    /// changed it. `None`: the config stays as it is.
    pub next: Option<Value>,
    /// What to say in the log, one line each.
    pub notes: Vec<String>,
}

/// Moves each valid entry of the config's `terminals` into a folder
/// (`title`, `terminal.command`). `terminals` loses its entries only after
/// every folder is written: one that cannot be written leaves the config
/// whole, and the next start tries again (a folder an earlier run wrote is
/// recognised). An id that clashes with another folder stays in `terminals`
/// and is said in `notes`.
pub fn migrate_terminals(dir: &Path, cfg: &Value) -> Migration {
    let mut out = Migration::default();
    if cfg.get("terminals").is_none() {
        return out;
    }
    let plan = config::terminal_migration(cfg, &existing(dir));
    out.notes = plan
        .left
        .iter()
        .map(|l| format!("terminals: not moved to a folder, {l}"))
        .collect();
    let mut failed = false;
    let mut moved = plan.done.clone();
    for (id, manifest) in &plan.folders {
        match write_module(dir, id, manifest) {
            Ok(()) => {
                out.notes
                    .push(format!("terminals: {id} is now {}", dir.join(id).display()));
                moved.push(id.clone());
            }
            Err(e) => {
                failed = true;
                out.notes.push(format!(
                    "terminals: could not write the folder of {id}: {e}"
                ));
            }
        }
    }
    if failed {
        out.notes
            .push("terminals: left in the config, to try again at the next start".into());
        return out;
    }
    let next = config::without_migrated_terminals(cfg, &moved);
    if next != *cfg {
        out.next = Some(next);
    }
    out
}

/// What `terminal add` made: the module's id and the `directory` setting to
/// store under it.
#[derive(Debug, PartialEq)]
pub struct Added {
    pub id: String,
    pub directory: Option<String>,
}

/// `terminal add <id> <command> [--directory <dir>] [--title <title>]`, or
/// `terminal add` alone (a terminal running `$SHELL`, with the first free id
/// and title: what the settings' Add terminal does): writes the folder of a
/// terminal-only module. `taken` are the ids of every module known, which a
/// new one cannot have. `Err` is the reply.
pub fn add_terminal(
    dir: &Path,
    cfg: &Value,
    taken: &[String],
    args: &[String],
) -> Result<Added, String> {
    let on_disk: Vec<String> = existing(dir).into_iter().map(|(n, _)| n).collect();
    let all: Vec<&str> = taken
        .iter()
        .chain(on_disk.iter())
        .map(String::as_str)
        .collect();
    let ask = if args.is_empty() {
        let id = config::new_terminal_id(cfg, &all);
        let n = id.strip_prefix("terminal-");
        TerminalAdd {
            title: Some(n.map_or("Terminal".to_owned(), |n| format!("Terminal {n}"))),
            id,
            command: "$SHELL".into(),
            directory: None,
        }
    } else {
        parse_terminal_add(args)?
    };
    if !config::is_module_id_free(&ask.id, &all) {
        return Err(format!(
            "{}: not a free module id (letters, digits, - and _, and not a module or config key already)",
            ask.id
        ));
    }
    let manifest = config::terminal_manifest(ask.title.as_deref().unwrap_or(""), &ask.command);
    write_module(dir, &ask.id, &manifest)?;
    Ok(Added {
        id: ask.id,
        directory: ask.directory,
    })
}

/// `module remove <id>`: deletes the folder of custom module `id`. `shipped`
/// are the ids of the modules notchd and the UIs ship, which are not
/// folders. `Err` is the reply.
pub fn remove_module(dir: &Path, id: &str, shipped: &[&str]) -> Result<(), String> {
    let no = || format!("no custom module {id}");
    if !config::is_module_id_free(id, shipped) {
        return Err(no());
    }
    let folder = dir.join(id);
    if !folder.is_dir() {
        return Err(no());
    }
    fs::remove_dir_all(&folder).map_err(|e| format!("{}: {e}", folder.display()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use notchd_testkit::tempdir::TempDir;
    use serde_json::json;

    fn args(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| (*s).to_string()).collect()
    }

    fn read(dir: &Path, id: &str) -> Value {
        serde_json::from_str(&fs::read_to_string(dir.join(id).join("module.json")).unwrap())
            .unwrap()
    }

    #[test]
    fn the_terminals_become_folders_and_leave_the_config_once_all_are_written() {
        let tmp = TempDir::new("migrate");
        let modules = tmp.path().join("modules");
        let cfg = json!({
            "modules": ["btop"],
            "btop": { "width": 900 },
            "terminals": {
                "btop": { "title": "System", "command": "btop" },
                "dev": { "command": "npm run dev" }
            }
        });
        let m = migrate_terminals(&modules, &cfg);
        assert_eq!(
            read(&modules, "btop"),
            json!({ "title": "System", "terminal": { "command": "btop" } })
        );
        assert_eq!(
            read(&modules, "dev"),
            json!({ "terminal": { "command": "npm run dev" } })
        );
        // The settings under the id are where they belong already.
        assert_eq!(
            m.next,
            Some(json!({ "modules": ["btop"], "btop": { "width": 900 } }))
        );
        // Again (an earlier run stopped before the config): the same.
        let again = migrate_terminals(&modules, &cfg);
        assert_eq!(again.next, m.next);
        // Nothing to move: nothing to do.
        assert_eq!(
            migrate_terminals(&modules, &m.next.unwrap()),
            Migration::default()
        );
    }

    #[test]
    fn a_clashing_id_stays_in_the_config_and_is_logged() {
        let tmp = TempDir::new("clash");
        let modules = tmp.path().join("modules");
        write_module(&modules, "dev", &json!({ "command": ["./run.sh"] })).unwrap();
        let cfg = json!({ "terminals": {
            "btop": { "command": "btop" },
            "dev": { "command": "npm run dev" }
        } });
        let m = migrate_terminals(&modules, &cfg);
        assert!(modules.join("btop/module.json").is_file());
        assert_eq!(
            read(&modules, "dev"),
            json!({ "command": ["./run.sh"] }),
            "the folder is not touched"
        );
        assert_eq!(
            m.next,
            Some(json!({ "terminals": { "dev": { "command": "npm run dev" } } }))
        );
        assert!(
            m.notes
                .iter()
                .any(|n| n.contains("dev") && n.contains("folder")),
            "{:?}",
            m.notes
        );
    }

    #[test]
    fn a_folder_that_cannot_be_written_leaves_the_config_whole() {
        let tmp = TempDir::new("unwritable");
        // A file where the modules directory should be.
        let modules = tmp.path().join("modules");
        fs::write(&modules, "not a folder").unwrap();
        let cfg = json!({ "terminals": { "btop": { "command": "btop" } } });
        let m = migrate_terminals(&modules, &cfg);
        assert_eq!(m.next, None);
        assert!(m.notes.iter().any(|n| n.contains("could not write")));
    }

    #[test]
    fn add_terminal_writes_a_terminal_only_folder() {
        let tmp = TempDir::new("add");
        let modules = tmp.path().join("modules");
        let cfg = json!({});
        let added = add_terminal(
            &modules,
            &cfg,
            &["media".into()],
            &args(&["btop", "btop", "--title", "System", "--directory", "~/x"]),
        )
        .unwrap();
        assert_eq!(
            added,
            Added {
                id: "btop".into(),
                directory: Some("~/x".into())
            }
        );
        assert_eq!(
            read(&modules, "btop"),
            json!({ "title": "System", "terminal": { "command": "btop" } })
        );
        // Taken by a folder, a module or a config key; or not an id.
        for bad in [
            args(&["btop", "x"]),
            args(&["media", "x"]),
            args(&["position", "x"]),
            args(&["a/b", "x"]),
            args(&["only-an-id"]),
        ] {
            assert!(
                add_terminal(&modules, &cfg, &["media".into()], &bad).is_err(),
                "{bad:?}"
            );
        }
        assert!(!modules.join("a").exists());
    }

    #[test]
    fn add_terminal_alone_runs_your_shell_under_the_first_free_id() {
        let tmp = TempDir::new("add-shell");
        let modules = tmp.path().join("modules");
        let first = add_terminal(&modules, &json!({}), &[], &[]).unwrap();
        assert_eq!(first.id, "terminal");
        assert_eq!(
            read(&modules, "terminal"),
            json!({ "title": "Terminal", "terminal": { "command": "$SHELL" } })
        );
        let second = add_terminal(&modules, &json!({}), &[], &[]).unwrap();
        assert_eq!(second.id, "terminal-2");
        assert_eq!(read(&modules, "terminal-2")["title"], "Terminal 2");
    }

    #[test]
    fn remove_module_deletes_the_folder_of_a_custom_module_only() {
        let tmp = TempDir::new("remove");
        let modules = tmp.path().join("modules");
        write_module(&modules, "linear", &json!({ "command": ["./run.sh"] })).unwrap();
        fs::write(modules.join("linear/run.sh"), "x").unwrap();
        write_module(
            &modules,
            "media",
            &json!({ "terminal": { "command": "x" } }),
        )
        .unwrap();
        assert_eq!(remove_module(&modules, "linear", &["media"]), Ok(()));
        assert!(!modules.join("linear").exists());
        // Not a folder, or not a custom module's: refused, nothing deleted.
        assert!(remove_module(&modules, "linear", &["media"]).is_err());
        assert!(remove_module(&modules, "media", &["media"]).is_err());
        assert!(modules.join("media").is_dir());
        assert!(remove_module(&modules, "../modules", &[]).is_err());
        assert!(remove_module(&modules, "position", &[]).is_err());
    }
}
