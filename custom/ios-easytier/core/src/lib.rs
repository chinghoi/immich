//! Process-local, no-TUN EasyTier adapter. Never changes system routes or DNS.
//! The Swift adapter serializes all FFI calls on a background executor.
use easytier::{
    common::config::{ConfigFileControl, TomlConfigLoader},
    instance_manager::NetworkInstanceManager,
};
use serde::Deserialize;
use serde_json::json;
use std::{
    ffi::{CStr, CString, c_char},
    net::{Ipv4Addr, TcpListener},
    panic::{AssertUnwindSafe, catch_unwind},
    sync::{LazyLock, Mutex},
};
use tokio::runtime::Runtime;

static RUNTIME: LazyLock<Runtime> = LazyLock::new(|| {
    tokio::runtime::Builder::new_multi_thread().worker_threads(2).enable_all().build().unwrap()
});
struct Instance { manager: NetworkInstanceManager, port: u16 }
static INSTANCE: Mutex<Option<Instance>> = Mutex::new(None);

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Options {
    network_name: String,
    network_secret: String,
    peer: String,
    ipv4: String,
    instance_id: String,
    #[serde(default = "default_tcp")]
    tcp_only: bool,
}
fn default_tcp() -> bool { true }
fn quoted(value: &str) -> String { serde_json::to_string(value).unwrap() }

