use std::time::Duration;

use ureq::Agent;

pub const USER_AGENT: &str = concat!("gnostr-dev/", env!("CARGO_PKG_VERSION"));

pub fn agent(timeout: Duration) -> Agent {
    Agent::config_builder()
        .timeout_global(Some(timeout))
        .user_agent(USER_AGENT)
        .build()
        .into()
}
