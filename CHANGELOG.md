# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [v5.17] - 2026-04-30

### 🔴 Security
- **CRITICAL**: Fixed 5 `rm -rf` vulnerabilities by adding `${VAR:?}` parameter expansion protection
  - Prevents accidental root directory deletion if variables are empty
  - Affected lines: 2437, 2641, 3612, 3620, 3644 in `install_landing_v5.17.sh`
  - Discovered by ShellCheck static analysis (SC2115)

### 🐛 Bug Fixes
- **BUG #38**: Fixed Nginx log file permission issue
  - Changed log file owner from `root:root` to `www-data:adm`
  - Changed logrotate `su` directive from `root root` to `www-data adm`
  - Prevents "Read-only file system" error when Nginx worker tries to write logs
  - Commit: `5f9be2a`

- **BUG #37**: Fixed awk syntax error in transit script
  - Changed `substr(\,1,64)` to `substr($1,1,64)` at line 319
  - Fixes "backslash not last character on line" error
  - Commit: `59a42c3`

- **BUG #36**: Enhanced interactive input validation with retry loops
  - All user inputs now support error retry instead of immediate exit
  - Improved user experience for typos and format errors
  - Commit: `7a61d92`

### ✅ Testing
- Complete landing server installation test passed (5 protocol nodes)
- Transit server SNI routing test passed
- End-to-end TLS handshake verification passed
- Certificate issuance and validation passed

### 📝 Documentation
- Completely rewrote README.md with modern formatting
- Added comprehensive troubleshooting guide
- Added FAQ section with collapsible details
- Reorganized repository structure (archive/ and docs/ directories)

### 🔧 Commits
- `d3a6349` - security: Fix 5 rm -rf vulnerabilities
- `5f9be2a` - fix(transit): BUG #38 - Nginx log permission
- `59a42c3` - fix(v5.17): BUG #37 - awk syntax error
- `7a61d92` - fix(v5.17): BUG #36 - input validation retry

---

## [v5.12] - 2026-04-29

### 🐛 Bug Fixes

#### Transit Server (中转机)
- **CRITICAL**: Fixed IFS restoration using `local` instead of `trap` (automatic scope recovery)
- **HIGH**: Firewall whitelist rules now use `-I 1` (insert) instead of `-A` (append)
- **HIGH**: Route conflict detection uses command substitution instead of process substitution (fixes variable loss)
- **MEDIUM**: Port conflict detection now validates process name (avoids false positives)
- **MEDIUM**: Metadata drift detection validates .map content matches .meta

#### Landing Server (落地机)
- **CRITICAL**: `gen_password()` uses `head -c` instead of `dd` (avoids pipefail crash)
- **CRITICAL**: DNS TXT record format validation (distinguishes NXDOMAIN from propagation)
- **CRITICAL**: Certificate delay Ctrl+C trap registered before sleep
- **HIGH**: Certificate reload script checks fullchain.pem is non-empty (prevents silent renewal failure)
- **HIGH**: IPv6 firewall adds NDP rules (ICMPv6 types 133-136)
- **HIGH**: TRANSIT_IP format validation

---

## [v5.11] - 2026-04-29

### 🐛 Bug Fixes
- Fixed all critical issues from code audit report
- IFS restoration improvements
- DNS propagation detection enhancements
- Certificate reload script hardening

---

## [v5.10] - 2026-04-29

### 🐛 Bug Fixes
- Fixed 26 issues from comprehensive audit report
- Uninstall completeness improvements
- IPv6 firewall fixes
- IP validation optimization
- Nginx configuration security enhancements

---

## [v5.00] - 2026-04-29

### 🎉 Initial Stable Release
- Architecture stabilization based on v4.90
- Firewall restore script fixes
- Whitelist rule ordering fixes
- Uninstall completeness improvements

### ✨ Features
- **Transit Server**: Nginx stream SNI blind forwarding
- **Landing Server**: Xray-core with 5 protocol nodes
  - Trojan-TCP-TLS
  - VLESS-TCP-XTLS-Vision
  - VLESS-gRPC-TLS
  - Trojan-gRPC-TLS
  - VLESS-WebSocket-TLS
- **Anti-Detection**: TCP window randomization, uTLS fingerprint randomization
- **Stability**: Health checks, auto-restart, certificate auto-renewal
- **Security**: Firewall hardening, IPv6 blocking, minimal privileges

---

## Legend

- 🔴 **Security**: Security vulnerabilities and fixes
- 🐛 **Bug Fixes**: Bug fixes
- ✨ **Features**: New features
- ✅ **Testing**: Test coverage and validation
- 📝 **Documentation**: Documentation updates
- 🔧 **Commits**: Git commit references

---

[v5.17]: https://github.com/vpn3288/Chained-Proxy/compare/v5.12...v5.17
[v5.12]: https://github.com/vpn3288/Chained-Proxy/compare/v5.11...v5.12
[v5.11]: https://github.com/vpn3288/Chained-Proxy/compare/v5.10...v5.11
[v5.10]: https://github.com/vpn3288/Chained-Proxy/compare/v5.00...v5.10
[v5.00]: https://github.com/vpn3288/Chained-Proxy/releases/tag/v5.00
