//! What the daemon knows of its user modules, between the module host's
//! events ([`ModEvent`]) and the two places they go: the store (a module's
//! facts, a peek or an open request, its settings page) and the UIs (the
//! `module` and `view` messages). Pure over a [`Store`]; the hub owns the
//! lock, the socket and the host.
//!
//! A custom module has a process (its views), a terminal (the daemon's own
//! `terminal` module, with the module's id) or both. The two parts are
//! one module to the UIs: the closed views are the process's (else the
//! terminal's), the expanded one the process's above the terminal's.
//!
//! The views a UI is sent are the module's, except while it has an error
//! (a crash, a manifest, an invalid tree, an `error` of its own): then its
//! `compact`, `verticalCompact` and `expanded` slots hold the host's error row
//! (`modhost::error_row`) and `attention` is set, until the host says it is
//! healthy again.

use crate::modhost::{ModEvent, error_row};
use notchd_core::store::{ModuleFacts, Store};
use notchd_proto::module::ModuleSet;
use notchd_proto::module::TerminalDef;
use notchd_proto::ui::{ModuleInfo, View};
use notchd_proto::{Manifest, Node, Slot, ToUi};
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::path::PathBuf;

/// `NotchModule.expandedWidth`'s default.
const DEFAULT_EXPANDED_WIDTH: u32 = 400;

/// The slots an error row takes the place of.
const ERROR_SLOTS: [Slot; 3] = [Slot::Compact, Slot::VerticalCompact, Slot::Expanded];

/// What a custom module's terminal says of itself (the daemon's `terminal`
/// module of the same id): its facts and its views.
#[derive(Debug, Clone, Default)]
struct TermPart {
    priority: i32,
    attention: bool,
    expanded_width: u32,
    views: Vec<(Slot, Node)>,
}

/// The facts a module has now, the process's and the terminal's together.
struct Merged {
    priority: i32,
    active: bool,
    attention: bool,
    expanded_width: u32,
}

#[derive(Debug, Clone, Default)]
struct ModState {
    title: String,
    priority: i32,
    active: bool,
    icon: String,
    /// The module's own `attention`; an error sets it on top.
    attention: bool,
    expanded_width: u32,
    urgent_peek: bool,
    peek_on_focused_screen: bool,
    /// The providers its manifest subscribes to.
    subscribe: Vec<String>,
    /// Its settings' defaults, as a config object (a key with a dot nests).
    defaults: Value,
    /// A module that lives in the daemon (`corehost`), not a custom one.
    builtin: bool,
    /// The manifest has a process (`command`).
    process: bool,
    /// The manifest has a terminal; `term` is what the daemon's terminal
    /// module of this id says while it is loaded.
    terminal: Option<TerminalDef>,
    term: Option<TermPart>,

    /// The error text, and the row that shows it.
    error: Option<(String, Node)>,
    /// What the module sent.
    views: Vec<(Slot, Node)>,
    /// What the UIs were last sent.
    sent_views: Vec<(Slot, Node)>,
    sent_info: Option<ModuleInfo>,
    rev: u64,
    view_rev: u64,
}

impl ModState {
    fn from_manifest(id: &str, m: &Manifest) -> ModState {
        ModState {
            process: m.has_process(),
            terminal: m.terminal.clone(),

            title: m.title.clone().unwrap_or_else(|| id.to_string()),
            priority: m.priority.unwrap_or(0),
            icon: m.icon.clone().unwrap_or_default(),
            expanded_width: m.expanded_width.unwrap_or(DEFAULT_EXPANDED_WIDTH),
            urgent_peek: m.urgent_peek.unwrap_or(false),
            peek_on_focused_screen: m.peek_on_focused_screen.unwrap_or(false),
            subscribe: m.subscribe.clone(),
            defaults: settings_defaults(m),
            ..ModState::default()
        }
    }

    /// The process's tree for a slot: the error row in place of its own.
    fn process_view(&self, slot: Slot) -> Option<&Node> {
        if let Some((_, row)) = &self.error
            && ERROR_SLOTS.contains(&slot)
        {
            return Some(row);
        }
        self.views.iter().find(|(s, _)| *s == slot).map(|(_, n)| n)
    }

    /// The tree a slot shows now. With a terminal too, a closed slot is the
    /// process's, else the terminal's; the expanded view is the process's
    /// above the terminal's, which fills the rest.
    fn effective(&self, slot: Slot) -> Option<Node> {
        let process = self.process_view(slot);
        let term = self
            .term
            .as_ref()
            .and_then(|t| t.views.iter().find(|(s, _)| *s == slot).map(|(_, n)| n));
        match (process, term) {
            (Some(p), Some(t)) if slot == Slot::Expanded => Some(stack(p, t)),
            (Some(p), _) => Some(p.clone()),
            (None, t) => t.cloned(),
        }
    }

