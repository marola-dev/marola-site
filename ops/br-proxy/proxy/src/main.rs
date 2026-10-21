//! The pool node's proxy (#171): an allowlist-only HTTP forward proxy, std only.
//! CONNECT to port 443 and plain HTTP to port 80 for the hosts in the allowlist file; all else is refused.
use std::collections::{HashMap, HashSet};
use std::io::{self, Read, Write};
use std::net::{Shutdown, SocketAddr, TcpListener, TcpStream, ToSocketAddrs};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

const MAX_HEAD: usize = 16 * 1024;
// Hop-by-hop headers, and Host (rewritten from the URL so it cannot disagree with where we connect).
const DROPPED: [&str; 5] = [
    "proxy-connection",
    "proxy-authorization",
    "connection",
    "keep-alive",
    "host",
];

pub struct Config {
    pub allow: HashSet<String>,
    pub max_clients: usize,
    pub timeout: Duration,
    /// Tests only: where a host really connects, so they never touch DNS.
    pub connect: HashMap<String, SocketAddr>,
}

enum Plan {
    Tunnel {
        host: String,
        port: u16,
    },
    Forward {
        host: String,
        port: u16,
        head: String,
    },
}

/// One host per line; `#` comments and blank lines ignored.
pub fn parse_hosts(text: &str) -> HashSet<String> {
    text.lines()
        .map(|l| l.split('#').next().unwrap_or("").trim())
        .filter(|l| !l.is_empty())
        .map(normalize)
        .collect()
}

fn normalize(host: &str) -> String {
    host.strip_suffix('.').unwrap_or(host).to_ascii_lowercase()
}

/// `host[:port]` -> (normalized host, port); `default` when no port is given.
fn host_port(authority: &str, default: u16) -> Option<(String, u16)> {
    let (host, port) = match authority.rsplit_once(':') {
        Some((h, p)) => (h, p.parse().ok()?),
        None => (authority, default),
    };
    (!host.is_empty()).then(|| (normalize(host), port))
}

fn clean(s: &str) -> String {
    s.chars().filter(char::is_ascii_graphic).take(100).collect()
}

fn plan(head: &str, allow: &HashSet<String>) -> (String, Result<Plan, u16>) {
    let mut lines = head.split("\r\n");
    let parts: Vec<&str> = lines.next().unwrap_or("").split(' ').collect();
    let [method, target, version] = parts[..] else {
        return ("- -".into(), Err(400));
    };
    if !version.starts_with("HTTP/1.") || method.is_empty() || target.is_empty() {
        return ("- -".into(), Err(400));
    }
    let headers: Vec<&str> = lines.collect();
    if headers.iter().any(|h| !h.contains(':')) {
        return ("- -".into(), Err(400));
    }
    let scheme = |s: &str| {
        target
            .get(..s.len())
            .is_some_and(|p| p.eq_ignore_ascii_case(s))
    };
    let (authority, default) = if method == "CONNECT" {
        (target, 0)
    } else if scheme("http://") {
        let rest = &target[7..];
        (&rest[..rest.find(['/', '?']).unwrap_or(rest.len())], 80)
    } else {
        // https:// in absolute form, or origin-form: this is not a general proxy.
        return (format!("{} -", clean(method)), Err(403));
    };
    let Some((host, port)) = host_port(authority, default) else {
        return ("- -".into(), Err(400));
    };
    let label = format!("{} {}:{}", clean(method), clean(&host), port);
    let want = if method == "CONNECT" { 443 } else { 80 };
    if port != want || !allow.contains(&host) {
        return (label, Err(403));
    }
    if method == "CONNECT" {
        return (label, Ok(Plan::Tunnel { host, port }));
    }
    let rest = &target[7 + authority.len()..];
    let path = if rest.starts_with('/') {
        rest.to_string()
    } else {
        format!("/{rest}")
    };
    let mut out = format!("{method} {path} {version}\r\nHost: {authority}\r\n");
    for h in headers {
        let name = h
            .split(':')
            .next()
            .unwrap_or("")
            .trim()
            .to_ascii_lowercase();
        if !DROPPED.contains(&name.as_str()) {
            out.push_str(h);
            out.push_str("\r\n");
        }
    }
    out.push_str("Connection: close\r\n\r\n");
    (
        label,
        Ok(Plan::Forward {
            host,
            port,
            head: out,
        }),
    )
}

