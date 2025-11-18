# PHASE 2: PROBLEM DEFINITION & USER SCENARIOS

## Executive Summary

This phase translates the Phase 1 analysis into concrete user scenarios, revealing the gap between what users expect and what the current interface delivers. Through four distinct personas, we expose critical friction points and establish design requirements for a conversational, focused redesign.

**Key Finding:** Users across all scenarios share a common mental model—"paste → link → share"—but face different environmental pressures (time, security concerns, technical literacy) that the current one-size-fits-all form doesn't accommodate.

---

## 1. CORE QUESTIONS ANSWERED

### What is the user's primary goal?

**Get a shareable link for sensitive text that:**
1. Can only be viewed once
2. Expires automatically
3. Cannot be intercepted or stored by intermediaries
4. Requires no recipient setup or account creation

**Secondary goals:**
- Communicate the link through an insecure channel (email, Slack, SMS) safely
- Optionally add extra protection (passphrase) for highly sensitive content
- Maintain plausible deniability ("the secret expired, I can't retrieve it")

### What is the user's context?

**Environmental factors:**
- **Time pressure:** Often rushed, sharing credentials during an incident or handoff
- **Device variability:** May be on mobile during a crisis, desktop during planned sharing
- **Attention scarcity:** Multitasking (on a call, in a chat window, switching between apps)
- **Trust uncertainty:** First-time users may be skeptical ("Is this site legit?")
- **Security consciousness:** Varies from "I just need this done" to "This is highly sensitive"

**Mental state:**
- **Anxious:** "Will this work? What if they can't access it?"
- **Distracted:** "I have 30 seconds to do this before my meeting"
- **Uncertain:** "Am I doing this right? Do I need a passphrase?"

### What is our hypothesis about why the current experience could be better?

**Hypothesis:**

The current experience treats all users as equally security-conscious and technically literate, requiring upfront configuration decisions that most users aren't prepared to make. This creates three failure modes:

1. **Paralysis:** Users see options, don't know what to choose, abandon the task
2. **Confusion:** Users choose wrong options (e.g., 60-second TTL for async sharing), fail to share successfully
3. **Distrust:** Users see a complex form, question legitimacy, leave the site

**By redesigning around a "defaults-first, progressive disclosure" model, we can:**
- Reduce time-to-first-link from 6 steps to 2 clicks
- Increase user confidence through clarity and feedback
- Maintain advanced features for power users without cluttering the primary path
- Build trust through transparency about what happens to the secret

---

## 2. USER SCENARIOS

### SCENARIO 1: Emergency Database Credentials

**Persona: Alex, Backend Developer**

**Context:**
- **Time:** 11:47 PM, production database down
- **Device:** Laptop (macOS, Chrome)
- **Environment:** Working from home, on Slack call with contractor
- **Pressure:** HIGH—every minute costs revenue
- **Security awareness:** Medium—knows credentials shouldn't go in Slack

**The Task:**
Alex needs to share production database credentials with a contractor (Carlos) who's debugging the outage. Carlos is in a different timezone, on a different VPN, and needs immediate access.

**Mental Model:**
1. Copy DB credentials from 1Password
2. Get a one-time link somehow
3. Paste link in Slack
4. Carlos uses link, fixes issue
5. Link expires automatically

**Current Flow Experience:**

**11:47 PM** - Alex pastes credentials into textarea ✅
**11:47 PM** - Sees "Secret Passphrase" field 🤔 *"Do I need this? Carlos is on the call, he can just use it now..."*
**11:48 PM** - Sees "Expires in 7 days" 🤔 *"That's too long... but what if Carlos is AFK? Maybe 1 hour?"*
**11:48 PM** - Changes dropdown to 1 hour ⏱️
**11:48 PM** - Clicks "Create Link" ✅
**11:48 PM** - Redirected to receipt page 🤷 *"Wait, where's the link? Oh, here..."*
**11:49 PM** - Copies link, pastes in Slack ✅
**11:49 PM** - Carlos clicks immediately 😓 *"It's asking for a passphrase?"* ❌

