# Technical README

Technische Dokumentation zu internen Parametern, Settings-Datei und Debug-Verhalten.

## Settings-Datei

- Dateiname: simplepresent_settings.json
- Standardordner:
  - Debug-Build: Dokumente/simplepresent-debug/
  - Release-Build: Dokumente/simplepresent/
- Override: Wenn storagePath gesetzt ist, werden Settings und Listen in diesem Ordner gespeichert.

## Wichtige Parameter

### debugWriteLog

- Typ: bool
- Default: false
- Wirkung:
  - Steuert, ob _debugLog(...) in simplepresent_debug.log schreibt.
  - Bei false: keine Debug-Log-Eintraege aus _debugLog.
  - Bei true: Debug-Log wird geschrieben und beim Laden der Settings wird ein Initialeintrag erzeugt.
- Log-Datei:
  - simplepresent_debug.log im aktiven Storage-Ordner.
- Hinweis:
  - Fuer normale Nutzung auf false lassen.
  - Fuer Fehleranalyse auf true setzen.

### storagePath

- Typ: string
- Default: leer
- Wirkung:
  - Definiert einen benutzerdefinierten Speicherpfad.
  - Bei leer nutzt die App den Standardordner (siehe oben).

### cloudAllowInsecureTls

- Typ: bool
- Default: false
- Wirkung:
  - Erlaubt unsichere Zertifikate fuer Cloud-Sync (nur wenn explizit aktiviert).

### cloudDeviceName

- Typ: string
- Default:
  - Android: android
  - Sonst: Hostname (Fallback desktop bei leer/localhost)
- Wirkung:
  - Geraetename fuer Register/Pair im Cloud-Sync.

### maxTasksToday / maxTasksBacklog

- Typ: int
- Defaults:
  - maxTasksToday: 25
  - maxTasksBacklog: 50
- Wirkung:
  - Schwellwerte fuer UI-Farbskalierung/Visualisierung.

### autoPurgeDoneEnabled / doneRetentionDays

- Typen: bool / int
- Defaults: false / 30
- Wirkung:
  - Aktiviert automatisches Loeschen alter Done-Eintraege.
  - doneRetentionDays bestimmt Aufbewahrungsdauer.

## Weitere persistierte Settings (Auszug)

Die Settings-Datei speichert zusaetzlich unter anderem:

- Reminder- und Inaktivitaetsparameter:
  - idleMinutes, attentionMinutes, reminderMinutes, urgentMinutes
  - reminderWindowFrom, reminderWindowTo
  - inactivityReminders
- UI-Parameter:
  - uiTextScaleFactor, fontFamily, swipeEnabled
- Cloud-Statusdaten:
  - cloudServerUrl, cloudAccountId, cloudDeviceId, cloudToken
  - cloudStateVersion, cloudLastSyncModifiedAt, cloudLastSyncSuccessAt
  - cloudSyncFailed, cloudSyncLastError

## Betriebsnotizen

- lastRunDate wird in der JSON-Settings-Datei erhalten, damit Tagesmigration nur einmal pro Tag laeuft.
- Window-Position/Geometry wird nicht persistiert (absichtlich deaktiviert).

## Empfehlung fuer Debugging

1. debugWriteLog auf true setzen.
2. Problem reproduzieren.
3. simplepresent_debug.log pruefen.
4. Nach Analyse debugWriteLog wieder auf false setzen.