    /// The facts the module has now: the process's and the terminal's.
    fn merged(&self) -> Merged {
        match &self.term {
            None => Merged {
                priority: self.priority,
                active: self.active,
                attention: self.attention || self.error.is_some(),
                expanded_width: self.expanded_width,
            },
            // A terminal alone is what it was: its own facts. With a process
            // the process's priority and icon win, and the notch is as wide
            // as the wider of the two.
            Some(t) if !self.process => Merged {
                priority: t.priority,
                active: true,
                attention: t.attention || self.error.is_some(),
                expanded_width: t.expanded_width,
            },
            Some(t) => Merged {
                priority: self.priority,
                active: true,
                attention: self.attention || t.attention || self.error.is_some(),
                expanded_width: self.expanded_width.max(t.expanded_width),
            },
        }
    }

    fn facts(&self, id: &str) -> ModuleFacts {
        let merged = self.merged();
        let mut f = ModuleFacts::new(id);
        f.info.priority = f64::from(merged.priority);
        f.info.active = merged.active;
        f.info.compact = self.effective(Slot::Compact).is_some();
        f.info.icon = !self.icon.is_empty();
        f.info.peek = self.effective(Slot::Peek).is_some();
        f.info.attention = merged.attention;
        f.info.urgent_peek = self.urgent_peek;
        f.expanded = self.effective(Slot::Expanded).is_some();
        f.peek_on_focused_screen = self.peek_on_focused_screen;
        f
    }

    fn info(&self, id: &str) -> ModuleInfo {
        let merged = self.merged();
        ModuleInfo {
            id: id.to_string(),
            rev: self.rev,
            title: self.title.clone(),
            priority: merged.priority,
            active: merged.active,
            icon: self.icon.clone(),
            attention: merged.attention,
            expanded_width: merged.expanded_width,
            urgent_peek: self.urgent_peek,
            peek_on_focused_screen: self.peek_on_focused_screen,
            status: None,
            error: self.error.as_ref().map(|(text, _)| text.clone()),
        }
    }
}

/// The user modules the host reported.
#[derive(Debug, Default)]
pub struct Mods {
    mods: BTreeMap<String, ModState>,
    /// The last `rev` and view `rev` sent for a module that was removed. A
    /// UI drops a message whose `rev` is not above the one it holds, so a
    /// module loaded again goes on from these instead of starting over.
    retired: BTreeMap<String, (u64, u64)>,
}

/// `{ moduleId, title, settings, origin, process, terminal, dir,
/// permissions }`: what the schema builds a module's page from
/// (`Settings.moduleFields`) and the Modules page lists it by. A terminal's
/// fields come first, the manifest's own after (one with the same key wins).
fn settings_def(id: &str, m: &Manifest, dir: Option<&PathBuf>) -> Value {
    let title = m.title.clone().unwrap_or_else(|| id.to_string());
    let own = serde_json::to_value(&m.settings).unwrap_or_else(|_| json!([]));
    let mut settings: Vec<Value> = Vec::new();
    if let Some(t) = &m.terminal {
        let own_keys: Vec<&str> = m.settings.iter().filter_map(|f| f.key.as_deref()).collect();
        settings.extend(
            notchd_core::settings::terminal_settings(&t.command, &title)
                .into_iter()
                .filter(|f| {
                    !f.get("key")
                        .and_then(Value::as_str)
                        .is_some_and(|k| own_keys.contains(&k))
                }),
        );
    }
    if let Value::Array(own) = own {
        settings.extend(own);
    }
    json!({
        "moduleId": id,
        "title": title,
        "settings": settings,
        "origin": "user",
        "process": m.has_process(),
        "terminal": m.terminal.is_some(),
        "dir": dir.map(|d| d.to_string_lossy().into_owned()),
        "permissions": m.permissions,
    })
}

/// Two trees one above the other, the second filling the rest: a custom
/// module's process view over its terminal.
fn stack(top: &Node, bottom: &Node) -> Node {
    let tree = json!({ "t": "column", "gap": 10, "children": [top, bottom] });
    serde_json::from_value(tree).unwrap_or_else(|_| top.clone())
}

/// The value each settings field has while the config says nothing: the
/// field's `default`, under its `key` (a dotted key nests).
fn settings_defaults(m: &Manifest) -> Value {
    let mut out = Value::Object(Default::default());
    for f in &m.settings {
        let Some(key) = f.key.as_deref().filter(|_| !f.default.is_null()) else {
            continue;
        };
        insert_at(&mut out, key, f.default.clone());
    }
    out
}

fn insert_at(into: &mut Value, key: &str, value: Value) {
    let Value::Object(map) = into else { return };
    match key.split_once('.') {
        None => {
            map.insert(key.to_string(), value);
        }
        Some((head, rest)) => {
            let child = map
                .entry(head.to_string())
                .or_insert_with(|| Value::Object(Default::default()));
            insert_at(child, rest, value);
        }
    }
}

/// `config` over `defaults`, object by object: what a module is sent as its
/// config, so it reads a setting the user never touched as its default.
pub fn with_defaults(defaults: &Value, config: &Value) -> Value {
    match (defaults, config) {
        (Value::Object(d), Value::Object(c)) => {
            let mut out = d.clone();
            for (k, v) in c {
                let merged = match d.get(k) {
                    Some(base) => with_defaults(base, v),
                    None => v.clone(),
                };
                out.insert(k.clone(), merged);
            }
            Value::Object(out)
        }
        (_, c) => c.clone(),
    }
}

