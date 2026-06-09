# SimplePresent

Eine einfache (Simple) Aufgabenverwaltung mit dem Fokus auf aktuelle Aufgaben (Gegenwart -> Present).

## Ideensammlung

- Step 1
- [ ] 2 Listen: heute, Backlog (Json-Filesystem)
- [ ] Hauptansicht heute, unten eine bzw. Textfeld für neue Aufgaben
- [ ] Backlog als Liste von unten reinschieben bis zum halben Bildschirm, nochmals raufziehen als Vollbild
- [ ] Layout soll auf für Hochformat und Schlichtheit optimiert sein!

- Step ?
- [ ] "heute" soll jeden Tag leer starten
- [ ] Erledigt nur als Filter auf die Listen
- [ ] Textfilter
- [ ] 3 Flags für Aufgaben: Wichtig, Erledigt, in Arbeit
- [ ] Unteraufgaben bzw. Schritte für Aufgaben
- [ ] Freitextfeld für Notizen/Lösung
- [ ] Optional Terminierung Tag+Uhrzeit
- [ ] Backlog sortieren nach Wichtigkeit und Reihenfolge des Einfügens (Berücksichtigung Aufgaben die aus heute rausfallen)
- [ ] Stopuhr: Start, Stopp, Rücksetzten
- [ ] Manuelle Zeiterfassung (Zeit der Stopuhr wird auf 15 Min aufgerundet und vorgeschlagen)
- [ ] App optimiert auf Hochformat
- [ ] Fenster soll sich Modal anpinnen lassen (Desktop)
- [ ] Erinnerungsfunktion an die Nutzung der App (Ton, Flackern, Aufpoppen, Benachrichtung etc.)

## Notizen

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
