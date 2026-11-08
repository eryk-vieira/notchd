//! The modules that live in the daemon (`notchd-modules`: timer, activities,
//! resources, osd), driven the way the module host drives a user module's
//! process: they are loaded while a notch lists them, told the config, the time, a provider's data, an
//! IPC command or an `event`, and after each call their facts, views and
//! effects (a peek, a notification) go to the store and the UIs, only what
//! changed. Pure over a [`Store`] and [`Mods`] and a time, like `modstate`;
//! the hub owns the lock, the clock and the providers.

use crate::modstate::Mods;
use crate::ptyhost::{Note, PtyHost, Session};
use notchd_core::store::Store;
use notchd_modules::module::{PtyCmd, PtyStart, Shown};
use notchd_modules::plan::Ask;
use notchd_modules::{CoreModule, Ctx, Effect};
use notchd_proto::common::Mode;
use notchd_proto::{EventValue, Slot, ToUi};
use notchd_providers::media::MediaCommand;
use notchd_providers::notifications::Notifier;
use notchd_providers::pty::PtySpec;
use notchd_providers::usage::{self as usage_provider, Curl, Http};
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::mpsc::Sender;

/// The IPC methods a module of the daemon answers, by module. A method of
/// one that is not loaded is answered `<id> module not loaded`.
const METHODS: &[(&str, &str)] = &[
    ("push", "activities"),
    ("clear", "activities"),
    ("timer", "timer"),
    ("osd", "osd"),
    ("claude", "claude"),
    ("codex", "codex"),
];

/// The agents `agent <id> ...` takes, in the order they are listed.
const AGENTS: &[&str] = &["claude", "codex"];

/// The modules told how the notches show them (`CoreModule::shown`): media
/// ticks its clock only while its expanded view is on screen.
const SHOWN_AWARE: &[&str] = &["media"];

/// How the daemon reads its environment: a closure, so tests give it their
/// own (a scratch `HOME`, no real login).
pub type Env = Arc<dyn Fn(&str) -> Option<String> + Send + Sync>;
/// The names in the daemon's environment.
pub type EnvNames = Arc<dyn Fn() -> Vec<String> + Send + Sync>;

/// The module that owns an IPC method.
pub fn owner(method: &str) -> Option<&'static str> {
    METHODS
        .iter()
        .find(|(m, _)| *m == method)
        .map(|(_, id)| *id)
}

pub struct CoreHost {
    loaded: BTreeMap<&'static str, Box<dyn CoreModule>>,
    /// When each wants `tick`, as it said after its last change.
    due: BTreeMap<&'static str, u64>,
    notifier: Option<Box<dyn Notifier>>,
    /// The media provider's commands (its thread makes the D-Bus calls, never
    /// this one, which runs under the hub's lock).
    media: Option<Sender<MediaCommand>>,
    /// The players of the system feed `media`; off once a test hook gave it
    /// demo players.
    media_live: bool,
    /// The system's readings feed `resources`; off once a test hook gave it
    /// demo values.
    pub sampling: bool,
    /// The programs of the terminal modules, and what they (and the plan
    /// usage's requests) tell their modules.
    ptys: PtyHost,
    notes: Option<Sender<Note>>,
    env: Env,
    env_names: EnvNames,
    /// The daemon that owns terminal programs, independent of inherited CLI env.
    terminal_instance: Option<(String, PathBuf, Option<PathBuf>)>,
    http: Arc<dyn Http>,
    /// Some UI can draw a terminal (`surfaces` of its `hello`).
    terminal_ui: bool,
    /// What the notches showed of each module last.
    shown_seen: BTreeMap<&'static str, Shown>,
    /// The loaded modules that are the terminal of a custom module (its
    /// `module.json`'s `terminal`), not a module of the daemon's own.
    terminal_ids: BTreeSet<&'static str>,
}

impl Default for CoreHost {
    fn default() -> CoreHost {
        CoreHost::new(notchd_providers::notifications::system())
    }
}

