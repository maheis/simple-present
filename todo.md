# ToDo

- [x] keine toasts by sync
- [x] icons für...
  - [x] notes
  - [x] statistik
  - [x] redo log
  - [x] settings
- [x] aufgaben mit datum "heute" automatisch aus dem backlog ins today verschieben!
- [x] sync redo-log klappt nicht. aber braucht es das wirklich? rückbauen?
- [x] repeat funktioniert nicht mehr?!
- [x] jsons in unterordner
- [x] jsons pro task. die einzelnen listen _backlog, _done , _today, _trash sollen dann als unterordner struktur abgebildet werden.
- [x] done setzten stoppt die stopuhr nicht mehr und setzt auch in progress nicht mehr zurück!
- [x] 24 Uhr move today -> backlog
- [x] android sound unterbricht musik wiedergaben...
        -> nutzt jetzt SystemSound auf Android (unterbricht nicht, Audio-Focus-freundlich)
- [x] repeat
  - [x] weekly
    - [x] 2
    - [x] 3
  - [x] monthly
    - [x] day of month (first, last, first weekday, last weekday...)
  - [x] yearly
  - [x] ask next repeat date on creating follow up task
- [x] repeat optional: dynamische zeit, fertigmeldung + intervall. -> "ask next repeat" reicht!
- [x] settings file wird nicht korrekt im ordner verwendet!
- [x] revoked device toast kommt von unten, alle toasts von unten sollen auf die standard von oben umgebaut werden
- [x] android sollte nicht immer den fokus auf neue aufgabe legen!
- [x] aufgaben die ins backlog geschoben werden lösen ein "there" aus. d.h. irgendwie wird der status geändert. -> find ich eigentlich gut!
- [x] repeat aufgaben die automatisch ins today geschoben weden, legen direkt eine repeat aufgabe an! damit doppeln die aufgaben sich!
- [x] Windows Zertifikat für exe?!
- [x] sync button muss ein vollständiges synchronisieren auslösen!
        -> lädt jetzt alle 3 Listen hoch, zieht Remote State, reloaded UI
- [x] aufgaben die im backlog in der vergangenheit liegen, sollen automatisch ins today verschoben werden, wenn sie noch nicht erledigt sind!
- [x] andoid statt localhost als geräte namen!
- [x] hübschere und fancy lade animation im loading screen
- [x] burger menü alles klein
- [x] termin im backlog < einer woche soll wochentag da stehen, termin > 1 woche soll datum stehen
- [x] icon im loding screen auf icon.png umstellen
- [x] runter sortieren, sortiert "drüber"
- [x] android: aktionen in der notification (erledigt, in arbeit)
- [ ] Google Play Store Veröffentlichung (.notes/PLAY_STORE_ANDROID.md) - IN WORK
- [ ] Windows Store Veröffentlichung (.notes/WINDOWS_APP_STORE.md)
- [ ] Worklog an Aufgaben...
- [ ] erinnerungen deaktiveren können (z.b. bei aktiver app?)
- [ ] Web Applikation
- [ ] animation:
  - [ ] aufklappen/zuklappen
  - [ ] positionsveränderungen
  - [ ] verschieben in andere listen
  - [ ] wackeln als animation
- [ ] Reihenfolge auch über andere Gruppen hinaus und dann optisch einsortieren
- [ ] Abhängigkeiten Reduzieren
  - [x] sqlite3.dll
  - [ ] mehr?
  - [ ] Aufräumen (ois)
- [ ] sync: erster sync muss schneller, es muss beim öffnen geprüft werden bevor der client selbst aktionen ausführt. sonst kann es zu chaos kommen! (aufgaben die anm handy in heute lagen nd schon erledigt waren, wurden beim anderen in backlog verschoben und da liegengelassen...) 
- [x] sync: move von backlog zu today wird nicht synchronisiert (wie button-fehler! touch stößt an!) ! verschwindet aus backlog, taucht aber im today nicht auf! sachen die ins backlog gehen, bleiben in today...
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
- [??] manchmal werden aufgaben falsch selektiert (bei kachel button move oder verschieben)
- [??] manchmal werden andere aufgauben auch in progress gesetzt wenn ich eine auf in progress setze (performance? müsste ein delay nach der aktion sein? beobachten konnte ich es wenn der pc ausgelastet war)
- [??] backlog wird manchmal komplett zu today
- [??] today manchmal leer, ziemlich wired grade!
- [x] sort bei öffnen von listen
- [x] android widget
  - [x] today widget, absprung in die app!
  - [x] keine actions
  - [x] breite soll kleiner gemacht werden können (aktuell geht nur breiter, nicht schmaler als 3 kacheln))
  - [x] oben links icon und überschrift
  - [x] transparentes widget (60% hintergrundstransparenz), damit es sich in den hintergrund einfügt
  - [x] schrift
  - [x] widget übernimmt konfigurierte app-schrift
  - [x] radio-button
  - [x] sortierreihenfolge wie in der app!
- [x] subtasks müssen in folgeaufgaben wieder nicht bearbeitet sein!
- [x] today wurde nicht nach heute geschoben
- [x] loading auf dem task wenn man z.b. verschiben drückt
- [-] widget: kalender einfügen? -> aktuell mit dem widget karussell gelöst!
- [x] in progress swipen -> switcht den text sofort auf done...
- [x] action que
- [ ] reopen in der done liste führt zu gecken effekten
- [x] nur ein pair button (wenn erstes gerät, soll es halt registriert werden, sonst hinzugefügt werden)
- [x] ausführliches sync testen! kommt ständig zu fehlern, die nicht reproduzierbar sind! 
      z.b. move von backlog zu today wird nicht synchronisiert, sachen die ins backlog gehen, bleiben in today...
      dopplung von aufgaben...
- [x] sync button macht immer noch nicht 100%
- [ ] 

## notes

- [ ] Übersetzung! Deutsch...
- [ ] LLM-Integration: Automatisches Generieren von Unteraufgaben/Schritten aus der Hauptaufgabe, Vorschläge für Notizen/Lösungen basierend auf der Aufgabe, intelligente Sortierung des Backlogs basierend auf Wichtigkeit und Dringlichkeit.
- [ ] Dark Mode: Unterstützung für dunkle und helle Designs, um die Benutzererfahrung zu verbessern und die Augenbelastung zu reduzieren.
- [ ] Barrierefreiheit: Unterstützung für Screenreader, Tastaturnavigation und andere Barrierefreiheitsfunktionen, um die App für alle Benutzer zugänglich zu machen.
- [ ] Export/Import: Möglichkeit, Aufgabenlisten zu exportieren und zu importieren, z.B. als JSON oder CSV, um Backups zu erstellen oder Daten zwischen verschiedenen Apps zu übertragen.
- [ ] Widgets: Unterstützung für Widgets auf dem Startbildschirm (Mobile) oder Desktop, um schnellen Zugriff auf die wichtigsten Aufgaben zu ermöglichen.
- [ ] Integration mit Kalendern: Möglichkeit, Aufgaben mit Kalenderereignissen zu verknüpfen, um eine bessere Übersicht über Termine und Aufgaben zu erhalten.
