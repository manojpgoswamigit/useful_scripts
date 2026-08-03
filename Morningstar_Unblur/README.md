# Morningstar Stock Unblurrer & Data Extractor

A set of scripts (Tampermonkey userscript & Playwright CLI automation) to unblur locked stock names, tickers, and badges on Morningstar investment lists (such as [Morningstar 5-Star Stocks](https://www.morningstar.com/best-investments/five-star-stocks)).

---

## How It Works

1. **CSS Unblur**: Morningstar applies `.mdc-locked-text--locked__mdc` and `.mdc-badge__label--locked__mdc` classes which render `filter: blur(4px)` and `color: transparent`.
2. **Data Recovery**: The server scrambles visual text into placeholders like `LOCK|...`, but populates the full dataset inside the initial Nuxt page state (`window.__NUXT__`). The un-scrambled stock name is stored in `fields.name.sortAs` (used for client-side table sorting).
3. **DOM Replacement**: The scripts extract `sortAs` from `window.__NUXT__`, strip the CSS blur filters, and replace scrambled text nodes with the real stock names in real time.

---

## Included Files

- `morningstar_unblur.user.js` – Tampermonkey / Violentmonkey userscript for automatic in-browser unblurring.
- `unblur_morningstar.js` – Playwright script to run via `@playwright/cli`.

---

## Installation & Usage

### Method 1: Tampermonkey / Violentmonkey Userscript (Recommended)

1. Install [Tampermonkey](https://www.tampermonkey.net/) or [Violentmonkey](https://violentmonkey.github.io/) in your browser.
2. Create a new script in Tampermonkey and paste the contents of [`morningstar_unblur.user.js`](file:///home/mpi/Documents/GitHub/useful_scripts/Morningstar_Unblur/morningstar_unblur.user.js).
3. Save the script (`Ctrl+S`).
4. Visit any Morningstar investment page (e.g., `https://www.morningstar.com/best-investments/five-star-stocks`). The table will automatically unblur as the page loads.

### Method 2: In-Browser DevTools Console

1. Open DevTools (`F12` -> Console tab) on the Morningstar page.
2. Copy and paste the script from `morningstar_unblur.user.js` directly into the console and press `Enter`.

### Method 3: Playwright CLI Automation

Run the script directly via Playwright CLI:

```bash
npx @playwright/cli open https://www.morningstar.com/best-investments/five-star-stocks
npx @playwright/cli run-code --filename=Morningstar_Unblur/unblur_morningstar.js
```
