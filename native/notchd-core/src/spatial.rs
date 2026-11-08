//! Where notches are: the screens in their physical layout, the one order of
//! the notches (the numbers, the arrows, the digits and the list in
//! settings), which screens a notch hangs on, and where a new one goes.
//!
//! A notch is identified by its `id` here, never by its index in the config:
//! a notch that is not in the config (a temporary one) takes part the same
//! way, and the config's index-based keys stay a matter of `config.rs`.

use crate::position::{self, ALL_SCREENS};
use serde_json::Value;
use std::cmp::Ordering;

/// A screen's place in the layout.
#[derive(Debug, Clone, PartialEq)]
pub struct ScreenAt {
    pub name: String,
    pub x: i32,
    pub y: i32,
}

/// The screens' names in layout order: left to right, then top to bottom.
pub fn layout(screens: &[ScreenAt]) -> Vec<String> {
    let mut list: Vec<&ScreenAt> = screens.iter().collect();
    list.sort_by_key(|a| (a.x, a.y));
    list.into_iter().map(|s| s.name.clone()).collect()
}

/// The screens a notch hangs on, for the `position.screen` it is configured
/// with (`position`: the raw value, `None` for no position) and the connected
/// `screens` in layout order. A name or a list of names is one copy per name
/// that is connected; `"all"` is every connected screen; no screen is the
/// first of the layout; names that are all unplugged fall back to the first
/// of the layout, for the time being (the config is not touched).
pub fn screens_of(position: Option<&Value>, screens: &[String]) -> Vec<String> {
    let Some(first) = screens.first() else {
        return Vec::new();
    };
    let listed = position.map(position::listed_screens).unwrap_or_default();
    if listed.iter().any(|s| s == ALL_SCREENS) {
        return screens.to_vec();
    }
    let on: Vec<String> = screens
        .iter()
        .filter(|s| listed.contains(s))
        .cloned()
        .collect();
    if on.is_empty() {
        vec![first.clone()]
    } else {
        on
    }
}

/// The top, left, right and bottom edges in the order navigation numbers them.
fn edge_rank(edge: &str) -> u8 {
    match edge {
        "top" => 0,
        "left" => 1,
        "right" => 2,
        _ => 3,
    }
}

/// A notch as the order sees it.
#[derive(Debug, Clone, PartialEq)]
pub struct Placed {
    pub id: String,
    pub edge: String,
    pub offset: f64,
    /// The screens it hangs on, by name.
    pub screens: Vec<String>,
}

/// The ids of `notches` in order: by the first screen of the layout it hangs
/// on (`layout`, all the connected screens in layout order), then edge (top,
/// left, right, bottom), then offset along the edge; ties keep the order of
/// `notches` (the config's).
pub fn order(notches: &[Placed], layout: &[String]) -> Vec<String> {
    let rank = |n: &Placed| {
        n.screens
            .iter()
            .filter_map(|s| layout.iter().position(|l| l == s))
            .min()
            .unwrap_or(usize::MAX)
    };
    let mut list: Vec<(usize, &Placed)> = notches.iter().enumerate().collect();
    list.sort_by(|(ia, a), (ib, b)| {
        rank(a)
            .cmp(&rank(b))
            .then_with(|| edge_rank(&a.edge).cmp(&edge_rank(&b.edge)))
            .then_with(|| a.offset.partial_cmp(&b.offset).unwrap_or(Ordering::Equal))
            .then_with(|| ia.cmp(ib))
    });
    list.into_iter().map(|(_, n)| n.id.clone()).collect()
}

/// The number a notch shows in navigation: its place in the order, 1 to 9;
/// 0 (no number, reached with the arrows) past that.
pub fn number(at: usize) -> u32 {
    if at < 9 { at as u32 + 1 } else { 0 }
}

/// Offsets tried for a new notch, nearest the center first.
const SPOTS: [f64; 9] = [0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8, 0.1, 0.9];
/// How close another notch on the same edge of a screen may be: a notch's
/// width is about a fifth of an edge.
const SPOT_GAP: f64 = 0.2;