**Failure Point:** Alex didn't realize the passphrase field being visible meant it was set. He left it empty but the form showed the field, creating confusion.

**Required Features:**
- ✅ REQUIRED: Fast path (2 steps max)
- ✅ REQUIRED: Clear link display on receipt page
- ✅ REQUIRED: Copy-to-clipboard button
- ⚠️ REQUIRED: Obvious "no passphrase set" state

**Nice-to-Have Features:**
- Short TTL options (1h, 4h) easily accessible
- Inline validation showing "secret will expire in X"
- Confirmation that secret was created ("Ready to share")

**Confusion/Abandonment Points:**
1. **Passphrase field ambiguity:** Is it required? Did I accidentally set one?
2. **Receipt page layout:** Where's the link? (Has to scroll/search)
3. **Expiration anxiety:** "What if I choose wrong and Carlos misses the window?"

---

### SCENARIO 2: Customer Support Password Reset

**Persona: Jamie, Customer Support Agent**

**Context:**
- **Time:** 2:34 PM, during shift
- **Device:** Desktop (Windows, Edge)
- **Environment:** Call center, wearing headset, customer on hold
- **Pressure:** MEDIUM—customer is frustrated, waiting
- **Security awareness:** Low—follows scripts, not technical

**The Task:**
Jamie needs to send a temporary password to a customer (Sarah) who's locked out of her account. Company policy: never send passwords via email directly. Customer is on hold, waiting for email.

**Mental Model:**
1. Generate a random password (use company tool)
2. Copy password to "that one-time secret site"
3. Send link via email to customer
4. Customer clicks link, sees password, logs in
5. Customer changes password after login

**Current Flow Experience:**

