# Play Store: Android Deployment Checklist

Kurz und präzise Anleitung, um eine Android-Version in den Google Play Store zu bringen.

## 1) Versioning
- Erhöhe die `version` in `pubspec.yaml`, z.B. `1.2.0+5` (`+5` = `versionCode`).

## 2) Keystore & Signing
- Erstelle einen Keystore (einmalig):

```bash
keytool -genkeypair -v \
  -keystore ~/.keystores/simplepresent.jks \
  -alias simplepresent_key \
  -keyalg RSA -keysize 2048 -validity 10000
```

## 3) Play Console — Vorbereitung
- Richte ein Google Play Developer Account ein (einmalige Gebühr).
- Erstelle eine App in der Play Console.
- Fülle Store Listing aus: Titel, Kurz-/Langbeschreibung, Screenshots, High‑res Icon (512×512), Feature Graphic (1024×500), Kontakt‑Email, Datenschutzerklärung.
- Content Rating, Ziel‑API (aktuell halten), Kategorien und Berechtigungen konfigurieren.

## 4) Upload & Testing
- Im Release‑Bereich ein Release anlegen und das `.aab` hochladen.
- Nutze Internal Testing (schnell) → Closed/Open Beta → Production.
- Teste auf echten Geräten; prüfe Crash‑Reports und Berechtigungen.

## 5) Rollout
- Starte mit kleinem Prozentsatz (z.B. 5%) und erhöhe schrittweise.

## 7) CI / GitHub Actions (kurzes Beispiel)
- Speichere Keystore und Passwörter als GitHub Secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`).

How to create KEYSTORE_BASE64 locally:
```
base64 ~/.keystores/simplepresent.jks | tr -d '\n' > ~/.keystores/simplepresent_base64.txt
```

- Beispiel-Snippet (Auszug):
```yaml
- name: Restore keystore
  run: |
    echo "$KEYSTORE_BASE64" | base64 --decode > ${{ github.workspace }}/keystore.jks
  env:
    KEYSTORE_BASE64: ${{ secrets.KEYSTORE_BASE64 }}

- name: Build AAB
  run: |
    echo "storePassword=$KEYSTORE_PASSWORD" > android/key.properties
    echo "keyPassword=$KEY_PASSWORD" >> android/key.properties
    echo "keyAlias=$KEY_ALIAS" >> android/key.properties
    echo "storeFile=$PWD/keystore.jks" >> android/key.properties
    flutter build appbundle --release
  env:
    KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
    KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
    KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
```

## 8) Checkliste vor Upload
- `versionCode` erhöht
- Keine Debug‑APIs/Secrets hardcodiert
- Datenschutzerklärung bereit
- Berechtigungen minimal gehalten
- Crash‑Reporting/Analytics (optional) konfiguriert

## 9) Troubleshooting / Tipps
- Play verlangt aktuelle `targetSdkVersion` — prüfe `android/app/build.gradle`.
- Wenn du Obfuscation nutzt: sichere `debug-info` für Deobfuskierung.
- Bei CI auf Windows: falls MSVC-Fehler auftreten, setze notwendige CMake‑Defines oder CI‑env `CL` Flags.

---

Speichere diese Datei als `docs/PLAY_STORE_ANDROID.md` im Repository. Wenn du möchtest, erstelle ich noch ein komplettes GitHub Actions Workflow‑Template, das das AAB baut und als Artefakt hochlädt oder direkt an die Play Console überträgt.
