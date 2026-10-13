# UI-Settings-Richtlinie: SimplePresent

Dieses Dokument beschreibt den aktuellen Aufbau der Einstellungen von SimplePresent und dient zugleich als Grundlage fuer Settings-Seiten in neuen Anwendungen.

## 1. Ziel der Settings

Die Einstellungen werden in funktionale Gruppen geteilt:

- **Darstellung:** Theme, Akzentfarben, Schriftart und Textskalierung.
- **Aufgaben und Erinnerungen:** Zeitgrenzen, Warnungen, Sounds, Hinweise und automatische Aktionen.
- **Bedienung:** Swipe-Gesten und separates Desktop-Fenster.
- **Datenpflege:** automatische Bereinigung von Done-/Papierkorb-Eintraegen.
- **Export und Backup:** automatische Exporte, Intervalle und Aufbewahrung.
- **Vorlagen und Limits:** Subtask-Vorlagen sowie Aufgabenlimits.

Settings sollen das Verhalten der Anwendung anpassen, ohne dass fachliche Daten verloren gehen oder die Hauptansicht mit Optionen ueberladen wird.

## 2. Aktuelles Datenmodell

SimplePresent verwendet aktuell eine `Map<String, dynamic>` als Settings-Modell. Die Werte werden von `SettingsPage` entgegengenommen, von der Hauptlogik angewendet und als JSON gespeichert.

### Darstellung

| Schluessel | Typ | Bedeutung |
|---|---|---|
| `useLightTheme` | `bool` | Light-Theme aktivieren; Standard ist Dark |
| `accentColorValue` | `int` | Primaer-/Seed-Farbe aus der Palette |
| `highlightColorValue` | `int` | Hervorhebungsfarbe aus der Palette |
| `fontFamily` | `String` | Standardschrift `OpenDyslexic` oder weitere gebundene Fonts |
| `uiTextScaleFactor` | `double` | Globale Textskalierung von 0.5 bis 1.6 |

### Aufgaben, Zeit und Erinnerungen

| Gruppe | Beispiele |
|---|---|
| Zeitwerte | `idleMinutes`, `attentionMinutes`, `reminderMinutes`, `urgentMinutes` |
| Inaktivitaet | `inactivityReminders` |
| Statusaktionen | `idle*`, `attention*`, `reminder*`, `urgent*` fuer Sound, Flash, Notification und Bring-to-front |
| Geplante Erinnerungen | `scheduledReminderSoundEnabled`, `reminderWindowFrom`, `reminderWindowTo` |
| Aufgabenlimits | `maxTasksToday`, `maxTasksBacklog` |

Zeit- und Alarmgruppen sollen in der UI jeweils zusammenbleiben. Pro Ereignisstufe werden zuerst der Zeitpunkt und danach die verfuegbaren Reaktionen angeboten.

### Datenpflege und Export

| Schluessel | Bedeutung |
|---|---|
| `autoPurgeDoneEnabled` | Erledigte Aufgaben automatisch bereinigen |
| `doneRetentionDays` | Aufbewahrung erledigter Aufgaben |
| `autoPurgeTrashEnabled` | Papierkorb automatisch bereinigen |
| `trashRetentionDays` | Aufbewahrung im Papierkorb |
| `autoExportOnStart` | Export beim Start |
| `autoExportIntervalMinutes` | Wiederholungsintervall |
| `autoExportTimes` | Liste geplanter Exportzeitpunkte |
| `autoExportMaxBackups` | Maximale Anzahl von Sicherungen |
| `subtaskTemplates` | Gespeicherte Checklisten-/Subtask-Vorlagen |

## 3. Seitenaufbau

Die aktuelle Settings-Seite ist eine scrollbare `ListView` in einem `Scaffold` mit `AppBar`.

Empfohlene Reihenfolge:

1. Darstellung
2. Aufgaben und Erinnerungen
3. Datenpflege
4. Backup und Export
5. Vorschau bzw. Versions-/Statusinformationen

Komponenten:

