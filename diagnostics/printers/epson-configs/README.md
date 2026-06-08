# Epson WF-C579R saved settings

These `.dat` files are Epson driver DEVMODE captures retained for controlled
experiments with `../Repair-EpsonWfC579rQueues.ps1 -ApplySavedSettings`.

- `a4_epson_config.dat` applies the saved A4 queue defaults.
- `token_epson_config.dat` applies the saved Token queue defaults.

They are driver-private settings blobs captured with `printui.dll /Ss` using
the `d g u` flags; they are not ordinary text config files.

Canary testing showed `printui.dll /Sr` can return success without actually
changing WF-C579R tray routing, so the main repair script does not apply these
by default. Use them only for controlled experiments, not as proof of tray
configuration.

Current known-good capture hashes:

- `a4_epson_config.dat`: `1556C5AF097EF6880D8DAD40DE25A3548AFF53F819683B7EF7D7F10F72B0916B`
- `token_epson_config.dat`: `DAE28A30D08089E6BBE8BB5E077DA55B5A8F79A74DA867D9D9390AF33B01F643`
