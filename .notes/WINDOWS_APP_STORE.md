# Windows App Store (Microsoft Store) Publication Guide

## Overview

Publishing SimplePresent to the Microsoft Store provides several benefits:
- ✅ **Windows Code Signing:** Apps are automatically signed by Microsoft
- ✅ **Automatic Updates:** Users get updates via Windows Update
- ✅ **Trusted Distribution:** Appears in Windows 11/10 native app store
- ✅ **Better UX:** No "Unknown Publisher" SmartScreen warnings
- ❌ **Cost:** $19 USD one-time developer account fee
- ⏱️ **Timeline:** 1-3 months from submission to approval

## Prerequisites

### 1. Developer Account Setup

**Step 1: Create Microsoft Account**
- Go to: https://account.microsoft.com/
- Use same email throughout entire process

**Step 2: Register as App Developer**
- Go to: https://developer.microsoft.com/en-us/microsoft-store/register/
- Pay **$19 USD** one-time registration fee
- Verify identity (Microsoft will ask for info)
- Wait for email confirmation (1-2 business days)

**Step 3: Set Up Developer Center**
- Login to: https://partner.microsoft.com/en-us/dashboard
- Create **App Publisher Identity** with:
  - Display name (e.g., "Mani Heiser")
  - Public contact email

### 2. Windows Package Requirements

For Microsoft Store, you must create an **MSIX package** (not just a .exe):

**MSIX = Microsoft Store app format** (like APK for Android)

#### Generate MSIX Package

**Option A: Via Windows Terminal (Recommended)**

```powershell
# 1. Install Windows SDK (includes MSIX tools)
# Download from: https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/
# OR via Package Manager:
winget install Microsoft.WindowsSDK

# 2. Navigate to your app build directory
cd path\to\your\app\build\windows\runner\Release

# 3. Create app manifest (MSIX needs AppxManifest.xml)
# See section "MSIX Manifest File" below

# 4. Package the app
# Using makeappx.exe (included in Windows SDK)
makeappx.exe pack /d path\to\app /p SimplePresent.msix

# 5. Sign the package (with self-signed cert for testing)
# Generate cert (only once):
New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=SimplePresent" `
  -FriendlyName "SimplePresent Code Signing" -CertStoreLocation "Cert:\CurrentUser\My" `
  -KeyUsage DigitalSignature -KeySpec Signature -TextExtension "2.5.29.37={text}1.3.6.1.5.5.7.3.3"

# Export cert to .pfx
$cert = Get-ChildItem -Path "Cert:\CurrentUser\My" -CodeSigningCert | Where-Object { $_.Subject -eq "CN=SimplePresent" }
Export-PfxCertificate -Cert $cert -FilePath "SimplePresent.pfx" -Password (ConvertTo-SecureString -String "yourpassword" -AsPlainText -Force)

# Sign the MSIX
signtool.exe sign /fd SHA256 /f "SimplePresent.pfx" /p "yourpassword" SimplePresent.msix
```

**Option B: Via Visual Studio**
- Open `windows/runner_windows.sln` in Visual Studio
- Right-click project → "Create App Packages..."
- Select "Microsoft Store"
- Follow wizard (generates MSIX automatically)

### 3. MSIX Manifest File

Create `AppxManifest.xml` in your project root or build directory:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:mp="http://schemas.microsoft.com/appx/2014/phone/manifest"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10">

  <Identity Name="ManiHeiser.SimplePresent"
            Publisher="CN=Mani Heiser, O=Mani Heiser, L=Heising, S=Bayern, C=DE"
            Version="0.6.16.0" />

  <Properties>
    <DisplayName>Simple Present</DisplayName>
    <PublisherDisplayName>Mani Heiser</PublisherDisplayName>
    <Logo>assets\icons\icon.png</Logo>
  </Properties>

  <Applications>
    <Application Id="SimplePresent" StartPage="SimplePresent.exe">
      <uap:VisualElements DisplayName="Simple Present"
                          Square150x150Logo="assets\icons\icon.png"
                          Square44x44Logo="assets\icons\icon.png"
                          Description="Cross-platform task management app"
                          BackgroundColor="#FFFFFF" />
    </Application>
  </Applications>

  <Capabilities>
    <!-- Required for file access -->
    <Capability Name="documentsLibrary" />
    <Capability Name="picturesLibrary" />
    <!-- Optional: for network sync -->
    <Capability Name="internetClient" />
    <Capability Name="internetClientServer" />
  </Capabilities>