/// What the creation rule decides for a new notch.
#[derive(Debug, Clone, PartialEq)]
pub struct Spot {
    pub screen: String,
    pub edge: String,
    pub offset: f64,
}

/// Where a new notch goes (the rule shared by Settings' Add, navigation's
/// `n` and `notch add`; it only decides, the caller writes or not). `screen`
/// and `edge` are what was asked for; without them it is the `focused` screen
/// (the first of the layout when that is not connected) and the top edge. The
/// offset is the free spot nearest the center, a notch of `others` on that
/// edge of that screen taking the room around it. Without any screen known
/// and none named, the screen is empty (nothing to write).
pub fn new_spot(
    others: &[Placed],
    layout: &[String],
    focused: &str,
    screen: Option<&str>,
    edge: Option<&str>,
) -> Spot {
    let screen = match screen {
        Some(s) if !s.is_empty() => s.to_string(),
        _ if layout.iter().any(|l| l == focused) => focused.to_string(),
        _ => layout.first().cloned().unwrap_or_default(),
    };
    let edge = edge.unwrap_or("top").to_string();
    let near: Vec<f64> = others
        .iter()
        .filter(|o| o.edge == edge && o.screens.contains(&screen))
        .map(|o| o.offset)
        .collect();
    let offset = SPOTS
        .into_iter()
        .find(|c| near.iter().all(|o| (o - c).abs() >= SPOT_GAP - 1e-9))
        .unwrap_or(position::DEFAULT_OFFSET);
    Spot {
        screen,
        edge,
        offset,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn names(l: &[&str]) -> Vec<String> {
        l.iter().map(|s| s.to_string()).collect()
    }

    fn at(name: &str, x: i32, y: i32) -> ScreenAt {
        ScreenAt {
            name: name.into(),
            x,
            y,
        }
    }

    fn placed(id: &str, edge: &str, offset: f64, screens: &[&str]) -> Placed {
        Placed {
            id: id.into(),
            edge: edge.into(),
            offset,
            screens: names(screens),
        }
    }

    // layout: left to right, then top to bottom, whatever order the UI lists them
    #[test]
    fn layout_goes_left_to_right_then_top_to_bottom() {
        let s = [
            at("C", 1920, 0),
            at("B", 0, 1080),
            at("A", 0, 0),
            at("D", -1920, 300),
        ];
        assert_eq!(layout(&s), ["D", "A", "B", "C"]);
        assert!(layout(&[]).is_empty());
    }

    // screens_of: a name, a list, "all", none, and an unplugged one
    #[test]
    fn screens_of_a_name_a_list_all_none_and_an_unplugged_one() {
        let l = names(&["A", "B", "C"]);
        let of = |v: Value| screens_of(Some(&v), &l);
        assert_eq!(of(json!({"screen": "B"})), ["B"]);
        assert_eq!(
            of(json!({"screen": ["C", "A"]})),
            ["A", "C"],
            "layout order"
        );
        assert_eq!(of(json!({"screen": "all"})), ["A", "B", "C"]);
        assert_eq!(of(json!({"screen": ["B", "all"]})), ["A", "B", "C"]);
        assert_eq!(of(json!({"edge": "left"})), ["A"], "no screen: the first");
        assert_eq!(of(json!({"screen": ""})), ["A"]);
        assert_eq!(screens_of(None, &l), ["A"]);
        assert_eq!(
            of(json!({"screen": "Z"})),
            ["A"],
            "unplugged: the first remaining"
        );
        assert_eq!(of(json!({"screen": ["Z", "C"]})), ["C"], "the plugged ones");
        assert_eq!(of(json!({"screen": ["Z", "Y"]})), ["A"]);
        assert!(screens_of(None, &[]).is_empty(), "no screens known");
    }

    // order: screen, then edge top/left/right/bottom, then offset, ties by config order
    #[test]
    fn order_by_screen_then_edge_then_offset_ties_by_config_order() {
        let l = names(&["A", "B"]);
        // Media (left), Herdr (top center), Infra (top right), FLEX (top left)
        let n = [
            placed("media", "left", 0.5, &["A"]),
            placed("herdr", "top", 0.5, &["A"]),
            placed("infra", "top", 0.8, &["A"]),
            placed("flex", "top", 0.2, &["A"]),
        ];
        assert_eq!(order(&n, &l), ["flex", "herdr", "infra", "media"]);
        let edges = [
            placed("b", "bottom", 0.5, &["A"]),
            placed("r", "right", 0.5, &["A"]),
            placed("l", "left", 0.5, &["A"]),
            placed("t", "top", 0.5, &["A"]),
        ];
        assert_eq!(order(&edges, &l), ["t", "l", "r", "b"]);
        let ties = [
            placed("x", "top", 0.5, &["A"]),
            placed("y", "top", 0.5, &["A"]),
            placed("z", "top", 0.5, &["A"]),
        ];
        assert_eq!(order(&ties, &l), ["x", "y", "z"]);
    }

    // order: numbering continues across screens, a copy on several takes the first
    #[test]
    fn order_continues_across_screens_and_a_copy_on_several_takes_the_first() {
        let l = names(&["A", "B"]);
        let n = [
            placed("on-b", "top", 0.1, &["B"]),
            placed("both", "bottom", 0.5, &["A", "B"]),
            placed("on-a", "right", 0.5, &["A"]),
            placed("late", "top", 0.5, &["B"]),
        ];
        assert_eq!(order(&n, &l), ["on-a", "both", "on-b", "late"]);
        // A screen the layout does not list comes last.
        let odd = [
            placed("g", "top", 0.5, &["Z"]),
            placed("a", "bottom", 0.5, &["A"]),
        ];
        assert_eq!(order(&odd, &l), ["a", "g"]);
    }

    // number: 1 to 9, none past that
    #[test]
    fn number_is_the_place_in_the_order_up_to_nine() {
        assert_eq!(number(0), 1);
        assert_eq!(number(8), 9);
        assert_eq!(number(9), 0);
    }

    // new_spot: top, on the focused screen, the free spot nearest the center
    #[test]
    fn new_spot_top_of_the_focused_screen_at_the_free_spot_nearest_the_center() {
        let l = names(&["A", "B"]);
        let spot = |o: &[Placed], f: &str| new_spot(o, &l, f, None, None);
        let first = spot(&[], "B");
        assert_eq!(
            (first.screen.as_str(), first.edge.as_str(), first.offset),
            ("B", "top", 0.5)
        );
        let centered = [placed("m", "top", 0.5, &["B"])];
        assert_eq!(spot(&centered, "B").offset, 0.3);
        let two = [
            placed("m", "top", 0.5, &["B"]),
            placed("n", "top", 0.3, &["B"]),
        ];
        assert_eq!(spot(&two, "B").offset, 0.7);
        // Another screen or another edge leaves the center free.
        assert_eq!(spot(&centered, "A").offset, 0.5);
        let side = [placed("m", "left", 0.5, &["B"])];
        assert_eq!(spot(&side, "B").offset, 0.5);
        // A focused screen that is not connected: the first of the layout.
        assert_eq!(spot(&[], "gone").screen, "A");
        assert_eq!(spot(&[], "").screen, "A");
        // Every spot taken: the center again.
        let full: Vec<Placed> = [0.1, 0.3, 0.5, 0.7, 0.9]
            .iter()
            .map(|o| placed("x", "top", *o, &["B"]))
            .collect();
        assert_eq!(spot(&full, "B").offset, 0.5);
    }

    // new_spot: what was asked for wins; nothing without a screen
    #[test]
    fn new_spot_takes_the_screen_and_edge_asked_for() {
        let l = names(&["A", "B"]);
        let s = new_spot(&[], &l, "A", Some("B"), Some("left"));
        assert_eq!((s.screen.as_str(), s.edge.as_str()), ("B", "left"));
        assert_eq!(new_spot(&[], &[], "", None, None).screen, "");
        assert_eq!(new_spot(&[], &[], "", Some("X"), None).screen, "X");
    }
}