/// The request head (up to the blank line) and any bytes read past it.
fn read_head(s: &mut TcpStream) -> Result<(String, Vec<u8>), u16> {
    let mut buf = Vec::new();
    let mut chunk = [0u8; 4096];
    loop {
        if let Some(i) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
            if i > MAX_HEAD {
                return Err(400);
            }
            let head = String::from_utf8(buf[..i].to_vec()).map_err(|_| 400u16)?;
            return Ok((head, buf[i + 4..].to_vec()));
        }
        if buf.len() > MAX_HEAD {
            return Err(400);
        }
        match s.read(&mut chunk) {
            Ok(0) | Err(_) => return Err(400),
            Ok(n) => buf.extend_from_slice(&chunk[..n]),
        }
    }
}

fn reply(s: &mut TcpStream, code: u16) {
    let reason = match code {
        200 => "Connection Established",
        400 => "Bad Request",
        403 => "Forbidden",
        502 => "Bad Gateway",
        _ => "Service Unavailable",
    };
    let body = if code == 200 {
        "\r\n"
    } else {
        "Connection: close\r\nContent-Length: 0\r\n\r\n"
    };
    let _ = s.write_all(format!("HTTP/1.1 {code} {reason}\r\n{body}").as_bytes());
}

fn connect(cfg: &Config, host: &str, port: u16) -> io::Result<TcpStream> {
    let addr = match cfg.connect.get(host) {
        Some(a) => *a,
        None => (host, port)
            .to_socket_addrs()?
            .next()
            .ok_or(io::ErrorKind::NotFound)?,
    };
    let s = TcpStream::connect_timeout(&addr, cfg.timeout)?;
    s.set_read_timeout(Some(cfg.timeout))?;
    s.set_write_timeout(Some(cfg.timeout))?;
    Ok(s)
}

/// Both directions until each side is done; the timeouts on the sockets end an idle tunnel.
fn splice(a: TcpStream, b: TcpStream) -> io::Result<()> {
    let (mut a_in, mut b_out) = (a.try_clone()?, b.try_clone()?);
    let t = thread::spawn(move || {
        let _ = io::copy(&mut a_in, &mut b_out);
        let _ = b_out.shutdown(Shutdown::Write);
    });
    let _ = io::copy(&mut &b, &mut &a);
    let _ = a.shutdown(Shutdown::Write);
    let _ = t.join();
    Ok(())
}

fn handle(mut client: TcpStream, cfg: &Config) {
    let _ = client.set_read_timeout(Some(cfg.timeout));
    let _ = client.set_write_timeout(Some(cfg.timeout));
    let (head, rest) = match read_head(&mut client) {
        Ok(h) => h,
        Err(code) => return refuse("- -", code, &mut client),
    };
    let (label, planned) = plan(&head, &cfg.allow);
    let planned = match planned {
        Ok(p) => p,
        Err(code) => return refuse(&label, code, &mut client),
    };
    let (host, port) = match &planned {
        Plan::Tunnel { host, port } | Plan::Forward { host, port, .. } => (host, *port),
    };
    let Ok(mut up) = connect(cfg, host, port) else {
        return refuse(&label, 502, &mut client);
    };
    let sent = match &planned {
        Plan::Tunnel { .. } => {
            println!("{label} 200");
            client.write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        }
        Plan::Forward { head, .. } => {
            println!("{label} forward");
            up.write_all(head.as_bytes())
        }
    };
    if sent.and_then(|_| up.write_all(&rest)).is_ok() {
        let _ = splice(client, up);
    }
}

fn refuse(label: &str, code: u16, client: &mut TcpStream) {
    println!("{label} {code}");
    reply(client, code);
}

struct Slot(Arc<AtomicUsize>);
impl Drop for Slot {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::SeqCst);
    }
}

pub fn serve(listener: TcpListener, cfg: Arc<Config>) {
    let active = Arc::new(AtomicUsize::new(0));
    for mut conn in listener.incoming().flatten() {
        let slot = Slot(active.clone());
        if active.fetch_add(1, Ordering::SeqCst) >= cfg.max_clients {
            let _ = conn.set_write_timeout(Some(cfg.timeout));
            refuse("- -", 503, &mut conn);
            continue;
        }
        let cfg = cfg.clone();
        thread::spawn(move || {
            let _slot = slot;
            handle(conn, &cfg);
        });
    }
}

