//! Custom modules (docs/modules.md): the rules of making one over IPC. A
//! custom module is a folder of the user's with a `module.json`; the daemon
//! writes and removes the folder, this reads what was asked.

/// The reply to `terminal add` with arguments that do not parse.
pub const TERMINAL_ADD_USAGE: &str =
    "usage: terminal add [<id> <command> [--directory <dir>] [--title <title>]]";

/// What `terminal add <id> <command> [--directory <dir>] [--title <title>]`
/// asks for.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TerminalAdd {
    pub id: String,
    pub command: String,
    /// The terminal's `directory` setting.
    pub directory: Option<String>,
    pub title: Option<String>,
}

/// The arguments of `terminal add` (those after `add`): the id, then the
/// command (words left over are part of it: `dev npm run dev`), with
/// `--directory` and `--title` (`--flag value` or `--flag=value`) anywhere.
/// `Err` is the reply.
pub fn parse_terminal_add(args: &[String]) -> Result<TerminalAdd, String> {
    let mut positional: Vec<&str> = Vec::new();
    let mut directory = None;
    let mut title = None;
    let mut it = args.iter();
    while let Some(a) = it.next() {
        let flag = |name: &str| -> Option<Option<String>> {
            if a == name {
                Some(None)
            } else {
                a.strip_prefix(&format!("{name}="))
                    .map(|v| Some(v.to_string()))
            }
        };
        let slot = if let Some(v) = flag("--directory") {
            Some((&mut directory, v))
        } else {
            flag("--title").map(|v| (&mut title, v))
        };
        match slot {
            Some((into, inline)) => {
                let value = match inline {
                    Some(v) => v,
                    None => it
                        .next()
                        .cloned()
                        .ok_or_else(|| format!("{a} needs a value; {TERMINAL_ADD_USAGE}"))?,
                };
                *into = Some(value);
            }
            None if a.starts_with("--") => {
                return Err(format!("unknown option {a}; {TERMINAL_ADD_USAGE}"));
            }
            None => positional.push(a),
        }
    }
    let [id, command @ ..] = positional.as_slice() else {
        return Err(TERMINAL_ADD_USAGE.into());
    };
    let command = command.join(" ");
    if command.trim().is_empty() {
        return Err(format!("a terminal needs a command; {TERMINAL_ADD_USAGE}"));
    }
    Ok(TerminalAdd {
        id: (*id).to_string(),
        command,
        directory: directory.filter(|d: &String| !d.trim().is_empty()),
        title: title.filter(|t: &String| !t.trim().is_empty()),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| (*s).to_string()).collect()
    }

    #[test]
    fn an_id_and_a_command_make_a_terminal() {
        assert_eq!(
            parse_terminal_add(&args(&["btop", "btop"])),
            Ok(TerminalAdd {
                id: "btop".into(),
                command: "btop".into(),
                directory: None,
                title: None
            })
        );
    }

    #[test]
    fn the_words_after_the_id_are_the_command_and_the_flags_go_anywhere() {
        let a = parse_terminal_add(&args(&[
            "--title",
            "Dev server",
            "dev",
            "npm",
            "run",
            "dev",
            "--directory=~/app",
        ]))
        .unwrap();
        assert_eq!(a.id, "dev");
        assert_eq!(a.command, "npm run dev");
        assert_eq!(a.directory.as_deref(), Some("~/app"));
        assert_eq!(a.title.as_deref(), Some("Dev server"));
        // An empty value is no value.
        let b = parse_terminal_add(&args(&["a", "x", "--directory", "", "--title", " "])).unwrap();
        assert_eq!((b.directory, b.title), (None, None));
    }

    #[test]
    fn what_does_not_parse_says_the_usage() {
        for bad in [
            args(&[]),
            args(&["only-an-id"]),
            args(&["a", "  "]),
            args(&["a", "x", "--directory"]),
            args(&["a", "x", "--color", "red"]),
        ] {
            let e = parse_terminal_add(&bad).unwrap_err();
            assert!(e.contains("terminal add"), "{bad:?}: {e}");
        }
    }
}