impl CoreHost {
    pub fn new(notifier: Option<Box<dyn Notifier>>) -> CoreHost {
        CoreHost {
            loaded: BTreeMap::new(),
            due: BTreeMap::new(),
            notifier,
            media: None,
            media_live: true,
            sampling: true,
            ptys: PtyHost::default(),
            notes: None,
            env: Arc::new(|k| std::env::var(k).ok()),
            env_names: Arc::new(|| {
                std::env::vars_os()
                    .filter_map(|(k, _)| k.into_string().ok())
                    .collect()
            }),
            terminal_instance: None,
            http: Arc::new(Curl),
            terminal_ui: false,
            shown_seen: BTreeMap::new(),
            terminal_ids: BTreeSet::new(),
        }
    }

    /// Where `media`'s commands go. A module that loaded before this asks for the players now.
    pub fn set_media(&mut self, commands: Sender<MediaCommand>) {
        self.media = Some(commands);
        if self.loaded.contains_key("media") {
            self.send_media(MediaCommand::Refresh);
        }
    }

    /// Whether the module `media` wants the system's players.
    pub fn wants_media(&self) -> bool {
        self.media_live && self.loaded.contains_key("media")
    }

    /// The environment the terminals' programs and the usage requests read
    /// (`HOME`, `CLAUDE_CONFIG_DIR`, `NOTCHD_OFFLINE`).
    pub fn with_env(mut self, env: Env) -> CoreHost {
        self.env = env;
        self
    }

    /// The names of the environment `with_env` reads, for what a terminal's
    /// program must not inherit of it.
    pub fn with_env_names(mut self, names: EnvNames) -> CoreHost {
        self.env_names = names;
        self
    }

    /// Give hosted terminal programs a CLI path and the daemon's exact socket.
    pub fn set_terminal_instance(&mut self, instance: &crate::instance::Instance) {
        self.terminal_instance = Some((
            instance.name.clone(),
            instance
                .socket
                .canonicalize()
                .unwrap_or_else(|_| instance.socket.clone()),
            std::env::current_exe().ok(),
        ));
    }

    /// What asks the network for the plan usage.
    pub fn with_http(mut self, http: Arc<dyn Http>) -> CoreHost {
        self.http = http;
        self
    }

    /// Where the modules' terminals and usage requests report to: the hub
    /// feeds each note to its module.
    pub fn set_notes(&mut self, notes: Sender<Note>) {
        self.ptys.set_notes(notes.clone());
        self.notes = Some(notes);
    }

    /// Some UI connected can (not) draw a terminal.
    pub fn set_terminal_ui(&mut self, on: bool) {
        self.terminal_ui = on;
    }

    /// The session of a terminal module, for a view to attach to.
    pub fn session(&self, id: &str) -> Option<Arc<Session>> {
        self.ptys.session(id)
    }

    /// The size a program starts at: the first view's.
    pub fn set_size_hint(&mut self, cols: u16, rows: u16) {
        self.ptys.hint = (cols, rows);
    }

    /// Stops every terminal's program (the daemon is going).
    pub fn stop_terminals(&mut self) {
        self.ptys.stop_all();
    }

    pub fn has(&self, id: &str) -> bool {
        self.loaded.contains_key(id)
    }

    /// Whether the module `id` wants the system's readings.
    pub fn wants_resources(&self) -> bool {
        self.sampling && self.loaded.contains_key("resources")
    }

    /// What a module's rules need to know of the notches.
    fn ctx(store: &Store, id: &str) -> Ctx {
        let st = store.state();
        let mut seen: Vec<(Mode, Option<String>)> = Vec::new();
        for c in st.notches.iter().flat_map(|n| n.copies.iter()) {
            seen.push((c.mode, c.peek.as_ref().map(|p| p.module.clone())));
        }
        for c in &st.visitor {
            seen.push((c.mode, c.peek.as_ref().map(|p| p.module.clone())));
        }
        let mut ctx = Ctx {
            listed: st.notches.iter().any(|n| n.modules.iter().any(|m| m == id)),
            visible: Self::shown_of(store, id).visible,
            ..Ctx::default()
        };
        for (mode, peek) in seen {
            ctx.expanded |= mode == Mode::Expanded;
            ctx.peeking |= mode == Mode::Peek && peek.as_deref() == Some(id);
        }
        ctx
    }

