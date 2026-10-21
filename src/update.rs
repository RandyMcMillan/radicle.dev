//! Update check against GitHub Releases.
//!
//! Every regular command prints a banner from a cached "latest version" file,
//! then refreshes that cache from a detached child process (at most once per
//! TTL) so the network call never slows the command down. `update` downloads
//! the release asset for this platform, verifies it against `SHA256SUMS` and
//! replaces the running binary.

use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, SystemTime};

use anyhow::{Context, Result, anyhow, bail};
use semver::Version;
use serde::Deserialize;
use sha2::{Digest, Sha256};

use crate::config::{Settings, home_dir};
use crate::{http, output};

pub const CURRENT: &str = env!("CARGO_PKG_VERSION");
pub const REFRESH_ARG: &str = "__refresh-update-cache";
/// Where the releases of this tool are published. It is this repository,
/// not the upstream project: an upstream release carries a binary that calls
/// itself by the upstream name, and a self-update that installed it would
/// replace gnostr-dev with a tool of another name.
const DEFAULT_API: &str = "https://api.github.com/repos/RandyMcMillan/radicle.dev/releases/latest";
const DEFAULT_TTL: u64 = 86_400;
const MAX_ASSET_BYTES: u64 = 200 * 1024 * 1024;

#[derive(Debug, Deserialize)]
struct Release {
    tag_name: String,
    #[serde(default)]
    assets: Vec<Asset>,
}

#[derive(Debug, Deserialize)]
struct Asset {
    name: String,
    browser_download_url: String,
}

fn api_url() -> String {
    // GNOSTR_DEV_UPDATE_URL wins; REPOS_MANAGER_UPDATE_URL is still read for
    // the setups that predate the rename.
    std::env::var("GNOSTR_DEV_UPDATE_URL")
        .or_else(|_| std::env::var("REPOS_MANAGER_UPDATE_URL"))
        .unwrap_or_else(|_| DEFAULT_API.to_string())
}

fn cache_path() -> PathBuf {
    if let Some(p) = std::env::var_os("GNOSTR_DEV_UPDATE_CACHE")
        .or_else(|| std::env::var_os("REPOS_MANAGER_UPDATE_CACHE"))
    {
        return PathBuf::from(p);
    }
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(dirs::cache_dir)
        .unwrap_or_else(|| home_dir().join(".cache"));
    base.join("gnostr-dev").join("latest-version")
}

fn ttl() -> Duration {
    let secs = std::env::var("GNOSTR_DEV_UPDATE_TTL")
        .or_else(|_| std::env::var("REPOS_MANAGER_UPDATE_TTL"))
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(DEFAULT_TTL);
    Duration::from_secs(secs)
}

fn parse_version(s: &str) -> Option<Version> {
    Version::parse(s.trim().trim_start_matches('v')).ok()
}

/// True when `latest` is strictly newer than `current`.
pub fn is_newer(latest: &str, current: &str) -> bool {
    matches!((parse_version(latest), parse_version(current)), (Some(l), Some(c)) if l > c)
}

fn cache_is_stale(path: &Path, ttl: Duration) -> bool {
    fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| SystemTime::now().duration_since(t).ok())
        .is_none_or(|age| age >= ttl)
}

/// Banner text for the cached latest version, if it is newer than this build.
const SELF_UPDATE_HINT: &str = "run: gnostr-dev update";

/// How to update when a package manager owns the binary: replacing it in
/// place would fail without root, or desync the package manager's records.
pub fn package_manager_hint(exe: &Path) -> Option<&'static str> {
    let p = exe.to_string_lossy().replace('\\', "/").to_lowercase();
    if p.contains("/cellar/") || p.starts_with("/opt/homebrew/") || p.contains("/linuxbrew/") {
        Some("run: brew upgrade gnostr-dev")
    } else if p.contains("/scoop/apps/") {
        Some("run: scoop update gnostr-dev")
    } else if p.contains("/microsoft/winget/") {
        Some("run: winget upgrade gnostr-dev")
    } else if p.contains("/.cargo/bin/") {
        Some("run: cargo install gnostr-dev")
    } else if p.starts_with("/usr/bin/") || p.starts_with("/bin/") {
        Some("update it with your system package manager")
    } else {
        None
    }
}

fn managed_hint() -> Option<&'static str> {
    std::env::current_exe()
        .ok()
        .and_then(|p| package_manager_hint(&p))
}

fn banner_message(cached: &str, hint: &str) -> Option<String> {
    let latest = cached.trim();
    is_newer(latest, CURRENT)
        .then(|| format!("⬆ gnostr-dev {latest} available (current {CURRENT}), {hint}"))
}

