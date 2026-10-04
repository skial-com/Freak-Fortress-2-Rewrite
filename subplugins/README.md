# Freak server subplugins

Sources for the third-party boss subplugins on the freak server. FF2R loads every plugin in `plugins/disabled/` while a boss is in play, so this folder only holds subplugins that a boss in `characters.cfg` (or its companion) uses. `ff2r_*` plugins use the FF2R API; the rest use the legacy FF2 1.x API through FF2R's compatibility layer.

Each source was first committed as the original and checked against the prod binary: built with the same compiler and diffed opcode by opcode. The SP2 ports and fixes came after.

| Plugin | Used by | Source | Verified against prod binary |
|---|---|---|---|
| `ff2_blockdropitem` | painiscupcake, v1 | Batfoxkid/FF2-Library @ 9588914 | opcode-identical, SM 1.12.0.7043 |
| `ff2_death` 1.7 | therock | Batfoxkid/FF2-Library @ 359011c | opcode-identical, SM 1.12.0.7043 |
| `ff2_dispenserrage` | pig | AlliedModders attachment 2721880 (LeAlex14) | opcode-identical, SM 1.12.0.7043 |
| `ff2_dynamic_defaults` 1.3.2 | buzzlightyear, onepunch, v1 | Batfoxkid/FF2-Library @ 359011c | opcode-identical, SM 1.12.0.7043 |
| `ff2r_special_zombie` | employee | J0BL3SS/FF2Subplugins @ 5375339 | opcode-identical, SM 1.12.0.7146 |
| `ff2r_tfcond` | 13 bosses | AlliedModders attachment 2810747 (J0BL3SS) | opcode-identical, SM 1.12.0.7043 |
| `ffsamu_airdash` | v1 | AlliedModders attachment 2779951 (Samuwu) | opcode-identical, SM 1.12.0.7043 |
| `halloween_2013` | doom, predator | Plum-Sandbag/Tf2_plugins | opcode-identical, SM 1.12.0.7043 |
| `m7_abilities_extended` | pig | Batfoxkid/FF2-Library @ eac05d5 (pre-AMS2) | opcode-identical, SM 1.12.0.7043 |
| `proc_samu_s93explosion` | chaddiger | AlliedModders attachment 2780192 (Samuwu) | opcode-identical, SM 1.12.0.7043 |
| `saitama` | onepunch | Batfoxkid/FF2-Library @ 9588914 | opcode-identical, SM 1.8.0.5864 |
| `shadow93_abilities` | hatsunemiku | Plum-Sandbag/Tf2_plugins | opcode-identical, SM 1.12.0.7043 |
| `the_killing_mann` | darkvader | Batfoxkid/FF2-Library @ af0cfa7 | opcode-identical, SM 1.12.0.7043 |

The SM 1.12 binaries were built with skial's includes (`MAXPLAYERS` 256). The AlliedModders attachments were found through dvander/sourcepawn-corpus.

Includes:
- `freak_fortress_2.inc`: Frenzoid/TF2_FF2, with fixes for newer compilers.
- `freak_fortress_2_subplugin.inc`: matched to the prod binaries.
- `ff2_ams.inc`: FF2-Library.
- `ff2_dynamic_defaults.inc`: Frenzoid/TF2_FF2.

Fixes made in the ports, besides what SP2 requires:
- Per-client arrays sized `MAXPLAYERS + 1`. Several were 34–36, so on the 101-slot server high client indexes went out of bounds or never got the ability (`ff2r_special_zombie` minion cleanup, `ff2r_tfcond`, `ffsamu_airdash`, `ff2_dynamic_defaults`, `ff2_death`).
- `ff2_dynamic_defaults.inc`, `ff2_ams.inc`: plugin lookups also match `.smx`. They only looked for `.ff2`, so under FF2R `ff2_death`'s dynamic defaults calls always failed.
- `ff2_death`: `ShootProjectile` took a sized string with a literal default (the SP2 heap corruption bug); round start applied every boss's settings to boss 0; client loops skipped the last slot.
- `ff2_dispenserrage`: timers hold entity references, so a reused entity index is never touched.
- `ffsamu_airdash`: recharge timers no longer stack across rounds.
- `ff2r_tfcond`: the respawn and boss-death cleanup paths of `tweak_tfcondition` used the wrong client and condition list.
- `halloween_2013`: the dropped-item kill checks `FL_ONGROUND` (was always true); no longer closes FF2R's KeyValues handle.
- `shadow93_abilities`: stale reanimator timer handles are cleared.
- `proc_samu_s93explosion`: timers carry userids; failed entity creation is handled.
- `ff2_blockdropitem`: the kick message is not used as a format string.
- `saitama`: drops the unused tf2attributes dependency.

Build all of them with `../buildplugins.sh` (SP2 compiler in `sdk/sourcemod-build`). It builds `freaks/*.sp` into `build/disabled/`, using the FF2R includes for `ff2r_*` and the legacy includes for the rest.