    /// How the notches show module `id` now: open on it by a click or a
    /// shortcut (pinned), and its expanded view on screen at all.
    fn shown_of(store: &Store, id: &str) -> Shown {
        let st = store.state();
        let mut out = Shown::default();
        let mut see = |mode: Mode, pinned: bool, shown: &[String]| {
            if mode == Mode::Expanded && shown.iter().any(|m| m == id) {
                out.visible = true;
                out.open |= pinned;
            }
        };
        for c in st.notches.iter().flat_map(|n| n.copies.iter()) {
            see(c.mode, c.pinned, &c.shown);
        }
        for c in &st.visitor {
            see(c.mode, c.pinned, &c.shown);
        }
        out
    }

    /// The notch state changed: tells the modules whose answer did how the
    /// notches show them now (media's clock follows its view).
    pub fn notches_changed(&mut self, store: &mut Store, mods: &mut Mods, now: u64) -> Vec<ToUi> {
        let ids: Vec<&'static str> = self.loaded.keys().copied().collect();
        let mut out = Vec::new();
        for id in ids {
            if !SHOWN_AWARE.contains(&id) {
                continue;
            }
            let shown = Self::shown_of(store, id);
            let before = self.shown_seen.get(id).copied().unwrap_or_default();
            if before == shown {
                continue;
            }
            self.shown_seen.insert(id, shown);
            if let Some(m) = self.loaded.get_mut(id) {
                m.shown(shown, now);
            }
            out.extend(self.settle(store, mods, id, now));
        }
        out
    }

    /// Loads and unloads to match the config, hands the loaded modules the
    /// config, and returns what the UIs need. A module that is not listed
    /// anywhere is gone with its state, as an unloaded QML module was.
    pub fn sync(&mut self, store: &mut Store, mods: &mut Mods, now: u64) -> Vec<ToUi> {
        let cfg = store.config().clone();
        let listed: Vec<String> = store
            .notch_specs()
            .into_iter()
            .flat_map(|n| n.module_ids)
            .collect();
        let mut out = Vec::new();
        // The modules of the daemon, and a terminal for each custom module
        // that has one (whatever its folder, if any); one that left is
        // unloaded.
        let terminals = mods.terminal_defs();
        let dynamic: Vec<&'static str> = terminals
            .iter()
            .map(|(i, ..)| notchd_modules::terminal::intern(i))
            .collect();
        let mut candidates: BTreeSet<&'static str> = notchd_modules::IDS.iter().copied().collect();
        candidates.extend(dynamic.iter().copied());
        candidates.extend(self.loaded.keys().copied());
        let make = |id: &str| -> Option<Box<dyn CoreModule>> {
            notchd_modules::create(id).or_else(|| {
                dynamic
                    .contains(&id)
                    .then(|| Box::new(notchd_modules::terminal::new(id)) as Box<dyn CoreModule>)
            })
        };
        for id in candidates {
            let known = notchd_modules::IDS.contains(&id) || dynamic.contains(&id);
            let wanted = known && listed.iter().any(|l| l == id);
            if wanted && !self.loaded.contains_key(id) {
                if let Some(m) = make(id) {
                    if dynamic.contains(&id) {
                        self.terminal_ids.insert(id);
                    }
                    self.loaded.insert(id, m);
                    if id == "media" {
                        // It wants the players as they are now.
                        self.send_media(MediaCommand::Refresh);
                    }
                }
            } else if !wanted && self.loaded.remove(id).is_some() {
                self.due.remove(id);
                // Its program goes with it, as its terminal did.
                self.ptys.stop(id);
                self.shown_seen.remove(id);
                store.set_module_extra(id, None);
                if self.terminal_ids.remove(id) {
                    // The module goes on with its process, if it has one.
                    out.extend(mods.clear_terminal(store, id));
                } else {
                    out.extend(mods.apply(
                        store,
                        crate::modhost::ModEvent::Removed { module: id.into() },
                        now,
                    ));
                }
            }
        }
        let ids: Vec<&'static str> = self.loaded.keys().copied().collect();
        for id in ids {
            if let Some(m) = self.loaded.get_mut(id) {
                if let Some((_, title, command)) = terminals.iter().find(|(t, ..)| t == id) {
                    m.define(title, command);
                }
                m.config(&cfg, now);
            }
            out.extend(self.settle(store, mods, id, now));
        }
        out.extend(self.notches_changed(store, mods, now));
        out
    }