pub fn banner(settings: &Settings) {
    if !settings.check_updates {
        return;
    }
    if let Some(msg) = fs::read_to_string(cache_path())
        .ok()
        .and_then(|c| banner_message(&c, managed_hint().unwrap_or(SELF_UPDATE_HINT)))
    {
        eprintln!("{}", output::yellow(&msg));
    }
}

/// Spawn a detached copy of ourselves to refresh the cache. Never fails the caller.
pub fn refresh_async(settings: &Settings) {
    if !settings.check_updates || !cache_is_stale(&cache_path(), ttl()) {
        return;
    }
    let Ok(exe) = std::env::current_exe() else {
        return;
    };
    let mut cmd = Command::new(exe);
    cmd.arg(REFRESH_ARG)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        // Own process group so Ctrl+C on the parent does not kill the refresh.
        cmd.process_group(0);
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const DETACHED_PROCESS: u32 = 0x0000_0008;
        const CREATE_NEW_PROCESS_GROUP: u32 = 0x0000_0200;
        cmd.creation_flags(DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP);
    }
    let _ = cmd.spawn();
}

fn fetch_release(url: &str, timeout: Duration) -> Result<Release> {
    http::agent(timeout)
        .get(url)
        .header("Accept", "application/vnd.github+json")
        .call()
        .with_context(|| format!("cannot read the release list at {url}"))?
        .body_mut()
        .read_json()
        .with_context(|| format!("unexpected release API response at {url}"))
}

/// Entry point of the detached child.
pub fn refresh_cache() -> Result<()> {
    refresh_cache_to(&api_url(), &cache_path())
}

fn refresh_cache_to(url: &str, path: &Path) -> Result<()> {
    let release = match fetch_release(url, Duration::from_secs(5)) {
        Ok(release) => release,
        Err(e) => {
            // Nothing could be learned about the latest release. A version
            // left in the cache would be advertised for as long as it stays
            // there, so it goes.
            let _ = fs::remove_file(path);
            return Err(e);
        }
    };

    // A release that carries no binary for this platform is not an update
    // for this tool: it belongs to another program. Advertising it would
    // offer an update that cannot be installed.
    if !carries_binary(&release) {
        let _ = fs::remove_file(path);
        return Ok(());
    }

    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    fs::write(path, release.tag_name.trim_start_matches('v'))?;
    Ok(())
}

/// Whether a release carries a binary of this tool for this platform.
fn carries_binary(release: &Release) -> bool {
    let Ok(asset) = asset_name() else {
        return false;
    };
    release.assets.iter().any(|a| a.name == asset)
}

/// GitHub release asset for a platform. Windows always maps to the MSVC
/// build: the mingw one only exists on the Forgejo release.
pub fn asset_name_for(os: &str, arch: &str) -> Result<String> {
    if !matches!(arch, "x86_64" | "aarch64") {
        bail!("no prebuilt binary for {arch}");
    }
    let name = match os {
        "linux" => format!("{arch}-unknown-linux-musl.tar.gz"),
        "macos" => format!("{arch}-apple-darwin.tar.gz"),
        "windows" => format!("{arch}-pc-windows-msvc.zip"),
        other => bail!("no prebuilt binary for {other}"),
    };
    Ok(format!("gnostr-dev-{name}"))
}

pub fn asset_name() -> Result<String> {
    asset_name_for(std::env::consts::OS, std::env::consts::ARCH)
}

fn download(url: &str) -> Result<Vec<u8>> {
    let mut buf = Vec::new();
    http::agent(Duration::from_secs(300))
        .get(url)
        .call()
        .with_context(|| format!("download failed: {url}"))?
        .body_mut()
        .as_reader()
        .take(MAX_ASSET_BYTES)
        .read_to_end(&mut buf)?;
    Ok(buf)
}

