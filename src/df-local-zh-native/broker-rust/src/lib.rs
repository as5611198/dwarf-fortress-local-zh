pub mod common;
pub mod bounded;
pub mod display;
pub mod equipment;
pub mod numeric_templates;
pub mod offline_prose;
pub mod offline_preferences;
pub mod offline_items;
pub mod offline_combat;
pub mod offline_history;
mod offline_dates;
pub mod official;
pub mod provider;
pub mod service;
mod registry;
mod translation_cache;
mod journal_compaction;
mod journal_tail;
mod runtime_history;
// Deferred rotation prototype: compile staging checks only in unit tests.
#[cfg(test)]
mod journal_snapshot;
pub mod settings;
pub mod shared;
