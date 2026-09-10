# sysctl-durability

A workstation that hard-locks should reboot on its own instead of sitting
frozen until someone reaches the power button. Three lockup detectors are
told to panic, panic is told to reboot after ten seconds, and SysRq is fully
enabled so a partially responsive machine can still be synced and rebooted
from the keyboard.

Arch defaults leave all three detectors at report-only, `kernel.panic` at 0
(hang forever), and `kernel.sysrq` at 16 (sync only).

Origin: a Chrome GPU VRAM leak on an RX 7900 XTX that froze the compositor
and the machine with it, 2026-03-01. Applied on north the same day and held
since. The recipe changes no hardware-specific value, so it applies to any
machine whose owner would rather reboot than wait.

Sources: `sysctl.d(5)`; Linux `Documentation/admin-guide/sysctl/kernel.rst`
for `softlockup_panic`, `hardlockup_panic`, `hung_task_panic`, `panic`,
`panic_on_io_nmi`, `sysrq`.

Undo: `pacman -Rns dotarchy-sysctl-durability && sysctl --system`.
