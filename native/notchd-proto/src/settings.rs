//! The `schema` entity: settings pages and fields, resolved by the core.
//! `FieldDef` is the source format (a module's `settings`, docs/settings.md);
//! `Field` is what the UI gets.

use crate::num::Num;
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// The field types of docs/settings.md.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum FieldType {
    Choice,
    Integer,
    Number,
    Boolean,
    String,
    Color,
    Modules,
    Workspaces,
    Notches,
    ModuleCatalog,
    Note,
}

/// `{ value, label, preview }`.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct FieldOption {
    pub value: Value,
    pub label: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub preview: Option<String>,
}

/// The field shows only while the field `key` of the same page is `is` (or one
/// of them, when it is a list).
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct When {
    pub key: String,
    pub is: Value,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Display {
    Cards,
    Chips,
    Percent,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Page {
    pub id: String,
    pub label: String,
    pub icon: String,
    /// A sub page (a module's), shown under its parent.
    pub sub: bool,
}

/// A field as the UI renders it. A null `default` or `value` is left out.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Field {
    pub page: String,
    pub section: String,
    /// Absent for a `note`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub key: Option<String>,
    pub r#type: FieldType,
    pub label: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub help: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub options: Option<Vec<FieldOption>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub display: Option<Display>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub min: Option<Num>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max: Option<Num>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub step: Option<Num>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub unit: Option<String>,
    #[serde(default, skip_serializing_if = "Value::is_null")]
    pub default: Value,
    #[serde(default, skip_serializing_if = "Value::is_null")]
    pub value: Value,
    /// `Settings.shownFields`'s answer.
    pub visible: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub when: Option<When>,
    /// For `moduleCatalog`: which list of the Modules page (`notch`,
    /// `agent` or `terminal`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub part: Option<String>,
}

/// A field as a module's `module.json` (or a built-in module's JSON) writes it.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct FieldDef {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub key: Option<String>,
    pub r#type: FieldType,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub help: Option<String>,
    #[serde(default, skip_serializing_if = "Value::is_null")]
    pub default: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub page: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub section: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub options: Option<Vec<FieldOption>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub display: Option<Display>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub min: Option<Num>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max: Option<Num>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub step: Option<Num>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub unit: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub absolute: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub when: Option<When>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub required: Option<bool>,
}
