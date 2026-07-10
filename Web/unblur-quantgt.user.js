// ==UserScript==
// @name         QuantGT Unblur Tool
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  Unblurs blurred picks on QuantGT (https://quantgt.io/quantgt-picks) and makes them selectable.
// @author       Antigravity
// @match        https://quantgt.io/*
// @match        https://*.quantgt.io/*
// @icon         https://www.google.com/s2/favicons?sz=64&domain=quantgt.io
// @grant        none
// @run-at       document-start
// ==/UserScript==

(function() {
    'use strict';

    // 1. Inject CSS immediately to prevent flickering before the DOM fully parses.
    const style = document.createElement('style');
    style.id = 'quantgt-unblur-styles';
    style.innerHTML = `
        /* Force remove blur filter on all Tailwind utility classes targeting blur */
        [class*="blur-"], .blur-\\[3px\\] {
            filter: none !important;
            --tw-blur: none !important;
        }
        /* Make text selectable again */
        .select-none {
            user-select: auto !important;
            -webkit-user-select: auto !important;
            -moz-user-select: auto !important;
            -ms-user-select: auto !important;
        }
    `;
    
    // Inject style tag as early as possible
    if (document.documentElement) {
        document.documentElement.appendChild(style);
    } else {
        document.addEventListener('DOMContentLoaded', () => {
            document.documentElement.appendChild(style);
        });
    }

    // 2. JavaScript DOM processor to physically clean classes, as requested,
    // converting 'blur-[3px]' to 'blur-0' (or removing blur classes) and removing 'select-none'.
    function cleanElements() {
        const elements = document.querySelectorAll('[class*="blur-"], .select-none');
        elements.forEach(el => {
            // Find and modify blur classes
            for (let i = 0; i < el.classList.length; i++) {
                const cls = el.classList[i];
                if (cls.startsWith('blur-') && cls !== 'blur-0') {
                    // Replace class with blur-0 as requested by the user
                    el.classList.replace(cls, 'blur-0');
                }
            }
            // Remove select-none class
            if (el.classList.contains('select-none')) {
                el.classList.remove('select-none');
            }
        });
    }

    // Run clean on DOMContentLoaded
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', cleanElements);
    } else {
        cleanElements();
    }

    // 3. Setup a MutationObserver to handle dynamic content loads, paging, or scrolling
    const observer = new MutationObserver((mutations) => {
        cleanElements();
    });

    // Start observing when document element is ready
    const startObserver = () => {
        observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['class']
        });
    };

    if (document.documentElement) {
        startObserver();
    } else {
        document.addEventListener('DOMContentLoaded', startObserver);
    }
})();
