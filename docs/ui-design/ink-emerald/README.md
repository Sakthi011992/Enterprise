# Ink & Emerald redesign

A premium restyle of every screen in `docs/ui-design/project`, keeping the same content and workflows.

- `project/` — 63 artboards (`.dc.html`) plus `canvas.json`, which groups them into 10 pages:
  Foundation, Core, Bar & stock, Guests, Displays, People & money, Platform, Mobile, More screens, Persona flows.
- `STYLE-BRIEF.md` — the tokens and rules every screen follows (colours, type scale, components, layout).
- `project/Foundations.dc.html` — the visual summary of those tokens.

## The look in one paragraph

Deep ink (`#0B1220`) navigation on a soft neutral page (`#F5F6F8`) with white cards. One accent, emerald
(`#0E7C66`; `#2FB896` on dark screens), used only for the primary action, the active item and key data.
Manrope for headings and large numbers, Inter for everything else, six text sizes, tabular figures for all amounts.
Status colours are soft fills with strong text that pass 4.5:1 contrast.

## Notes

- Back-office web screens import the shared `Sidebar.dc.html` and `Topbar.dc.html` with `<dc-import>`, so they
  need the design tool's runtime (`support.js`) to show the shell. Opened as plain HTML they render without it.
- `Flows.dc.html` replaces the 18 original `Flow-*.dc.html` pages, which depended on that runtime.
- Themes and Theme switcher use a sample palette; the original swatch values were not recoverable.
- Most screens were not checked in a browser yet; expect small layout fixes.
