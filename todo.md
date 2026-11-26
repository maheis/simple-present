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
- [x] Worklog an Aufgaben...
- [ ] Reihenfolge auch über andere Gruppen hinaus und dann optisch einsortieren
- [?] Zeiterfassung muss granularer sein, damit die Zeiten pro Tag passen!
- [ ] SimplePresent -> simple present | dateinamen: simple-present
- [ ] Anzeigen wenn es Notes gibt?
- [x] aufgaben fenster position und größe merken
- [x] highlight der aktuelle selektierten aufgabe (wenn z.b. neue aufgabe angelegt wird)
- [x] suche bei neuanlage soll bei aufgaben im backlog nicht reaktivieren anbieten, sondern als aktion "move to today" anbieten
- [x] aufgaben suche (strg+f)
- [x] strg+f suche für android (button im burgermenü?)
- [x] deselektieren wwenn man ins leere klickt
- [x] deselektion auch wenn man z.b. in neue aufgabe springt
- [x] suche nach aufgaben soll die aufgabe öffnen können (Weil man z.b. infos nachschauen mag)
- [x] notes button aus dem burgermenü raus und daneben verschieben
- [x] Fokus auch weg wenn app kein Fokus
- [x] animierer fokus (kurz vergrößern) der nach zeit verschwindet/verblasst
- [x] suchfenster muss beim anlegen einer neuen aufgabe geschlossen werden.
- [x] Cloud-Sync inklusive Servercode entfernen
- [-] nur windows?
- [x] stundenerfassung pro tag!
- [ ] export subtasks als template (text export in zwischenablage ausreichend)
- [x] statistik button oben neben notes
- [ ] filter in simplepresent
- [x] selektion zum verschieben nimmt immer aufgabe unter dem ding..
- [x] subaufgaben in arbeit
- [x] wenn eine aufgabe editiert wird, muss unten das neue aufgabenfeld entweder weg oder umfunktioniert werden um subtasks anzulegen
- [ ] stundenerfassung suboptimal
  - [?] pro tag!
  - [x] anzeige an der aufgabe
  - [?] buchung manuell soll als manuell erfasst werden (als eintrag)
  - [x] buchung mit einheit m h
  - [x] manuelle buchungen auf 15m aufrunden
  - [?] stundenerfassung nur wenn die app läuft!
  - [x] zeiterfassung tabelle umbennen in englisch
  - [x] filter für tabelle
  - [x] statistik seite zeigt "fertige" aufgaben nicht mehr richtig an!
  - [x] horizontale skrallbar in tabelle
  - [ ] zeiterfassung alles klein schreiben!
- [x] links an punkten (jira-links generieren, bzw. pattern zum generieren)
- [x] fällig uhrzeit bei punkten behalten für follow-up
- [x] wird in "new task" ein vorhandener ausgewählt, muss die leiste danach leer sein
- [?] existiert bereits ein followup für die Aufgabe, sollte keine zweite erstellt werden wenn z.b. eine aufgabe reopen und wieder geschlossen wird
- [ ] Hints für ticket link rule anpassen
            [A-Za-z]+-\d+ pattern for task identifiers (e.g., JIRA issue keys)
- [x] ticket link rules und subtask templates kopieren können
- [x] ticket link rules und subtasks nach unten in den settings, über "counter" unter "font/colors"

## notes

- [ ] Übersetzung! Deutsch...
- [ ] LLM-Integration: Automatisches Generieren von Unteraufgaben/Schritten aus der Hauptaufgabe, Vorschläge für Notizen/Lösungen basierend auf der Aufgabe, intelligente Sortierung des Backlogs basierend auf Wichtigkeit und Dringlichkeit.
- [x] Dark Mode: Unterstützung für dunkle und helle Designs, um die Benutzererfahrung zu verbessern und die Augenbelastung zu reduzieren.
- [ ] Barrierefreiheit: Unterstützung für Screenreader, Tastaturnavigation und andere Barrierefreiheitsfunktionen, um die App für alle Benutzer zugänglich zu machen.
- [x] Export/Import: Möglichkeit, Aufgabenlisten zu exportieren und zu importieren, z.B. als JSON oder CSV, um Backups zu erstellen oder Daten zwischen verschiedenen Apps zu übertragen.
- [x] Widgets: Unterstützung für Widgets auf dem Startbildschirm (Mobile) oder Desktop, um schnellen Zugriff auf die wichtigsten Aufgaben zu ermöglichen.
- [ ] Integration mit Kalendern: Möglichkeit, Aufgaben mit Kalenderereignissen zu verknüpfen, um eine bessere Übersicht über Termine und Aufgaben zu erhalten.