impl Mods {
    pub fn new() -> Mods {
        Mods::default()
    }

    pub fn knows(&self, id: &str) -> bool {
        self.mods.contains_key(id)
    }

    /// The user modules' ids: the ones the module host runs.
    pub fn ids(&self) -> Vec<String> {
        self.mods
            .iter()
            .filter(|(_, m)| !m.builtin)
            .map(|(id, _)| id.clone())
            .collect()
    }

    /// Whether a module of the daemon itself has this id.
    pub fn is_builtin(&self, id: &str) -> bool {
        self.mods.get(id).is_some_and(|m| m.builtin)
    }

    /// A module that lives in the daemon (`corehost`): its facts and its
    /// views, as it says them now. The store follows, and the `module` and
    /// `view` messages the UIs need are returned. Its settings page is the
    /// UI catalog's (the JSON file next to its QML), not a def of its own.
    pub fn set_builtin(
        &mut self,
        store: &mut Store,
        id: &str,
        title: &str,
        facts: &notchd_modules::Facts,
        views: Vec<(Slot, Option<Node>)>,
    ) -> Vec<ToUi> {
        let m = self.entry(id);
        m.builtin = true;
        m.title = title.to_string();
        m.priority = facts.priority;
        m.active = facts.active;
        m.icon = facts.icon.clone();
        m.attention = facts.attention;
        m.expanded_width = facts.expanded_width;
        m.urgent_peek = facts.urgent_peek;
        m.peek_on_focused_screen = facts.peek_on_focused_screen;
        m.views = views
            .into_iter()
            .filter_map(|(slot, tree)| tree.map(|t| (slot, t)))
            .collect();
        self.sync(store, id)
    }

    /// A custom module's terminal (the daemon's own `terminal` module of its
    /// id): its facts and its views, as it says them now. The module is one
    /// to the UIs: see [`ModState::effective`].
    pub fn set_terminal(
        &mut self,
        store: &mut Store,
        id: &str,
        facts: &notchd_modules::Facts,
        views: Vec<(Slot, Option<Node>)>,
    ) -> Vec<ToUi> {
        let m = self.entry(id);
        m.term = Some(TermPart {
            priority: facts.priority,
            attention: facts.attention,
            expanded_width: facts.expanded_width,
            views: views
                .into_iter()
                .filter_map(|(slot, tree)| tree.map(|t| (slot, t)))
                .collect(),
        });
        self.sync(store, id)
    }

    /// The terminal of a custom module is gone (unloaded): the module goes on
    /// with its process, or with no views at all.
    pub fn clear_terminal(&mut self, store: &mut Store, id: &str) -> Vec<ToUi> {
        let Some(m) = self.mods.get_mut(id) else {
            return Vec::new();
        };
        if m.term.take().is_none() {
            return Vec::new();
        }
        self.sync(store, id)
    }

    /// The custom modules that have a terminal, as `(id, title, command)`:
    /// what the daemon's terminal modules are made from.
    pub fn terminal_defs(&self) -> Vec<(String, String, String)> {
        self.mods
            .iter()
            .filter(|(_, m)| !m.builtin)
            .filter_map(|(id, m)| {
                let t = m.terminal.as_ref()?;
                Some((id.clone(), m.title.clone(), t.command.clone()))
            })
            .collect()
    }

    /// Whether `id` is a custom module with a process.
    pub fn has_process(&self, id: &str) -> bool {
        self.mods.get(id).is_some_and(|m| !m.builtin && m.process)
    }

    /// Whether an event of `action` in a module's view is for its terminal
    /// (the daemon's `terminal` module) rather than its process, for a module
    /// with both. The terminal's surface and header say `typed`, `leave`,
    /// `keyboard`, `close` and `restart`; `restart` is the process's while it
    /// shows its error row (the row's button).
    pub fn is_terminal_action(&self, id: &str, action: &str) -> bool {
        match action {
            "typed" | "leave" | "keyboard" | "close" => true,
            "restart" => self.mods.get(id).is_none_or(|m| m.error.is_none()),
            _ => false,
        }
    }

    /// The providers a user module's manifest subscribes to.
    pub fn subscriptions(&self, id: &str) -> Vec<String> {
        self.mods
            .get(id)
            .map_or_else(Vec::new, |m| m.subscribe.clone())
    }

    /// The config a module is sent: its settings' values from the config
    /// file over the defaults of its manifest.
    pub fn module_config(&self, id: &str, stored: &Value) -> Value {
        let defaults = self
            .mods
            .get(id)
            .map_or(Value::Null, |m| m.defaults.clone());
        with_defaults(&defaults, stored)
    }