/// `--flag value`, else the env var, else the default.
fn opt(args: &[String], flag: &str, env: &str, default: &str) -> String {
    args.iter()
        .position(|a| a == flag)
        .and_then(|i| args.get(i + 1).cloned())
        .or_else(|| std::env::var(env).ok())
        .unwrap_or_else(|| default.to_string())
}

fn die(msg: String) -> ! {
    eprintln!("br-proxy: {msg}");
    std::process::exit(2)
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let listen = opt(&args, "--listen", "BR_PROXY_LISTEN", "127.0.0.1:8888");
    let hosts = opt(&args, "--hosts", "BR_PROXY_HOSTS", "/etc/br-proxy/hosts");
    let max = opt(&args, "--max-clients", "BR_PROXY_MAX_CLIENTS", "20");
    let secs = opt(&args, "--timeout", "BR_PROXY_TIMEOUT", "60");
    let allow = parse_hosts(
        &std::fs::read_to_string(&hosts).unwrap_or_else(|e| die(format!("{hosts}: {e}"))),
    );
    if allow.is_empty() {
        die(format!(
            "{hosts}: no hosts, the proxy would refuse everything"
        ));
    }
    let cfg = Config {
        allow,
        max_clients: max
            .parse()
            .unwrap_or_else(|_| die(format!("bad --max-clients {max}"))),
        timeout: Duration::from_secs(
            secs.parse()
                .unwrap_or_else(|_| die(format!("bad --timeout {secs}"))),
        ),
        connect: HashMap::new(),
    };
    let listener = TcpListener::bind(&listen).unwrap_or_else(|e| die(format!("{listen}: {e}")));
    println!("listening on {listen}, {} hosts allowed", cfg.allow.len());
    serve(listener, Arc::new(cfg));
}

#[cfg(test)]
mod tests {
    use super::*;

    fn allow() -> HashSet<String> {
        parse_hosts("# c\n\nAllowed.Test.  # trailing\nother.test\n")
    }

    fn start(max_clients: usize, upstream: Option<SocketAddr>) -> SocketAddr {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = l.local_addr().unwrap();
        let connect = upstream
            .map(|a| ("allowed.test".to_string(), a))
            .into_iter()
            .collect();
        let cfg = Config {
            allow: allow(),
            max_clients,
            timeout: Duration::from_secs(5),
            connect,
        };
        thread::spawn(move || serve(l, Arc::new(cfg)));
        addr
    }

    fn ask(proxy: SocketAddr, raw: &[u8]) -> String {
        let mut s = TcpStream::connect(proxy).unwrap();
        let _ = s.write_all(raw);
        let mut out = String::new();
        let _ = s.read_to_string(&mut out);
        out
    }

    fn status(resp: &str) -> &str {
        resp.split(' ').nth(1).unwrap_or("")
    }

    #[test]
    fn allowlist_ignores_comments_case_and_trailing_dot() {
        let a = allow();
        assert_eq!(a.len(), 2);
        assert!(a.contains("allowed.test") && a.contains("other.test"));
    }

    #[test]
    fn host_and_port_parsing() {
        assert_eq!(
            host_port("Example.COM.:443", 0),
            Some(("example.com".into(), 443))
        );
        assert_eq!(
            host_port("example.com", 80),
            Some(("example.com".into(), 80))
        );
        assert_eq!(host_port("example.com:x", 80), None);
        assert_eq!(host_port(":80", 80), None);
    }

    #[test]
    fn request_line_parsing() {
        let p = |h: &str| plan(h, &allow()).1;
        assert!(matches!(
            p("CONNECT ALLOWED.test.:443 HTTP/1.1\r\nHost: x:443"),
            Ok(Plan::Tunnel { .. })
        ));
        assert!(matches!(
            p("GET http://allowed.test/a HTTP/1.1\r\nHost: x"),
            Ok(Plan::Forward { .. })
        ));
        assert_eq!(p("GET http://example.com/ HTTP/1.1").err(), Some(403));
        assert_eq!(p("GET /path HTTP/1.1").err(), Some(403));
        assert_eq!(
            p("GET http://allowed.test@evil.test/ HTTP/1.1").err(),
            Some(403)
        );
        assert_eq!(p("GET http://allowed.test:8080/ HTTP/1.1").err(), Some(403));
        assert_eq!(
            p("GET http://allowed.test/ HTTP/1.1\r\nno colon").err(),
            Some(400)
        );
        assert_eq!(p("garbage").err(), Some(400));
    }

