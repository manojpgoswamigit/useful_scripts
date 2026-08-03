// ==UserScript==
// @name         Morningstar Stock Unblurrer, Interactive Pager & Table Column Sort
// @namespace    https://github.com/manojpgoswamigit/useful_scripts
// @version      1.0.6
// @description  Automatically unblurs locked stock names, resolves real tickers, links to Yahoo Finance, unlocks page navigation, and enables interactive table column sorting on Morningstar.
// @author       Antigravity
// @match        https://www.morningstar.com/*
// @grant        none
// @run-at       document-idle
// ==/UserScript==

(function () {
    'use strict';

    // In-memory ticker cache
    const tickerCache = new Map();

    // Sort State
    let currentSortColumn = null;
    let currentSortDirection = 'asc';

    const uncertaintyRank = { 'Low': 1, 'Medium': 2, 'High': 3, 'Very High': 4, 'Extreme': 5 };

    /**
     * Convert lowercase/uppercase string to Title Case
     */
    function toTitleCase(str) {
        if (!str) return str;
        const minorWords = new Set(['a', 'an', 'the', 'and', 'but', 'or', 'for', 'nor', 'on', 'at', 'to', 'from', 'by', 'of', 'in', 'with', 'inc', 'corp', 'ltd', 'plc', 'adr', 'ag', 'nv', 'class']);
        return str.toLowerCase().split(' ').map((word, idx, arr) => {
            if (word.length === 0) return '';
            if (word === 'plc' || word === 'adr' || word === 'nv' || word === 'ag' || word === 'ltd' || word === 'inc' || word === 'corp') {
                return word.toUpperCase();
            }
            if (idx > 0 && idx < arr.length - 1 && minorWords.has(word)) {
                return word;
            }
            return word.charAt(0).toUpperCase() + word.slice(1);
        }).join(' ');
    }

    /**
     * Fetch real ticker symbol using Morningstar Official Search API
     */
    async function resolveRealTicker(rawCompany) {
        if (!rawCompany) return null;
        const key = rawCompany.toLowerCase().trim();
        
        if (tickerCache.has(key)) {
            return tickerCache.get(key);
        }

        try {
            const url = 'https://www.morningstar.com/api/v2/stores/search/nav?q=' + encodeURIComponent(key);
            const res = await fetch(url);
            const json = await res.json();
            const ticker = json?.entities?.[0]?.value?.ticker;

            if (ticker) {
                tickerCache.set(key, ticker);
                return ticker;
            }
        } catch (e) {
            console.error('Failed to resolve ticker for:', rawCompany, e);
        }
        return null;
    }

    /**
     * Extract property value from stock item for sorting
     */
    function getFieldValue(item, fieldKey) {
        const fields = item?.fields || {};
        switch (fieldKey) {
            case 'name':
                return (fields.name?.sortAs || fields.name?.value || '').toLowerCase();
            case 'sector':
                return (fields.sector?.value || '').toLowerCase();
            case 'starRating':
                return fields.stockStarRating?.value || 0;
            case 'fairValue':
                return fields.fairValue?.value || 0;
            case 'uncertainty':
                return uncertaintyRank[fields.fairValueUncertainty?.value] || 0;
            case 'return1Yr':
                return fields['totalReturn[1y]']?.value ?? -9999;
            case 'dividendYield':
                return fields['dividendYield[forward]']?.value ?? -9999;
            case 'marketCap':
                return fields.marketCap?.value || 0;
            default:
                return 0;
        }
    }

    /**
     * Safely locate active page results array from Vue Component or window.__NUXT__
     */
    function getActiveResults() {
        const nav = document.querySelector('.mdc-pager__mdc');
        if (nav && nav.__vue__) {
            let curr = nav.__vue__;
            while (curr && !curr.results) {
                curr = curr.$parent;
            }
            if (curr && Array.isArray(curr.results)) {
                return curr.results;
            }
        }

        if (!window.__NUXT__) return null;

        if (Array.isArray(window.__NUXT__.data)) {
            const found = window.__NUXT__.data.find(d => d && Array.isArray(d.results));
            if (found) return found.results;
        }

        const search = (obj, depth = 0) => {
            if (!obj || depth > 5) return null;
            if (Array.isArray(obj)) {
                for (let item of obj) {
                    const r = search(item, depth + 1);
                    if (r) return r;
                }
            } else if (typeof obj === 'object') {
                if (Array.isArray(obj.results)) return obj.results;
                for (let k of Object.keys(obj)) {
                    try {
                        const r = search(obj[k], depth + 1);
                        if (r) return r;
                    } catch (e) {}
                }
            }
            return null;
        };

        return search(window.__NUXT__);
    }

    /**
     * Clear unblurred flags when switching pages or sorting
     */
    function resetUnblurredFlags() {
        const els = document.querySelectorAll('[data-unblurred], [data-ticker-resolved]');
        els.forEach(el => {
            el.removeAttribute('data-unblurred');
            el.removeAttribute('data-ticker-resolved');
        });
    }

    /**
     * Enable interactive column header click sorting
     */
    function enableTableSorting() {
        const table = document.querySelector('table');
        if (!table) return;

        const headers = table.querySelectorAll('thead th');
        const fieldMapping = [
            null,               // 0: Checkbox tag column
            'name',             // 1: Name
            'sector',           // 2: Sector
            'starRating',       // 3: Morningstar Rating for Stocks
            'fairValue',        // 4: Fair Value
            'uncertainty',      // 5: Fair Value Uncertainty
            'return1Yr',        // 6: Total Return 1 Year
            'dividendYield',    // 7: Dividend Yield Forward
            'marketCap'         // 8: Market Cap
        ];

        headers.forEach((th, colIdx) => {
            const fieldKey = fieldMapping[colIdx];
            if (!fieldKey) return;

            th.style.cursor = 'pointer';
            th.style.userSelect = 'none';
            th.title = 'Click to sort table by this column';

            if (!th.hasAttribute('data-sort-listener')) {
                th.setAttribute('data-sort-listener', 'true');

                th.addEventListener('click', () => {
                    // Determine direction
                    if (currentSortColumn === fieldKey) {
                        currentSortDirection = currentSortDirection === 'asc' ? 'desc' : 'asc';
                    } else {
                        currentSortColumn = fieldKey;
                        currentSortDirection = 'asc';
                    }

                    // Sort Vue results
                    const results = getActiveResults();
                    if (results && Array.isArray(results)) {
                        const mult = currentSortDirection === 'asc' ? 1 : -1;
                        results.sort((a, b) => {
                            const valA = getFieldValue(a, fieldKey);
                            const valB = getFieldValue(b, fieldKey);
                            if (typeof valA === 'string') {
                                return valA.localeCompare(valB) * mult;
                            }
                            return (valA - valB) * mult;
                        });
                    }

                    // Update Header Sort Icons
                    headers.forEach((h, idx) => {
                        const oldIcon = h.querySelector('.sort-indicator');
                        if (oldIcon) oldIcon.remove();

                        const key = fieldMapping[idx];
                        if (key && key === currentSortColumn) {
                            const span = document.createElement('span');
                            span.className = 'sort-indicator';
                            span.style.marginLeft = '4px';
                            span.style.fontSize = '11px';
                            span.style.fontWeight = 'bold';
                            span.textContent = currentSortDirection === 'asc' ? ' ▲' : ' ▼';
                            h.appendChild(span);
                        }
                    });

                    resetUnblurredFlags();
                    safeScheduleUnblur();
                });
            }
        });
    }

    /**
     * Enable disabled navigation dropdowns and Prev/Next buttons
     */
    function enablePaginationControls() {
        const navs = document.querySelectorAll('.mdc-pager__mdc, nav[class*="pager"]');
        navs.forEach(nav => {
            if (nav.__vue__ && nav.__vue__.disabled) {
                nav.__vue__.disabled = false;
            }

            const select = nav.querySelector('select');
            if (select) {
                if (select.hasAttribute('disabled')) {
                    select.removeAttribute('disabled');
                }
                if (!select.hasAttribute('data-pager-listener')) {
                    select.setAttribute('data-pager-listener', 'true');
                    select.addEventListener('change', (e) => {
                        const pageNum = parseInt(e.target.value, 10);
                        if (nav.__vue__ && typeof nav.__vue__.onChange === 'function') {
                            nav.__vue__.onChange(pageNum);
                        }
                        resetUnblurredFlags();
                        safeScheduleUnblur();
                    });
                }
            }

            const buttons = nav.querySelectorAll('button');
            buttons.forEach(btn => {
                const isNext = btn.getAttribute('aria-label')?.includes('Next') || btn.textContent.includes('Next');
                const isPrev = btn.getAttribute('aria-label')?.includes('Prev') || btn.textContent.includes('Prev');

                if (btn.hasAttribute('disabled')) {
                    btn.removeAttribute('disabled');
                }

                if (!btn.hasAttribute('data-pager-listener')) {
                    btn.setAttribute('data-pager-listener', 'true');
                    btn.addEventListener('click', () => {
                        if (nav.__vue__) {
                            if (isNext && typeof nav.__vue__.onNext === 'function') {
                                nav.__vue__.onNext();
                            } else if (isPrev && typeof nav.__vue__.onPrev === 'function') {
                                nav.__vue__.onPrev();
                            }
                        }
                        resetUnblurredFlags();
                        safeScheduleUnblur();
                    });
                }
            });
        });
    }

    let isProcessing = false;

    /**
     * Unblur, resolve ticker, link to Yahoo Finance, and update table DOM
     */
    function unblurTable() {
        enablePaginationControls();
        enableTableSorting();

        if (isProcessing) return;
        isProcessing = true;

        try {
            const results = getActiveResults();
            if (!results || results.length === 0) return;

            const tbody = document.querySelector('tbody');
            if (!tbody) return;

            const rows = tbody.querySelectorAll('tr');
            results.forEach((r, idx) => {
                const tr = rows[idx];
                if (!tr) return;

                const th = tr.querySelector('th');
                if (!th) return;

                const rawSortName = r.fields?.name?.sortAs;
                if (!rawSortName || rawSortName.startsWith('LOCK|')) {
                    return;
                }

                const realName = toTitleCase(rawSortName);

                // 1. Unblur Name element
                const nameEl = th.querySelector('.mdc-locked-text__mdc, [data-nosnippet]');
                if (nameEl && nameEl.getAttribute('data-unblurred') !== 'true') {
                    nameEl.textContent = realName;
                    nameEl.classList.remove('mdc-locked-text--locked__mdc');
                    nameEl.style.filter = 'none';
                    nameEl.style.color = 'inherit';
                    nameEl.style.opacity = '1';
                    nameEl.style.textShadow = 'none';
                    nameEl.setAttribute('data-unblurred', 'true');
                }

                // 2. Resolve Ticker & attach Yahoo Finance Hyperlink
                const badgeEl = th.querySelector('.mdc-badge__label--locked__mdc, .mdc-badge__label__mdc span');
                const processTickerAndLink = (ticker) => {
                    if (!ticker || ticker === 'N/A') return;

                    if (badgeEl) {
                        badgeEl.textContent = ticker;
                        badgeEl.classList.remove('mdc-badge__label--locked__mdc');
                        badgeEl.style.filter = 'none';
                        badgeEl.style.color = 'inherit';
                        badgeEl.style.textShadow = 'none';
                        badgeEl.setAttribute('data-ticker-resolved', 'true');
                    }

                    const yahooUrl = `https://finance.yahoo.com/quote/${encodeURIComponent(ticker)}`;
                    let linkEl = th.querySelector('a');

                    if (!linkEl && nameEl && nameEl.parentNode) {
                        linkEl = document.createElement('a');
                        linkEl.style.color = 'inherit';
                        linkEl.style.textDecoration = 'none';
                        nameEl.parentNode.replaceChild(linkEl, nameEl);
                        linkEl.appendChild(nameEl);
                    }

                    if (linkEl) {
                        linkEl.href = yahooUrl;
                        linkEl.target = '_blank';
                        linkEl.rel = 'noopener noreferrer';
                        linkEl.title = `View ${ticker} on Yahoo Finance`;
                    }
                };

                if (badgeEl && badgeEl.getAttribute('data-ticker-resolved') !== 'true') {
                    const isAlreadyUnlocked = !r.fields?.ticker?.locked && r.fields?.ticker?.value;
                    if (isAlreadyUnlocked) {
                        processTickerAndLink(r.fields.ticker.value);
                    } else {
                        resolveRealTicker(rawSortName).then(realTicker => {
                            if (realTicker) {
                                processTickerAndLink(realTicker);
                            }
                        });
                    }
                }
            });
        } finally {
            isProcessing = false;
        }
    }

    // Debounce runner
    let debounceTimer = null;
    function safeScheduleUnblur() {
        if (debounceTimer) clearTimeout(debounceTimer);
        debounceTimer = setTimeout(unblurTable, 150);
    }

    // Initial runs
    safeScheduleUnblur();
    setTimeout(safeScheduleUnblur, 600);
    setTimeout(safeScheduleUnblur, 1500);

    // Watch for dynamic DOM changes (e.g. pagination or tab switches)
    const observer = new MutationObserver((mutations) => {
        let shouldTrigger = false;
        for (let mutation of mutations) {
            const target = mutation.target;
            if (target && target.nodeType === 1 && !target.hasAttribute('data-unblurred')) {
                shouldTrigger = true;
                break;
            }
        }
        if (shouldTrigger) {
            safeScheduleUnblur();
        }
    });

    const targetNode = document.querySelector('main') || document.body;
    if (targetNode) {
        observer.observe(targetNode, { childList: true, subtree: true });
    }

})();
