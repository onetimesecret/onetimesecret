window.apxDns = {
    "init": function(config){
        if(!('api_url' in config)){
            config.api_url = "";
        }

        setTimeout(function(){ window.apxDns.renewToken(); }, 300000)
        window.apxDns.keepRenewingToken = true;

        if(!('widget_id' in config)){
            config.widget_id = 'apxdnswidget';
        }

        window.apxDns.config = config;
        if(!('domain' in config)){
            window.apxDns.showEnterDomain();
        }else{
            window.apxDns.domain = config.domain;
            window.apxDns.can_restart = false;
            window.apxDns.setDomain(config.domain);
        }
    },
    "stop": function(){
        document.getElementById(window.apxDns.config.widget_id).innerHTML = "";
        window.apxDns.keepRenewingToken = false;
        window.apxDns.domain = null;
        window.apxDns.can_restart = false;
        window.apxDns.temp_records = null;
        window.apxDns.config = null;

        const event = new CustomEvent('apx-dnswidget-stopped', {});
        document.dispatchEvent(event);
    },
    "renewToken": function(){
        if(window.apxDns.keepRenewingToken === true){
            fetch(window.apxDns.config.api_url + "/token/renew", {
                method: "POST",
                cache: "no-cache",
                headers: {
                "Content-Type": "application/json",
                },
                body: JSON.stringify({"token": window.apxDns.config.token}),
            }).then(function(resp){
                resp.json().then(function(data){
                    window.apxDns.config.token = data.token
                    setTimeout(function(){ window.apxDns.renewToken(); }, 300000)
                })
            });
        }
    },
    "showEnterDomain": function(domain, showSubdomain, subdomain){
        var widget = document.getElementById(window.apxDns.config.widget_id);
        widget.innerHTML = `
        <div class="apxdns-enter-domain-container">
            <form onsubmit="return window.apxDns.submitDomain(this)">
                <div class="apxdns-domain-container">
                    <div class="apxdns-domain-input-label">Enter a domain or subdomain</div>
                    <div class="apxdns-domain-tld-container">
                        <input type="text" name="apxdns-domain-input" required="true" placeholder="yourdomain.com" class="apxdns-domain-input">
                    </div>
                    <div class="apxdns-domain-explainer">For example: mydomain.com or app.mydomain.com</div>
                </div>
                <div class="apxdns-domain-button-container">
                    <button type="submit" class="apxdns-domain-submit apxdns-button">Continue</button>
                    <div class="apxdns-domain-loader apxdns-hide">
                        <div class="loader"></div>
                    </div>
                </div>
            </form>
        </div>
        `
        // [M-4] Assign the prefill value via the DOM property instead of
        // template interpolation so it can never break out of the attribute.
        var domain_input_el = widget.querySelector('.apxdns-domain-input');
        if(domain_input_el){
            domain_input_el.value = window.apxDns.config.prefillDomain || '';
        }
    },
    "submitDomain": function(form){;
        let data = new FormData(form);
        let domain_submit_btn_el = document.querySelector("#"+window.apxDns._cssEscape(window.apxDns.config.widget_id)+" .apxdns-domain-submit")

        let loader_el = document.querySelector("#"+window.apxDns._cssEscape(window.apxDns.config.widget_id)+" .apxdns-domain-loader")
        loader_el.classList.remove("apxdns-hide");
        domain_submit_btn_el.classList.add("apxdns-disable-btn");
        try {
            const event = new CustomEvent('apx-dnswidget-user-submitted-domain', {
                detail: data.get("apxdns-domain-input")
            });
            document.dispatchEvent(event);
            window.apxDns.setDomain(data.get("apxdns-domain-input"));
        } catch (e) {
            throw new Error(e.message);
        }
        loader_el.classList.remove("apxdns-hide");
        domain_submit_btn_el.classList.add("apxdns-disable-btn");
        window.apxDns.can_restart = true;
        return false; // cancels form action
    },
    "setDomain": function(domain){
        window.apxDns.domain = domain;
        window.apxDns.temp_records = window.apxDns.config.dnsRecords.map(function(record){
            var temp = window.apxDns.deepClone(record);
            if(!('domain' in temp)){
                temp.domain = window.apxDns.domain;
            }

            if(temp.value === "{domain}"){
                temp.value = window.apxDns.domain;
            }
            return temp;
        })

        fetch(window.apxDns.config.api_url + "/get-provider-instructions", {
            method: "POST",
            cache: "no-cache",
            headers: {
              "Content-Type": "application/json",
            },
            body: JSON.stringify({"records": window.apxDns.temp_records, "token": window.apxDns.config.token}),
          }).then(function(resp){
            resp.json().then(function(data){
                window.apxDns.renderProviderInstructions(data);
            })
          });
    },
    "restart": function(){
        const event = new CustomEvent('apx-dnswidget-restarted', {});
        document.dispatchEvent(event);
        window.apxDns.domain = null;
        window.apxDns.temp_records = null;
        this.showEnterDomain();
    },
    "renderProviderInstructions": function(data){
        var widget = document.getElementById(window.apxDns.config.widget_id);

        widget.innerHTML = '';

        if(window.apxDns.can_restart){
            widget.innerHTML = `
            <div class="apxdns-restart-section">
                <button class="apxdns-restart-btn apxdns-text-btn" type="button" onclick="window.apxDns.restart()">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M9 15 3 9m0 0 6-6M3 9h12a6 6 0 0 1 0 12h-3" />
                    </svg>
                    Go back
                </div>
            </div>
            `;
        }

        for(const key in data.domain_results){
            data.domain_results[key].steps.forEach(function(inst, index){
                // [M-4] API-supplied HTML is sanitized before DOM insertion.
                window.apxDns.insertSanitizedHtml(widget, inst.html);
            })
        }

        // [M-4] API-supplied HTML is sanitized before DOM insertion.
        window.apxDns.insertSanitizedHtml(widget, data.verify_section.html);
    },
    "showManualInstructions": function(dataApxId){
        // [M-4] Escape the id before interpolating it into the attribute
        // selector so a hostile value cannot break out of the selector.
        var manual_el = document.querySelector("[data-apxid='"+window.apxDns._cssEscape(dataApxId)+"']");
        if(manual_el){
            manual_el.classList.toggle('apxdns-hide');
        }
    },
    "verifyRecords": function(){
        let verify_btn_el = document.querySelector("#"+window.apxDns._cssEscape(window.apxDns.config.widget_id)+" .apxdns-verify-btn")
        if(verify_btn_el.classList.contains("apxdns-disable-btn")){
            return;
        }
        let loader_el = document.querySelector("#"+window.apxDns._cssEscape(window.apxDns.config.widget_id)+" .apxdns-verify-loader")
        loader_el.classList.remove("apxdns-hide");
        verify_btn_el.classList.add("apxdns-disable-btn");

        let match_array = window.apxDns.temp_records.map(function(record){
            return {
                "apex": record.apex,
                "tld": record.tld,
                "domain": record.domain,
                "host": record.host,
                "value": record.value,
                "match_against": record.value,
                "type": record.type.toLowerCase()
            };
        })

        fetch(window.apxDns.config.api_url + "/token/check-records-match-exactly", {
            method: "POST",
            cache: "no-cache",
            headers: {
              "Content-Type": "application/json",
            },
            body: JSON.stringify({"records": match_array, "token": window.apxDns.config.token})
        }).then(function(resp){
            resp.json().then(function(data){

                let partially_verified = data.records.some(function(item){ return item.match === true });
                let completely_verified = data.records.every(function(item){ return item.match === true });
                let event_name = 'apx-dnswidget-records-failed-verification';

                if(completely_verified === true){
                    event_name = 'apx-dnswidget-records-completely-verified'
                }else if(partially_verified === true){
                    event_name = 'apx-dnswidget-records-partially-verified'
                }

                const event = new CustomEvent(event_name, {
                    detail: data.records
                });
                document.dispatchEvent(event);


                var domain_records = {};
                data.records.forEach(function(record){
                    if(!domain_records[record.apex + "." + record.tld]){
                        domain_records[record.apex + "." +record.tld] = [];
                    }
                    domain_records[record.apex + "." + record.tld].push(record);
                });

                var verify_section = document.getElementById("apxdnswidget-verify-section");
                verify_section.innerHTML = "";

                Object.keys(domain_records).forEach(function(apex_domain){
                    verify_section.insertAdjacentHTML('beforeend', `
                    <div class="apxdns-verify-domain">Verify records for ${window.apxDns.escapeHtml(apex_domain)}</div>
                    `);


                    domain_records[apex_domain].forEach(function(record){
                        let actual_values_html = "";
                        if(record.actual_values != record.value){
                            actual_values_html = `
                            <div class="apxdns-verify-record-actual-values">
                                <div class="apxdns-record-actual-values-label">Actual value found:</div>
                                <textarea rows="1" class="apxdns-verify-record-actual-values-textarea">${window.apxDns.escapeHtml(record.actual_values || "No value set")}</textarea>
                            </div>
                            `
                        }

                        let verified = `
                            <div class="apxdns-verify-record-result-container-false">
                                False
                            </div>
                            `;
                        if(record.match === true){
                            verified = `
                            <div class="apxdns-verify-record-result-container-true">
                                True
                            </div>
                            `
                        }

                        verify_section.insertAdjacentHTML('beforeend', `
                        <div class="apxdns-verify-record apxdns-verify-record-is-${window.apxDns.escapeHtml(record.match)}">
                            <div class="apxdns-verify-record-slot">
                                <div class="apxdns-verify-record-type"><span class="apxdns-verify-record-label-span">Type:</span> ${window.apxDns.escapeHtml(record.type.toUpperCase())} record</div>
                                <div class="apxdns-verify-record-address"><span class="apxdns-verify-record-label-span">Host:</span> ${window.apxDns.escapeHtml(record.combined_host)}</div>
                                <div class="apxdns-verify-record-address"><span class="apxdns-verify-record-label-span">Value:</span> ${window.apxDns.escapeHtml(record.value)}</div>
                                <div class="apxdns-verify-record-match"><span class="apxdns-verify-record-label-span">Verified:</span> ${verified}</div>
                                ${actual_values_html}
                            </div>
                        </div>
                    `);
                    });
                })

                loader_el.classList.add("apxdns-hide");
                verify_btn_el.classList.remove("apxdns-disable-btn");
                if(window.apxDns.config.verifyAutoScroll !== false){
                    verify_section.scrollIntoView({block: "start", inline: "nearest", behavior: "smooth"});
                }
            })
        });
    },
    "copyInputText": function(input_el){
        input_el.select();
        input_el.setSelectionRange(0, 99999); // For mobile devices
        navigator.clipboard.writeText(input_el.value);
    },
    // ------------------------------------------------------------------
    // [M-4] Sanitization helpers. The Approximated API returns pre-built
    // HTML (per-provider instruction steps and the verify section). This
    // file is served as a classic script (loaded via <script src> from a
    // Vite `?url` asset import in useDnsWidget.ts), so it cannot use ES
    // imports (e.g. DOMPurify). The helpers below implement a strict,
    // self-contained allowlist sanitizer instead: allowlisted tags only,
    // no event-handler attributes (known-trusted onclick patterns are
    // converted to real listeners), and URL attributes restricted to the
    // same scheme allowlist used for DOMPurify in GlobalBroadcast.vue.
    // ------------------------------------------------------------------
    // FORM is deliberately absent: sanitizeHtmlToFragment unwraps forms so
    // API-supplied fragments keep their visible content but cannot submit
    // data anywhere (the widget's own domain-entry form is trusted template
    // markup that never passes through the sanitizer).
    "_APX_ALLOWED_TAGS": {
        A:1, ARTICLE:1, B:1, BLOCKQUOTE:1, BR:1, BUTTON:1, CAPTION:1,
        CIRCLE:1, CODE:1, DD:1, DIV:1, DL:1, DT:1, ELLIPSE:1, EM:1,
        FIELDSET:1, FOOTER:1, G:1, H1:1, H2:1, H3:1, H4:1, H5:1,
        H6:1, HEADER:1, HR:1, I:1, IMG:1, INPUT:1, LABEL:1, LEGEND:1,
        LI:1, LINE:1, OL:1, OPTION:1, P:1, PATH:1, POLYGON:1, POLYLINE:1,
        PRE:1, RECT:1, S:1, SECTION:1, SELECT:1, SMALL:1, SPAN:1,
        STRONG:1, SUB:1, SUP:1, SVG:1, TABLE:1, TBODY:1, TD:1, TEXTAREA:1,
        TFOOT:1, TH:1, THEAD:1, TR:1, U:1, UL:1
    },
    // Non-URL, non-event attributes that survive sanitization.
    "_APX_ALLOWED_ATTR": /^(?:class|id|type|value|placeholder|readonly|disabled|checked|selected|multiple|rows|cols|size|maxlength|minlength|required|name|alt|title|target|rel|for|style|tabindex|autocomplete|spellcheck|role|lang|dir|d|viewbox|preserveaspectratio|fill|fill-rule|clip-rule|stroke|stroke-width|stroke-linecap|stroke-linejoin|stroke-dasharray|cx|cy|r|rx|ry|x|y|x1|x2|y1|y2|points|transform|xmlns(?::[a-z]+)?|aria-[a-z-]+|data-[\w.:-]+)$/,
    // Mirrors the restrictive ALLOWED_URI_REGEXP used with DOMPurify in
    // GlobalBroadcast.vue: https?/mailto, relative paths and fragments.
    // Blocks javascript:, data:, vbscript:, etc. NOTE: this regex alone
    // misclassifies protocol-relative URLs ("//host") as relative paths;
    // _APX_PROTOCOL_RELATIVE below is checked first to reject them.
    "_APX_ALLOWED_URI": /^(?:(?:https?|mailto):|[^a-z]|[a-z+.-]+(?:[^a-z+.:-]|$))/i,
    // Protocol-relative URLs (//host, and \\ or /\ variants — browsers
    // normalize backslashes to slashes) inherit the page scheme but
    // navigate cross-origin, so they are rejected outright.
    "_APX_PROTOCOL_RELATIVE": /^[\\/][\\/]/,
    // Control/whitespace characters stripped before URI validation so
    // "java\nscript:" style smuggling cannot bypass the scheme check.
    "_APX_ATTR_WHITESPACE": /[\u0000-\u0020\u00A0\u1680\u180E\u2000-\u2029\u205F\u3000]/g,
    "escapeHtml": function(value){
        return String(value === null || value === undefined ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    },
    "_cssEscape": function(value){
        var str = String(value === null || value === undefined ? '' : value);
        if(window.CSS && typeof window.CSS.escape === 'function'){
            return window.CSS.escape(str);
        }
        // Fallback: hex-escape everything outside the identifier-safe set.
        return str.replace(/[^a-zA-Z0-9_-]/g, function(ch){
            return '\\' + ch.charCodeAt(0).toString(16) + ' ';
        });
    },
    // Compile a known-trusted inline onclick value into a real listener.
    // Only exact calls into the widget's own public API compile; anything
    // else returns null and the attribute is simply dropped.
    "_compileTrustedHandler": function(value){
        if(typeof value !== 'string'){
            return null;
        }
        var v = value.trim().replace(/;\s*$/, '').trim();
        var m = v.match(/^(?:return\s+)?window\.apxDns\.(verifyRecords|restart)\(\s*\)$/);
        if(m){
            var method = m[1];
            return function(){ window.apxDns[method](); };
        }
        m = v.match(/^(?:return\s+)?window\.apxDns\.showManualInstructions\(\s*(['"])([A-Za-z0-9_.:-]{0,128})\1\s*\)$/);
        if(m){
            var apxid = m[2];
            return function(){ window.apxDns.showManualInstructions(apxid); };
        }
        m = v.match(/^(?:return\s+)?window\.apxDns\.copyInputText\(\s*(this(?:\.(?:parentElement|parentNode|previousElementSibling|nextElementSibling|firstElementChild|lastElementChild)|\.querySelector\(\s*(['"])[A-Za-z0-9_ .#>:()-]{0,128}\2\s*\))*)\s*\)$/);
        if(m){
            var chain = m[1];
            return function(){
                var target = window.apxDns._resolveElementChain(this, chain);
                if(target){
                    window.apxDns.copyInputText(target);
                }
            };
        }
        return null;
    },
    // Interpret a validated `this.<prop>...` chain without eval, so the
    // compiled copy-button handlers work under a nonce-only CSP.
    "_resolveElementChain": function(start, expr){
        var rest = expr.slice(4); // drop leading "this"
        var node = start;
        var m;
        while(rest.length > 0 && node){
            m = rest.match(/^\.(parentElement|parentNode|previousElementSibling|nextElementSibling|firstElementChild|lastElementChild)/);
            if(m){
                node = node[m[1]];
                rest = rest.slice(m[0].length);
                continue;
            }
            // Defense in depth: re-enforce the compile-time selector
            // allowlist (same character set and 128-char cap as
            // _compileTrustedHandler) so the two parsers cannot drift.
            m = rest.match(/^\.querySelector\(\s*(['"])([A-Za-z0-9_ .#>:()-]{0,128})\1\s*\)/);
            if(m){
                node = node.querySelector(m[2]);
                rest = rest.slice(m[0].length);
                continue;
            }
            return null;
        }
        if(!node || node.nodeType !== 1){
            return null;
        }
        // Containment: the resolved element must live inside the widget
        // container. Legitimate copy-button chains only reach sibling
        // inputs within the widget's own markup; a chain that climbs out
        // of the widget (e.g. to copy unrelated page content such as a
        // token from an adjacent panel) resolves to null.
        var config = window.apxDns.config;
        var root = (config && config.widget_id) ? document.getElementById(config.widget_id) : null;
        if(!root || !root.contains(node)){
            return null;
        }
        return node;
    },
    "_sanitizeAttributes": function(el){
        var attrs = Array.prototype.slice.call(el.attributes);
        for(var i = 0; i < attrs.length; i++){
            var name = attrs[i].name.toLowerCase();
            var rawValue = attrs[i].value;
            if(name === 'onclick'){
                var handler = window.apxDns._compileTrustedHandler(rawValue);
                if(handler){
                    el.addEventListener('click', handler);
                }
                el.removeAttribute(attrs[i].name);
                continue;
            }
            if(name.indexOf('on') === 0){
                el.removeAttribute(attrs[i].name);
                continue;
            }
            // Form-submission attributes are dropped unconditionally:
            // FORM elements are unwrapped by sanitizeHtmlToFragment, and
            // no surviving element may point a submission anywhere.
            if(name === 'srcdoc' || name === 'formaction' || name === 'action' || name === 'ping' || name === 'background'){
                el.removeAttribute(attrs[i].name);
                continue;
            }
            if(name === 'href' || name === 'src' || name === 'xlink:href'){
                var normalized = rawValue.replace(window.apxDns._APX_ATTR_WHITESPACE, '');
                if(window.apxDns._APX_PROTOCOL_RELATIVE.test(normalized) ||
                   !window.apxDns._APX_ALLOWED_URI.test(normalized)){
                    el.removeAttribute(attrs[i].name);
                }
                continue;
            }
            if(!window.apxDns._APX_ALLOWED_ATTR.test(name)){
                el.removeAttribute(attrs[i].name);
            }
        }
        // Harden anchors the same way GlobalBroadcast.vue does: only
        // target="_blank" survives, and it always carries noopener.
        if(el.tagName === 'A'){
            var target = el.getAttribute('target');
            if(target !== null && target !== '_blank'){
                el.removeAttribute('target');
            }
            if(el.getAttribute('target') === '_blank'){
                el.setAttribute('rel', 'noopener noreferrer');
            }
        }
    },
    "sanitizeHtmlToFragment": function(html){
        var template = document.createElement('template');
        template.innerHTML = (html === null || html === undefined) ? '' : String(html);
        var elements = template.content.querySelectorAll('*');
        for(var i = 0; i < elements.length; i++){
            var el = elements[i];
            if(!template.content.contains(el)){
                continue; // already removed with a disallowed ancestor
            }
            var tag = el.tagName.toUpperCase();
            if(tag === 'FORM'){
                // Form-submission primitive: unwrap. Children are kept
                // (and sanitized in later iterations) but with no FORM
                // ancestor — and with action/formaction stripped and the
                // `form` attribute outside _APX_ALLOWED_ATTR — nothing in
                // a sanitized fragment can submit data anywhere.
                while(el.firstChild){
                    el.parentNode.insertBefore(el.firstChild, el);
                }
                el.parentNode.removeChild(el);
                continue;
            }
            if(!window.apxDns._APX_ALLOWED_TAGS[tag]){
                el.parentNode.removeChild(el);
                continue;
            }
            window.apxDns._sanitizeAttributes(el);
        }
        return template.content;
    },
    "insertSanitizedHtml": function(parent, html){
        parent.appendChild(window.apxDns.sanitizeHtmlToFragment(html));
    },
    "deepClone": function(obj, hash = new WeakMap()) {
        // Handle primitives and functions
        if (obj === null || typeof obj !== 'object') {
            return obj;
        }

        // Handle circular references
        if (hash.has(obj)) {
            return hash.get(obj);
        }

        // Handle different types of objects
        // Date
        if (obj instanceof Date) {
            return new Date(obj);
        }
        // RegExp
        if (obj instanceof RegExp) {
            return new RegExp(obj.source, obj.flags);
        }
        // Map
        if (obj instanceof Map) {
            const clonedMap = new Map();
            hash.set(obj, clonedMap);
            obj.forEach((value, key) => {
                clonedMap.set(
                    window.apxDns.deepClone(key, hash),
                    window.apxDns.deepClone(value, hash)
                );
            });
            return clonedMap;
        }
        // Set
        if (obj instanceof Set) {
            const clonedSet = new Set();
            hash.set(obj, clonedSet);
            obj.forEach(value => {
                clonedSet.add(window.apxDns.deepClone(value, hash));
            });
            return clonedSet;
        }
        // ArrayBuffer
        if (obj instanceof ArrayBuffer) {
            const clonedBuffer = obj.slice(0);
            hash.set(obj, clonedBuffer);
            return clonedBuffer;
        }
        // TypedArrays
        if (ArrayBuffer.isView(obj)) {
            const clonedView = new obj.constructor(
                obj.buffer.slice(0),
                obj.byteOffset,
                obj.length
            );
            hash.set(obj, clonedView);
            return clonedView;
        }
        // Array
        if (Array.isArray(obj)) {
            const clonedArr = [];
            hash.set(obj, clonedArr);
            clonedArr.push(...obj.map(item => window.apxDns.deepClone(item, hash)));
            return clonedArr;
        }

        // Handle plain objects
        const clonedObj = Object.create(Object.getPrototypeOf(obj));
        hash.set(obj, clonedObj);

        // Clone own properties
        const descriptors = Object.getOwnPropertyDescriptors(obj);
        for (const [key, descriptor] of Object.entries(descriptors)) {
            if (typeof descriptor.value === 'object' && descriptor.value !== null) {
                descriptor.value = window.apxDns.deepClone(descriptor.value, hash);
            }
            Object.defineProperty(clonedObj, key, descriptor);
        }

        return clonedObj;
    }
}
