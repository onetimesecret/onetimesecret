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
                        <input type="text" name="apxdns-domain-input" required="true" placeholder="yourdomain.com" value="${apxDns.config.prefillDomain || ''}" class="apxdns-domain-input">
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
    },
    "submitDomain": function(form){;
        let data = new FormData(form);
        let domain_submit_btn_el = document.querySelector("#"+window.apxDns.config.widget_id+" .apxdns-domain-submit")

        let loader_el = document.querySelector("#"+window.apxDns.config.widget_id+" .apxdns-domain-loader")
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
                widget.insertAdjacentHTML('beforeend', inst.html);
            })
        }

        widget.insertAdjacentHTML('beforeend', data.verify_section.html);
    },
    "showManualInstructions": function(dataApxId){
        document.querySelector("[data-apxid='"+dataApxId+"']").classList.toggle('apxdns-hide');
    },
    "verifyRecords": function(){
        let verify_btn_el = document.querySelector("#"+window.apxDns.config.widget_id+" .apxdns-verify-btn")
        if(verify_btn_el.classList.contains("apxdns-disable-btn")){
            return;
        }
        let loader_el = document.querySelector("#"+window.apxDns.config.widget_id+" .apxdns-verify-loader")
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
                    <div class="apxdns-verify-domain">Verify records for ${apex_domain}</div>
                    `);


                    domain_records[apex_domain].forEach(function(record){
                        let actual_values_html = "";
                        if(record.actual_values != record.value){
                            actual_values_html = `
                            <div class="apxdns-verify-record-actual-values">
                                <div class="apxdns-record-actual-values-label">Actual value found:</div>
                                <textarea rows="1" class="apxdns-verify-record-actual-values-textarea">${record.actual_values || "No value set"}</textarea>
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
                        <div class="apxdns-verify-record apxdns-verify-record-is-${record.match}">
                            <div class="apxdns-verify-record-slot">
                                <div class="apxdns-verify-record-type"><span class="apxdns-verify-record-label-span">Type:</span> ${record.type.toUpperCase()} record</div>
                                <div class="apxdns-verify-record-address"><span class="apxdns-verify-record-label-span">Host:</span> ${record.combined_host}</div>
                                <div class="apxdns-verify-record-address"><span class="apxdns-verify-record-label-span">Value:</span> ${record.value}</div>
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
