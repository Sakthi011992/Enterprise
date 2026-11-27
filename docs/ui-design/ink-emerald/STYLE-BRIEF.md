# Ink & Emerald redesign: brief for screen agents

You restyle existing pub/bar ERP design screens into the "Ink & Emerald" premium look. Keep every screen's CONTENT
(sections, labels, data, states, flows) from its source file; change only the visual design. Make it look like a
best-in-class modern ERP (calm, precise, generous whitespace, clear hierarchy).

## Paths
- Sources: `docs/ui-design/project/<Name>.dc.html` (the original designs)
- Redesigned screens: `docs/ui-design/ink-emerald/project/` (same file names)
- Reference screens for the new look (copy their patterns exactly):
  `Main.dc.html` (dashboard, light), `Inventory.dc.html` (table + detail panel), `POS.dc.html` (dark touch UI),
  `Login.dc.html` (no shell), `Foundations.dc.html` (tokens), `Sidebar.dc.html` + `Topbar.dc.html` (shared components).

Write each output with the SAME file name as its source. Write each file ONCE with the Write tool, whole. Do not
publish, do not open a browser, do not screenshot, do not verify renders, do not edit any other file, no git.

## File format (.dc.html), rules that fail silently if broken
```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Screen name</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&amp;family=Manrope:wght@600;700;800&amp;display=swap">
<style>body{margin:0}a{color:#0E7C66}a:hover{color:#0A5F4E}</style>
</helmet>
<div style="...root...">...</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{"$preview":{"width":1440,"height":960}}'>
class Component extends DCLogic {
  renderVals() { return {}; }
}
</script>
</body>
</html>
```
- Keep the `support.js` line exactly. Close every non-void element; quote every attribute. All styling inline `style="…"`
  (helmet style only for body margin and link colours). No `{{ }}` except simple dotted lookups into renderVals
  (never expressions). Literal text stays literal markup. No `<iframe>`, no emoji, no external images (use a labelled
  placeholder box), icons = small inline stroke SVG with `aria-hidden="true"`. Escape `&` as `&amp;` in text.
- Accessible markup: real `<button type="button">`, `<a href="#">`, `<input>` with `<label>`, `<table>` with `<th scope>`,
  `aria-label` on icon-only buttons. Touch targets ≥ 44px on POS/tablet/mobile/kiosk.
- Sizes: keep the source's frame size (given per file). Web app PAGES (1440 wide, "fill"): fluid root, NO fixed px
  width; side menu + content as a `display:flex; flex-wrap:wrap` row; content `flex: 999 1 560px; min-width:0`; wide tables
  inside `overflow-x:auto`; root `min-height:<H>px`. Fixed frames (phones 390x844, tablets, TVs 1920x1080, multi-phone
  boards): root fixed at exactly w x h px. `$preview` = the frame w/h.

## Shared shell for back-office web pages (use it, do not redraw a sidebar)
```html
<div style="display: flex; flex-wrap: wrap; min-height: 960px; background: #F5F6F8; font-family: Inter, system-ui, sans-serif; color: #101828; font-size: 14px; line-height: 1.45">
  <div style="flex: 1 1 248px; max-width: 280px; display: flex">
    <dc-import name="Sidebar" section="stock" sub="Inventory" user-name="Meena S." role="Storekeeper" hint-size="100%,960px"></dc-import>
  </div>
  <div style="flex: 999 1 560px; min-width: 0; display: flex; flex-direction: column">
    <dc-import name="Topbar" trail="Menu &amp; stock" page="Inventory" hint-size="100%,69px"></dc-import>
    <main style="padding: 28px 32px 40px; display: flex; flex-direction: column; gap: 24px; box-sizing: border-box; width: 100%; max-width: 1240px">…</main>
  </div>
</div>
```
Sidebar `section` ∈ dashboard | sales | stock | guests | displays | people | settings. `sub` = one of its items:
sales: POS billing, Orders & invoices, Bar tabs, Floor plan, Kitchen display · stock: Menu & products, Inventory,
Recipes & costing, Procurement · guests: Customers & bookings, Walk-in queue · displays: Display control, Campaigns ·
people: Users & roles, Staff & shifts, Accounting · settings: Outlets & devices, Tax, invoice & payments, Hardware,
Permissions, Themes & branding, Localisation, Subscription, Monitoring. (Write `&amp;` for & inside attributes.)
Platform/super-admin and support screens: draw their own simple dark ink sidebar instead (they are a different product area).
Screens that are documentation boards (several mini-screens side by side, phones, tablets, TVs, flows) do not use the shell.

