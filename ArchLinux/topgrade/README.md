# Topgrade Configuration

Backup of the [Topgrade](https://github.com/topgrade-rs/topgrade) configuration file (`topgrade.toml`). Topgrade is a CLI utility that detects all package managers and tools on your system and updates them all with a single command.

## File Paths

- **System Config Location:** `~/.config/topgrade.toml`
- **Backup Location in Repository:** `Linux/topgrade/topgrade.toml`

## How to Backup

If you modify your system configuration, copy the updated config back to this repository folder before committing:

```bash
cp ~/.config/topgrade.toml /home/mpi/Documents/GitHub/useful_scripts/Linux/topgrade/topgrade.toml
```

## How to Restore

To restore this configuration on a new installation or another machine, run:

```bash
mkdir -p ~/.config
cp /home/mpi/Documents/GitHub/useful_scripts/Linux/topgrade/topgrade.toml ~/.config/topgrade.toml
```

## Key Configuration Settings in this Backup
- **Package Manager**: Configured to use `paru` for Arch Linux (with `--nodevel` flag).
- **Cleanup**: Enabled to clean up temporary files/caches after upgrades.
- **Flatpak**: Enabled upgrades using `sudo`.
- **Disabled Upgraders**: Firmware, Snap, and Chezmoi are disabled to avoid conflicts/redundancies.
- **Ignored Failures**: Ignores failures in `pip3` and `antigravity` to prevent halting the entire update cycle.
- **Post-commands**: Configured to reload the shell after completion.

## Custom System Upgrade Script (`upgrade.sh`)

We created a custom wrapper script (`upgrade.sh`) that runs `topgrade` first to update all application runtimes and repositories, and then runs CachyOS-specific cleanups and checks:

- **Orphans**: Scans for and removes orphan packages and their dependencies.
- **Flatpak Cleanup**: Uninstalls unused Flatpak packages and runtimes.
- **Package Cache**: Cleans up older versions of cached package archives using `paccache` (retains the 3 latest versions, removes uninstalled packages).
- **Kernel Update Reboot Check**: Detects if a kernel upgrade has occurred by verifying if modules match the running system, prompting the user for a reboot if required.

### How to Run:
```bash
/home/mpi/Documents/GitHub/useful_scripts/Linux/topgrade/upgrade.sh
```
