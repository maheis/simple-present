# ToDo

- [x] Google Play Store Veröffentlichung (.notes/PLAY_STORE_ANDROID.md) - Geschlossener Test läuft... Hab nur keine Anwender!
- [x] Windows Store Veröffentlichung (.notes/WINDOWS_APP_STORE.md)
- [ ] Web Applikation ?
      Variante1: Die PWA kann lokal alle Aufgaben in IndexedDB speichern und zusätzlich eine beliebige API im Internet oder im eigenen Netzwerk verwenden.
            -> Ja
            PWA im Browser
            ├─ lokale Daten: IndexedDB
            └─ Synchronisation: https://mein-server/api
      Variante 2: Web-App zentral hosten, während die eigentlichen Aufgaben ausschließlich lokal im Browser gespeichert werden.
            https://simple-present.example
                  |
                  v
            PWA/Web-Oberfläche
                  |
                  v
            IndexedDB im Browser des Nutzers
      Variante 3: Gehostet als Web-App mit Login und zentraler Speicherung der Aufgaben in einer Datenbank. (z.B. Firebase, Supabase, eigene API)
            https://simple-present.example
                  |
                  v
            PWA/Web-Oberfläche
                  |
                  v
            Zentrale Datenbank (z.B. Firebase, Supabase, eigene API) 
- [ ] Worklog an Aufgaben...
- [ ] Reihenfolge auch über andere Gruppen hinaus und dann optisch einsortieren
- [ ] sync: self signed certs prüfen (ca-chain)
- [ ] sync: nur ein gerät sollte automatisches löschen aktiv haben! (primärgerät-definieren?)
- [ ] Zeiterfassung muss granularer sein, damit die Zeiten pro Tag passen!
- [ ] SimplePresent -> simple present | dateinamen: simple-present
- [ ] ausführliches sync testen! kommt ständig zu fehlern, die nicht reproduzierbar sind!
      - [ ] aufgaben doppeln sich, bei tages beginn. es kommt die konfliktabfrage.
      - [ ] was ist ein konflikt? konflikt sollte nur sein, wenn zwei clients unterschiedliche änderungen machen.
      - [ ] sync muss vor tagesmigration erfolgen?! (siehe punkt 1)
- [ ] Anzeigen wenn es Notes gibt?
- [ ] aufgaben fenster position und größe merken
- [ ] Server Geheimnis (optinal rotierend) damit kein Client ohne Geheimnis auf den Server zugreifen bzw. registrieren kann!
- [x] highlight der aktuelle selektierten aufgabe (wenn z.b. neue aufgabe angelegt wird)
- [x] suche bei neuanlage soll bei aufgaben im backlog nicht reaktivieren anbieten, sondern als aktion "move to today" anbieten
- [x] aufgaben suche (strg+f)

## notes

- [ ] Übersetzung! Deutsch...
- [ ] LLM-Integration: Automatisches Generieren von Unteraufgaben/Schritten aus der Hauptaufgabe, Vorschläge für Notizen/Lösungen basierend auf der Aufgabe, intelligente Sortierung des Backlogs basierend auf Wichtigkeit und Dringlichkeit.
- [x] Dark Mode: Unterstützung für dunkle und helle Designs, um die Benutzererfahrung zu verbessern und die Augenbelastung zu reduzieren.
- [ ] Barrierefreiheit: Unterstützung für Screenreader, Tastaturnavigation und andere Barrierefreiheitsfunktionen, um die App für alle Benutzer zugänglich zu machen.
- [x] Export/Import: Möglichkeit, Aufgabenlisten zu exportieren und zu importieren, z.B. als JSON oder CSV, um Backups zu erstellen oder Daten zwischen verschiedenen Apps zu übertragen.
- [x] Widgets: Unterstützung für Widgets auf dem Startbildschirm (Mobile) oder Desktop, um schnellen Zugriff auf die wichtigsten Aufgaben zu ermöglichen.
- [ ] Integration mit Kalendern: Möglichkeit, Aufgaben mit Kalenderereignissen zu verknüpfen, um eine bessere Übersicht über Termine und Aufgaben zu erhalten.
