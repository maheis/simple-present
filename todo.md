# ToDo

- [x] Programmiersprache, Framework, Frontend etc.
    Wenn Desktop-first + Go-Kenntnisse: Go + Wails ist gut geeignet — native Desktop-Apps mit moderner Web-UI, einfacher Zugriff auf Go-Bibliotheken, deutlich kleinere Bundles als Electron. Nachteil: keine Android-Unterstützung (Wails ist desktop-only).   
    **Wenn Desktop + Mobile (Android) aus einer Hand: Flutter ist die beste Wahl — Windows, Linux und Android mit einem einzigen UI-Framework, sehr gute UI-Design-Tools, starke Cross‑Platform-Qualität. Sprache: Dart.**
    Wenn Web-Stack bevorzugt + schlanke Desktop-Bundles: Tauri (Rust backend + Web-UI) ist sehr leichtgewichtig für Desktop; Mobile ist aber nicht so reif.
    Andere Optionen: React Native / Capacitor (Web → Mobile, Desktop per Electron/Proton), Kotlin Multiplatform/Compose Multiplatform (gute native Mobile-Optionen), .NET MAUI (C#, mobile + desktop aber Linux-Ökosystem schwächer).
- [x] Testprojekt mit Flutter aufsetzen, um die Entwicklungsumgebung zu evaluieren und erste UI-Elemente zu erstellen.
- [x] Hauptansicht heute, unten eine bzw. Textfeld für neue Aufgaben
- [ ] 2 Listen: heute, Backlog (Json-Filesystem)
- [ ] Backlog als Liste von unten reinschieben bis zum halben Bildschirm, nochmals raufziehen als Vollbild
- [x] Layout soll auf für Hochformat und Schlichtheit optimiert sein!
- [ ] "heute" soll jeden Tag leer starten
- [x] Erledigt nur als Filter auf die Listen <- wird nicht umgesetzt!
- [ ] Textfilter
- [ ] 3 Flags für Aufgaben: Wichtig, Erledigt, in Arbeit
- [ ] Unteraufgaben bzw. Schritte für Aufgaben
- [ ] Freitextfeld für Notizen/Lösung
- [ ] Optional Terminierung Tag+Uhrzeit
- [ ] Backlog sortieren nach Wichtigkeit und Reihenfolge des Einfügens (Berücksichtigung Aufgaben die aus heute rausfallen)
- [ ] Stopuhr: Start, Stopp, Rücksetzten
- [ ] Manuelle Zeiterfassung (Zeit der Stopuhr wird auf 15 Min aufgerundet und vorgeschlagen)
- [x] App optimiert auf Hochformat
- [ ] Fenster soll sich Modal anpinnen lassen (Desktop)
- [ ] Erinnerungsfunktion an die Nutzung der App (Ton, Flackern, Aufpoppen, Benachrichtung etc.)
- [x] Text eingabe soll immer in die Textbox geschubst werden
- [x] Löschen bestätigen
- [x] "Toast" soll oben rein fahren
- [x] heute mit Datum und Tag
- [x] Kein Header
- [x] Darkmode
- [ ] Zoom
- [x] 600x1000 statt 1280x720 (Desktop)
- [ ] icon
- [x] Sortierung
- [x] Timestamp für Aktionen "Erlödigt", Wichtig", "In Arbeit", "Angelegt"
- [ ] Worklog an Aufgaben...
- [x] Json formatiert ablegen
- [ ] Editieren

## notes

- [ ] LLM-Integration: Automatisches Generieren von Unteraufgaben/Schritten aus der Hauptaufgabe, Vorschläge für Notizen/Lösungen basierend auf der Aufgabe, intelligente Sortierung des Backlogs basierend auf Wichtigkeit und Dringlichkeit.
- [ ] Cloud-Synchronisation: Möglichkeit, Aufgaben über mehrere Geräte hinweg zu synchronisieren, z.B. über einen eigenen Server oder Dienste wie Firebase.
- [ ] Dark Mode: Unterstützung für dunkle und helle Designs, um die Benutzererfahrung zu verbessern und die Augenbelastung zu reduzieren.
- [ ] Barrierefreiheit: Unterstützung für Screenreader, Tastaturnavigation und andere Barrierefreiheitsfunktionen, um die App für alle Benutzer zugänglich zu machen.
- [ ] Export/Import: Möglichkeit, Aufgabenlisten zu exportieren und zu importieren, z.B. als JSON oder CSV, um Backups zu erstellen oder Daten zwischen verschiedenen Apps zu übertragen.
- [ ] Widgets: Unterstützung für Widgets auf dem Startbildschirm (Mobile) oder Desktop, um schnellen Zugriff auf die wichtigsten Aufgaben zu ermöglichen.
- [ ] Integration mit Kalendern: Möglichkeit, Aufgaben mit Kalenderereignissen zu verknüpfen, um eine bessere Übersicht über Termine und Aufgaben zu erhalten.
- [ ] Build-Pipeline über Github (kann man hier Zertifizieren?)
- [ ] App-Store-Distribution (Google Play, Microsoft Store, Linux-Distributionen etc.)

Ich baue Drag‑und‑Drop zwischen Backlog und Heute (komplizierter, ich implementiere ReorderableDragTargets).
Ich füge visuelle Verbesserungen (Icons, spacing) und einfache Tests hinzu.
Ich sorge für Undo/Confirm bei Löschungen oder füge eine kleine Animation beim Verschieben hinzu.
