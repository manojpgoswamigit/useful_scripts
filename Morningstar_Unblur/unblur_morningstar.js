async (page) => {
    console.log('Navigating to Morningstar Best Investments...');
    await page.goto('https://www.morningstar.com/best-investments/five-star-stocks', { waitUntil: 'domcontentloaded' });

    // Wait for Nuxt state object
    await page.waitForFunction(() => window.__NUXT__);

    console.log('Extracting, unblurring, and enabling interactive column sorting...');

    const allExtractedStocks = await page.evaluate(async () => {
        const toTitleCase = (str) => {
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
        };

        const tickerCache = new Map();
        const resolveRealTicker = async (rawCompany) => {
            if (!rawCompany) return 'N/A';
            const key = rawCompany.toLowerCase().trim();
            if (tickerCache.has(key)) return tickerCache.get(key);

            try {
                const res = await fetch('https://www.morningstar.com/api/v2/stores/search/nav?q=' + encodeURIComponent(key));
                const json = await res.json();
                const ticker = json?.entities?.[0]?.value?.ticker;
                if (ticker) {
                    tickerCache.set(key, ticker);
                    return ticker;
                }
            } catch (e) {}
            return 'N/A';
        };

        const nav = document.querySelector('.mdc-pager__mdc');
        if (nav && nav.__vue__) {
            nav.__vue__.disabled = false;
        }

        let listVue = nav && nav.__vue__ ? nav.__vue__ : null;
        while (listVue && !listVue.results) listVue = listVue.$parent;

        const totalPages = listVue?.pages?.length || 1;
        const allRows = [];

        for (let p = 1; p <= totalPages; p++) {
            if (nav && nav.__vue__ && typeof nav.__vue__.onChange === 'function') {
                nav.__vue__.onChange(p);
            }

            await new Promise(res => setTimeout(res, 300));

            const results = listVue?.results || [];
            for (let idx = 0; idx < results.length; idx++) {
                const r = results[idx];
                const fields = r.fields || {};
                const rawSortName = fields.name?.sortAs;
                
                let realName = fields.name?.value || 'N/A';
                if (rawSortName && !rawSortName.startsWith('LOCK|')) {
                    realName = toTitleCase(rawSortName);
                }

                let realTicker = fields.ticker?.value || r.meta?.ticker || 'N/A';
                if (fields.ticker?.locked && rawSortName) {
                    realTicker = await resolveRealTicker(rawSortName);
                }

                const yahooUrl = realTicker !== 'N/A' ? `https://finance.yahoo.com/quote/${encodeURIComponent(realTicker)}` : 'N/A';

                allRows.push({
                    page: p,
                    row: allRows.length + 1,
                    ticker: realTicker,
                    name: realName,
                    yahooUrl: yahooUrl,
                    sector: fields.sector?.value || 'N/A',
                    starRating: fields.stockStarRating?.value || 'N/A',
                    fairValueNum: fields.fairValue?.value || 0,
                    fairValue: fields.fairValue?.value ? `$${fields.fairValue.value}` : 'N/A',
                    uncertainty: fields.fairValueUncertainty?.value || 'N/A',
                    return1Yr: fields['totalReturn[1y]']?.value !== undefined 
                        ? `${fields['totalReturn[1y]'].value.toFixed(2)}%` 
                        : 'N/A',
                    dividendYield: fields['dividendYield[forward]']?.value !== undefined 
                        ? `${fields['dividendYield[forward]'].value.toFixed(2)}%` 
                        : 'N/A',
                    marketCapNum: fields.marketCap?.value || 0,
                    marketCap: fields.marketCap?.value ? `$${(fields.marketCap.value / 1e9).toFixed(1)}B` : 'N/A'
                });
            }
        }

        if (nav && nav.__vue__ && typeof nav.__vue__.onChange === 'function') {
            nav.__vue__.onChange(1);
        }

        return allRows;
    });

    console.log(`\n===============================================================`);
    console.log(`SUCCESSFULLY EXTRACTED ${allExtractedStocks.length} STOCKS ACROSS ALL PAGES`);
    console.log(`===============================================================\n`);

    console.table(allExtractedStocks.slice(0, 15));

    // Enable interactive sorting and unblur Page 1 in browser DOM
    await page.evaluate(async () => {
        const toTitleCase = (str) => {
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
        };

        const nav = document.querySelector('.mdc-pager__mdc');
        if (nav && nav.__vue__) nav.__vue__.disabled = false;

        const select = nav ? nav.querySelector('select') : null;
        if (select) select.removeAttribute('disabled');
        const btns = nav ? nav.querySelectorAll('button') : [];
        btns.forEach(b => b.removeAttribute('disabled'));

        let listVue = nav && nav.__vue__ ? nav.__vue__ : null;
        while (listVue && !listVue.results) listVue = listVue.$parent;

        const results = listVue?.results || [];
        const tbody = document.querySelector('tbody');
        if (!tbody) return;

        const rows = tbody.querySelectorAll('tr');
        await Promise.all(results.map(async (r, idx) => {
            const tr = rows[idx];
            if (!tr) return;

            const th = tr.querySelector('th');
            if (!th) return;

            const rawSortName = r.fields?.name?.sortAs;
            if (!rawSortName || rawSortName.startsWith('LOCK|')) return;

            const realName = toTitleCase(rawSortName);

            // Unblur Name
            const nameEl = th.querySelector('.mdc-locked-text__mdc, [data-nosnippet]');
            if (nameEl) {
                nameEl.textContent = realName;
                nameEl.classList.remove('mdc-locked-text--locked__mdc');
                nameEl.style.filter = 'none';
                nameEl.style.color = 'inherit';
                nameEl.setAttribute('data-unblurred', 'true');
            }

            // Unblur Ticker & attach Yahoo Finance Link
            const badgeEl = th.querySelector('.mdc-badge__label--locked__mdc, .mdc-badge__label__mdc span');
            let realTicker = r.fields?.ticker?.value || 'N/A';
            if (r.fields?.ticker?.locked) {
                try {
                    const res = await fetch('https://www.morningstar.com/api/v2/stores/search/nav?q=' + encodeURIComponent(rawSortName));
                    const data = await res.json();
                    realTicker = data?.entities?.[0]?.value?.ticker || realTicker;
                } catch (e) {}
            }

            if (badgeEl) {
                badgeEl.textContent = realTicker;
                badgeEl.classList.remove('mdc-badge__label--locked__mdc');
                badgeEl.style.filter = 'none';
                badgeEl.style.color = 'inherit';
            }

            // Create / update Yahoo Finance hyperlink on stock name
            if (realTicker && realTicker !== 'N/A') {
                const yahooUrl = `https://finance.yahoo.com/quote/${encodeURIComponent(realTicker)}`;
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
                    linkEl.title = `View ${realTicker} on Yahoo Finance`;
                }
            }
        }));
    });

    console.log('\nWebpage DOM successfully unblurred, interactive column header click sorting enabled, and Yahoo Finance hyperlinks attached!');
}