## Tokens (use exactly)
- Ink 900 `#0B1220` (sidebar, dark surfaces, ink buttons) · page ground `#F5F6F8` · surface `#FFFFFF` · subtle fill `#F9FAFB`
- Borders `#E4E7EC` (cards), `#F2F4F7` (row dividers), `#D0D5DD` (inputs/secondary buttons)
- Text: primary `#101828`, headings `#0B1220`, secondary `#475467`, tertiary `#667085` (never lighter for text)
- Accent emerald `#0E7C66` (hover `#0A5F4E`, soft `#E7F4F0`, soft border `#A6E3D3`). Use ONLY for: the single primary
  action per area, active nav/tab, selected state, key chart series, links. Everything else neutral.
- Status (soft bg / strong text): success `#ECFDF3`/`#067647` · warning `#FFFAEB`/`#B54708` · danger `#FEF3F2`/`#B42318`
  (border `#FECDCA`, input error border `#FDA29B` + ring `0 0 0 4px #FEE4E2`) · info `#EFF8FF`/`#175CD3` ·
  neutral `#F2F4F7`/`#344054` · brass (happy hour, premium, "Pro") `#FBF3E4`/`#8A5A12`.
  Status dots: `#D92D20` red, `#F79009` amber, `#12B76A` green, `#2E90FA` blue.
- Dark mode (POS, KDS, TV, signage, kiosk dark): bg `#0A0F1A`, panel `#0E1524`, card `#151E30`, raised `#1A2438`,
  borders `#1C263A`/`#233049`/`#2B3A57`, text `#F2F4F7`, secondary `#A3ADC2`, tertiary `#8A94A6`, accent `#2FB896`
  with dark text `#04231C` on accent buttons, brass `#F5C46B` on `#2A2213`.
- Type: headings & big numbers `Manrope` (700/800, letter-spacing -0.02em); everything else `Inter`.
  Only these sizes: 12, 13, 14, 16, 20, 28 (40 for one hero number). Page title 28/700; card heading 16/700;
  body 14; secondary 13; captions/badges 12/500-600. ALL amounts/quantities/times: `font-variant-numeric: tabular-nums`,
  right-aligned in tables. Indian rupee formatting as in sources (₹1,84,320).
- Radius: 6 (chips/small), 10 (buttons/inputs), 16 (cards); pills 999. Shadows: cards
  `0 1px 2px rgba(16,24,40,.04)`; elevated/hero/drawer `0 1px 2px rgba(16,24,40,.04), 0 8px 24px -8px rgba(16,24,40,.08)`.
- Buttons 40px high (44–56 on touch): primary = emerald bg white text 600; ink = #0B1220 bg; secondary = white,
  1px #D0D5DD, text #344054 500; destructive = white, 1px #FDA29B, text #B42318. At most ONE primary per area.
- Cards: white, 1px #E4E7EC, radius 16, padding 20–24. KPI groups: one card split by #F2F4F7 dividers, one hero metric
  larger than the rest. Tables: header row bg #F9FAFB, 12px #475467 500 labels, rows 12–14px padding, #F2F4F7 dividers,
  selected row bg #F3FAF8 + inset 3px emerald left edge. Badges: pill, 12px 600, soft colours above. Tabs: underline,
  active = 600 #0B1220 + `box-shadow: inset 0 -2px 0 #0E7C66`. Segmented controls: #EAECF0 track, white selected pill.
- Avoid: gradients washes, coloured left-border cards, black pill buttons everywhere, more than one accent colour,
  heavy borders, all-caps headings (small caps labels 12px uppercase letter-spacing .06em are ok sparingly).

## When done
Reply with one line per file: `<File>.dc.html — WxH — done` (or the problem). Nothing else.