</Package>
```

## Submission Process

### Step 1: Create App Listing in Partner Center

1. Login to: https://partner.microsoft.com/dashboard/apps/overview
2. Click **"Create a new app"**
3. Enter **"Simple Present"** as app name
4. Click **"Create"**
5. Wait for name reservation (5-10 minutes)

### Step 2: Fill Out App Details

In Partner Center, complete:

**Identity Section:**
- App name: `Simple Present`
- Publisher name: Your legal name
- Package/Identity GUID: Auto-generated

**Description Section:**
- Short description (100 chars): "Cross-platform task management"
- Full description (see DESCRIPTION below)
- Keywords: task, management, gtd, productivity, flutter

**Category:**
- Select: **Productivity** or **Utilities**

**Age Rating:**
- Select: **PEGI 3** (or equivalent - no restricted content)

### Step 3: Prepare Screenshots & Graphics

Microsoft Store requires:

| Asset | Dimensions | Format | Required |
|-------|-----------|--------|----------|
| **App Logo** | 240×240 px | PNG | ✅ Yes |
| **Screenshots** | 1080×1080 px | PNG/JPG | ✅ Yes (min 1, max 9) |
| **Store Hero** | 1920×1080 px | PNG | ❌ Optional |
| **Feature Graphic** | 1920×1080 px | PNG | ❌ Optional |
| **Trailer Video** | MP4, H.264 | MP4 | ❌ Optional |

**Screenshot Tips:**
- Show: Task creation, task list, calendar view, settings
- Include English captions
- Use actual app UI (not artwork)
- At least 2-3 screenshots minimum

### Step 4: Upload MSIX Package

1. In Partner Center → **Packages**
2. Upload your signed `SimplePresent.msix` file
3. Microsoft runs automated tests (30-60 minutes)
4. Review results for:
   - Certificate validity
   - MSIX integrity
   - Malware scan (Windows Defender)
   - API compliance

### Step 5: Certification & Policies

Before submission, review Microsoft's policies:

**Must comply with:**
- [Microsoft Store Policies](https://docs.microsoft.com/en-us/windows/uwp/publish/store-policies)
- **Key rules for SimplePresent:**
  - ✅ Must not collect personal data without consent
  - ✅ Must have privacy policy (link in Store listing)
  - ✅ Must disclose any tracking/analytics
  - ✅ Network sync must use HTTPS only
  - ✅ File access must be transparent to user
  - ❌ Must NOT auto-download large files
  - ❌ Must NOT modify system settings
  - ❌ Must NOT require admin privileges

**Prepare privacy policy:**
- Simple one-pager on SimplePresent website or GitHub
- Explain: Cloud sync data handling, no ads, no tracking

### Step 6: Submit for Review

1. In Partner Center → **Submission**
2. Click **"Submit for Review"**
3. Read final checklist
4. Accept policies
5. Click **"Publish"**

**Review Timeline:**
- Automatic malware scan: 1-2 hours
- Microsoft human review: 1-3 days
- Certification decision: 1-3 weeks
- If rejected: Get detailed feedback, fix, resubmit

## After Publishing

### Maintenance

- **Updates:** Resubmit new MSIX when you have new version
- **Changelog:** Add update notes in Partner Center
- **Version numbers:** MUST increment (0.6.16.0 → 0.6.17.0, etc.)
- **Build number:** MSIX must have unique version each submission

### Analytics

In Partner Center, you get:
- Download stats
- Crash reports
- Rating distribution
- Review feedback

### Auto-Updates

Users get updates automatically via Windows Update when:
1. New version published to Store
2. Windows Update runs (usually daily)
3. User may manually check: **Store → Get Updates**

## Troubleshooting

### "Certificate Validation Failed"

```
Error: Digital signature validation failed
```

**Solution:**
- Ensure cert is valid Code Signing certificate
- Use SHA256 signing (not MD5)
- Verify cert hasn't expired: `signtool.exe verify /pa SimplePresent.msix`

### "MSIX Package Corrupted"

```
Error: The appx package signature is invalid
```

**Solution:**
```powershell
# Validate MSIX structure
Test-AppxPackage -Path SimplePresent.msix

# Extract and re-package
makeappx.exe unpack /p SimplePresent.msix /d SimplePresent_extracted
makeappx.exe pack /d SimplePresent_extracted /p SimplePresent_fixed.msix
```

### "Insufficient Permissions for File Access"

Ensure `AppxManifest.xml` declares capabilities:
```xml
<Capability Name="documentsLibrary" />
```

### "App crashes on launch in Store"

- Likely: Missing `network_security_config.xml` (Android specific)
- Windows version: Check Windows 10/11 runtime compatibility
- Test locally: Install MSIX before submitting

## Cost Breakdown

| Item | Cost | Notes |
|------|------|-------|
| Developer Account | $19 USD | One-time |
| Yearly renewal | $0 | No renewal fee after first year |
| Time investment | ~5-10 hrs | Setup, packaging, testing, submission |
| **Total** | **$19 USD** | Relatively low cost |

## Timeline Summary

```
Week 1: Developer account setup + fee payment
Week 2: Package & test MSIX locally
Week 3: Create Partner Center listing + graphics
Week 4: Submit for review
Week 4-5: Microsoft certification (1-3 weeks)
Week 5+: Published on Microsoft Store!
```

## Resources

- **Windows App SDK Docs:** https://learn.microsoft.com/en-us/windows/apps/
- **MSIX Packaging:** https://learn.microsoft.com/en-us/windows/msix/
- **Store Policies:** https://learn.microsoft.com/en-us/windows/uwp/publish/store-policies
- **Partner Center:** https://partner.microsoft.com/dashboard
- **MSIX Toolkit:** https://github.com/microsoft/MSIX-Toolkit

---

**Last Updated:** 2026-07-01
**SimplePresent Version:** 0.6.16+