    #[test]
    fn refusals() {
        let proxy = start(5, None);
        let cases: [(&[u8], &str); 8] = [
            (b"GET http://example.com/ HTTP/1.1\r\n\r\n", "403"),
            (b"CONNECT example.com:443 HTTP/1.1\r\n\r\n", "403"),
            (b"CONNECT allowed.test:8443 HTTP/1.1\r\n\r\n", "403"),
            (b"CONNECT 93.184.216.34:443 HTTP/1.1\r\n\r\n", "403"),
            (b"GET http://93.184.216.34/ HTTP/1.1\r\n\r\n", "403"),
            (b"GET https://allowed.test/ HTTP/1.1\r\n\r\n", "403"),
            (b"GET /x HTTP/1.1\r\nHost: allowed.test\r\n\r\n", "403"),
            (b"garbage\r\n\r\n", "400"),
        ];
        for (raw, want) in cases {
            let r = ask(proxy, raw);
            assert_eq!(status(&r), want, "{}", String::from_utf8_lossy(raw));
        }
    }

    #[test]
    fn oversized_head_is_400() {
        let proxy = start(5, None);
        let big = format!(
            "GET http://allowed.test/ HTTP/1.1\r\nX: {}\r\n\r\n",
            "a".repeat(MAX_HEAD + 1)
        );
        assert_eq!(status(&ask(proxy, big.as_bytes())), "400");
    }

    #[test]
    fn over_the_client_limit_is_503() {
        let proxy = start(0, None);
        assert_eq!(
            status(&ask(proxy, b"CONNECT allowed.test:443 HTTP/1.1\r\n\r\n")),
            "503"
        );
    }

    #[test]
    fn connect_tunnel_echoes() {
        let up = TcpListener::bind("127.0.0.1:0").unwrap();
        let proxy = start(5, Some(up.local_addr().unwrap()));
        thread::spawn(move || {
            let (s, _) = up.accept().unwrap();
            let _ = io::copy(&mut &s, &mut &s);
        });
        let mut c = TcpStream::connect(proxy).unwrap();
        c.write_all(b"CONNECT allowed.test:443 HTTP/1.1\r\nHost: allowed.test:443\r\n\r\n")
            .unwrap();
        let mut head = [0u8; 39];
        c.read_exact(&mut head).unwrap();
        assert_eq!(&head, b"HTTP/1.1 200 Connection Established\r\n\r\n");
        c.write_all(b"hello").unwrap();
        let mut echo = [0u8; 5];
        c.read_exact(&mut echo).unwrap();
        assert_eq!(&echo, b"hello");
    }

    #[test]
    fn plain_http_is_forwarded_in_origin_form() {
        let up = TcpListener::bind("127.0.0.1:0").unwrap();
        let proxy = start(5, Some(up.local_addr().unwrap()));
        let (tx, rx) = std::sync::mpsc::channel();
        thread::spawn(move || {
            let (mut s, _) = up.accept().unwrap();
            let mut seen = Vec::new();
            let mut b = [0u8; 1024];
            while !seen.windows(4).any(|w| w == b"\r\n\r\n") {
                let n = s.read(&mut b).unwrap();
                seen.extend_from_slice(&b[..n]);
            }
            tx.send(String::from_utf8(seen).unwrap()).unwrap();
            s.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
                .unwrap();
        });
        let resp = ask(
            proxy,
            b"GET http://allowed.test/x?y=1 HTTP/1.1\r\nHost: other\r\nProxy-Connection: keep-alive\r\n\
              Proxy-Authorization: Basic eA==\r\nConnection: keep-alive\r\nKeep-Alive: 5\r\nX-Keep: 1\r\n\r\n",
        );
        assert!(resp.ends_with("\r\n\r\nok"), "{resp}");
        let seen = rx.recv().unwrap();
        assert!(
            seen.starts_with("GET /x?y=1 HTTP/1.1\r\nHost: allowed.test\r\n"),
            "{seen}"
        );
        assert!(
            seen.contains("X-Keep: 1\r\n") && seen.ends_with("Connection: close\r\n\r\n"),
            "{seen}"
        );
        let lower = seen.to_ascii_lowercase();
        assert!(
            !lower.contains("proxy-")
                && !lower.contains("keep-alive")
                && !lower.contains("host: other"),
            "{seen}"
        );
    }
}
