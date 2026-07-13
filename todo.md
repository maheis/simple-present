# ToDo

- [?] ausführliches sync testen! kommt ständig zu fehlern, die nicht reproduzierbar sind! 
      z.b. move von backlog zu today wird nicht synchronisiert, sachen die ins backlog gehen, bleiben in today...
      dopplung von aufgaben...
- [?] sync button macht immer noch nicht 100%
- [?] android hintergrund synchronisation (push) implementieren
- [?] aufgaben durcheinander
  - [ ] es kommt zu vielen dopplungen von aufgaben
  - [ ] today war auf einmal komplett leer!
  - [ ] aufgaben werden nicht automatisch aus dem backlog geholt wenn sie auf heute liegen!
  - [ ] verschieben zwischen listen (insbesondere durch status änderungen!)
- [?] android verliert manchmal den text focus beim editieren und springt runter in "neue aufgaben"-feld
- [ ] Google Play Store Veröffentlichung (.notes/PLAY_STORE_ANDROID.md) - IN WORK
- [ ] Windows Store Veröffentlichung (.notes/WINDOWS_APP_STORE.md)
- [ ] Worklog an Aufgaben...
- [ ] erinnerungen deaktiveren können (z.b. bei aktiver app?)
- [ ] Web Applikation
- [ ] Reihenfolge auch über andere Gruppen hinaus und dann optisch einsortieren
- [ ] Abhängigkeiten Reduzieren
  - [x] sqlite3.dll
  - [ ] mehr?
  - [ ] Aufräumen (ois)
- [ ] sync: erster sync muss schneller, es muss beim öffnen geprüft werden bevor der client selbst aktionen ausführt. sonst kann es zu chaos kommen! (aufgaben die anm handy in heute lagen nd schon erledigt waren, wurden beim anderen in backlog verschoben und da liegengelassen...) 
- [ ] sync: self signed certs prüfen (ca-chain) 
- [ ] sync: nur ein gerät sollte automatisches löschen aktiv haben! (primärgerät-definieren?)
- [ ] papierkorb:
        schiebt sync in den papierkorb?
        papierkorb sichtbar machen (um wiederherstellen zu können)
- [ ] install server soll updaten können
- [ ] android: icon fritte (muss es einen hintergrund haben?), was ist mit weißem icon für statusleiste z.b.?
      notification funktioniert mit weißen icon.[text](about:blank#blocked)
      kleines app icon in der taks auswahl und benachrichtigung klappt auch
      app icon ist 4 eckig auf weißem grund (rund)
      jetzt ist das icon wieder vermatscht, glaube muss transparentes icon mit gößerem transparenten rand sein, damit es rund passt
- [ ] Zeiterfassung muss granularer sein, damit die Zeiten pro Tag passen!
- [ ] SimplePresent -> simple present | dateinamen: simple-present
- [ ] refresh widget - bei aktualisierung von today in der app!
- [x] fertige aufgaben werden nicht mehr automatisch aus dem today entfernt
- [x] aufgaben von yesterday legen nach erledigung eine neue today aufgabe an. follow up soll auch bei vergangenen aufgaben wie today behandelt werden, also follow up vom heutigem tag aus generiert werden!
- [x] settings in eine eigene sembast-db
- [x] funktionen heißen immer noch alle sqlite... 
- [x] clean done
- [x] android: widget funktioniert seit umstellung auf sembast nicht mehr bzw. zeigt nichts mehr an!
- [x] aufgaben die ich im backlog auf heute oder in vergangenheit lege, sollen in today gemoved werden!
- [x] default backup strategie: 90 Backups, alle 5 Minuten und beim Start
- [ ] cliens hängen häufiger im start loading fest, ich glaube tritt nur bei cloud sync clients auf!
- [ ] qr-code scan füllt nicht mehr die URL
- [ ] today migration funktioniert nicht mehr sauber. today soll beim ersten start leer sein. alle aufgaben die done sind sollen in done verschoben werden, alle aufaben die offen  sind sollen ins backlog geschoben werden. alle aufgaben die auf heute oder in der vergangenheit liegen, sollen danach vom backlog ins today verschoben werden! 

## notes

- [ ] Übersetzung! Deutsch...
- [ ] LLM-Integration: Automatisches Generieren von Unteraufgaben/Schritten aus der Hauptaufgabe, Vorschläge für Notizen/Lösungen basierend auf der Aufgabe, intelligente Sortierung des Backlogs basierend auf Wichtigkeit und Dringlichkeit.
- [ ] Dark Mode: Unterstützung für dunkle und helle Designs, um die Benutzererfahrung zu verbessern und die Augenbelastung zu reduzieren.
- [ ] Barrierefreiheit: Unterstützung für Screenreader, Tastaturnavigation und andere Barrierefreiheitsfunktionen, um die App für alle Benutzer zugänglich zu machen.
- [ ] Export/Import: Möglichkeit, Aufgabenlisten zu exportieren und zu importieren, z.B. als JSON oder CSV, um Backups zu erstellen oder Daten zwischen verschiedenen Apps zu übertragen.
- [ ] Widgets: Unterstützung für Widgets auf dem Startbildschirm (Mobile) oder Desktop, um schnellen Zugriff auf die wichtigsten Aufgaben zu ermöglichen.
- [ ] Integration mit Kalendern: Möglichkeit, Aufgaben mit Kalenderereignissen zu verknüpfen, um eine bessere Übersicht über Termine und Aufgaben zu erhalten.