fn config(options: &Options, port: u16) -> Result<TomlConfigLoader, ()> {
    let peer = url::Url::parse(&options.peer).map_err(|_| ())?;
    if !matches!(peer.scheme(), "tcp" | "udp") || peer.host_str().is_none() ||
       peer.port().is_none() || !peer.username().is_empty() || peer.password().is_some() ||
       peer.query().is_some() || peer.fragment().is_some() || !matches!(peer.path(), "" | "/") ||
       (options.tcp_only && peer.scheme() != "tcp") ||
       options.network_name.is_empty() || options.network_secret.is_empty() ||
       options.network_name.len() > 128 || options.network_secret.len() > 1024 {
        return Err(());
    }
    let ip: Ipv4Addr = options.ipv4.parse().map_err(|_| ())?;
    if ip.is_unspecified() || ip.is_loopback() || ip.is_multicast() || ip.is_broadcast() {
        return Err(());
    }
    // JSON string quoting is valid for these TOML basic strings. No raw config
    // from Flutter can enable TUN, wildcard listeners, RPC, or plaintext tunnels.
    let text = format!(
        "instance_name = 'immich-ios'\ninstance_id = {}\nhostname = 'immich-ios'\nipv4 = {}\nlisteners = []\nsocks5_proxy = {}\n[network_identity]\nnetwork_name = {}\nnetwork_secret = {}\n[[peer]]\nuri = {}\n[flags]\nno_tun = true\nuse_smoltcp = true\nbind_device = false\ndefault_protocol = 'tcp'\nenable_encryption = true\ndisable_p2p = {}\ndisable_udp_hole_punching = {}\ndisable_tcp_hole_punching = {}\ndisable_upnp = true\naccept_dns = false\n",
        quoted(&options.instance_id), quoted(&format!("{ip}/24")),
        quoted(&format!("socks5://127.0.0.1:{port}")),
        quoted(&options.network_name), quoted(&options.network_secret), quoted(peer.as_str()),
        options.tcp_only, options.tcp_only, options.tcp_only,
    );
    TomlConfigLoader::new_from_str(&text).map_err(|_| ())
}
fn start(options: Options) -> Result<u16, ()> {
    let mut active = INSTANCE.lock().map_err(|_| ())?;
    if active.is_some() { return Err(()); }
    let reservation = TcpListener::bind("127.0.0.1:0").map_err(|_| ())?;
    let port = reservation.local_addr().map_err(|_| ())?.port();
    let cfg = config(&options, port)?;
    let _entered = RUNTIME.enter();
    let manager = NetworkInstanceManager::new();
    drop(reservation); // core owns its listener; Swift verifies SOCKS readiness
    manager.run_network_instance(cfg, true, ConfigFileControl::STATIC_CONFIG).map_err(|_| ())?;
    *active = Some(Instance { manager, port });
    Ok(port)
}
fn stop() -> Result<(), ()> {
    let mut active = INSTANCE.lock().map_err(|_| ())?;
    if let Some(instance) = active.take() {
        let _entered = RUNTIME.enter();
        instance.manager.delete_network_instance(instance.manager.list_network_instance_ids()).map_err(|_| ())?;
    }
    Ok(())
}
fn status(target: &str) -> Result<String, ()> {
    let active = INSTANCE.lock().map_err(|_| ())?;
    let Some(instance) = active.as_ref() else {
        return Ok(json!({"state":"Disabled","targetRoute":"Unlinked"}).to_string());
    };
    let infos = RUNTIME.block_on(instance.manager.collect_network_infos()).map_err(|_| ())?;
    let Some(info) = infos.values().next() else {
        return Ok(json!({"state":"Starting","targetRoute":"Connecting"}).to_string());
    };
    let route = info.routes.iter().find(|route| {
        route.ipv4_addr.as_ref().and_then(|v| v.address.as_ref())
            .is_some_and(|v| Ipv4Addr::from(v.addr).to_string() == target)
    });
    let (path, protocol) = match route {
        Some(route) => {
            let hop = route.next_hop_peer_id;
            let protocol = info.peers.iter().find(|p| p.peer_id == hop)
                .and_then(|p| p.conns.iter().find(|c| !c.is_closed))
                .and_then(|c| c.tunnel.as_ref()).map(|t| t.tunnel_type.as_str()).unwrap_or("");
            (if route.cost <= 1 { "Direct" } else { "Relay" }, protocol)
        }
        None => ("Unlinked", ""),
    };
    // Never export network secrets, peer lists, endpoint URLs, or raw errors.
    Ok(json!({"state": if info.error_msg.is_some() { "Unavailable" } else if info.running { "Running" } else { "Starting" },
        "targetRoute":path,"protocol":protocol,"port":instance.port}).to_string())
}
unsafe fn argument<'a>(value: *const c_char) -> Result<&'a str, ()> {
    if value.is_null() { return Err(()); }
    unsafe { CStr::from_ptr(value) }.to_str().map_err(|_| ())
}
/// Returns loopback SOCKS port, or -1. A port is not proof of network readiness.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn immich_et_start(options: *const c_char) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        let options: Options = serde_json::from_str(unsafe { argument(options)? }).map_err(|_| ())?;
        start(options).map(i32::from)
    })).ok().and_then(Result::ok).unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn immich_et_stop() -> i32 {
    if matches!(catch_unwind(AssertUnwindSafe(stop)), Ok(Ok(()))) { 0 } else { -1 }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn immich_et_status(target: *const c_char) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        CString::new(status(unsafe { argument(target)? })?).map(CString::into_raw).map_err(|_| ())
    })).ok().and_then(Result::ok).unwrap_or(std::ptr::null_mut())
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn immich_et_free(value: *mut c_char) {
    if !value.is_null() { unsafe { drop(CString::from_raw(value)); } }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn options() -> Options { Options {
        network_name: "test".into(), network_secret: "local-test-only".into(),
        peer: "tcp://127.0.0.1:11010".into(), ipv4: "10.77.23.2".into(),
        instance_id: "b60ee0cf-e733-4cdd-9937-26934bb81065".into(), tcp_only: true,
    }}
    #[test] fn validates_tcp_mode_and_config_boundaries() {
        assert!(config(&options(), 22222).is_ok());
        let mut o = options();
        o.peer = "udp://127.0.0.1:11010".into();
        assert!(config(&o, 22222).is_err());
        o.tcp_only = false;
        assert!(config(&o, 22222).is_ok());
        o.network_name = "quoted \"name\"\n[flags]\nno_tun=false".into();
        assert!(config(&o, 22222).is_ok()); // remains a string, never TOML syntax
        o.ipv4 = "127.0.0.1".into();
        assert!(config(&o, 22222).is_err());
    }
    #[test] fn ffi_handles_invalid_input_without_unwinding() {
        unsafe {
            assert_eq!(immich_et_start(std::ptr::null()), -1);
            let invalid = CString::new("{}").unwrap();
            assert_eq!(immich_et_start(invalid.as_ptr()), -1);
        }
    }
}
