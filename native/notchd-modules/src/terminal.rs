//! The terminal of a custom module (`module.json`'s `terminal`): its command
//! in a terminal in the notch (`term::TermModule`), with the id of the
//! module; its title and default command are the manifest's, its other
//! settings are under its id (`directory`, `command`, `idleMinutes`, `width`,
//! `height`, `font`). The closed notch shows the title the program gives the
//! terminal, else the module's (when the module has no compact view of its
//! own); without a folder it starts in the home. The command is a shell
//! script: "cd ~/app && npm run dev" runs both. Over IPC: `terminal <id> ...`.

use crate::term::{Kind, TermModule};
use notchd_core::agent::AgentTitle;
use notchd_core::terminal::plain_title;
use std::collections::BTreeSet;
use std::sync::Mutex;

/// A program of your own is never "working": its title as it is.
fn title_of(raw: &str) -> AgentTitle {
    AgentTitle {
        working: false,
        title: plain_title(Some(raw)).title,
    }
}

/// An id as the `&'static str` a module names itself by: one allocation per
/// distinct id for the life of the daemon (the few terminals a config ever
/// names), reused after.
pub fn intern(id: &str) -> &'static str {
    static IDS: Mutex<BTreeSet<&'static str>> = Mutex::new(BTreeSet::new());
    let mut set = IDS.lock().unwrap_or_else(|p| p.into_inner());
    if let Some(s) = set.get(id) {
        return s;
    }
    let s: &'static str = Box::leak(id.to_string().into_boxed_str());
    set.insert(s);
    s
}

/// The terminal of custom module `id`; its title and command come with
/// `define` (the module's `module.json`).
pub fn new(id: &str) -> TermModule {
    TermModule::new(Kind {
        id: intern(id),
        app: id.to_string(),
        parse_title: title_of,
        default_command: String::new(),
        logo: None,
        own_dir: false,
        script: true,
        ipc: "terminal",
        usage: None,
        custom: true,
    })
}
