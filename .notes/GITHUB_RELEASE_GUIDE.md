# GitHub Release Template & Integrity Verification Guide

## Quick Start: Creating a Release with Integrity Verification

### Step 1: Generate SHA256 & GPG Signatures

```bash
# Navigate to your release directory (e.g., build/windows/runner/Release/)
cd build/windows/runner/Release

# Generate SHA256 checksum
sha256sum SimplePresent.exe > SimplePresent.exe.sha256
sha256sum SimplePresent_0.6.16_x64.msi >> SimplePresent.exe.sha256  # If you have MSI

# Generate GPG signature (if you have GPG key set up)
gpg --detach-sign --armor SimplePresent.exe
# Output: SimplePresent.exe.asc

# Verify GPG signature works
gpg --verify SimplePresent.exe.asc SimplePresent.exe
# Should show: Good signature from "Your Name <your@email.com>"
```

### Step 2: Create GitHub Release with Template

Go to: https://github.com/your-username/simple-present/releases/new

**Copy-paste this template:**

---

## Release Template (Copy This)

```markdown
# Simple Present v0.6.16

**Release Date:** 2026-07-01
**Status:** Stable Release

## What's New

- ✅ Fixed repeat task duplication bug
- ✅ Added optional "Ask repeat date on creation" feature
- ✅ Fixed Android sound playback
- ✅ Optimized performance (move from backlog 3s → <1s)
- ✅ Implemented bidirectional cloud sync
- 🐛 Various bug fixes and improvements

## Downloads

| Platform | File | Version |
|----------|------|---------|
| Windows (portable) | `SimplePresent.exe` | 0.6.16 |
| Windows (installer) | `SimplePresent_0.6.16_x64.msi` | 0.6.16 |
| Desktop (Linux) | Build from source or install via package manager | 0.6.16 |
| Web | https://simplepresent.example.com | 0.6.16 |
| Android | See [Play Store](#) or [GitHub Releases](#) | 0.6.16 |

## 🔒 Integrity Verification

We provide multiple ways to verify that you've downloaded an authentic, unmodified SimplePresent binary.

### Option 1: SHA256 Checksum (Easiest)

**⚠️ Make sure the SHA256 below matches your downloaded file!**

```
SimplePresent.exe SHA256:
abc123def456789abc123def456789abc123def456789abc123def456789abc1

SimplePresent_0.6.16_x64.msi SHA256:
def456789abc123def456789abc123def456789abc123def456789abc123def4
```

**Verify on Windows (PowerShell):**
```powershell
# Replace "C:\Downloads\SimplePresent.exe" with actual path
(Get-FileHash -Path "C:\Downloads\SimplePresent.exe" -Algorithm SHA256).Hash

# Output should match the SHA256 above ↑
# Example output: ABC123DEF456789ABC123DEF456789ABC123DEF456789ABC123DEF456789ABC1
```

**Verify on Linux/Mac (Terminal):**
```bash
sha256sum ~/Downloads/SimplePresent.exe
# Output should match the SHA256 above ↑
```

### Option 2: GPG Signature (Most Secure)

For advanced users: We sign all releases with a GPG key for cryptographic verification.

**1. Import our GPG public key:**
```bash
gpg --recv-keys YOUR_GPG_KEY_ID
# Key fingerprint: XXXX XXXX XXXX XXXX XXXX  XXXX XXXX XXXX XXXX XXXX
```

**2. Verify the signature:**
```bash
gpg --verify SimplePresent.exe.asc SimplePresent.exe
```

**Expected output:**
```
gpg: Signature made [Date] using RSA key ID XXXXXXXX
gpg: Good signature from "Mani Heiser <your@email.com>"
```

**If you see "BAD signature":**
- ⚠️ **DO NOT RUN THE FILE** — something is wrong
- Download again from official GitHub releases page only
- Contact maintainer if problem persists

### Option 3: VirusTotal Scan (Community Verification)

For additional peace of mind:
1. Go to: https://www.virustotal.com/
2. Upload `SimplePresent.exe`
3. Wait for scan results (usually 2-5 minutes)
4. Review detection rate (should be 0/XX or minimal false positives)

## Installation Instructions

### Windows (.exe)

**Portable version (no installation):**
1. Download `SimplePresent.exe`
2. Double-click to run
3. Choose where to store your tasks (local or cloud sync)

**Installer version (.msi):**
1. Download `SimplePresent_0.6.16_x64.msi`
2. Double-click to run installer
3. Follow setup wizard
4. App appears in Start Menu

### Linux

**Build from source:**
```bash
git clone https://github.com/your-username/simple-present.git
cd simple-present
flutter build linux --release
# Output: build/linux/x64/release/bundle/simple_present
```

### macOS

**Build from source:**
```bash
git clone https://github.com/your-username/simple-present.git
cd simple-present
flutter build macos --release
# Output: build/macos/Build/Products/Release/simple_present.app
```

### Android

**From GitHub:**
- Download `.apk` file from this release
- Enable "Unknown Sources" in Settings → Security
- Open file and tap "Install"

**From Play Store:**
- Search "Simple Present" in Google Play Store
- Tap "Install"
- Updates delivered via Play Store

## Known Issues

- None at this time. Please report issues on [GitHub Issues](https://github.com/your-username/simple-present/issues)

## Support

- **Documentation:** [README.md](../README.md)
- **Bug Reports:** [GitHub Issues](https://github.com/your-username/simple-present/issues)
- **Feature Requests:** [GitHub Discussions](https://github.com/your-username/simple-present/discussions)

## License

SimplePresent is released under the [MIT License](../LICENSE)

---

**Questions about security or signatures?** See [INTEGRITY_VERIFICATION.md](.notes/INTEGRITY_VERIFICATION.md)
```

