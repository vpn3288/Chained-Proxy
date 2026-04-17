# Chained-Proxy 审计日志

## 2026-04-17

### Landing (R10 → R10_fixed)

| Round | Model | Key | Result |
|-------|-------|-----|--------|
| R1 | opus-20260130 | Key1 | 2 CRITICAL fixed (local rollback + trap ERR) |
| R2 | opus-4-7 | Key2 | CLEAN (2 false positives by model) |

**Fixed bugs**:
- `_fresh_install_rollback()` local→GLOBAL (was inside fresh_install())
- trap `ERR INT TERM`→`INT TERM`

**SHA256**: landing_R10_fixed.sh = TBD after push

### Transit (v3.35 → v3.35_fixed)

| Round | Model | Key | Result |
|-------|-------|-----|--------|
| R1 | opus-20260130 | Key1 | 4 rollback functions globalized |
| R2 | opus-4-7 | Key2 | CLEAN (verified all fixes) |

**Fixed bugs**:
- `_fw_transit_rollback()` local→GLOBAL (was inside _fw_transit_apply())
- `_route_rollback()` local→GLOBAL (was inside _atomic_apply_route())
- `_import_install_rollback()` local→GLOBAL (was inside import function)
- local duplicate `_fresh_install_rollback()` DELETED (global one kept)
- 7 rollback traps: ERR removed (INT TERM only)

**SHA256**: ca72a7a1915f9ebf1a3ceb2818deb57a40ee7ead793662dc04abe893fd195101

### Files pushed to GitHub
- `install_landing_v3.37-audit_R10_fixed.sh`
- `install_transit_v3.35-audit_fixed.sh`

---

## 历史
- R7→R10→R12→R13→R14→R15→R16→R17 (prior sessions)
- R12 first PERFECT result (never pushed to GitHub - PAIN-010)
- R17 last session (landing R14 damaged by heredoc - PAIN-009)
