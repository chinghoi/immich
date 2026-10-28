//! Process-local, no-TUN EasyTier adapter. Never changes system routes or DNS.
//! The Swift adapter serializes all FFI calls on a background executor.
use easytier::{
    common::config::{ConfigFileControl, ConfigLoader, TomlConfigLoader},
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
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .unwrap()
});
struct Instance {
    manager: NetworkInstanceManager,
    port: u16,
}
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
    #[serde(default = "default_tcp")]
    allow_p2p: bool,
}
fn default_tcp() -> bool {
    true
}
fn quoted(value: &str) -> String {
    serde_json::to_string(value).unwrap()
}

fn config(options: &Options, port: u16) -> Result<TomlConfigLoader, ()> {
    let peer = url::Url::parse(&options.peer).map_err(|_| ())?;
    if !matches!(peer.scheme(), "tcp" | "udp")
        || peer.host_str().is_none()
        || peer.port().is_none()
        || !peer.username().is_empty()
        || peer.password().is_some()
        || peer.query().is_some()
        || peer.fragment().is_some()
        || !matches!(peer.path(), "" | "/")
        || (options.tcp_only && peer.scheme() != "tcp")
        || options.network_name.is_empty()
        || options.network_secret.is_empty()
        || options.network_name.len() > 128
        || options.network_secret.len() > 1024
    {
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
        quoted(&options.instance_id),
        quoted(&format!("{ip}/24")),
        quoted(&format!("socks5://127.0.0.1:{port}")),
        quoted(&options.network_name),
        quoted(&options.network_secret),
        quoted(peer.as_str()),
        !options.allow_p2p,
        options.tcp_only || !options.allow_p2p,
        !options.allow_p2p,
    );
    let config = TomlConfigLoader::new_from_str(&text).map_err(|_| ())?;
    // Keep upstream STUN discovery: TCP punching needs address/NAT discovery too.
    Ok(config)
}
fn start(options: Options) -> Result<u16, ()> {
    let mut active = INSTANCE.lock().map_err(|_| ())?;
    if active.is_some() {
        return Err(());
    }
    let reservation = TcpListener::bind("127.0.0.1:0").map_err(|_| ())?;
    let port = reservation.local_addr().map_err(|_| ())?.port();
    let cfg = config(&options, port)?;
    let _entered = RUNTIME.enter();
    let manager = NetworkInstanceManager::new();
    drop(reservation); // core owns its listener; Swift verifies SOCKS readiness
    manager
        .run_network_instance(cfg, true, ConfigFileControl::STATIC_CONFIG)
        .map_err(|_| ())?;
    *active = Some(Instance { manager, port });
    Ok(port)
}
fn stop() -> Result<(), ()> {
    let mut active = INSTANCE.lock().map_err(|_| ())?;
    if let Some(instance) = active.take() {
        let _entered = RUNTIME.enter();
        instance
            .manager
            .delete_network_instance(instance.manager.list_network_instance_ids())
            .map_err(|_| ())?;
    }
    Ok(())
}
fn status(target: &str) -> Result<String, ()> {
    let active = INSTANCE.lock().map_err(|_| ())?;
    let Some(instance) = active.as_ref() else {
        return Ok(json!({"state":"Disabled","targetRoute":"Unlinked"}).to_string());
    };
    let infos = RUNTIME
        .block_on(instance.manager.collect_network_infos())
        .map_err(|_| ())?;
    let Some(info) = infos.values().next() else {
        return Ok(json!({"state":"Starting","targetRoute":"Connecting"}).to_string());
    };
    let route = info.routes.iter().find(|route| {
        route
            .ipv4_addr
            .as_ref()
            .and_then(|v| v.address.as_ref())
            .is_some_and(|v| Ipv4Addr::from(v.addr).to_string() == target)
    });
    let (path, protocol) = match route {
        Some(route) => {
            let hop = route.next_hop_peer_id;
            let protocol = info
                .peers
                .iter()
                .find(|p| p.peer_id == hop)
                .and_then(|p| p.conns.iter().find(|c| !c.is_closed))
                .and_then(|c| c.tunnel.as_ref())
                .map(|t| t.tunnel_type.as_str())
                .unwrap_or("");
            (if route.cost <= 1 { "Direct" } else { "Relay" }, protocol)
        }
        None => ("Unlinked", ""),
    };
    // Never export network secrets, peer lists, endpoint URLs, or raw errors.
    Ok(json!({"state": if info.error_msg.is_some() { "Unavailable" } else if info.running { "Running" } else { "Starting" },
        "targetRoute":path,"protocol":protocol,"port":instance.port,
        "connected": info.peers.iter().any(|peer| peer.conns.iter().any(|conn| !conn.is_closed))}).to_string())
}
unsafe fn argument<'a>(value: *const c_char) -> Result<&'a str, ()> {
    if value.is_null() {
        return Err(());
    }
    unsafe { CStr::from_ptr(value) }.to_str().map_err(|_| ())
}
/// Returns loopback SOCKS port, or -1. A port is not proof of network readiness.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn immich_et_start(options: *const c_char) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        let options: Options =
            serde_json::from_str(unsafe { argument(options)? }).map_err(|_| ())?;
        start(options).map(i32::from)
    }))
    .ok()
    .and_then(Result::ok)
    .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn immich_et_stop() -> i32 {
    if matches!(catch_unwind(AssertUnwindSafe(stop)), Ok(Ok(()))) {
        0
    } else {
        -1
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn immich_et_status(target: *const c_char) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        CString::new(status(unsafe { argument(target)? })?)
            .map(CString::into_raw)
            .map_err(|_| ())
    }))
    .ok()
    .and_then(Result::ok)
    .unwrap_or(std::ptr::null_mut())
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn immich_et_free(value: *mut c_char) {
    if !value.is_null() {
        unsafe {
            drop(CString::from_raw(value));
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn options() -> Options {
        Options {
            network_name: "test".into(),
            network_secret: "local-test-only".into(),
            peer: "tcp://127.0.0.1:11010".into(),
            ipv4: "10.77.23.2".into(),
            instance_id: "b60ee0cf-e733-4cdd-9937-26934bb81065".into(),
            tcp_only: true,
            allow_p2p: true,
        }
    }
    #[test]
    fn tcp_only_keeps_tcp_punching_and_discovery_enabled() {
        let o = options();
        let cfg = config(&o, 22222).unwrap();
        let flags = cfg.get_flags();
        assert!(!flags.disable_p2p);
        assert!(!flags.disable_tcp_hole_punching);
        assert!(flags.disable_udp_hole_punching);
        assert_ne!(cfg.get_stun_servers(), Some(Vec::new()));
        assert_ne!(cfg.get_stun_servers_v6(), Some(Vec::new()));
        let mut relay = options();
        relay.allow_p2p = false;
        let flags = config(&relay, 22222).unwrap().get_flags();
        assert!(
            flags.disable_p2p && flags.disable_tcp_hole_punching && flags.disable_udp_hole_punching
        );
        let mut automatic = options();
        automatic.tcp_only = false;
        let flags = config(&automatic, 22222).unwrap().get_flags();
        assert!(
            !flags.disable_p2p
                && !flags.disable_tcp_hole_punching
                && !flags.disable_udp_hole_punching
        );
        let mut legacy = serde_json::to_value(json!({
            "networkName": "test", "networkSecret": "local-test-only",
            "peer": "tcp://127.0.0.1:11010", "ipv4": "10.77.23.2",
            "instanceId": "b60ee0cf-e733-4cdd-9937-26934bb81065", "tcpOnly": true
        }))
        .unwrap();
        let migrated: Options = serde_json::from_value(legacy.take()).unwrap();
        assert!(migrated.allow_p2p);
    }
    #[test]
    fn validates_tcp_mode_and_config_boundaries() {
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
    #[test]
    fn tcp_direct_and_relay_transfer_http_range_and_survive_restart() {
        use std::{
            io::{Read, Write},
            net::TcpStream,
            thread,
            time::{Duration, Instant},
        };
        let http = TcpListener::bind("127.0.0.1:0").unwrap();
        let http_port = http.local_addr().unwrap().port();
        let fixture = thread::spawn(move || {
            // One Range request per path: direct TCP, then a two-hop TCP relay.
            for _ in 0..2 {
                let (mut socket, _) = http.accept().unwrap();
                socket
                    .set_read_timeout(Some(Duration::from_secs(10)))
                    .unwrap();
                let mut request = Vec::new();
                while !request.ends_with(b"\r\n\r\n") {
                    let mut byte = [0; 1];
                    socket.read_exact(&mut byte).unwrap();
                    request.push(byte[0]);
                }
                assert!(String::from_utf8_lossy(&request).contains("Range: bytes=4096-12287"));
                let body: Vec<u8> = (4096..12288).map(|n| (n % 251) as u8).collect();
                socket.write_all(b"HTTP/1.1 206 Partial Content\r\nContent-Length: 8192\r\nContent-Range: bytes 4096-12287/1048576\r\nConnection: close\r\n\r\n").unwrap();
                socket.write_all(&body).unwrap();
            }
        });
        let tcp = TcpListener::bind("127.0.0.1:0").unwrap();
        let peer_port = tcp.local_addr().unwrap().port();
        drop(tcp);
        let text = format!(
            "ipv4 = '10.77.23.1/24'\nlisteners = ['tcp://127.0.0.1:{peer_port}']\n[network_identity]\nnetwork_name = 'test'\nnetwork_secret = 'local-test-only'\n[flags]\nno_tun = true\nuse_smoltcp = true\nbind_device = false\ndisable_upnp = true\ndisable_p2p = true\n"
        );
        let server = NetworkInstanceManager::new();
        {
            let _entered = RUNTIME.enter();
            server
                .run_network_instance(
                    TomlConfigLoader::new_from_str(&text).unwrap(),
                    true,
                    ConfigFileControl::STATIC_CONFIG,
                )
                .unwrap();
        }
        let relay_socket = TcpListener::bind("127.0.0.1:0").unwrap();
        let relay_port = relay_socket.local_addr().unwrap().port();
        drop(relay_socket);
        let relay_text = format!(
            "ipv4 = '10.77.23.254/24'\nlisteners = ['tcp://127.0.0.1:{relay_port}']\n[network_identity]\nnetwork_name = 'test'\nnetwork_secret = 'local-test-only'\n[[peer]]\nuri = 'tcp://127.0.0.1:{peer_port}'\n[flags]\nno_tun = true\nuse_smoltcp = true\nbind_device = false\ndisable_upnp = true\ndisable_p2p = true\n"
        );
        let relay = NetworkInstanceManager::new();
        {
            let _entered = RUNTIME.enter();
            relay
                .run_network_instance(
                    TomlConfigLoader::new_from_str(&relay_text).unwrap(),
                    true,
                    ConfigFileControl::STATIC_CONFIG,
                )
                .unwrap();
        }
        for (path_port, expected_route) in [(peer_port, "Direct"), (relay_port, "Relay")] {
            let mut opts = options();
            opts.peer = format!("tcp://127.0.0.1:{path_port}");
            let port = start(opts).unwrap();
            let deadline = Instant::now() + Duration::from_secs(30);
            loop {
                if serde_json::from_str::<serde_json::Value>(&status("10.77.23.1").unwrap())
                    .unwrap()["targetRoute"]
                    == expected_route
                {
                    break;
                }
                assert!(
                    Instant::now() < deadline,
                    "TCP peer did not become routable"
                );
                thread::sleep(Duration::from_millis(100));
            }
            let mut stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
            stream
                .set_read_timeout(Some(Duration::from_secs(15)))
                .unwrap();
            stream.write_all(&[5, 1, 0]).unwrap();
            let mut greeting = [0; 2];
            stream.read_exact(&mut greeting).unwrap();
            assert_eq!(greeting, [5, 0]);
            let mut request = vec![5, 1, 0, 1, 10, 77, 23, 1];
            request.extend_from_slice(&http_port.to_be_bytes());
            stream.write_all(&request).unwrap();
            let mut response = [0; 10];
            stream.read_exact(&mut response).unwrap();
            assert_eq!(response[1], 0, "SOCKS connect failed");
            stream
                .write_all(
                    b"GET /video HTTP/1.1\r\nHost: fixture\r\nRange: bytes=4096-12287\r\n\r\n",
                )
                .unwrap();
            let mut received = Vec::new();
            stream.read_to_end(&mut received).unwrap();
            let headers = received.windows(4).position(|w| w == b"\r\n\r\n").unwrap() + 4;
            assert!(received.starts_with(b"HTTP/1.1 206"));
            assert_eq!(
                &received[headers..],
                (4096..12288).map(|n| (n % 251) as u8).collect::<Vec<_>>()
            );
            drop(stream);
            stop().unwrap();
            assert!(status("").unwrap().contains("Disabled"));
        }
        {
            let _entered = RUNTIME.enter();
            relay
                .delete_network_instance(relay.list_network_instance_ids())
                .unwrap();
            server
                .delete_network_instance(server.list_network_instance_ids())
                .unwrap();
        }
        fixture.join().unwrap();
    }
    #[test]
    fn ffi_handles_invalid_input_without_unwinding() {
        unsafe {
            assert_eq!(immich_et_start(std::ptr::null()), -1);
            let invalid = CString::new("{}").unwrap();
            assert_eq!(immich_et_start(invalid.as_ptr()), -1);
        }
    }
}
