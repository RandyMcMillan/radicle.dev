//! The Radicle provider: the repositories the local node knows about.
//!
//! The `rad` CLI has no machine readable output - there is no `rad ls
//! --json` - so the table it prints is read instead. The name and the RID of
//! every repository come from that table, the owner from the identity
//! document, which `rad inspect` prints as JSON.
//!
//! The table is only truncated when `rad` writes to a terminal. Its output
//! is captured through a pipe here, so every row is complete.

use std::process::Command;

use anyhow::{Result, bail};
use serde_json::Value;

use super::{ListError, Listing, Repo, has_cli, require_cli, run_capture, run_interactive};

pub fn login() -> Result<()> {
    if !has_cli("rad") {
        bail!("rad CLI not found. Install it from https://radicle.xyz");
    }
    run_interactive("rad", &["auth"])
}

/// One repository as `rad ls` lists it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    /// The name of the project.
    pub name: String,
    /// The repository identifier, without the `rad:` prefix.
    pub rid: String,
}

/// The prefix the CLI prints a repository identifier with.
const RAD_PREFIX: &str = "rad:";

/// The repositories `rad ls` lists.
///
/// Every repository is a row of the table: the name in the first column, the
/// RID in the second. The RID is printed as `rad:z3...`; the header row
/// holds the word `RID` instead of an identifier and is therefore skipped.
pub fn parse_ls(out: &str) -> Vec<Entry> {
    let mut entries = Vec::new();

    for line in out.lines() {
        let Some(row) = row_of(line) else { continue };
        let Some((name, rid)) = row_entry(row) else {
            continue;
        };
        entries.push(Entry { name, rid });
    }

    entries
}

/// The contents of a table row, without its borders.
fn row_of(line: &str) -> Option<&str> {
    let line = line.trim();
    let row = line.strip_prefix('│')?.strip_suffix('│')?;
    Some(row)
}

/// The name and the identifier of a table row.
///
/// The identifier is printed as `rad:` followed by a base58 string. The name
/// is everything before it and may contain spaces.
fn row_entry(row: &str) -> Option<(String, String)> {
    let mut at = 0;

    while let Some(found) = row[at..].find(RAD_PREFIX) {
        let start = at + found;
        at = start + RAD_PREFIX.len();
        let word = row[at..].split_whitespace().next().unwrap_or_default();
        if word.is_empty() || !word.chars().all(is_base58) {
            continue;
        }
        let name = row[..start].trim();
        if name.is_empty() {
            continue;
        }
        return Some((name.to_string(), word.to_string()));
    }

    None
}

/// A character of a base58 encoded identifier.
fn is_base58(c: char) -> bool {
    c.is_ascii_alphanumeric() && !matches!(c, '0' | 'O' | 'I' | 'l')
}

/// The owner of a repository: the first delegate of its identity document.
///
/// The DID is shortened to the part that is safe to put in a path.
pub fn parse_namespace(identity: &Value) -> String {
    let did = identity
        .get("delegates")
        .and_then(Value::as_array)
        .and_then(|delegates| delegates.first())
        .and_then(Value::as_str)
        .unwrap_or_default();

    did.strip_prefix("did:key:")
        .unwrap_or(did)
        .replace(':', "-")
}

/// The name a repository is listed under.
///
/// `rad ls` prints a placeholder for a repository without a project
/// payload; such a repository is listed under its RID.
fn name_of(name: &str, rid: &str) -> String {
    match name {
        "No name provided." | "Error determining name." => rid.to_string(),
        other => other.to_string(),
    }
}

fn ls_command() -> Command {
    let mut cmd = Command::new("rad");
    cmd.args(["ls"]);
    cmd
}

fn inspect_command(rid: &str) -> Command {
    let mut cmd = Command::new("rad");
    cmd.args(["inspect", rid, "--identity"]);
    cmd
}

/// The owner of a repository, read from its identity document.
///
/// A repository whose identity cannot be read has no owner; the caller
/// falls back to the RID, which identifies the repository just as well.
fn namespace_of(rid: &str) -> Option<String> {
    let raw = run_capture(&mut inspect_command(rid)).ok()?;
    let identity: Value = serde_json::from_str(&raw).ok()?;
    let namespace = parse_namespace(&identity);
    (!namespace.is_empty()).then_some(namespace)
}

pub fn list_repos() -> Result<Listing, ListError> {
    require_cli("rad")?;
    let raw = run_capture(&mut ls_command())?;

    let mut repos = Vec::new();
    for entry in parse_ls(&raw) {
        let name = name_of(&entry.name, &entry.rid);
        let namespace = namespace_of(&entry.rid).unwrap_or_else(|| entry.rid.clone());
        let url = format!("rad://{}", entry.rid);
        repos.push(Repo {
            full_name: format!("{namespace}/{name}"),
            ssh_url: url.clone(),
            https_url: url,
            ..Default::default()
        });
    }

    Ok(repos.into())
}

#[cfg(test)]
mod tests {
    use super::super::tests::args;
    use super::*;

    const LS: &str = "\
╭──────────────────────────────────────────────────────────────────────────╮
│ Name            RID                                 Visibility   Head    │
├──────────────────────────────────────────────────────────────────────────┤
│ heartwood       rad:z3roth2n2bWgajcPTbK8cCGLJEdEk   public       b01ccd2 │
│ radicle-hello   rad:z4NAgnqBFpEWFvX6QdofHGqqfUgqu   public       179e27a │
╰──────────────────────────────────────────────────────────────────────────╯
";

    #[test]
    fn runs_rad_ls() {
        let cmd = ls_command();
        assert_eq!(cmd.get_program(), "rad");
        assert_eq!(args(&cmd), ["ls"]);
    }

    #[test]
    fn runs_rad_inspect() {
        let cmd = inspect_command("z3abc");
        assert_eq!(cmd.get_program(), "rad");
        assert_eq!(args(&cmd), ["inspect", "z3abc", "--identity"]);
    }

    #[test]
    fn parses_rad_ls() {
        let entries = parse_ls(LS);
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].name, "heartwood");
        assert_eq!(entries[0].rid, "z3roth2n2bWgajcPTbK8cCGLJEdEk");
        assert_eq!(entries[1].name, "radicle-hello");
        assert_eq!(entries[1].rid, "z4NAgnqBFpEWFvX6QdofHGqqfUgqu");
    }

    #[test]
    fn ignores_a_table_without_repositories() {
        assert!(parse_ls("Nothing to show.\n").is_empty());
        assert!(parse_ls("").is_empty());
    }

    #[test]
    fn parses_the_owner_of_a_repository() {
        let identity: Value = serde_json::from_str(
            r#"{"delegates":["did:key:z6MknaPSgdX4VLt3qxQ4ip3b5DFABqDhWFhkjEnwgR21eWMd"],"threshold":1}"#,
        )
        .unwrap();
        assert_eq!(
            parse_namespace(&identity),
            "z6MknaPSgdX4VLt3qxQ4ip3b5DFABqDhWFhkjEnwgR21eWMd"
        );
    }

    #[test]
    fn a_repository_without_an_owner_has_none() {
        let identity: Value = serde_json::from_str(r#"{"threshold":1}"#).unwrap();
        assert_eq!(parse_namespace(&identity), "");
    }

    #[test]
    fn a_repository_without_a_name_is_listed_under_its_rid() {
        assert_eq!(name_of("heartwood", "z3abc"), "heartwood");
        assert_eq!(name_of("No name provided.", "z3abc"), "z3abc");
        assert_eq!(name_of("Error determining name.", "z3abc"), "z3abc");
    }
}