---

## Step 3: Upload Files to Release

1. Scroll down to **"Attach binaries"** section
2. Drag & drop these files:
   - `SimplePresent.exe`
   - `SimplePresent.exe.sha256`
   - `SimplePresent.exe.asc` (if you have GPG signature)
   - `SimplePresent_0.6.16_x64.msi` (if applicable)

3. Click **"Publish release"**

## Automating This with GitHub Actions

For future releases, you can automate SHA256 + GPG signing:

Create `.github/workflows/release.yml`:

```yaml
name: Create Release Artifacts

on:
  push:
    tags:
      - 'v*'

jobs:
  build-and-sign:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build Windows App
        run: |
          flutter build windows --release
          
      - name: Generate SHA256
        shell: pwsh
        run: |
          cd build/windows/runner/Release
          (Get-FileHash -Path "SimplePresent.exe" -Algorithm SHA256).Hash | Out-File SimplePresent.exe.sha256
          
      - name: GPG Sign (if key available)
        env:
          GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
          GPG_PASSPHRASE: ${{ secrets.GPG_PASSPHRASE }}
        run: |
          gpg --import <<< "${{ env.GPG_PRIVATE_KEY }}"
          gpg --detach-sign --armor SimplePresent.exe
          
      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            build/windows/runner/Release/SimplePresent.exe
            build/windows/runner/Release/SimplePresent.exe.sha256
            build/windows/runner/Release/SimplePresent.exe.asc
          body_path: RELEASE_NOTES.md
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Setting Up GPG Signing

### Generate a GPG Key (One-time)

```bash
# Generate new key
gpg --full-gen-key

# Choose:
# - Key type: RSA (option 1)
# - Key length: 4096
# - Expiration: 3 years
# - Name: Your Name
# - Email: your@email.com

# List your keys
gpg --list-keys

# Export public key (share this)
gpg --armor --export YOUR_KEY_ID > public.key

# Export private key (KEEP SECRET, never share)
gpg --armor --export-secret-key YOUR_KEY_ID > private.key

# Add public key to GitHub profile:
# GitHub Settings → SSH and GPG keys → Add GPG key
```

### Sign Files Locally

```bash
# Sign a file
gpg --detach-sign --armor SimplePresent.exe
# Creates: SimplePresent.exe.asc

# Verify signature
gpg --verify SimplePresent.exe.asc SimplePresent.exe
```

## Best Practices

✅ **DO:**
- Generate new SHA256 for every release
- Sign releases with GPG key
- Include integrity info in every release
- Keep GPG key safe (encrypted, backup)
- Document verification instructions
- Test downloaded file locally before release

❌ **DON'T:**
- Share private GPG key anywhere
- Use weak passwords for GPG key
- Skip verification for "trusted" releases
- Reuse SHA256 from previous releases

---

**Last Updated:** 2026-07-01
**For:** SimplePresent v0.6.16+
