# Self-Signed Certificate Support

## Problem: Custom CA Certificates on Android

SimplePresent uses Flutter's `dart:io` HttpClient for cloud sync operations. However, there is a known limitation:

**On Android release builds, `dart:io` HttpClient does NOT fully respect the `network_security_config.xml` configuration**, even though native Android apps respect it automatically.

This means:
- ❌ User-installed CA certificates are NOT automatically trusted
- ❌ Self-signed certificates fail with `CERTIFICATE_VERIFY_FAILED` errors
- ✅ But: Official CAs (Let's Encrypt, DigiCert, etc.) work fine

## Solution 1: Proper Server Configuration (Recommended)

Configure your Apache/Nginx to send the complete certificate chain:

### Apache 2.4:
```apache
SSLCertificateFile /path/to/server.crt
SSLCertificateKeyFile /path/to/server.key
SSLCertificateChainFile /path/to/HeisAG-CA.pem   ← Include the CA certificate
```

### Verify with curl:
```bash
openssl s_client -connect your-server.com:443 -showcerts < /dev/null 2>/dev/null | grep -c "BEGIN CERTIFICATE"
# Should show 2 certificates (server cert + CA cert)
```

When properly configured, all clients (including SimplePresent) will work without additional settings.

## Solution 2: Enable "Accept Insecure Certificates" (For Selfhosted)

If you cannot modify server configuration, use the built-in app setting:

1. **Settings → Cloud Sync**
2. **Enable: "Accept insecure certificates"**
3. **Note:** This only accepts certificates for your configured server, not globally

### Security:
- ✅ Hostname verification: Certificate must be for your server domain
- ✅ Port verification: Must match configured server port
- ✅ Only affects one server: Other cloud services not affected
- ⚠️ Warning: Disables full certificate validation chain checking

## Why Other Apps Work

Applications like Nextcloud, Firefox, etc. work because they either:
1. Use native platform HTTP stacks (respects `network_security_config.xml`)
2. Load CA certificates differently than Flutter
3. Use OpenSSL directly with system CA store

SimplePresent uses Flutter's abstraction layer, which has platform limitations.

## Verification

To verify your certificate chain is complete:

```bash
# Check if CA is in chain (should show 2+ certificates)
openssl s_client -connect your-server.com:443 -showcerts < /dev/null 2>/dev/null | grep -c "BEGIN CERTIFICATE"

# View full chain
openssl s_client -connect your-server.com:443 -showcerts < /dev/null 2>/dev/null | grep -A1 "subject="
```

## Future

This limitation may be addressed in future Flutter versions. Follow progress:
- https://github.com/flutter/flutter/issues (search: "network_security_config")
- https://github.com/dart-lang/sdk (search: "HttpClient" + "security")