    /// Applies an event from the host: the store follows, and the `module`
    /// and `view` messages the UIs need are returned.
    pub fn apply(&mut self, store: &mut Store, ev: ModEvent, now: u64) -> Vec<ToUi> {
        match ev {
            ModEvent::Loaded {
                module,
                manifest,
                dir,
            } => {
                let old = self.mods.remove(&module);
                let mut m = ModState::from_manifest(&module, &manifest);
                if let Some((rev, view_rev)) = self.retired.remove(&module) {
                    m.rev = rev;
                    m.view_rev = view_rev;
                }
                if let Some(old) = old {
                    // A save: the module's own state carries over until it
                    // sends again.
                    m.active = old.active;
                    m.attention = old.attention;
                    m.error = old.error;
                    m.term = old.term;
                    m.views = old.views;
                    m.sent_views = old.sent_views;
                    m.sent_info = old.sent_info;
                    m.rev = old.rev;
                    m.view_rev = old.view_rev;
                }
                store.set_module_def(settings_def(&module, &manifest, dir.as_ref()));
                self.mods.insert(module.clone(), m);
                self.sync(store, &module)
            }
            ModEvent::Removed { module } => {
                let Some(old) = self.mods.remove(&module) else {
                    return Vec::new();
                };
                store.remove_module(&module);
                store.remove_module_def(&module);
                let view_rev = old.view_rev + 1;
                self.retired.insert(module.clone(), (old.rev, view_rev));
                // The slots it had go empty.
                old.sent_views
                    .iter()
                    .map(|(slot, _)| {
                        ToUi::View(View {
                            module: module.clone(),
                            slot: *slot,
                            rev: view_rev,
                            tree: None,
                        })
                    })
                    .collect()
            }
            ModEvent::View { module, slot, tree } => {
                let m = self.entry(&module);
                m.views.retain(|(s, _)| *s != slot);
                if let Some(tree) = tree {
                    m.views.push((slot, tree));
                }
                self.sync(store, &module)
            }
            ModEvent::Set { module, set } => {
                apply_set(self.entry(&module), &set);
                self.sync(store, &module)
            }
            ModEvent::Peek { module, peek } => {
                // `NotchModule.requestPeek(ms)`; the facts are current.
                let out = self.sync(store, &module);
                store.request_peek(&module, Some(f64::from(peek.ms)), now);
                out
            }
            ModEvent::Open { module } => {
                let out = self.sync(store, &module);
                store.open_module(&module, now);
                out
            }
            ModEvent::Error {
                module,
                text,
                log_path,
                ..
            } => {
                let row = error_row(&text, &log_path);
                self.entry(&module).error = Some((text, row));
                self.sync(store, &module)
            }
            ModEvent::ErrorCleared { module } => {
                self.entry(&module).error = None;
                self.sync(store, &module)
            }
            // Providers, notifications and the log are the host's and the
            // providers' business, not the notch's state.
            ModEvent::Started { .. }
            | ModEvent::Notify { .. }
            | ModEvent::Subscribe { .. }
            | ModEvent::Unsubscribe { .. }
            | ModEvent::Log { .. } => Vec::new(),
        }
    }

    /// A module's state, made on its first word: a module removed before
    /// goes on from its last revs.
    fn entry(&mut self, id: &str) -> &mut ModState {
        let retired = &mut self.retired;
        self.mods.entry(id.to_string()).or_insert_with(|| {
            let (rev, view_rev) = retired.remove(id).unwrap_or_default();
            ModState {
                rev,
                view_rev,
                ..ModState::default()
            }
        })
    }

    /// Puts a module's facts in the store and returns what changed for the
    /// UIs: a `module` when its facts differ from the last sent, a `view` per
    /// slot whose tree does.
    fn sync(&mut self, store: &mut Store, id: &str) -> Vec<ToUi> {
        let Some(m) = self.mods.get_mut(id) else {
            return Vec::new();
        };
        store.set_module(m.facts(id));
        let mut out = Vec::new();
        let mut info = m.info(id);
        let changed = m.sent_info.as_ref().is_none_or(|last| {
            let mut a = last.clone();
            a.rev = info.rev;
            a != info
        });
        if changed {
            m.rev += 1;
            info.rev = m.rev;
            m.sent_info = Some(info.clone());
            out.push(ToUi::Module(info));
        }
        for slot in Slot::ALL {
            let now = m.effective(slot);
            let before = m
                .sent_views
                .iter()
                .find(|(s, _)| *s == slot)
                .map(|(_, n)| n);
            if now.as_ref() == before {
                continue;
            }
            m.sent_views.retain(|(s, _)| *s != slot);
            if let Some(n) = &now {
                m.sent_views.push((slot, n.clone()));
            }
            m.view_rev += 1;
            out.push(ToUi::View(View {
                module: id.to_string(),
                slot,
                rev: m.view_rev,
                tree: now,
            }));
        }
        out
    }

    /// What a UI that just connected is sent: every module's facts and one
    /// `view` per slot in use.
    pub fn snapshot(&self) -> Vec<ToUi> {
        let mut out = Vec::new();
        for (id, m) in &self.mods {
            if let Some(info) = &m.sent_info {
                out.push(ToUi::Module(info.clone()));
            }
            for (slot, tree) in &m.sent_views {
                out.push(ToUi::View(View {
                    module: id.clone(),
                    slot: *slot,
                    rev: m.view_rev,
                    tree: Some(tree.clone()),
                }));
            }
        }
        out
    }
}

