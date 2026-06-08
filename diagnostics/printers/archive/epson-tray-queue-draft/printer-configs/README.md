# Printer DEVMODE captures

This folder holds per-queue settings blobs replayed by
[`../Add-Epson-TrayQueues.ps1`](../Add-Epson-TrayQueues.ps1). Each `.dat` is a
binary DEVMODE capture made with `printui.dll`, holding the tray, paper size,
and colour defaults that PowerShell can't set directly.

| File | Queue | Holds |
|---|---|---|
| `a4_epson_config.dat` | `A4` | Paper Cassette 1, A4, Grayscale |
| `token_epson_config.dat` | `Token` | Paper Cassette 2, custom 211×177mm "Token" size, Grayscale |

Naming convention is `<size>_<vendor>_config.dat` so the same pattern extends
to other printers later (e.g. `a4_brother_config.dat`).

## One-time capture (on a fully-configured reference machine)

1. Install the Epson WF-C579R and create both queues named **exactly** `A4`
   and `Token`, then set each queue's **Printing Preferences** per the
   "Configuring Epson WF-C579 Printer with Titan" runbook:
   - **A4** → Paper Source: Cassette 1, Document Size: A4, Color: Grayscale.
   - **Token** → Paper Source: Cassette 2, Color: Grayscale, Document Size:
     User-Defined "Token" 211.0 × 177.0 mm. Save the preset and move it to the
     top of the list.
2. Confirm a test print from each queue feeds the right cassette.
3. Capture each queue's settings (run elevated):

   ```
   rundll32 printui.dll,PrintUIEntry /Ss /n "A4"    /a "a4_epson_config.dat"    d g
   rundll32 printui.dll,PrintUIEntry /Ss /n "Token" /a "token_epson_config.dat" d g
   ```

   `d g` captures the public default DEVMODE **and** the Epson driver-private
   data (cassette selection, the user-defined Token size, grayscale).
4. Drop `a4_epson_config.dat` and `token_epson_config.dat` into this folder and
   commit them.

## Caveats

- **Driver version must match.** A DEVMODE blob is tied to the driver version
  it was captured from. Capture on the same Epson driver package the estate
  runs; if you roll the driver forward, re-capture.
- The replay (`/Sr`) runs on every machine that has the WF-C579R. Machines
  without it are skipped entirely by the script.
- If a blob is missing, the script still creates the queue and logs a warning —
  a tech then sets that one tray by hand once.
