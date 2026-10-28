# Android Emulator and Local AI Setup Log

Last updated: 2026-10-27

This file records what was installed on this PC, why, where it lives, and how to operate it. It was written from the actual commands and results of the setup session.

## The PC

| Item | Value |
|---|---|
| OS | Windows 11 Home |
| CPU | Intel Core i7-9750H (6 cores / 12 threads) |
| RAM | 15.8 GB |
| GPU | NVIDIA GTX 1660 Ti (Max-Q), plus Intel UHD 630 |
| Disk | 512 GB NVMe SSD (about 110 GB free at the start, about 91 GB now) |

Conclusion: the PC can run one small emulator and one small local AI model at the same time.

## What was installed

### 1. LDPlayer 14 (Android emulator)

- **Why:** a lightweight emulator, chosen over Android Studio's emulator because it is lighter and easier to set up. There was no spare real phone to use with scrcpy.
- **Source:** the official installer link on ldplayer.net. LDPlayer is not in winget.
- **Version note:** the file named `LDPlayer9.exe` on the site installs **LDPlayer 14** (beta, Android 14 core), not version 9. Both files that were downloaded carried the same valid digital signature (signer: JUST OKAY LIMITED, Hong Kong). The signer name could not be tied to LDPlayer's publisher by any other means, so it is reasonable evidence rather than proof.
- **Location:** `C:\LDPlayer\LDPlayer14` (about 5.8 GB).
- **The virtual phone:** one instance, index 0, named "LDPlayer". Set with `ldconsole` to 720x1280 at 240 dpi, 2 CPU cores and 2048 MB RAM.
- **Google Play and apps:** signed in by the user. The user installed Whatnot and it runs on the emulator.
- **ADB debugging:** switched on by the user in LDPlayer Settings > Other settings, so scripts can take screenshots and send taps.

Useful commands (PowerShell):

```powershell
$ld = "C:\LDPlayer\LDPlayer14\ldconsole.exe"
& $ld list2                 # list virtual phones
& $ld launch --index 0      # start the phone
& $ld quit --index 0        # shut it down cleanly
& $ld quitall               # shut down every phone (do this before turning off the PC)
& $ld backup --index 0 --file C:\Emulator\backups\phone0.ldbk   # backup (not yet run)
```

### 2. Ollama (installed, then removed)

- Installed with `winget install Ollama.Ollama` (version 0.40.11).
- **It never worked.** Every model download (`llama3.2:3b`, `qwen2.5:1.5b`) failed with `401`, even after the user signed in at ollama.com. `ollama signin` kept reporting the PC as not signed in. The cause was not found.
- No models were ever downloaded. The program itself used 3.1 GB.
- **Uninstalled** with `winget uninstall Ollama.Ollama`.
- **Leftover:** the folder `C:\Users\Mark Scheiber\.ollama` still exists. It holds only empty model folders, a small cache file and an unused key pair, about 2 KB in total. It can be deleted.

### 3. LM Studio (current local AI tool)

- Installed with `winget install ElementLabs.LMStudio` (version 0.4.26).
- **Why:** it downloads models from Hugging Face with no account, and it has a built-in chat window.
- **Location:** app in `AppData\Local\Programs\LM Studio` (about 2 GB). Models and data in `C:\Users\Mark Scheiber\.lmstudio` (about 4.1 GB at last check, outside Dropbox so they do not sync).
- **Model:** a Llama 3.2 3B Instruct file (Q4_K_S, about 2 GB) was downloaded by the user. Expect about 3 GB of RAM in use while a model is loaded. Eject the model when finished to free it.

## Cleanup done

- Deleted the downloaded installer folder `C:\Emulator\download` and the screenshots folder `C:\Emulator\shots`.
- Deleted the stray `LDPlayer14_ens_1397_ld.exe` from the Dropbox Downloads folder.

## What was tried and declined

- **Disguising the emulator as a real phone** (faking device identity, location or IP so apps believe it is a real handset): declined. It is meant to evade platform fraud and emulator checks. A VPN for ordinary privacy was offered, but not installed.
- **A timer-based bot that automatically enters giveaways:** declined. It would break Whatnot's rules and could get the account banned. Two single taps were done on request: opening a giveaway panel and pressing "Follow Host & Enter Giveaway". This followed one host account.

## Still to do

- Run a first backup of the phone (the user chose to wait). The command is in the list above.
- Optionally delete `C:\Users\Mark Scheiber\.ollama`.
- Optionally write a small PowerShell script for shutting down and backing up.

## Rules this setup follows

- Official downloads or winget only, with signatures or hashes checked.
- No Python. Only PowerShell or bash.
- Passwords and verification codes are always entered by the user.
- Large data (emulator files, models, backups) stays outside Dropbox.
