# Epson WF-C579R saved settings

These `.dat` files are Epson driver DEVMODE captures used by
`../Repair-EpsonWfC579rQueues.ps1`.

- `a4_epson_config.dat` applies the saved A4 queue defaults.
- `token_epson_config.dat` applies the saved Token queue defaults.

They are driver-private settings blobs captured with `printui.dll /Ss`; they are
not ordinary text config files. If the Epson driver package changes, recapture
them from a known-good reference machine.
