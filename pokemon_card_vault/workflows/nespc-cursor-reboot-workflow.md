# nespc Cursor update + reboot

Use this when the operator asks to **update Cursor on nespc** and/or **reboot nespc**.

## Scope

- Target host: **nespc** at `192.168.178.25` (not `.45`).
- Do **not** reboot Oracle peers, `pi-home`, or cloud agent VMs for this request.
- Cloud agents cannot reach the LAN; run the script on nespc (local shell or local Cursor agent).

## Script

```bash
cd /path/to/cardvault/pokemon_card_vault
chmod +x workflows/nespc-update-cursor-and-reboot.sh

# preview
./workflows/nespc-update-cursor-and-reboot.sh --dry-run

# update Cursor, then reboot nespc
./workflows/nespc-update-cursor-and-reboot.sh
```

Override the hostname/IP guard only if you are certain:

```bash
NESPC_FORCE=1 ./workflows/nespc-update-cursor-and-reboot.sh
```

## What it does

1. Confirms the machine looks like nespc (hostname or `192.168.178.25`).
2. Updates Cursor via `apt` or `snap`, or clears stuck AppImage pending updater state.
3. Prints `/var/run/reboot-required` / `needrestart` info.
4. Notes A1 capacity hunt will not survive reboot (restart script path printed).
5. Runs `sudo reboot`.

## After reboot on nespc

1. Open Cursor once and confirm Help → About shows the expected version.
2. If A1 hunt should be running:  
   `~/secrets/deploy/oci-free-stack/scripts/oci-a1-capacity-hunt.sh`
3. Optional: `curl -fsS https://api.pokoin.com/healthz`
