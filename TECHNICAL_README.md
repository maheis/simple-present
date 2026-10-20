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

## Betriebsnotizen

- lastRunDate wird in der JSON-Settings-Datei erhalten, damit Tagesmigration nur einmal pro Tag laeuft.
- Das Hauptfenster verwendet weiterhin seine Startposition und Startgroesse.
- Separate Aufgabenfenster speichern ihre letzte Position, Normalgroesse und den Maximierungszustand gemeinsam in `simplepresent_task_window_geometry.json` im jeweiligen App-Datenordner. Alte Werte aus `taskWindowGeometry` werden weiterhin gelesen.
- Aenderungen werden beim Verschieben/Skalieren und vor dem nativen Schliessen gespeichert; ein periodischer Abgleich bleibt als Fallback aktiv.
- Unter Linux starten separate Aufgabenfenster bei vorhandenem `DISPLAY` ueber X11/XWayland, damit ihre Position wiederhergestellt werden kann. Ohne X11 bestimmt der Wayland-Compositor die Position; die App kann sie dort nicht erzwingen.

## Aufgaben-Worklog

- Das History-Symbol (`worklog`) in der aufgeklappten Aufgabe bzw. im separaten Aufgabenfenster oeffnet die Historie dieser Aufgabe, neueste Eintraege zuerst.
- Aufgaben-Schreibvorgaenge und Worklog werden gemeinsam in einer Sembast-Transaktion gespeichert. Erfasst werden Anlage, Status, Wichtigkeit, Inhalte, Unteraufgaben, Termine, Wiederholungen, Listenwechsel, Listenentfernung und Aenderungen der Reihenfolge. Feldwerte vor und nach einer Aenderung bleiben im Worklog erhalten.
- Zeitbuchungen enthalten zusaetzlich den Buchungstag und die davor/danach gebuchten Minuten bzw. Sekunden. Ein unveraenderter Speichervorgang erzeugt keinen Eintrag.
- In separaten Aufgabenfenstern werden Zustandsaenderungen bereits waehrend der Bearbeitung geordnet gespeichert. Dadurch bleiben beispielsweise Start und Stopp als einzelne Ereignisse erhalten, auch wenn erst spaeter geschlossen wird.
- Sembast-Stores: `task_worklog` enthaelt Eintraege pro Aufgaben-ID; `task_worklog_state` haelt den letzten Zustand fuer Listenwechsel und Feldvergleiche. Die Historie bleibt auch nach Entfernen einer Aufgabe erhalten.
- JSON-Export und automatische Backups enthalten den Schluessel `worklog`. Beim Import werden vorhandene Eintraege anhand ihrer IDs zusammengefuehrt, nicht verdoppelt. Alte Exporte ohne Worklog bleiben lesbar.
- Die vollstaendige Erfassung beginnt mit dieser Version. Bereits existierende Aufgaben erhalten keine erfundenen Erstellungsereignisse; aeltere, nicht protokollierte Vorgaenge lassen sich nicht nachtraeglich rekonstruieren. Ungespeicherte und verworfene Texteingaben werden nicht als Aenderung protokolliert.

## Empfehlung fuer Debugging

1. debugWriteLog auf true setzen.
2. Problem reproduzieren.
3. simplepresent_debug.log pruefen.
4. Nach Analyse debugWriteLog wieder auf false setzen.