**2:34 PM** - Opens OneTimeSecret.com
**2:34 PM** - Sees large empty box 🤔 *"Do I paste the password here?"*
**2:35 PM** - Pastes temporary password ✅
**2:35 PM** - Sees "Secret Passphrase" 😰 *"What's this? Is this different from the password?"*
**2:35 PM** - Skips passphrase (leaves empty) ⏭️
**2:35 PM** - Sees "Expires in 7 days" 🤷 *"That seems fine..."* (doesn't change it)
**2:35 PM** - Clicks "Create Link" ✅
**2:36 PM** - Redirected to receipt page
**2:36 PM** - Copies link, pastes in email ✅
**2:36 PM** - Sends email to Sarah
**2:37 PM** - Returns to call, tells Sarah "Check your email" ✅

**Success!** But Jamie didn't realize:
- The password will be accessible for 7 days (security risk if Sarah doesn't use it immediately)
- There's a "Generate Password" feature that would've saved a step
- No way to verify if Sarah actually used the link

**Required Features:**
- ✅ REQUIRED: Simple paste → link flow (no configuration)
- ✅ REQUIRED: Clear confirmation that link is ready
- ⚠️ REQUIRED: Email field for sending directly (Jamie sends manually, but this would help)

**Nice-to-Have Features:**
- Discovery of "Generate Password" feature (would save step 1)
- Suggested TTL for password resets (1 day, not 7)
- Notification when link is viewed ("Sarah got it")

**Confusion/Abandonment Points:**
1. **Terminology confusion:** "Passphrase" vs "Password" (are they different?)
2. **Hidden features:** No awareness of Generate Password option
3. **No feedback loop:** Can't tell if Sarah used the link or ignored email

---

### SCENARIO 3: Personal Tax Document Sharing

**Persona: Morgan, Freelancer (Non-Technical)**

**Context:**
- **Time:** 9:15 AM, Saturday morning
- **Device:** iPhone 13 (iOS Safari)
- **Environment:** Coffee shop, using public WiFi
- **Pressure:** LOW—no immediate deadline, but wants to finish task
- **Security awareness:** HIGH—paranoid about identity theft

**The Task:**
Morgan needs to send a scanned W-9 form (containing SSN) to a new client. Client requested it via email, but Morgan knows "email isn't secure."

**Mental Model:**
1. Upload W-9 to "some secure site" (doesn't know which)
2. Get a link that expires
3. Email link to client
4. Client downloads W-9 once
5. Link becomes invalid automatically

**Current Flow Experience:**

**9:15 AM** - Googles "send sensitive document securely" 🔍
**9:16 AM** - Finds OneTimeSecret.com in results
**9:16 AM** - Opens site on iPhone 📱
**9:16 AM** - Sees large empty box 🤔 *"This looks like a message form... can I upload a file here?"* ❌
**9:17 AM** - Tries to drag/drop file (doesn't work on mobile) ❌
**9:17 AM** - Gives up, goes back to Google 🚫 **ABANDONED**

**Failure Point:** Morgan expected file upload, not a text field. OneTimeSecret doesn't support file uploads—only text—but this wasn't clear upfront.

**Alternate Flow (If Morgan Used Text):**

**9:15 AM** - Copy-pastes SSN and tax info as text
**9:16 AM** - Sees "Secret Passphrase" field 😰 *"I should definitely set this..."*
**9:16 AM** - Types passphrase: "Coffee2024" ✅
**9:17 AM** - Sees "Expires in 7 days" 🤔 *"What if client is on vacation? Better make it longer..."*
**9:17 AM** - Scrolls dropdown on phone (accidentally selects 30 minutes) ❌
**9:18 AM** - Doesn't notice mistake ⚠️
**9:18 PM** - Clicks "Create Link" ✅
**9:18 PM** - Receipt page loads (has to scroll to find link on mobile) 📱
**9:19 PM** - Copies link, switches to email app
**9:20 PM** - Pastes link in email to client ✅
**9:20 PM** - Types separate email: "The passphrase is Coffee2024" 😱 **SECURITY FAIL**

**Failure Point:** Morgan sent passphrase in same email as link, defeating the purpose. No guidance provided on how to share passphrase separately.

**10:45 AM** - Client tries to access link (90 minutes later) ❌
**10:45 AM** - Link expired (30-minute TTL selected by mistake) 💥

**Required Features:**
- ✅ REQUIRED: Mobile-optimized interface
- ✅ REQUIRED: Clear "text only, no files" explanation upfront
- ⚠️ REQUIRED: Passphrase guidance (how to share separately)
- ⚠️ REQUIRED: TTL confirmation/review before creation

**Nice-to-Have Features:**
- File upload support (or clear redirect to alternative service)
- Passphrase tips ("Share via SMS or phone call, not same email")
- TTL preview ("Link will expire on [date/time]")
- Undo/edit link (if mistake noticed within 1 minute)

**Confusion/Abandonment Points:**
1. **File upload expectation:** Site looks like it accepts files (large empty box)
2. **Passphrase security theater:** Users set passphrase but share it insecurely
3. **Mobile dropdown friction:** Easy to mis-tap expiration option
4. **No review step:** Can't verify settings before finalizing

---

### SCENARIO 4: API Key Handoff to Team Member

**Persona: Priya, DevOps Engineer**

**Context:**
- **Time:** 3:42 PM, Tuesday afternoon
- **Device:** Linux workstation (Firefox)
- **Environment:** Office, desk, headphones on (in flow state)
- **Pressure:** LOW—planned handoff, not urgent
- **Security awareness:** VERY HIGH—knows threat models, uses security tools daily

**The Task:**
Priya needs to share an AWS API key with a new team member (Raj) for a deployment pipeline. Key should be:
- Protected with a passphrase (shared verbally)
- Short-lived (Raj will rotate it immediately)
- Trackable (Priya wants to know if Raj retrieved it)

**Mental Model:**
1. Copy API key from vault
2. Create one-time secret with passphrase
3. Set short expiration (1 hour)
4. Message Raj: "Link: [URL], passphrase: [shared on Signal]"
5. Verify Raj got it
6. Raj rotates key immediately

**Current Flow Experience:**

**3:42 PM** - Opens OneTimeSecret.com (has used before) ✅
**3:42 PM** - Pastes AWS API key into textarea ✅
**3:42 PM** - Sets passphrase: `xK9$mP2#vL5@` (strong) ✅
**3:43 PM** - Changes expiration to 1 hour ✅
**3:43 PM** - Looks for "recipient email" field 🤔 *"I thought I could send directly... guess not"*
**3:43 PM** - Looks for "notify me when viewed" option 🤔 *"Would be nice to know when Raj got it..."*
**3:43 PM** - Clicks "Create Link" ✅
**3:43 PM** - Receipt page loads
**3:44 PM** - Copies link, pastes in Slack ✅
**3:44 PM** - Opens Signal, sends passphrase to Raj ✅
**3:45 PM** - Returns to work, assumes Raj will get it ⏳

**4:30 PM** - Raj still hasn't retrieved it (Priya doesn't know) ⚠️
**4:45 PM** - Link expires ❌
**4:46 PM** - Raj messages: "Link expired, can you resend?" 😓

**Failure Point:** Priya had no way to track if Raj retrieved the secret. No notification, no dashboard showing "viewed" status.

**Required Features:**
- ✅ REQUIRED: Passphrase support (already exists)
- ✅ REQUIRED: Granular TTL options (already exists)
- ⚠️ REQUIRED: Confirmation that passphrase was set correctly
- ⚠️ OPTIONAL: View status tracking ("viewed at 3:52 PM")

**Nice-to-Have Features:**
- Email notification when secret is viewed
- Dashboard showing created secrets + status (new/viewed/expired)
- Burn-after-reading confirmation ("Secret was retrieved and burned")
- Passphrase strength indicator

**Confusion/Abandonment Points:**
1. **No feedback loop:** Can't tell if recipient got the secret
2. **Email recipient hidden:** Feature exists but not visible on public homepage
3. **No review step:** Can't double-check passphrase before sending
4. **No history:** Can't see previously created secrets for reference

---

## 3. CROSS-SCENARIO PATTERNS

### Shared Pain Points Across All Users

**1. Upfront Configuration Burden**
- All users face "Should I set a passphrase?" decision immediately
- Most users (Alex, Jamie, Morgan) don't know how to answer
- Only Priya (power user) confidently navigates options

**2. Mobile Experience Gaps**
- Morgan's mobile flow failed at multiple points (dropdown, scrolling, copy-paste)
- No mobile-specific optimizations visible in current design

**3. No Feedback Loop**
- Alex and Priya both wanted confirmation that recipient got the secret
- Jamie had no idea if Sarah used the password link
- Current design is "fire and forget"

**4. Hidden Advanced Features**
- Jamie never discovered "Generate Password" (would've been perfect for her workflow)
- Priya couldn't access "email recipient" feature (requires authentication, not obvious)

**5. Trust Deficit**
- Morgan abandoned on first visit (site didn't look legitimate)
- No security indicators visible (HTTPS badge, encryption explanation)

### Mental Model Mismatches

| User Expects | Current Design Provides |
|--------------|------------------------|
| "Paste → Link" (2 steps) | "Paste → Configure → Link" (6+ steps) |
| File upload support | Text-only (not explained) |
| Passphrase = extra security | Passphrase = confusion |
| Short TTL for urgent sharing | 7-day default (too long) |
| Notification when viewed | No tracking at all |
| Review before sending | Immediate creation + redirect |

---

## 4. ENVIRONMENTAL CONTEXT ANALYSIS

### Time Pressure Spectrum

**HIGH PRESSURE** (Alex, Jamie)
- Need: Minimal steps, obvious defaults, fast completion
- Friction: Every extra click/decision costs time
- Risk: Mistakes due to rushing (wrong TTL, forgot passphrase)

**LOW PRESSURE** (Morgan, Priya)
- Need: Clarity, guidance, review step
- Friction: Uncertainty about whether they did it right
- Risk: Abandonment due to confusion

### Device Context

**MOBILE** (Morgan)
- Need: Thumb-friendly targets, minimal scrolling, native copy/paste
- Friction: Dropdown selection, finding link on receipt page
- Risk: Mis-taps, abandonment

**DESKTOP** (Alex, Jamie, Priya)
- Need: Keyboard shortcuts, paste-and-go, tab navigation
- Friction: Less severe, but still present
- Risk: Lower, but configuration still burdensome

### Security Consciousness

**LOW** (Jamie)
- Follows scripts, trusts defaults
- Doesn't understand security implications of 7-day TTL
- Would benefit from suggested TTLs per use case

**MEDIUM** (Alex, Morgan)
- Knows "email is insecure" but not expert
- Passphrase feels like "extra security" but unsure when to use
- Would benefit from contextual tips

**HIGH** (Priya)
- Knows exactly what she needs
- Wants advanced features (tracking, history)
- Would benefit from power user mode

---

## 5. REQUIRED vs NICE-TO-HAVE FEATURES

### Must-Have (Across All Scenarios)

1. **Fast default path** (paste → link, 2 steps max)
2. **Clear link display** on receipt page
3. **Copy-to-clipboard** button (one-click)
4. **Mobile-optimized** interface (touch targets, no dropdowns)
5. **Passphrase clarity** (required vs optional, set vs not set)
6. **TTL preview** ("expires on [date/time]" or "in 7 days")
7. **Trust indicators** (HTTPS badge, "how it works" explainer)

### Should-Have (Multiple Scenarios Benefit)

8. **Passphrase guidance** (how to share separately)
9. **TTL suggestions** based on use case (password reset: 1 day, emergency: 1 hour)
10. **Generate Password** feature discovery (for Jamie)
11. **View status** tracking (for Priya, Alex)
12. **Review step** before finalizing (for Morgan)
13. **Undo/extend** link within short window (1-5 minutes)

### Nice-to-Have (Power Users)

14. **Email recipient** integration (visible for authenticated users)
15. **Email notifications** when secret is viewed
16. **Dashboard** showing created secrets + status
17. **Passphrase strength** indicator
18. **Custom TTL** input (not just dropdown presets)
19. **Burn-after-reading** confirmation message
20. **File upload** support (or clear redirect to alternative)

---

## 6. CONFUSION & ABANDONMENT RISK POINTS

### Critical Risk Points (High Impact)

**1. Passphrase Field Ambiguity** ⚠️⚠️⚠️
- Affects: All users
- Current state: Visible but empty, no clear required/optional indicator
- Risk: Users don't know if they should set it, accidentally set it, or send it insecurely
- Solution: Progressive disclosure (hide by default, show on demand with guidance)

**2. Mobile Dropdown Friction** ⚠️⚠️⚠️
- Affects: Mobile users (40%+ of traffic?)
- Current state: 11-option dropdown with small tap targets
- Risk: Mis-selection, frustration, abandonment
- Solution: Mobile-specific UI (buttons, sliders, or preset chips)

**3. No Review Step** ⚠️⚠️
- Affects: All users, especially first-timers
- Current state: Click "Create Link" → immediate redirect
- Risk: Can't verify settings, no undo, anxiety
- Solution: Confirmation screen with editable settings before finalizing

**4. Receipt Page Link Visibility** ⚠️⚠️
- Affects: All users, worse on mobile
- Current state: Link on receipt page requires scrolling/searching
- Risk: "Where's the link?" confusion, copy-paste errors
- Solution: Prominent link display, auto-focus, one-click copy

### Moderate Risk Points

**5. File Upload Expectation** ⚠️
- Affects: Non-technical users (Morgan)
- Current state: Textarea looks like it might accept files
- Risk: Abandonment when drag/drop doesn't work
- Solution: Clear "text only" messaging, or add file upload support

**6. Hidden Features** ⚠️
- Affects: All users (feature discovery)
- Current state: Generate Password, recipient email hidden or obscure
- Risk: Users manually do what the site could automate
- Solution: Contextual feature hints, onboarding tooltips

**7. No Feedback Loop** ⚠️
- Affects: Power users (Priya), urgent scenarios (Alex)
- Current state: No way to track if secret was viewed
- Risk: Uncertainty, repeated messages asking "did you get it?"
- Solution: View status tracking, optional email notifications

### Low Risk Points (Edge Cases)

**8. Passphrase Sharing in Same Channel** ⚠️
- Affects: Security-conscious users who set passphrase
- Current state: No guidance on how to share passphrase
- Risk: Security theater (passphrase sent in same email as link)
- Solution: Inline tips ("Share passphrase via phone or separate channel")

**9. Expiration Anxiety** ⚠️
- Affects: Users with async recipients (Morgan, Jamie)
- Current state: Must guess when recipient will access link
- Risk: Too short = expired before viewed, too long = security risk
- Solution: TTL suggestions, preview, or extend option

---

## 7. SUMMARY: PROBLEM SPACE DEFINITION

### The Core User Need

**Get a shareable link for sensitive text in the fastest, clearest way possible, with confidence that:**
1. The secret is secure
2. The link will work when recipient accesses it
3. The link won't work after one view or expiration
4. No mistakes were made in configuration

### The Primary Design Challenge

**How do we serve four distinct user types with one interface?**

1. **The Rusher** (Alex) - wants speed, zero config
2. **The Scripter** (Jamie) - wants simplicity, follows defaults
3. **The Worrier** (Morgan) - wants guidance, clarity, review
4. **The Expert** (Priya) - wants control, tracking, power features

**Current approach:** One-size-fits-all form (doesn't fit anyone well)

**Proposed approach:** Layered interface with progressive disclosure
- **Layer 1:** Default path (paste → link, 2 clicks)
- **Layer 2:** Quick options (passphrase, TTL, visible but not required)
- **Layer 3:** Advanced features (tracking, email, custom domain)

### Success Metrics for Redesign

**Speed:**
- Time-to-first-link: < 10 seconds (currently ~20-30 seconds)
- Clicks required: 2 (currently 4-6)

**Clarity:**
- First-time user success rate: > 90% (currently unknown, likely ~70%)
- Passphrase confusion rate: < 5% (currently high, estimated 30%+)

**Confidence:**
- Return visit rate: > 60% (measure trust)
- Advanced feature discovery: > 40% (generate password, passphrase)

**Mobile:**
- Mobile completion rate: Match desktop (currently likely lower)
- Mobile time-to-link: Match desktop (currently 2-3x slower)

---

## Next Steps → PHASE 3

With user scenarios defined, we can now:
1. Propose 2-3 fundamentally different interaction models
2. Test each model against our four scenarios
3. Identify which approach best serves all user types
4. Design the specific interaction flow for the winning approach

**Key Questions for Phase 3:**
- Input-first vs guide-first: Should we hide the textarea until after explaining?
- Single-page progressive vs multi-step: Wizard or dynamic form?
- Minimal defaults vs explicit choices: How much do we hide?
- Conversational/chat-like vs traditional form: How "conversational" is right?

**Evaluation Criteria:**
- Does it solve Alex's speed need?
- Does it reduce Jamie's confusion?
- Does it build Morgan's trust?
- Does it enable Priya's power use?

---

**Document Status:** ✅ Complete
**Next Phase:** PHASE 3 - Explore Interaction Models
**Date:** 2025-11-18
