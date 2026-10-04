# Legacy FF2 subplugins (prod freak server)

Sources for legacy FF2 1.x boss subplugins that FF2R loads from `plugins/disabled/` on the freak server.

| Plugin | Source | Verified against prod binary |
|---|---|---|
| `the_killing_mann` | Batfoxkid/FF2-Library @ af0cfa7 | opcode-identical when built with SM 1.12.0.7043 |
| `m7_abilities_extended` | Batfoxkid/FF2-Library @ eac05d5 (pre-AMS2) | opcode-identical when built with SM 1.12.0.7043 |
| `public_dots` | sarysa, via Plum-Sandbag/Tf2_plugins @ 93a3ba1 | opcode-identical when built with SM 1.5.3 (2014 binary) |
| `drain_over_time` | sarysa 1.1.0, reconstructed from the prod binary (1.0.0 at Plum-Sandbag/Tf2_plugins @ 93a3ba1; Zell3/FF2R-subplugins ports 1.1.0 to FF2R) | opcode-identical when built with SM 1.9.0.6248 (2018 binary) |

Includes:
- `freak_fortress_2.inc`: Frenzoid/TF2_FF2, with fixes for newer compilers.
- `freak_fortress_2_subplugin.inc`: matched to the prod binaries.
- `ff2_ams.inc`: FF2-Library.
- `drain_over_time.inc`, `drain_over_time_subplugin.inc`: sarysa, via Plum-Sandbag/Tf2_plugins @ 93a3ba1.

Build (also compiles with the SP2 compiler in `sdk/sourcemod-build`):

    spcomp -i scripting/include -i ../addons/sourcemod/scripting/thirdparty scripting/freaks/<name>.sp