- `SwitchListTile` fuer Ein-/Aus-Zustaende.
- `DropdownButton` fuer Schriftarten und Farben.
- `Slider` fuer Textskalierung und numerische Bereiche.
- `TextField` fuer editierbare Einstellungswerte.
- `Card` fuer Vorschau oder klar abgegrenzte Funktionsgruppen.
- `AlertDialog` fuer Verwerfen und destruktive Aktionen.
- `Tooltip` fuer iconbasierte Aktionen.

Die Seite arbeitet mit einem lokalen Entwurfszustand. Aenderungen werden erst durch **Speichern** an den Elternkontext zurueckgegeben. Beim Verlassen mit ungespeicherten Aenderungen erscheint eine Bestaetigung.

## 4. Aenderungsfluss

```text
SettingsPage
    -> lokale Felder und Validierung
    -> Speichern
    -> Ergebnis-Map an Haupt-State
    -> Theme/Timer/Backup anwenden
    -> JSON-Datei persistieren
```

Theme-Werte werden ueber `ValueNotifier` beobachtet. Dadurch aktualisieren sich `theme`, `darkTheme` und `themeMode` unmittelbar nach dem Anwenden der gespeicherten Werte.

Nach Aenderungen an Zeit- oder Erinnerungswerten muessen laufende Timer bzw. Benachrichtigungslogik neu synchronisiert werden. Nach Aenderungen an Cloud-Werten muss der Sync-Status zurueckgesetzt oder eindeutig aktualisiert werden.

## 5. Speicherung und Migration

- Dateiname: `simplepresent_settings.json`.
- Speicherung erfolgt lokal im konfigurierten App-Speicher.
- Beim Schreiben werden bestehende Werte gelesen und mit den aktuellen Werten zusammengefuehrt.
- Fehlende oder falsch typisierte Werte fallen auf Defaults zurueck.
- Farbwerte werden gegen die erlaubte Palette geprueft.
- Zahlen und Booleans werden robust aus JSON-Werten gelesen.
- Aenderungen am Schema brauchen eine Migrationsstrategie oder kompatible Defaults.

Fuer neue Anwendungen ist statt einer untypisierten Map ein unveraenderliches Modell vorzuziehen:

```dart
class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.fontFamily,
    required this.textScaleFactor,
  });

  final ThemeModePreference themeMode;
  final String fontFamily;
  final double textScaleFactor;
}
```

## 6. Designregeln fuer neue Anwendungen

- Einstellungen nach Aufgabenbereichen gruppieren, nicht nach Implementierungsdateien.
- Sichtbare Defaults und Wertebereiche direkt am Control zeigen.
- Sofortige Vorschau nur dort verwenden, wo sie die Entscheidung erleichtert.
- Destruktive Funktionen von Darstellungseinstellungen trennen und bestaetigen lassen.
- Sensible Zugangsdaten maskieren und nicht als normale Vorschautexte darstellen.
- Jede Einstellung braucht einen stabilen Schluessel, einen Default, eine Validierung und eine Persistenzregel.
- Einstellungen muessen auch bei fehlender, alter oder fehlerhafter Speicherung starten koennen.
- Neue Optionen zuerst als Modell und Repository-Vertrag definieren, danach die UI bauen.

## 7. Wiederverwendbare Vorlage

```text
Settings
+- Darstellung
|  +- Theme-Modus
|  +- Akzentfarbe
|  +- Schriftart
|  +- Textskalierung
+- Verhalten
|  +- Bedienung
|  +- Benachrichtigungen
+- Daten
|  +- Aufbewahrung
|  +- Export/Import
+- Verbindungen
|  +- Server/Konto
|  +- Geraete
|  +- Sync-Status
+- Sicherheit
|  +- sensible Werte
|  +- bestaetigungspflichtige Aktionen
```

## 8. Offene Qualitaetspruefungen

- Vollstaendige Tastatur- und Screenreader-Navigation.
- Kontrastpruefung aller auswaehlbaren Farben in Dark und Light.
- Tests fuer fehlende, alte und ungueltige JSON-Werte.
- Tests fuer ungespeicherte Aenderungen und Abbruchdialoge.
- Pruefung, dass Tokens und PINs nicht in Debug-Logs erscheinen.
