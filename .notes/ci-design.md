# Design CI & Styleguide

Dieses Dokument fasst die Design‑Regeln und einen Beispiel‑CI‑Workflow zusammen, damit neue Apps einheitlich aussehen.

## Grundprinzipien
- **Konsistenz:** Farben, Abstände, Typografie und Komponenten müssen projektübergreifend gleich sein.
- **Wiederverwendbarkeit:** UI als wiederverwendbare Komponenten und Design Tokens ablegen.
- **Zugänglichkeit:** Kontrast und Tastaturbedienbarkeit prüfen.

## Design Tokens (Empfehlung)
- Legt eine JSON‑Datei `design-tokens.json` im `design/` Ordner an.

Beispiel (kleine Auswahl):

```json
{
  "color": {
    "primary": "#0B63C6",
    "accent": "#F29E1E",
    "background": "#FFFFFF",
    "surface": "#F7F8FA",
    "text": "#111827",
    "muted": "#6B7280"
  },
  "font": {
    "family": "Inter, system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial",
    "sizes": { "sm": "0.875rem", "md": "1rem", "lg": "1.125rem" }
  },
  "space": { "xs": "4px", "sm": "8px", "md": "16px", "lg": "24px", "xl": "40px" },
  "radii": { "sm": "4px", "md": "8px", "round": "9999px" }
}
```

## Komponenten‑ und Asset‑Konventionen
- Komponenten: `PascalCase` (z. B. `PrimaryButton`).
- CSS/SCSS/Styles: Nutzt CSS‑Variablen aus den Tokens (z. B. `--color-primary`).
- Icons: Verwaltet als SVGs im Ordner `assets/icons/` und verwendet ein zentrales Icon‑System.
- Bilder: Maximale Dateigröße 200 KB, WebP bevorzugt, mit `srcset` für responsive Auslieferung.

## Barrierefreiheit
- Mindestkontrast: 4.5:1 für normalen Text, 3:1 für großen Text.
- Prüft mit `axe` oder `pa11y` im CI.
- Alle interaktiven Elemente müssen `:focus` Zustände haben.

## Naming & Repository‑Layout (Empfehlung)
- `design/` — Design Tokens, Farben, Typografie.
- `assets/` — Icons, Bilder, Fonts.
- `src/components/` — Wiederverwendbare UI‑Komponenten.
- `docs/` — Screenshots, Guidelines, Branding‑Assets.

## Beispiel: GitHub Actions Workflow (Design CI)
- Dies ist ein Beispiel, das man unter `.github/workflows/design-ci.yml` ablegen kann.

```yaml
name: Design CI
on: [push, pull_request]

jobs:
  design-checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Use Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 18
      - name: Install dependencies
        run: npm ci
      - name: Lint styles
        run: npm run lint:styles # z.B. stylelint
      - name: Lint JS/TS
        run: npm run lint:js # eslint
      - name: Build Storybook
        run: npm run build:storybook
      - name: Accessibility check (axe)
        run: npx @axe-core/cli "dist/storybook/index.html"
      - name: Validate design tokens (JSON schema)
        run: npx ajv validate -s design/token-schema.json -d design/design-tokens.json

```

Hinweis: Skriptnamen (`lint:styles`, `lint:js`, `build:storybook`) sind Beispiele — in eurem Projekt muss `package.json` passende Scripts enthalten.

## Lokale Prüfungen / Befehle
- Lint CSS: `npm run lint:styles`
- Lint JS: `npm run lint:js`
- Storybook lokal: `npm run storybook`
- Build Storybook: `npm run build:storybook`
- Accessibility lokal: `npx @axe-core/cli dist/storybook/index.html`
- Token‑Validierung: `npx ajv validate -s design/token-schema.json -d design/design-tokens.json`

## Weiteres Vorgehen
- Einen zentralen `design/` Ordner in neuen Apps anlegen und `design-tokens.json` übernehmen.
- Optional: Ein kleines `create-app` Template oder `cookiecutter` anlegen, das Tokens und CI konfiguriert.

Wenn du willst, erstelle ich daraus direkt eine `.github/workflows/design-ci.yml` und ein `design/design-tokens.json` Beispiel.
