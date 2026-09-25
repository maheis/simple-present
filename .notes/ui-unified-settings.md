# Einheitliche UI Controls, Design und Settings

## Status

Bereits vorhanden; entspricht dem gemeinsamen Standard weitgehend.

## Gemeinsamer Standard

Alle Apps in `m.git` sollen dieselbe UI-Settings-Auswahl anbieten:

- Schriftart: `OpenDyslexic`, `NotoSans`, `CourierPrime`, `Ubuntu`, `Ubuntu Mono`
- Schriftgröße: 50 % bis 160 %
- Designmodus: hell oder dunkel
- Akzentfarbe: Rot, Orange, Grün, Gelb, Blau, Mint, Lila
- Highlight-Farbe: Rot, Orange, Grün, Gelb, Blau, Mint, Lila

## SimplePresent Umsetzung

- Settings und Theme liegen derzeit in `lib/main.dart`
- Persistenz: `simplepresent_settings.json`
- App-weite Werte: `useLightTheme`, `highlightColorValue`, `uiTextScaleFactor`, `fontFamily`
- Theme-Anwendung: zentraler `_buildTheme(...)` Pfad

## Abgleich

SimplePresent nutzt bereits:

- `fontFamily`
- `uiTextScaleFactor`
- `useLightTheme`
- `highlightColorValue`
- Theme-Anwendung auf Buttons, Icons, Inputs und Selection

## Nächster Feinschliff

Die Settings-UI sollte bei Gelegenheit in eine eigene Settings-Schicht ausgelagert werden, damit sie strukturell wie VolleyAce/PlaySheet/Fibu/Bloemcher/Biografie aussieht. Funktional ist die gemeinsame Auswahl aber vorhanden.