fn apply_set(m: &mut ModState, set: &ModuleSet) {
    if let Some(v) = set.active {
        m.active = v;
    }
    if let Some(v) = set.priority {
        m.priority = v;
    }
    if let Some(v) = &set.icon {
        m.icon = v.clone();
    }
    if let Some(v) = set.attention {
        m.attention = v;
    }
    if let Some(v) = set.urgent_peek {
        m.urgent_peek = v;
    }
    if let Some(v) = set.expanded_width {
        m.expanded_width = v;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::modhost::ErrorKind;
    use notchd_proto::module::Peek;
    use serde_json::json;

    fn manifest() -> Manifest {
        serde_json::from_value(json!({
            "title": "Weather", "command": ["./run.sh"], "priority": 40, "icon": "W",
            "settings": [{"key": "city", "type": "string", "label": "City", "default": "Berlin"}]
        }))
        .unwrap()
    }

    fn text(s: &str) -> Node {
        serde_json::from_value(json!({"t": "text", "text": s})).unwrap()
    }

    fn loaded() -> (Mods, Store) {
        let mut mods = Mods::new();
        let mut store = Store::new();
        store.set_config(json!({"modules": ["weather"]}));
        let out = mods.apply(
            &mut store,
            ModEvent::Loaded {
                module: "weather".into(),
                manifest: Box::new(manifest()),
                dir: None,
            },
            0,
        );
        assert!(matches!(&out[..], [ToUi::Module(m)] if m.title == "Weather" && m.rev == 1));
        (mods, store)
    }

    fn view(slot: Slot, s: &str) -> ModEvent {
        ModEvent::View {
            module: "weather".into(),
            slot,
            tree: Some(text(s)),
        }
    }

    #[test]
    fn loaded_gives_the_store_a_module_with_the_manifests_facts_and_a_settings_page() {
        let (_, store) = loaded();
        let f = store.module("weather").unwrap();
        assert_eq!(f.info.priority, 40.0);
        assert!(!f.info.active, "a module says when it is active");
        assert!(f.info.icon);
        assert!(
            store
                .compute_schema()
                .fields
                .iter()
                .any(|f| f.key.as_deref() == Some("weather.city"))
        );
    }

    #[test]
    fn a_view_reaches_the_ui_once_and_sets_the_facts_that_depend_on_it() {
        let (mut mods, mut store) = loaded();
        let out = mods.apply(&mut store, view(Slot::Compact, "18"), 0);
        let [ToUi::View(v)] = &out[..] else {
            panic!("{out:?}")
        };
        assert_eq!(
            (v.module.as_str(), v.slot, v.rev),
            ("weather", Slot::Compact, 1)
        );
        assert!(store.module("weather").unwrap().info.compact);
        // The same tree again: nothing to send.
        let out = mods.apply(&mut store, view(Slot::Compact, "18"), 0);
        assert!(out.is_empty(), "{out:?}");
        let out = mods.apply(&mut store, view(Slot::Compact, "19"), 0);
        assert!(matches!(&out[..], [ToUi::View(v)] if v.rev == 2));
        let out = mods.apply(
            &mut store,
            ModEvent::View {
                module: "weather".into(),
                slot: Slot::Compact,
                tree: None,
            },
            0,
        );
        assert!(matches!(&out[..], [ToUi::View(v)] if v.tree.is_none()));
    }

    #[test]
    fn set_moves_the_facts_and_a_peek_goes_to_the_store() {
        let (mut mods, mut store) = loaded();
        mods.apply(&mut store, view(Slot::Peek, "rain"), 0);
        let set: ModuleSet =
            serde_json::from_value(json!({"active": true, "priority": 90})).unwrap();
        let out = mods.apply(
            &mut store,
            ModEvent::Set {
                module: "weather".into(),
                set,
            },
            0,
        );
        assert!(
            matches!(&out[..], [ToUi::Module(m)] if m.active && m.priority == 90 && m.rev == 2)
        );
        store.set_screens(notchd_proto::ui::Screens {
            screens: vec![notchd_proto::ui::ScreenInfo {
                name: "DP-1".into(),
                x: 0,
                y: 0,
                w: 1000,
                h: 800,
                scale: notchd_proto::Num(1.0),
            }],
            focused: "DP-1".into(),
            fullscreen: vec![],
            workspaces: Default::default(),
            known: vec![],
            supports_workspaces: false,
            bar_edge: None,
        });
        mods.apply(
            &mut store,
            ModEvent::Peek {
                module: "weather".into(),
                peek: Peek {
                    ms: 1500,
                    slot: None,
                },
            },
            10,
        );
        let st = store.state();
        let p = st.notches[0].copies[0].peek.as_ref().expect("peeking");
        assert_eq!((p.module.as_str(), p.until), ("weather", 1510));
    }

    #[test]
    fn an_error_puts_its_row_in_the_slots_and_clearing_it_brings_the_views_back() {
        let (mut mods, mut store) = loaded();
        mods.apply(&mut store, view(Slot::Compact, "18"), 0);
        mods.apply(&mut store, view(Slot::Peek, "rain"), 0);
        let out = mods.apply(
            &mut store,
            ModEvent::Error {
                module: "weather".into(),
                kind: ErrorKind::Crash,
                text: "weather exited (1)".into(),
                log_path: "/logs/weather.log".into(),
            },
            0,
        );
        let [
            ToUi::Module(info),
            ToUi::View(compact),
            ToUi::View(_vertical),
            ToUi::View(expanded),
        ] = &out[..]
        else {
            panic!("{out:?}")
        };
        assert_eq!(info.error.as_deref(), Some("weather exited (1)"));
        assert!(info.attention, "an error asks for the eye");
        assert_eq!(
            (compact.slot, expanded.slot),
            (Slot::Compact, Slot::Expanded)
        );
        let row = serde_json::to_string(compact.tree.as_ref().unwrap()).unwrap();
        assert!(row.contains("weather exited (1)") && row.contains("/logs/weather.log"));
        assert!(row.contains("restart"), "the Restart button");
        assert!(
            store.module("weather").unwrap().expanded,
            "the row shows expanded too"
        );
        let out = mods.apply(
            &mut store,
            ModEvent::ErrorCleared {
                module: "weather".into(),
            },
            0,
        );
        let [
            ToUi::Module(info),
            ToUi::View(compact),
            ToUi::View(_vertical),
            ToUi::View(expanded),
        ] = &out[..]
        else {
            panic!("{out:?}")
        };
        assert!(info.error.is_none() && !info.attention);
        assert_eq!(compact.tree, Some(text("18")));
        assert!(expanded.tree.is_none());
    }

    #[test]
    fn a_new_ui_is_sent_the_facts_and_the_views_in_use() {
        let (mut mods, mut store) = loaded();
        mods.apply(&mut store, view(Slot::Compact, "18"), 0);
        let snap = mods.snapshot();
        assert!(matches!(&snap[..], [ToUi::Module(_), ToUi::View(v)] if v.slot == Slot::Compact));
    }

    #[test]
    fn a_save_keeps_what_the_module_sent_and_a_removed_module_empties_its_slots() {
        let (mut mods, mut store) = loaded();
        let set: ModuleSet = serde_json::from_value(json!({"active": true})).unwrap();
        mods.apply(
            &mut store,
            ModEvent::Set {
                module: "weather".into(),
                set,
            },
            0,
        );
        mods.apply(&mut store, view(Slot::Compact, "18"), 0);
        let mut m2 = manifest();
        m2.priority = Some(10);
        let out = mods.apply(
            &mut store,
            ModEvent::Loaded {
                module: "weather".into(),
                manifest: Box::new(m2),
                dir: None,
            },
            0,
        );
        assert!(matches!(&out[..], [ToUi::Module(m)] if m.priority == 10 && m.active));
        let out = mods.apply(
            &mut store,
            ModEvent::Removed {
                module: "weather".into(),
            },
            0,
        );
        assert!(matches!(&out[..], [ToUi::View(v)] if v.tree.is_none()));
        assert!(store.module("weather").is_none());
        assert!(
            !store
                .compute_schema()
                .pages
                .iter()
                .any(|p| p.id == "modules/weather")
        );
    }

    /// What a UI keeps of the messages, as `Protocol.apply` does: a message
    /// whose `rev` is not above the one held for its entity is dropped.
    #[derive(Default)]
    struct Ui {
        revs: BTreeMap<String, u64>,
        modules: BTreeMap<String, ModuleInfo>,
        views: BTreeMap<String, Option<Node>>,
    }

    impl Ui {
        fn take(&mut self, out: Vec<ToUi>) {
            for msg in out {
                let (key, rev) = match &msg {
                    ToUi::Module(m) => (format!("module:{}", m.id), m.rev),
                    ToUi::View(v) => (format!("view:{}/{:?}", v.module, v.slot), v.rev),
                    _ => continue,
                };
                if self.revs.get(&key).is_some_and(|held| rev <= *held) {
                    continue;
                }
                self.revs.insert(key, rev);
                match msg {
                    ToUi::Module(m) => {
                        self.modules.insert(m.id.clone(), m);
                    }
                    ToUi::View(v) => {
                        self.views
                            .insert(format!("{}/{:?}", v.module, v.slot), v.tree);
                    }
                    _ => {}
                }
            }
        }

        fn view(&self, module: &str, slot: Slot) -> Option<&Node> {
            self.views.get(&format!("{module}/{slot:?}"))?.as_ref()
        }
    }

    #[test]
    fn a_module_loaded_again_reaches_a_ui_that_saw_it_before() {
        // A module of the daemon (an agent added to a notch at runtime after
        // it was in one before), however many revs it went through first.
        let mut mods = Mods::new();
        let mut store = Store::new();
        store.set_config(json!({"modules": ["codex"]}));
        let mut ui = Ui::default();
        let facts = notchd_modules::Facts::default();
        for n in 0..5 {
            let views = vec![
                (Slot::Compact, Some(text(&format!("title {n}")))),
                (Slot::Expanded, Some(text(&format!("terminal {n}")))),
            ];
            let out = mods.set_builtin(&mut store, "codex", &format!("Codex {n}"), &facts, views);
            ui.take(out);
        }
        ui.take(mods.apply(
            &mut store,
            ModEvent::Removed {
                module: "codex".into(),
            },
            0,
        ));
        assert!(ui.view("codex", Slot::Expanded).is_none());
        let views = vec![(Slot::Expanded, Some(text("terminal again")))];
        let out = mods.set_builtin(&mut store, "codex", "Codex", &facts, views);
        ui.take(out);
        assert_eq!(
            ui.view("codex", Slot::Expanded),
            Some(&text("terminal again"))
        );
        assert_eq!(ui.modules["codex"].title, "Codex");

        // A user module the host loads again.
        let (mut mods, mut store) = loaded();
        let mut ui = Ui::default();
        for n in 0..5 {
            ui.take(mods.apply(&mut store, view(Slot::Expanded, &format!("{n}")), 0));
        }
        ui.take(mods.apply(
            &mut store,
            ModEvent::Removed {
                module: "weather".into(),
            },
            0,
        ));
        let mut m2 = manifest();
        m2.title = Some("Weather again".into());
        ui.take(mods.apply(
            &mut store,
            ModEvent::Loaded {
                module: "weather".into(),
                manifest: Box::new(m2),
                dir: None,
            },
            0,
        ));
        ui.take(mods.apply(&mut store, view(Slot::Expanded, "back"), 0));
        assert_eq!(ui.view("weather", Slot::Expanded), Some(&text("back")));
        assert_eq!(ui.modules["weather"].title, "Weather again");
    }

    // ---- custom modules: a process, a terminal, or both

    fn custom(id: &str, manifest: serde_json::Value) -> ModEvent {
        ModEvent::Loaded {
            module: id.into(),
            manifest: Box::new(serde_json::from_value(manifest).unwrap()),
            dir: Some(PathBuf::from(format!(
                "/home/u/.config/notchd/modules/{id}"
            ))),
        }
    }

    fn term_facts() -> notchd_modules::Facts {
        notchd_modules::Facts {
            priority: 40,
            active: true,
            expanded_width: 760,
            ..Default::default()
        }
    }

    fn term_views(compact: &str, expanded: &str) -> Vec<(Slot, Option<Node>)> {
        vec![
            (Slot::Compact, Some(text(compact))),
            (Slot::Expanded, Some(text(expanded))),
        ]
    }

    fn def_of(store: &Store, id: &str) -> Value {
        store
            .compute_schema()
            .modules
            .unwrap()
            .into_iter()
            .find(|m| m["moduleId"] == id)
            .unwrap()
    }

    #[test]
    fn a_custom_module_is_listed_as_the_users_with_what_it_has() {
        let mut mods = Mods::new();
        let mut store = Store::new();
        store.set_config(json!({}));
        store.set_builtin_catalog(vec![
            json!({"moduleId": "media", "title": "Now playing", "settings": []}),
        ]);
        mods.apply(
            &mut store,
            custom(
                "herdr",
                json!({"title": "Herdr", "command": ["python3", "run.py"],
                       "permissions": ["network"], "terminal": {"command": "herdr"}}),
            ),
            0,
        );
        mods.apply(
            &mut store,
            custom("btop", json!({"terminal": {"command": "btop"}})),
            0,
        );
        mods.apply(
            &mut store,
            custom("linear", json!({"command": ["./run.sh"]})),
            0,
        );
        let herdr = def_of(&store, "herdr");
        assert_eq!(herdr["origin"], "user");
        assert_eq!(
            (&herdr["process"], &herdr["terminal"]),
            (&json!(true), &json!(true))
        );
        assert_eq!(herdr["dir"], "/home/u/.config/notchd/modules/herdr");
        assert_eq!(herdr["permissions"], json!(["network"]));
        let btop = def_of(&store, "btop");
        assert_eq!(
            (&btop["process"], &btop["terminal"]),
            (&json!(false), &json!(true))
        );
        // The terminal's fields are on its page, `command` defaulting to the manifest's.
        let schema = store.compute_schema();
        let command = schema
            .fields
            .iter()
            .find(|f| f.key.as_deref() == Some("btop.command"))
            .expect("the terminal's command setting");
        assert_eq!(command.default, "btop");
        assert!(
            schema
                .fields
                .iter()
                .all(|f| f.key.as_deref() != Some("linear.command")),
            "a process alone has no terminal fields"
        );
        // The Modules page lists them under "user"; the built-ins are not.
        let catalog = schema.modules.unwrap();
        let user = notchd_core::settings::catalog_part(&catalog, Some("user"));
        let ids: Vec<&str> = user
            .iter()
            .map(|m| m["moduleId"].as_str().unwrap())
            .collect();
        assert_eq!(ids, ["btop", "herdr", "linear"]);
        assert!(
            catalog
                .iter()
                .any(|m| m["moduleId"] == "media" && m["origin"] == "builtin")
        );
    }

    #[test]
    fn the_module_lists_the_terminals_of_the_modules_that_have_one() {
        let mut mods = Mods::new();
        let mut store = Store::new();
        store.set_config(json!({}));
        mods.apply(
            &mut store,
            custom(
                "btop",
                json!({"title": "Top", "terminal": {"command": "btop"}}),
            ),
            0,
        );
        mods.apply(
            &mut store,
            custom("linear", json!({"command": ["./run.sh"]})),
            0,
        );
        assert_eq!(
            mods.terminal_defs(),
            [("btop".to_string(), "Top".to_string(), "btop".to_string())]
        );
        assert!(mods.has_process("linear") && !mods.has_process("btop"));
    }

    #[test]
    fn with_a_process_and_a_terminal_the_closed_view_is_the_process_and_the_expanded_both() {
        let mut mods = Mods::new();
        let mut store = Store::new();
        store.set_config(json!({"modules": ["herdr"]}));
        mods.apply(
            &mut store,
            custom(
                "herdr",
                json!({"command": ["./run.sh"], "priority": 70, "terminal": {"command": "herdr"}}),
            ),
            0,
        );
        let mut ui = Ui::default();
        // The terminal alone: its own views.
        ui.take(mods.set_terminal(
            &mut store,
            "herdr",
            &term_facts(),
            term_views("title", "term"),
        ));
        assert_eq!(ui.view("herdr", Slot::Compact), Some(&text("title")));
        assert_eq!(ui.view("herdr", Slot::Expanded), Some(&text("term")));
        // The process's compact wins; its expanded goes above the terminal's.
        let ev = |slot, s: &str| ModEvent::View {
            module: "herdr".into(),
            slot,
            tree: Some(text(s)),
        };
        ui.take(mods.apply(&mut store, ev(Slot::Compact, "3 agents"), 0));
        ui.take(mods.apply(&mut store, ev(Slot::Expanded, "summary"), 0));
        assert_eq!(ui.view("herdr", Slot::Compact), Some(&text("3 agents")));
        let Some(expanded) = ui.view("herdr", Slot::Expanded) else {
            panic!("no expanded view")
        };
        let v = serde_json::to_value(expanded).unwrap();
        assert_eq!(v["t"], "column");
        assert_eq!(v["children"][0]["text"], "summary");
        assert_eq!(v["children"][1]["text"], "term");
        // The facts: the process's priority, the wider notch, always active.
        let f = store.module("herdr").unwrap();
        assert_eq!(f.info.priority, 70.0);
        assert!(f.info.active);
        assert_eq!(ui.modules["herdr"].expanded_width, 760);
        // The terminal going (unlisted) leaves the process's views.
        ui.take(mods.clear_terminal(&mut store, "herdr"));
        assert_eq!(ui.view("herdr", Slot::Expanded), Some(&text("summary")));
        assert!(mods.clear_terminal(&mut store, "herdr").is_empty());
    }

    #[test]
    fn a_terminal_alone_has_its_own_facts_and_a_removed_module_empties_its_slots() {
        let mut mods = Mods::new();
        let mut store = Store::new();
        store.set_config(json!({"modules": ["btop"]}));
        mods.apply(
            &mut store,
            custom("btop", json!({"terminal": {"command": "btop"}})),
            0,
        );
        let mut ui = Ui::default();
        ui.take(mods.set_terminal(&mut store, "btop", &term_facts(), term_views("t", "e")));
        assert_eq!(store.module("btop").unwrap().info.priority, 40.0);
        assert_eq!(ui.modules["btop"].expanded_width, 760);
        ui.take(mods.apply(
            &mut store,
            ModEvent::Removed {
                module: "btop".into(),
            },
            0,
        ));
        assert_eq!(ui.view("btop", Slot::Expanded), None);
        assert!(!mods.knows("btop"));
    }

    #[test]
    fn the_terminals_own_actions_go_to_it_and_the_rest_to_the_process() {
        let mut mods = Mods::new();
        let mut store = Store::new();
        store.set_config(json!({}));
        mods.apply(
            &mut store,
            custom(
                "herdr",
                json!({"command": ["./run.sh"], "terminal": {"command": "herdr"}}),
            ),
            0,
        );
        for a in ["typed", "leave", "keyboard", "close", "restart"] {
            assert!(mods.is_terminal_action("herdr", a), "{a}");
        }
        assert!(!mods.is_terminal_action("herdr", "refresh"));
        // While the process shows its error row, its Restart is the process's.
        mods.apply(
            &mut store,
            ModEvent::Error {
                module: "herdr".into(),
                kind: crate::modhost::ErrorKind::Crash,
                text: "herdr exited".into(),
                log_path: PathBuf::from("/tmp/herdr.log"),
            },
            0,
        );
        assert!(!mods.is_terminal_action("herdr", "restart"));
        assert!(mods.is_terminal_action("herdr", "typed"));
    }
}
