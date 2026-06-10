# ToDo

- [x] Programmiersprache, Framework, Frontend etc.
    Wenn Desktop-first + Go-Kenntnisse: Go + Wails ist gut geeignet — native Desktop-Apps mit moderner Web-UI, einfacher Zugriff auf Go-Bibliotheken, deutlich kleinere Bundles als Electron. Nachteil: keine Android-Unterstützung (Wails ist desktop-only).   
    **Wenn Desktop + Mobile (Android) aus einer Hand: Flutter ist die beste Wahl — Windows, Linux und Android mit einem einzigen UI-Framework, sehr gute UI-Design-Tools, starke Cross‑Platform-Qualität. Sprache: Dart.**
    Wenn Web-Stack bevorzugt + schlanke Desktop-Bundles: Tauri (Rust backend + Web-UI) ist sehr leichtgewichtig für Desktop; Mobile ist aber nicht so reif.
    Andere Optionen: React Native / Capacitor (Web → Mobile, Desktop per Electron/Proton), Kotlin Multiplatform/Compose Multiplatform (gute native Mobile-Optionen), .NET MAUI (C#, mobile + desktop aber Linux-Ökosystem schwächer).
- [x] Testprojekt mit Flutter aufsetzen, um die Entwicklungsumgebung zu evaluieren und erste UI-Elemente zu erstellen.
- [x] Hauptansicht heute, unten eine bzw. Textfeld für neue Aufgaben
- [x] Layout soll auf für Hochformat und Schlichtheit optimiert sein!
- [x] Erledigt nur als Filter auf die Listen <- wird nicht umgesetzt!
- [x] 3 Flags für Aufgaben: Wichtig, Erledigt, in Arbeit
- [x] Freitextfeld für Notizen/Lösung
- [x] App optimiert auf Hochformat
- [x] Text eingabe soll immer in die Textbox geschubst werden
- [x] Löschen bestätigen
- [x] "Toast" soll oben rein fahren
- [x] heute mit Datum und Tag
- [x] Kein Header
- [x] Darkmode
- [x] 600x900 statt 1280x720 (Desktop)
- [x] Sortierung
- [x] Timestamp für Aktionen "Erlödigt", Wichtig", "In Arbeit", "Angelegt"
- [x] Json formatiert ablegen
- [x] Editieren
- [x] makefile
- [x] Build-Pipeline über Github
- [x] Sounds
- [x] Optional Terminierung Tag+Uhrzeit
  - [x] Tag+Uhrzeit angaben können
  - [x] Icon für terminierte Aufgaben
  - [x] Sortierung terminierter Aufgaben nach Termin
  - [x] Benachrichtigung/Erinnerung für terminierte Aufgaben (Desktop: Benachrichtigung, Ton, Aufpoppen; Mobile: Benachrichtigung, Ton)
- [x] Zoom (Pinch, Strg+Scrollen)
- [x] Fertig Sounds geht nicht
- [x] Erinnerung kommt x-fach, soll aber nur einmalig je Erinnerungstyp kommen
- [x] Sortierung per D&D in der Liste
- [x] Editieren vom Titel per Button?
- [x] Aufgaben die in Arbeit sind, sollen nach Rechts Wischen wieder "aus Arbeit" gesetzt werden
- [?] icon
- [?] Erinnerungsfunktion bei nicht Nutzung der App ([x] Ton (45m), [x] Flackern (60m), [x] Benachrichtung (75m), [] Aufpoppen (90m))
- [ ] 2 Listen: heute, Backlog (Json-Filesystem)
- [ ] Backlog als Liste von unten reinschieben bis zum halben Bildschirm, nochmals raufziehen als Vollbild <- nope, liste soll einfach wechselbar sein und dann per swipe von heute nach backlog und umgekehrt geschoben werden können
- [ ] "heute" soll jeden Tag leer starten
- [ ] Textfilter
- [ ] Unteraufgaben bzw. Schritte für Aufgaben
- [ ] Backlog sortieren nach Wichtigkeit und Reihenfolge des Einfügens (Berücksichtigung Aufgaben die aus heute rausfallen)
- [ ] Stopuhr: Start, Stopp, Rücksetzten
- [ ] Manuelle Zeiterfassung (Zeit der Stopuhr wird auf 15 Min aufgerundet und vorgeschlagen)
- [ ] Fenster soll sich Modal anpinnen lassen (Desktop)
- [ ] Worklog an Aufgaben...
- [ ] Erinnergunsfunktion konfigurierbar machen (Zeit, Art der Erinnerung, etc.)
- [x] Position, Größe und Zoom beim schließen merken und beim start wieder laden
- [x] Schrift viel später resizen!
- [x] Icon für in Arbeit immer sichtbar und als button zum setzen/entfernen der Flagge
- [x] Titelleiste Windows
- [x] Icon Redesign
- [ ] Sounds Redesignen mit Lizenzprüfung (Pixabay)
  
## notes

- [ ] LLM-Integration: Automatisches Generieren von Unteraufgaben/Schritten aus der Hauptaufgabe, Vorschläge für Notizen/Lösungen basierend auf der Aufgabe, intelligente Sortierung des Backlogs basierend auf Wichtigkeit und Dringlichkeit.
- [ ] Cloud-Synchronisation: Möglichkeit, Aufgaben über mehrere Geräte hinweg zu synchronisieren, z.B. über einen eigenen Server oder Dienste wie Firebase.
- [ ] Dark Mode: Unterstützung für dunkle und helle Designs, um die Benutzererfahrung zu verbessern und die Augenbelastung zu reduzieren.
- [ ] Barrierefreiheit: Unterstützung für Screenreader, Tastaturnavigation und andere Barrierefreiheitsfunktionen, um die App für alle Benutzer zugänglich zu machen.
- [ ] Export/Import: Möglichkeit, Aufgabenlisten zu exportieren und zu importieren, z.B. als JSON oder CSV, um Backups zu erstellen oder Daten zwischen verschiedenen Apps zu übertragen.
- [ ] Widgets: Unterstützung für Widgets auf dem Startbildschirm (Mobile) oder Desktop, um schnellen Zugriff auf die wichtigsten Aufgaben zu ermöglichen.
- [ ] Integration mit Kalendern: Möglichkeit, Aufgaben mit Kalenderereignissen zu verknüpfen, um eine bessere Übersicht über Termine und Aufgaben zu erhalten.
- [ ] App-Store-Distribution (Google Play, Microsoft Store, Linux-Distributionen etc.)