    fn send_media(&self, c: MediaCommand) {
        if let Some(tx) = &self.media {
            let _ = tx.send(c);
        }
    }

    /// A module's facts, views and effects, after something changed it.
    fn settle(&mut self, store: &mut Store, mods: &mut Mods, id: &str, now: u64) -> Vec<ToUi> {
        let Some(m) = self.loaded.get_mut(id) else {
            return Vec::new();
        };
        let facts = m.facts(now);
        let views = Slot::ALL.iter().map(|s| (*s, m.view(*s, now))).collect();
        let effects = m.take_effects();
        match m.next_due(now) {
            Some(at) => self.due.insert(m.id(), at),
            None => self.due.remove(m.id()),
        };
        let title = m
            .title()
            .unwrap_or_else(|| notchd_modules::title(id).to_string());
        store.set_module_extra(id, m.state_extra());
        let out = if self.terminal_ids.contains(id) {
            mods.set_terminal(store, id, &facts, views)
        } else {
            mods.set_builtin(store, id, &title, &facts, views)
        };
        for e in effects {
            match e {
                Effect::Peek(ms) => store.request_peek(id, Some(f64::from(ms)), now),
                Effect::DismissPeek => store.dismiss_peek(id),
                Effect::Media(c) => self.send_media(c),
                Effect::Notify { title, body } => {
                    if let Some(n) = &self.notifier {
                        n.notify(&title, &body);
                    }
                }
                Effect::Pty(cmd) => self.pty_command(id, cmd),
                Effect::Usage(ask) => self.ask_usage(id, ask),
                Effect::Notch(op) => store.module_op(id, op, now),
            }
        }
        out
    }

    /// What a terminal module asked of its program.
    fn pty_command(&mut self, id: &str, cmd: PtyCmd) {
        match cmd {
            PtyCmd::Start(s) => {
                let run = s.run;
                let spec = self.terminal_spec(id, s);
                self.ptys.start(id, run, spec);
            }
            PtyCmd::Stop => self.ptys.stop(id),
            PtyCmd::Write(bytes) => self.ptys.write(id, &bytes),
        }
    }

    /// How a terminal module's program runs: in its folder, with `TERM` and
    /// the daemon's `NOTCHD_*` on top of the daemon's environment, less what
    /// a session host the daemon was started from gave it
    /// (`terminal::is_session_host_var`): a notch terminal is the same
    /// wherever the daemon started.
    fn terminal_spec(&self, id: &str, s: PtyStart) -> PtySpec {
        let home = (self.env)("HOME").unwrap_or_default();
        let mut env = vec![("TERM".into(), "xterm-256color".into())];
        if let Some((name, socket, bin)) = &self.terminal_instance {
            env.extend([
                ("NOTCHD_INSTANCE".into(), name.clone()),
                (
                    "NOTCHD_SOCKET".into(),
                    socket.to_string_lossy().into_owned(),
                ),
                ("NOTCHD_TERMINAL_ID".into(), id.into()),
            ]);
            if let Some(bin) = bin {
                env.push(("NOTCHD_BIN".into(), bin.to_string_lossy().into_owned()));
            }
        }
        let mut unset: Vec<String> = (self.env_names)()
            .into_iter()
            .filter(|k| notchd_core::terminal::is_session_host_var(k))
            .collect();
        unset.sort();
        unset.dedup();
        PtySpec {
            program: s.program,
            args: s.args,
            cwd: Some(notchd_core::terminal::expand_home(Some(&s.dir), &home)),
            unset,
            env,
            cols: 0,
            rows: 0,
        }
    }

    /// Asks the plan usage on a thread of its own, so a slow network never
    /// holds the hub; the answer comes back as a note. Offscreen runs and
    /// tests (`NOTCHD_OFFLINE`) never ask.
    fn ask_usage(&self, id: &str, ask: Ask) {
        if (self.env)("NOTCHD_OFFLINE").as_deref() == Some("1") {
            return;
        }
        let Some(notes) = self.notes.clone() else {
            return;
        };
        let (env, http, id) = (
            Arc::clone(&self.env),
            Arc::clone(&self.http),
            id.to_string(),
        );
        let _ = std::thread::Builder::new()
            .name("notchd-usage".into())
            .spawn(move || {
                let mut data = usage_provider::fetch(
                    ask.provider,
                    ask.unless_login_is,
                    usage_provider::epoch_ms(),
                    &*env,
                    &*http,
                );
                data["id"] = json!(id);
                let _ = notes.send(Note {
                    provider: "usage",
                    data,
                });
            });
    }

