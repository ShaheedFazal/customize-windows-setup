if (Test-MachineWideSentinel -Name 'Disable-Guest-Account') { return }

## Disable guest account
net.exe user guest /active:no