pub fn expected_checksum(sums: &str, asset: &str) -> Option<String> {
    sums.lines().find_map(|l| {
        let (hash, name) = l.split_once(char::is_whitespace)?;
        (name.trim().trim_start_matches('*') == asset).then(|| hash.to_lowercase())
    })
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn extract_binary(archive: &[u8], asset: &str) -> Result<Vec<u8>> {
    let bin = if cfg!(windows) {
        "gnostr-dev.exe"
    } else {
        "gnostr-dev"
    };
    let is_bin = |p: &Path| p.file_name().is_some_and(|n| n == bin);
    let mut out = Vec::new();
    if asset.ends_with(".zip") {
        let mut zip = zip::ZipArchive::new(io::Cursor::new(archive))?;
        for i in 0..zip.len() {
            let mut f = zip.by_index(i)?;
            if f.enclosed_name().is_some_and(|p| is_bin(&p)) {
                f.read_to_end(&mut out)?;
                return Ok(out);
            }
        }
    } else {
        let mut tar = tar::Archive::new(flate2::read::GzDecoder::new(archive));
        for entry in tar.entries()? {
            let mut e = entry?;
            if is_bin(&e.path()?) {
                e.read_to_end(&mut out)?;
                return Ok(out);
            }
        }
    }
    Err(anyhow!("{bin} not found in {asset}"))
}

/// Download the asset `name` and `SHA256SUMS` through `fetch`, check the
/// archive's hash and return the binary it contains.
fn verified_binary(
    release: &Release,
    name: &str,
    fetch: impl Fn(&str) -> Result<Vec<u8>>,
) -> Result<Vec<u8>> {
    let find = |n: &str| {
        release
            .assets
            .iter()
            .find(|a| a.name == n)
            .map(|a| a.browser_download_url.clone())
            .ok_or_else(|| anyhow!("release {} has no asset {n}", release.tag_name))
    };
    let archive = fetch(&find(name)?)?;
    let sums = String::from_utf8(fetch(&find("SHA256SUMS")?)?)?;
    let expected =
        expected_checksum(&sums, name).ok_or_else(|| anyhow!("{name} missing from SHA256SUMS"))?;
    let actual = hex(&Sha256::digest(&archive));
    if actual != expected {
        bail!("checksum mismatch for {name}: expected {expected}, got {actual}");
    }
    extract_binary(&archive, name)
}

fn confirm(prompt: &str) -> Result<bool> {
    print!("{prompt} [y/N] ");
    io::stdout().flush()?;
    let mut answer = String::new();
    io::stdin().read_line(&mut answer)?;
    Ok(matches!(answer.trim(), "y" | "Y" | "yes"))
}

pub fn self_update(assume_yes: bool) -> Result<()> {
    if let Some(hint) = managed_hint() {
        bail!("this install is managed by a package manager, {hint}");
    }
    output::info("Checking for updates...");
    let release = fetch_release(&api_url(), Duration::from_secs(15))?;
    let latest = release.tag_name.trim_start_matches('v');
    if !is_newer(latest, CURRENT) {
        output::success(&format!("Already up to date ({CURRENT})"));
        return Ok(());
    }
    output::info(&format!(
        "New version available: {} (current: {CURRENT})",
        output::green(latest)
    ));
    let asset = asset_name()?;
    if !release.assets.iter().any(|a| a.name == asset) {
        bail!("release {latest} carries no {asset} binary");
    }
    if !assume_yes && !confirm("Update now?")? {
        return Ok(());
    }

    let binary = verified_binary(&release, &asset, download)?;
    let tmp = std::env::temp_dir().join(format!("gnostr-dev-update-{}", std::process::id()));
    fs::write(&tmp, &binary)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&tmp, fs::Permissions::from_mode(0o755))?;
    }
    let res = self_replace::self_replace(&tmp)
        .context("cannot replace the running binary (permissions?)");
    let _ = fs::remove_file(&tmp);
    res?;
    let _ = fs::write(cache_path(), latest);
    output::success(&format!("Updated to {latest}"));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_server::{Response, Server};

    #[test]
    fn version_comparison() {
        assert!(is_newer("1.0.1", "1.0.0"));
        assert!(is_newer("v1.1.0", "1.0.9"));
        assert!(!is_newer("1.0.0", "1.0.0"));
        assert!(!is_newer("0.9.0", "1.0.0"));
        assert!(!is_newer("garbage", "1.0.0"));
    }

    #[test]
    fn checksum_lookup() {
        let sums = "abc123  gnostr-dev-x86_64-unknown-linux-musl.tar.gz\nDEF456 *gnostr-dev-x86_64-pc-windows-msvc.zip\n";
        assert_eq!(
            expected_checksum(sums, "gnostr-dev-x86_64-unknown-linux-musl.tar.gz").as_deref(),
            Some("abc123")
        );
        assert_eq!(
            expected_checksum(sums, "gnostr-dev-x86_64-pc-windows-msvc.zip").as_deref(),
            Some("def456")
        );
        assert_eq!(expected_checksum(sums, "nope"), None);
    }

    #[test]
    fn asset_names_match_release_targets() {
        assert_eq!(
            asset_name_for("linux", "aarch64").unwrap(),
            "gnostr-dev-aarch64-unknown-linux-musl.tar.gz"
        );
        assert_eq!(
            asset_name_for("macos", "x86_64").unwrap(),
            "gnostr-dev-x86_64-apple-darwin.tar.gz"
        );
        assert_eq!(
            asset_name_for("windows", "x86_64").unwrap(),
            "gnostr-dev-x86_64-pc-windows-msvc.zip"
        );
        assert!(asset_name_for("freebsd", "x86_64").is_err());
        assert!(asset_name_for("linux", "riscv64").is_err());
    }

    #[test]
    fn asset_name_for_this_platform() {
        let n = asset_name().unwrap();
        assert!(n.starts_with("gnostr-dev-"));
        assert!(n.ends_with(".tar.gz") || n.ends_with(".zip"));
    }

    const BIN: &str = if cfg!(windows) {
        "gnostr-dev.exe"
    } else {
        "gnostr-dev"
    };

    fn tar_gz(name: &str, data: &[u8]) -> Vec<u8> {
        let mut tar = tar::Builder::new(flate2::write::GzEncoder::new(
            Vec::new(),
            flate2::Compression::fast(),
        ));
        let mut header = tar::Header::new_gnu();
        header.set_size(data.len() as u64);
        header.set_mode(0o755);
        header.set_cksum();
        tar.append_data(&mut header, name, data).unwrap();
        tar.into_inner().unwrap().finish().unwrap()
    }

    fn zip(name: &str, data: &[u8]) -> Vec<u8> {
        let mut zip = zip::ZipWriter::new(io::Cursor::new(Vec::new()));
        zip.start_file("README.md", zip::write::SimpleFileOptions::default())
            .unwrap();
        zip.write_all(b"readme").unwrap();
        zip.start_file(name, zip::write::SimpleFileOptions::default())
            .unwrap();
        zip.write_all(data).unwrap();
        zip.finish().unwrap().into_inner()
    }

    #[test]
    fn extracts_from_tar_gz() {
        let gz = tar_gz(&format!("dir/{BIN}"), b"binary");
        assert_eq!(extract_binary(&gz, "x.tar.gz").unwrap(), b"binary");
        let other = tar_gz("something-else", b"x");
        assert!(extract_binary(&other, "x.tar.gz").is_err());
    }

    #[test]
    fn extracts_from_zip() {
        let z = zip(BIN, b"exe");
        assert_eq!(extract_binary(&z, "x.zip").unwrap(), b"exe");
        let other = zip("other.exe", b"x");
        let err = extract_binary(&other, "x.zip").unwrap_err();
        assert!(err.to_string().contains("not found in x.zip"), "{err}");
        assert!(extract_binary(b"not a zip", "x.zip").is_err());
    }

    #[test]
    fn hex_encoding() {
        assert_eq!(hex(&[0x00, 0x0f, 0xab]), "000fab");
    }

    #[test]
    fn banner_only_for_newer_versions() {
        let msg = banner_message("99.0.0\n", SELF_UPDATE_HINT).unwrap();
        assert!(
            msg.contains("99.0.0 available") && msg.contains(CURRENT),
            "{msg}"
        );
        assert!(msg.ends_with(SELF_UPDATE_HINT));
        assert_eq!(banner_message(CURRENT, SELF_UPDATE_HINT), None);
        assert_eq!(banner_message("not a version", SELF_UPDATE_HINT), None);
        assert_eq!(banner_message("", SELF_UPDATE_HINT), None);
    }

    #[test]
    fn package_manager_installs_are_detected() {
        let hint = |p: &str| package_manager_hint(Path::new(p));
        let system = Some("update it with your system package manager");
        let brew = Some("run: brew upgrade gnostr-dev");
        assert_eq!(hint("/usr/bin/gnostr-dev"), system);
        assert_eq!(hint("/opt/homebrew/bin/gnostr-dev"), brew);
        assert_eq!(
            hint("/usr/local/Cellar/gnostr-dev/1.0.0/bin/gnostr-dev"),
            brew
        );
        assert_eq!(
            hint(r"C:\Users\me\scoop\apps\gnostr-dev\current\gnostr-dev.exe"),
            Some("run: scoop update gnostr-dev")
        );
        assert_eq!(
            hint(r"C:\Users\me\AppData\Local\Microsoft\WinGet\Packages\x\gnostr-dev.exe"),
            Some("run: winget upgrade gnostr-dev")
        );
        assert_eq!(
            hint("/home/me/.cargo/bin/gnostr-dev"),
            Some("run: cargo install gnostr-dev")
        );
        assert_eq!(hint("/home/me/.local/bin/gnostr-dev"), None);
        assert_eq!(hint("/usr/local/bin/gnostr-dev"), None);
        assert_eq!(
            hint(r"C:\Users\me\AppData\Local\Programs\gnostr-dev\gnostr-dev.exe"),
            None
        );
    }

    #[test]
    fn cache_staleness() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("latest-version");
        assert!(cache_is_stale(&path, Duration::from_secs(3600)));
        fs::write(&path, "1.0.0").unwrap();
        assert!(!cache_is_stale(&path, Duration::from_secs(3600)));
        assert!(cache_is_stale(&path, Duration::ZERO));
    }

    #[test]
    fn banner_and_refresh_are_noops_when_disabled() {
        let mut settings = Settings::for_tests(Path::new("/"));
        settings.check_updates = false;
        banner(&settings);
        refresh_async(&settings);
    }

    /// A release as the API returns it, with the given assets.
    fn release_json(tag: &str, assets: &[&str]) -> String {
        let assets: Vec<String> = assets
            .iter()
            .map(|n| format!(r#"{{"name":"{n}","browser_download_url":"mem://{n}"}}"#))
            .collect();
        format!(r#"{{"tag_name":"{tag}","assets":[{}]}}"#, assets.join(","))
    }

    #[test]
    fn refresh_writes_cache_without_v_prefix() {
        let asset = asset_name().unwrap();
        let body = release_json("v9.9.9", &[&asset]);
        let server = Server::start(move |target| match target {
            "/latest" => Response::json(&body),
            _ => Response::not_found(),
        });
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("cache").join("latest-version");
        refresh_cache_to(&format!("{}/latest", server.url), &path).unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), "9.9.9");
        assert!(server.requests()[0].contains("application/vnd.github+json"));
    }

    #[test]
    fn a_release_without_a_binary_is_not_an_update() {
        // A release of another program: its version is not ours to offer.
        let body = release_json(
            "v9.9.9",
            &["some-other-tool-x86_64-unknown-linux-musl.tar.gz"],
        );
        let server = Server::start(move |_| Response::json(&body));
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("cache").join("latest-version");
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, "1.0.0").unwrap();
        refresh_cache_to(&server.url, &path).unwrap();
        assert!(!path.exists(), "the stale version is still advertised");
    }

    #[test]
    fn a_failed_refresh_drops_the_stale_version() {
        let server = Server::start(|_| Response::not_found());
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("cache").join("latest-version");
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, "1.0.0").unwrap();
        assert!(refresh_cache_to(&server.url, &path).is_err());
        assert!(!path.exists(), "the stale version is still advertised");
    }

    #[test]
    fn invalid_release_payload_is_an_error() {
        let server = Server::start(|_| Response::json(r#"{"name":"no tag"}"#));
        let err = fetch_release(&server.url, Duration::from_secs(5)).unwrap_err();
        assert!(err.to_string().contains("unexpected"), "{err}");
    }

    #[test]
    fn download_returns_body() {
        let server = Server::start(|_| Response::bytes(vec![1, 2, 3]));
        assert_eq!(download(&server.url).unwrap(), [1, 2, 3]);
        let missing = Server::start(|_| Response::not_found());
        assert!(download(&missing.url).is_err());
    }

    #[test]
    fn verified_binary_checks_sha256() {
        let name = "gnostr-dev-x86_64-unknown-linux-musl.tar.gz";
        let archive = tar_gz(BIN, b"new binary");
        let good_sums = format!("{}  {name}\n", hex(&Sha256::digest(&archive)));
        let release = |assets: &[&str]| Release {
            tag_name: "v2.0.0".into(),
            assets: assets
                .iter()
                .map(|n| Asset {
                    name: n.to_string(),
                    browser_download_url: format!("mem://{n}"),
                })
                .collect(),
        };
        let full = release(&[name, "SHA256SUMS"]);
        let fetch = |sums: String| {
            let archive = archive.clone();
            move |url: &str| -> Result<Vec<u8>> {
                Ok(if url.ends_with("SHA256SUMS") {
                    sums.clone().into_bytes()
                } else {
                    archive.clone()
                })
            }
        };

        let bin = verified_binary(&full, name, fetch(good_sums.clone())).unwrap();
        assert_eq!(bin, b"new binary");

        let bad = format!("{}  {name}\n", "0".repeat(64));
        let err = verified_binary(&full, name, fetch(bad)).unwrap_err();
        assert!(err.to_string().contains("checksum mismatch"), "{err}");

        let err = verified_binary(&full, name, fetch("abc  other\n".into())).unwrap_err();
        assert!(err.to_string().contains("missing from SHA256SUMS"), "{err}");

        let err = verified_binary(&release(&[name]), name, fetch(good_sums)).unwrap_err();
        assert!(err.to_string().contains("no asset SHA256SUMS"), "{err}");
    }
}