    /// An IPC method of a module of the daemon: the answer and what changed.
    /// `None` when no module of the daemon owns the method.
    pub fn command(
        &mut self,
        store: &mut Store,
        mods: &mut Mods,
        method: &str,
        args: &[String],
        now: u64,
    ) -> Option<(String, Vec<ToUi>)> {
        let id = match method {
            // `agent <id> ...` and `terminal <id> ...` name the module in
            // their first argument.
            "agent" => {
                let want = args.first().map_or("", String::as_str);
                match AGENTS.iter().find(|a| **a == want) {
                    Some(a) => *a,
                    None => {
                        return Some((
                            format!("no agent {want}; agents: {}", AGENTS.join(", ")),
                            Vec::new(),
                        ));
                    }
                }
            }
            "terminal" => {
                let want = args.first().map_or("", String::as_str);
                let list: Vec<String> = mods
                    .terminal_defs()
                    .into_iter()
                    .map(|(id, ..)| id)
                    .collect();
                if !list.iter().any(|t| t == want) {
                    let named = if list.is_empty() {
                        String::new()
                    } else {
                        format!("; terminals: {}", list.join(", "))
                    };
                    return Some((format!("no terminal {want}{named}"), Vec::new()));
                }
                notchd_modules::terminal::intern(want)
            }
            _ => owner(method)?,
        };
        let mut ctx = Self::ctx(store, id);
        ctx.terminal_ui = self.terminal_ui;
        let Some(m) = self.loaded.get_mut(id) else {
            return Some((format!("{id} module not loaded"), Vec::new()));
        };
        let answer = m.command(&ctx, method, args, now)?;
        Some((answer, self.settle(store, mods, id, now)))
    }

    /// A primitive's `action` in a module's view.
    pub fn event(
        &mut self,
        store: &mut Store,
        mods: &mut Mods,
        id: &str,
        action: &str,
        value: &EventValue,
        now: u64,
    ) -> Vec<ToUi> {
        let ctx = Self::ctx(store, id);
        let Some(m) = self.loaded.get_mut(id) else {
            return Vec::new();
        };
        m.event(&ctx, action, value, now);
        self.settle(store, mods, id, now)
    }

    /// A provider's data, for the modules that take it.
    pub fn feed(
        &mut self,
        store: &mut Store,
        mods: &mut Mods,
        provider: &str,
        data: &Value,
        now: u64,
    ) -> Vec<ToUi> {
        if provider == "media" && !self.media_live {
            return Vec::new();
        }
        let ids: Vec<&'static str> = self.loaded.keys().copied().collect();
        let mut out = Vec::new();
        for id in ids {
            if let Some(m) = self.loaded.get_mut(id) {
                m.feed(provider, data, now);
            }
            out.extend(self.settle(store, mods, id, now));
        }
        out
    }

    /// What happened to one module's terminal or usage request (`pty`,
    /// `usage`): fed to that module alone.
    pub fn feed_to(
        &mut self,
        store: &mut Store,
        mods: &mut Mods,
        id: &str,
        provider: &str,
        data: &Value,
        now: u64,
    ) -> Vec<ToUi> {
        let Some(m) = self.loaded.get_mut(id) else {
            return Vec::new();
        };
        m.feed(provider, data, now);
        self.settle(store, mods, id, now)
    }

    /// The views attached to a terminal module's session are `n` now (the
    /// first one starts the program).
    pub fn pty_views(
        &mut self,
        store: &mut Store,
        mods: &mut Mods,
        id: &str,
        n: usize,
        now: u64,
    ) -> Vec<ToUi> {
        let data = json!({"id": id, "event": "views", "n": n});
        self.feed_to(store, mods, id, "pty", &data, now)
    }

    /// Runs the modules whose time has come.
    pub fn tick(&mut self, store: &mut Store, mods: &mut Mods, now: u64) -> Vec<ToUi> {
        let due: Vec<&'static str> = self
            .due
            .iter()
            .filter(|(_, at)| **at <= now)
            .map(|(id, _)| *id)
            .collect();
        let mut out = Vec::new();
        for id in due {
            if let Some(m) = self.loaded.get_mut(id) {
                m.tick(now);
            }
            out.extend(self.settle(store, mods, id, now));
        }
        out
    }

    /// When the first module wants `tick`.
    pub fn next_due(&self) -> Option<u64> {
        self.due.values().copied().min()
    }

    /// The test hook `test-<id>`: demo data in a module's place of the
    /// system's. `None` when there is no such hook.
    pub fn demo(
        &mut self,
        store: &mut Store,
        mods: &mut Mods,
        id: &str,
        args: &[String],
        now: u64,
    ) -> Option<(String, Vec<ToUi>)> {
        if id == "resources" {
            self.sampling = false;
        }
        if id == "media" {
            self.media_live = false;
        }
        let m = self.loaded.get_mut(id)?;
        let answer = m.demo(args, now)?;
        Some((answer, self.settle(store, mods, id, now)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::sync::{Arc, Mutex};

    struct Spy(Arc<Mutex<Vec<(String, String)>>>);
    impl Notifier for Spy {
        fn notify(&self, title: &str, body: &str) {
            self.0.lock().unwrap().push((title.into(), body.into()));
        }
    }

    type Seen = Arc<Mutex<Vec<(String, String)>>>;

    fn rig(cfg: Value) -> (CoreHost, Store, Mods, Seen) {
        let seen = Arc::new(Mutex::new(Vec::new()));
        let mut store = Store::new();
        store.set_config(cfg);
        (
            CoreHost::new(Some(Box::new(Spy(seen.clone())))),
            store,
            Mods::new(),
            seen,
        )
    }

    fn say(
        h: &mut CoreHost,
        s: &mut Store,
        m: &mut Mods,
        method: &str,
        args: &[&str],
        now: u64,
    ) -> String {
        let args: Vec<String> = args.iter().map(|a| a.to_string()).collect();
        h.command(s, m, method, &args, now).expect("an owner").0
    }

    #[test]
    fn a_terminal_does_not_inherit_the_session_host_that_started_the_daemon() {
        // Issue #22: a daemon started from a Herdr pane inside Claude Code
        // gave `herdr` in a notch terminal HERDR_ENV, and it took itself for nested.
        let names = || -> Vec<String> {
            [
                "PATH",
                "HOME",
                "HERDR_ENV",
                "HERDR_PANE_ID",
                "CLAUDECODE",
                "TMUX",
                "CLAUDE_CONFIG_DIR",
            ]
            .iter()
            .map(|k| k.to_string())
            .collect()
        };
        let h = CoreHost::new(None)
            .with_env(Arc::new(|k| (k == "HOME").then(|| "/h".to_string())))
            .with_env_names(Arc::new(names));
        let spec = h.terminal_spec(
            "herdr-terminal",
            PtyStart {
                run: 1,
                program: "/bin/sh".into(),
                args: vec!["-c".into(), "herdr".into()],
                dir: "~/x".into(),
            },
        );
        assert_eq!(
            spec.unset,
            ["CLAUDECODE", "HERDR_ENV", "HERDR_PANE_ID", "TMUX"]
        );
        assert_eq!(spec.cwd.as_deref(), Some("/h/x"));
        assert!(
            spec.env
                .iter()
                .any(|(k, v)| k == "TERM" && v == "xterm-256color")
        );
        assert!(
            spec.env
                .iter()
                .all(|(k, _)| !notchd_core::terminal::is_session_host_var(k))
        );
    }

    #[test]
    fn the_removed_voice_modules_and_their_config_keys_are_ignored_like_any_unknown_one() {
        let (mut h, mut s, mut m, _) = rig(json!({
            "modules": ["timer", "codex-live", "local-live"],
            "codex-live": {"voice": "maple", "command": "codex"},
            "local-live": {"voiceModel": "piper", "voiceLanguage": "pt"}
        }));
        h.sync(&mut s, &mut m, 0);
        assert!(h.has("timer"), "the others load");
        assert!(!h.has("codex-live") && !h.has("local-live"));
        assert_eq!(
            say(&mut h, &mut s, &mut m, "timer", &["5m"], 1000),
            "ok",
            "nothing refused"
        );
        assert!(
            s.config()["codex-live"]["voice"] == "maple",
            "and nothing rewritten"
        );
    }

    #[test]
    fn a_module_loads_while_a_notch_lists_it_and_is_gone_with_its_state_when_not() {
        let (mut h, mut s, mut m, _) = rig(json!({"modules": ["timer"]}));
        let out = h.sync(&mut s, &mut m, 0);
        assert!(h.has("timer") && !h.has("activities"));
        assert!(
            out.iter()
                .any(|u| matches!(u, ToUi::Module(i) if i.id == "timer" && i.title == "Timer"))
        );
        assert_eq!(say(&mut h, &mut s, &mut m, "timer", &["5m"], 1000), "ok");
        assert_eq!(
            say(&mut h, &mut s, &mut m, "push", &["{}"], 0),
            "activities module not loaded"
        );
        s.set_config(json!({"modules": ["activities"]}));
        let out = h.sync(&mut s, &mut m, 2000);
        assert!(!h.has("timer") && h.has("activities"));
        assert!(
            out.iter()
                .any(|u| matches!(u, ToUi::View(v) if v.module == "timer" && v.tree.is_none()))
        );
        assert!(s.module("timer").is_none(), "its facts leave the store");
        s.set_config(json!({"modules": ["timer"]}));
        h.sync(&mut s, &mut m, 3000);
        assert_eq!(
            say(&mut h, &mut s, &mut m, "timer", &["pause"], 3000),
            "no timer running"
        );
    }

    #[test]
    fn the_osd_loads_while_a_notch_lists_it_like_any_module() {
        let (mut h, mut s, mut m, _) = rig(json!({"modules": []}));
        h.sync(&mut s, &mut m, 0);
        assert!(!h.has("osd"), "no notch lists it");
        // The host declares a notch with it: it exists and the module loads.
        s.set_ui_catalog(
            vec![json!({"moduleId": "osd", "title": "OSD", "settings": []})],
            None,
            Some(vec![
                json!({"id": "osd", "decoration": false, "modules": ["osd"]}),
            ]),
        );
        h.sync(&mut s, &mut m, 0);
        assert!(h.has("osd"));
        // The config removes the notch: nothing lists it, the module goes.
        s.remove_notch("osd").unwrap();
        h.sync(&mut s, &mut m, 0);
        assert!(!h.has("osd"));
        assert_eq!(
            say(&mut h, &mut s, &mut m, "osd", &["ping"], 0),
            "osd module not loaded"
        );
    }

    #[test]
    fn a_views_change_goes_to_the_ui_once_and_the_peek_to_the_store() {
        let (mut h, mut s, mut m, _) = rig(json!({"modules": ["activities"]}));
        h.sync(&mut s, &mut m, 0);
        let json = r#"{"id":"a","title":"Deploy","sticky":true}"#;
        let args = [json.to_string()];
        let (answer, out) = h.command(&mut s, &mut m, "push", &args, 5).unwrap();
        assert_eq!(answer, "ok");
        assert!(out.iter().any(|u| matches!(u, ToUi::Module(i) if i.active)));
        let slots: Vec<Slot> = out
            .iter()
            .filter_map(|u| match u {
                ToUi::View(v) => Some(v.slot),
                _ => None,
            })
            .collect();
        for slot in [
            Slot::Compact,
            Slot::VerticalCompact,
            Slot::Peek,
            Slot::Expanded,
        ] {
            assert!(slots.contains(&slot), "{slot:?} in {slots:?}");
        }
        // The same push again changes nothing the UIs see.
        let (_, out) = h.command(&mut s, &mut m, "push", &args, 6).unwrap();
        assert!(out.is_empty(), "{out:?}");
        assert!(s.module("activities").unwrap().info.compact);
    }

    #[test]
    fn the_clock_drives_a_running_timer_and_its_end_notifies() {
        let (mut h, mut s, mut m, seen) = rig(json!({"modules": ["timer"]}));
        h.sync(&mut s, &mut m, 0);
        say(&mut h, &mut s, &mut m, "timer", &["1m Tea"], 10_000);
        let due = h.next_due().unwrap();
        assert!(due > 10_000 && due <= 11_100);
        let out = h.tick(&mut s, &mut m, due);
        let compact = out.iter().find_map(|u| match u {
            ToUi::View(v) if v.slot == Slot::Compact => v.tree.clone(),
            _ => None,
        });
        assert!(
            serde_json::to_string(&compact.unwrap())
                .unwrap()
                .contains("0:59")
        );
        h.tick(&mut s, &mut m, 70_010);
        assert_eq!(
            *seen.lock().unwrap(),
            vec![("Time's up".to_string(), "Tea".to_string())]
        );
        assert_eq!(
            h.next_due(),
            Some(70_010 + 60_000),
            "a done timer goes after a minute"
        );
    }

    #[test]
    fn a_button_of_a_view_is_an_event_and_resources_take_a_providers_data() {
        let (mut h, mut s, mut m, _) = rig(json!({"modules": ["timer", "resources"]}));
        h.sync(&mut s, &mut m, 0);
        let out = h.event(
            &mut s,
            &mut m,
            "timer",
            "start",
            &EventValue::Text("5".into()),
            1000,
        );
        assert!(
            out.iter()
                .any(|u| matches!(u, ToUi::View(v) if v.slot == Slot::Compact && v.tree.is_some()))
        );
        let sample = json!({"cpu": 0.5, "cores": 4, "memory": {"used": 1.0, "total": 2.0, "fraction": 0.5}, "disk": null});
        let out = h.feed(&mut s, &mut m, "resources", &sample, 2000);
        assert!(out.iter().any(
            |u| matches!(u, ToUi::View(v) if v.module == "resources" && v.slot == Slot::Compact)
        ));
        assert!(
            h.demo(
                &mut s,
                &mut m,
                "resources",
                &["0.1".into(), "0.2".into(), "0.3".into()],
                3000
            )
            .is_some()
        );
        assert!(!h.wants_resources(), "demo values stop the readings");
    }

    #[test]
    fn media_asks_for_the_players_when_it_loads_and_its_buttons_reach_the_provider() {
        use std::sync::mpsc::channel;
        let (mut h, mut s, mut m, _) = rig(json!({"modules": ["media"]}));
        let (tx, rx) = channel();
        h.set_media(tx);
        assert!(!h.wants_media(), "not loaded yet");
        h.sync(&mut s, &mut m, 0);
        assert!(h.wants_media());
        assert_eq!(rx.try_recv(), Ok(MediaCommand::Refresh));
        let player = json!({"id": "p", "name": "P", "playing": true, "title": "Song", "artist": "A",
            "album": "", "artUrl": "", "length": 100, "position": 10, "canPlay": true, "canPause": true,
            "canNext": true, "canPrev": true, "canSeek": true});
        let out = h.feed(&mut s, &mut m, "media", &json!({"players": [player]}), 1000);
        assert!(
            out.iter()
                .any(|u| matches!(u, ToUi::Module(i) if i.id == "media" && i.active))
        );
        let null = EventValue::Null(());
        h.event(&mut s, &mut m, "media", "next", &null, 1100);
        let half = EventValue::Number(notchd_proto::Num(0.5));
        h.event(&mut s, &mut m, "media", "seek", &half, 1200);
        assert_eq!(rx.try_recv(), Ok(MediaCommand::Next { player: "p".into() }));
        assert_eq!(
            rx.try_recv(),
            Ok(MediaCommand::Seek {
                player: "p".into(),
                seconds: 50.0
            })
        );
        // Demo players stop the system's.
        let demo = json!({"players": []}).to_string();
        h.demo(&mut s, &mut m, "media", &[demo], 2000).unwrap();
        assert!(!h.wants_media());
        let out = h.feed(&mut s, &mut m, "media", &json!({"players": [player]}), 3000);
        assert!(out.is_empty());
    }

    #[test]
    fn the_context_says_whether_a_notch_is_open() {
        let (mut h, mut s, mut m, _) = rig(json!({"modules": ["timer"]}));
        h.sync(&mut s, &mut m, 0);
        assert!(!CoreHost::ctx(&s, "timer").expanded);
    }
}
