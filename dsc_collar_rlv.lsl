/* =============================================================
   TITLE: ds_collar_rlv - RLV Suite/Control Plugin (Apps Menu)
   VERSION: 0.8 (Sit dialog label limit fix, extra debug)
   REVISION: 2025-07-12
   ============================================================= */

/* =============================================================
   BLOCK: GLOBAL VARIABLES & CONFIG BEGIN
   ============================================================= */
integer DEBUG = TRUE;

integer page_size = 6;
float   dialog_timeout = 180.0;
integer RLV_CHANNEL = 0; // Use 0 for local RLV; relay channel if necessary

// ACL info (set via state_sync message)
key     g_owner = NULL_KEY;
list    g_trustees = [];
list    g_blacklist = [];
integer g_public_access = FALSE;

// Privileges state
integer g_owner_im = TRUE;
integer g_owner_tp = TRUE;
integer g_trustee_im = TRUE;
integer g_trustee_tp = FALSE;

// Session cache: [av, page, csv, expiry, ctx, param, step, menucsv, chan, listen]
list    g_sessions;

/* --- Sit Sensor Globals --- */
integer g_sit_sensor_active = FALSE;
key     g_sit_target_av = NULL_KEY;
integer g_sit_chan = 0;
list    g_sit_targets = []; // [key, name, key, name...]

/* =============================================================
   BLOCK: GLOBAL VARIABLES & CONFIG END
   ============================================================= */

/* =============================================================
   BLOCK: SESSION HELPERS BEGIN
   ============================================================= */
integer s_idx(key av) { return llListFindList(g_sessions, [av]); }

integer s_set(key av, integer page, string csv, float expiry, string ctx, string param, string step, string menucsv, integer chan)
{
    integer i = s_idx(av);
    if (~i) {
        integer old = llList2Integer(g_sessions, i+9);
        if (old != -1) llListenRemove(old);
        g_sessions = llDeleteSubList(g_sessions, i, i+9);
    }
    integer lh = llListen(chan, "", av, "");
    g_sessions += [av, page, csv, expiry, ctx, param, step, menucsv, chan, lh];
    return TRUE;
}
integer s_clear(key av)
{
    integer i = s_idx(av);
    if (~i) {
        integer old = llList2Integer(g_sessions, i+9);
        if (old != -1) llListenRemove(old);
        g_sessions = llDeleteSubList(g_sessions, i, i+9);
    }
    return TRUE;
}
list s_get(key av)
{
    integer i = s_idx(av);
    if (~i) return llList2List(g_sessions, i, i+9);
    return [];
}

// Standard ACL mapping: 1=Owner/Unowned wearer, 2=Trustee, 3=Owned wearer, 4=Public, 5=Blacklist
integer get_acl(key av)
{
    if (llListFindList(g_blacklist, [av]) != -1) return 5;
    if (av == g_owner) return 1;
    if (llListFindList(g_trustees, [av]) != -1) return 2;
    if (av == llGetOwner()) {
        if (g_owner == NULL_KEY) return 1; // wearer, unowned = LV1
        return 3; // wearer, owned = LV3
    }
    if (g_public_access == TRUE) return 4;
    return 4;
}
/* =============================================================
   BLOCK: SESSION HELPERS END
   ============================================================= */

/* =============================================================
   BLOCK: BUTTON/REORDER HELPERS BEGIN
   ============================================================= */
list reorder_buttons(list buttons)
{
    integer L = llGetListLength(buttons);
    list nav  = llList2List(buttons, L-3, L-1);
    list body = llList2List(buttons, 0, L-4);

    integer rows = llGetListLength(body) / 3;
    list reversed_body = [];
    integer r;
    for (r = rows-1; r >= 0; --r)
        reversed_body += llList2List(body, r*3, r*3+2);
    return nav + reversed_body;
}
list slice(list L, integer start, integer count)
{
    return llList2List(L, start, start + count - 1);
}
/* =============================================================
   BLOCK: BUTTON/REORDER HELPERS END
   ============================================================= */

/* =============================================================
   BLOCK: MAIN MENU/UI BUILDERS BEGIN
   ============================================================= */

// Main menu: feature buttons (LV1/2), else SOS for LV3 wearer
list rlv_feature_btns(integer acl)
{
    if (acl == 3) return [ "SOS Release", " ", " ", " ", " ", " " ];
    return [ "Restrictions", "Privileges", "Force Sit", "Force Stand", " ", " " ];
}
list rlv_feature_ctxs(integer acl)
{
    if (acl == 3) return [ "sos", " ", " ", " ", " ", " " ];
    return [ "restrict", "priv", "sit", "stand", " ", " " ];
}

show_rlv_menu(key av, integer page, integer chan, integer acl)
{
    if (DEBUG) llOwnerSay("[DEBUG RLV] show_rlv_menu av=" + (string)av + " page=" + (string)page + " chan=" + (string)chan + " acl=" + (string)acl);
    list features = rlv_feature_btns(acl);
    list ctxs     = rlv_feature_ctxs(acl);

    integer total = llGetListLength(features);
    integer pages = (total + page_size - 1) / page_size;
    integer start = page * page_size;

    list page_btns = slice(features, start, page_size);
    list page_ctxs = slice(ctxs, start, page_size);

    // NAV row: « Prev | Main | Next »
    list nav_btns = [];
    if (page > 0) nav_btns += ["« Prev"]; else nav_btns += [" "];
    nav_btns += ["Main"];
    if (page < pages-1) nav_btns += ["Next »"]; else nav_btns += [" "];

    list buttons = page_btns + nav_btns;
    list menuctx = page_ctxs + ["prev", "main", "next"];

    while (llGetListLength(buttons) % 3 != 0) {
        buttons += [" "];
        menuctx += [" "];
    }

    buttons = reorder_buttons(buttons);
    menuctx = reorder_buttons(menuctx);

    s_set(av, page, "", llGetUnixTime() + dialog_timeout,
          "main", "", "", llDumpList2String(menuctx, ","), chan);

    string header;
    if (acl == 3)
        header = "You are wearing the collar and are owned.\nYou can use SOS Release only.";
    else
        header = "RLV Suite - Select an option (page " + (string)(page+1) + "/" + (string)pages + "):";
    llDialog(av, header, buttons, chan);
}

// Owner/Trustee Permissions menus
show_ownerp_menu(key av, integer chan)
{
    string im_txt;
    string tp_txt;
    if (g_owner_im) im_txt = "IM: ON"; else im_txt = "IM: OFF";
    if (g_owner_tp) tp_txt = "TP: ON"; else tp_txt = "TP: OFF";
    list btns = [ im_txt, tp_txt ];
    list ctxs = [ "owner_im", "owner_tp" ];
    btns += [ " ", "Main", " " ];
    ctxs += [ " ", "main", " " ];
    while (llGetListLength(btns) % 3 != 0) { btns += [ " " ]; ctxs += [ " " ]; }
    btns = reorder_buttons(btns);
    ctxs = reorder_buttons(ctxs);

    string info = "Owner Permissions:\nIM: ";
    if (g_owner_im) info += "ON"; else info += "OFF";
    info += "\nTP: ";
    if (g_owner_tp) info += "ON"; else info += "OFF";

    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "ownerp", "", "", llDumpList2String(ctxs, ","), chan);
    llDialog(av, info, btns, chan);
}

show_trustp_menu(key av, integer chan)
{
    string im_txt;
    string tp_txt;
    if (g_trustee_im) im_txt = "IM: ON"; else im_txt = "IM: OFF";
    if (g_trustee_tp) tp_txt = "TP: ON"; else tp_txt = "TP: OFF";
    list btns = [ im_txt, tp_txt ];
    list ctxs = [ "trustee_im", "trustee_tp" ];
    btns += [ " ", "Main", " " ];
    ctxs += [ " ", "main", " " ];
    while (llGetListLength(btns) % 3 != 0) { btns += [ " " ]; ctxs += [ " " ]; }
    btns = reorder_buttons(btns);
    ctxs = reorder_buttons(ctxs);

    string info = "Trustee Permissions:\nIM: ";
    if (g_trustee_im) info += "ON"; else info += "OFF";
    info += "\nTP: ";
    if (g_trustee_tp) info += "ON"; else info += "OFF";

    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "trustp", "", "", llDumpList2String(ctxs, ","), chan);
    llDialog(av, info, btns, chan);
}

show_sos_menu(key av, integer chan)
{
    list btns = [ "SOS Release", " ", " " ];
    list ctxs = [ "sos", " ", " " ];
    btns += [ " ", "Main", " " ];
    ctxs += [ " ", "main", " " ];
    while (llGetListLength(btns) % 3 != 0) { btns += [ " " ]; ctxs += [ " " ]; }
    btns = reorder_buttons(btns);
    ctxs = reorder_buttons(ctxs);

    string info = "Release all owner-set restrictions?\nThis will notify your owner.";
    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "sos", "", "", llDumpList2String(ctxs, ","), chan);
    llDialog(av, info, btns, chan);
}

show_sos_confirm(key av, integer chan)
{
    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "sos_confirm", "", "", "", chan);
    llDialog(av, "Are you sure you want to release all owner-set RLV restrictions?", ["Cancel", "OK", " "], chan);
}

/* --- Force Sit/Stand UI and Helpers --- */
sit_scan(key av, integer chan)
{
    g_sit_sensor_active = TRUE;
    g_sit_target_av = av;
    g_sit_chan = chan;
    g_sit_targets = [];
    if (DEBUG) llOwnerSay("[DEBUG RLV] sit_scan() triggered by av=" + (string)av + ", starting sensor...");
    llSensor("", NULL_KEY, ACTIVE|PASSIVE, 5.0, PI);
}

show_sit_dialog(key av, integer chan)
{
    integer N = llGetListLength(g_sit_targets) / 2;
    if (DEBUG) llOwnerSay("[DEBUG RLV] show_sit_dialog, targets=" + (string)N);
    if (N == 0)
    {
        llDialog(av, "No sit targets detected within 5 meters.", [ " ", "Main", " " ], chan);
        s_clear(av);
        return;
    }
    list btns = [];
    list ctxs = [];
    integer i;
    for (i = 0; i < llGetListLength(g_sit_targets); i += 2)
    {
        string name = llList2String(g_sit_targets, i+1);
        // TRIM to 24 chars for dialog
        if (llStringLength(name) > 24) name = llGetSubString(name, 0, 23);
        btns += [ name ];
        ctxs += [ llList2Key(g_sit_targets, i) ];
    }
    btns += [ " ", "Main", " " ];
    ctxs += [ " ", "main", " " ];
    while (llGetListLength(btns) % 3 != 0) { btns += [ " " ]; ctxs += [ " " ]; }
    btns = reorder_buttons(btns);
    ctxs = reorder_buttons(ctxs);
    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "sit_targets", "", "", llDumpList2String(ctxs, ","), chan);
    llDialog(av, "Select an object for the wearer to sit on:", btns, chan);
}

do_force_stand(key av)
{
    llRegionSayTo(llGetOwner(), RLV_CHANNEL, "@unsit=force");
    llDialog(av, "Wearer has been forced to stand.", [ " ", "Main", " " ], llList2Integer(s_get(av),8));
    s_clear(av);
}

do_force_sit(key av, key target_obj)
{
    llRegionSayTo(llGetOwner(), RLV_CHANNEL, "@sit:" + (string)target_obj + "=force");
    llDialog(av, "Wearer has been forced to sit on the selected object.", [ " ", "Main", " " ], llList2Integer(s_get(av),8));
    s_clear(av);
}

/* =============================================================
   BLOCK: MAIN MENU/UI BUILDERS END
   ============================================================= */

/* =============================================================
   BLOCK: MAIN EVENT LOOP BEGIN
   ============================================================= */
default
{
    state_entry()
    {
        llSetTimerEvent(1.0);
        // Set min_acl to 3 (Trustees, Owners, Owned wearer)
        llMessageLinked(LINK_THIS, 500, "register|1015|RLV|3|apps_rlv", NULL_KEY);
        if (DEBUG) llOwnerSay("[RLV] Plugin ready.");
    }

    sensor(integer detected)
    {
        if (!g_sit_sensor_active) return;
        g_sit_sensor_active = FALSE;
        g_sit_targets = [];
        if (DEBUG) llOwnerSay("[DEBUG RLV] sensor event, detected=" + (string)detected);
        integer i;
        for (i = 0; i < detected; ++i)
        {
            key id = llDetectedKey(i);
            string name = llDetectedName(i);
            if (id != llGetKey())
            {
                g_sit_targets += [ id, name ];
                if (DEBUG) llOwnerSay("[DEBUG RLV] sensor found: " + name + " (" + (string)id + ")");
            }
        }
        show_sit_dialog(g_sit_target_av, g_sit_chan);
    }

    link_message(integer sn, integer num, string str, key id)
    {
        if (num == 510)
        {
            list p = llParseString2List(str, ["|"], []);
            if (llList2String(p, 0) == "apps_rlv" && llGetListLength(p) >= 3)
            {
                key av = (key)llList2String(p, 1);
                integer chan = (integer)llList2String(p, 2);
                integer acl = get_acl(av);

                // LV1 (Owner), LV2 (Trustee), LV3 (owned wearer) only
                if (acl != 1 && acl != 2 && acl != 3) {
                    llDialog(av, "Access denied: Only owners, trustees, and wearers may use RLV Suite controls.", [" ", "OK", " "], chan);
                    return;
                }
                // If owned, wearer gets only SOS
                show_rlv_menu(av, 0, chan, acl);
            }
        }
        // Listen for state_sync from core (to get g_owner, etc)
        if (num == 520)
        {
            list p = llParseString2List(str, ["|"], []);
            if (llGetListLength(p) == 8 && llList2String(p, 0) == "state_sync")
            {
                g_owner = (key)llList2String(p, 1);
                string trust_csv = llList2String(p, 3);
                string bl_csv = llList2String(p, 5);
                string pub_str = llList2String(p, 6);
                if (trust_csv == " ") g_trustees = [];
                else g_trustees = llParseString2List(trust_csv, [","], []);
                if (bl_csv == " ") g_blacklist = [];
                else g_blacklist = llParseString2List(bl_csv, [","], []);
                if (pub_str == "1") g_public_access = TRUE;
                else g_public_access = FALSE;
            }
        }
    }

    listen(integer chan, string nm, key av, string msg)
    {
        if (DEBUG) llOwnerSay("[DEBUG RLV] listen event: av=" + (string)av + " msg=" + msg);

        list s = s_get(av);
        if (llGetListLength(s) == 0) return;
        if (chan != llList2Integer(s, 8)) return;

        integer page = llList2Integer(s, 1);
        string ctx   = llList2String(s, 4);
        string menucsv = llList2String(s, 7);
        list menuctx = llParseString2List(menucsv, [","], []);

        integer acl = get_acl(av);

        if (DEBUG) llOwnerSay("[DEBUG RLV] listen: msg=" + msg + " menuctx=" + llDumpList2String(menuctx,",") + " ctx=" + ctx + " acl=" + (string)acl);

        // NAV: Main always returns to main menu for all flows
        if (msg == "Main")
        {
            llMessageLinked(LINK_THIS, 510, "main|" + (string)av + "|" + (string)chan, NULL_KEY);
            s_clear(av);
            return;
        }
        // NAV: Previous/Next
        if (msg == "« Prev") { if (page > 0) show_rlv_menu(av, page-1, chan, acl); return; }
        if (msg == "Next »") { if (page < 1) show_rlv_menu(av, page+1, chan, acl); return; }

        // ACL3: SOS flow
        if (acl == 3 && ctx == "main")
        {
            integer sel = llListFindList(menuctx, [msg]);
            if (sel != -1 && llList2String(menuctx, sel) == "sos")
            {
                show_sos_confirm(av, chan);
                return;
            }
        }
        if (ctx == "sos_confirm")
        {
            if (msg == "OK")
            {
                llDialog(av, "All owner-set restrictions have been released.\nYour owner has been notified.", [" ", "OK", " "], chan);
                // Optionally: llInstantMessage(g_owner, ...);
                s_clear(av);
                return;
            }
            if (msg == "Cancel")
            {
                s_clear(av);
                return;
            }
        }

        // ACL1/2: Full menu flows
        if ((acl == 1 || acl == 2) && ctx == "main")
        {
            integer sel = llListFindList(menuctx, [msg]);
            if (DEBUG) llOwnerSay("[DEBUG RLV] main menu sel=" + (string)sel);
            if (sel != -1)
            {
                string act = llList2String(menuctx, sel);
                if (act == "restrict") { llDialog(av, "RLV Restrictions UI - [stub]", [" ", "OK", " "], chan); return; }
                if (act == "priv")     {
                    list perm_btns = [ "Owner Perms", "Trustee Perms", "Main" ];
                    list perm_ctxs = [ "ownerp", "trustp", "main" ];
                    while (llGetListLength(perm_btns) % 3 != 0) { perm_btns += [ " " ]; perm_ctxs += [ " " ]; }
                    perm_btns = reorder_buttons(perm_btns);
                    perm_ctxs = reorder_buttons(perm_ctxs);
                    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "priv", "", "", llDumpList2String(perm_ctxs, ","), chan);
                    llDialog(av, "Select permissions to manage:", perm_btns, chan);
                    return;
                }
                if (act == "sit")      { sit_scan(av, chan); return; }
                if (act == "stand")    { do_force_stand(av); return; }
            }
        }
        // Permissions menu (choose owner/trustee/main)
        if (ctx == "priv")
        {
            list perm_ctxs = llParseString2List(menucsv, [","], []);
            integer sel = llListFindList(perm_ctxs, [msg]);
            if (sel != -1)
            {
                string act = llList2String(perm_ctxs, sel);
                if (act == "ownerp")   { show_ownerp_menu(av, chan); return; }
                if (act == "trustp")   { show_trustp_menu(av, chan); return; }
            }
        }
        // Owner Permissions toggle
        if (ctx == "ownerp")
        {
            list perm_ctxs = llParseString2List(menucsv, [","], []);
            integer sel = llListFindList(perm_ctxs, [msg]);
            if (sel != -1)
            {
                string act = llList2String(perm_ctxs, sel);
                if (act == "owner_im") { g_owner_im = !g_owner_im; show_ownerp_menu(av, chan); return; }
                if (act == "owner_tp") { g_owner_tp = !g_owner_tp; show_ownerp_menu(av, chan); return; }
                if (act == "main") {
                    llMessageLinked(LINK_THIS, 510, "main|" + (string)av + "|" + (string)chan, NULL_KEY);
                    s_clear(av);
                    return;
                }
            }
        }
        // Trustee Permissions toggle
        if (ctx == "trustp")
        {
            list perm_ctxs = llParseString2List(menucsv, [","], []);
            integer sel = llListFindList(perm_ctxs, [msg]);
            if (sel != -1)
            {
                string act = llList2String(perm_ctxs, sel);
                if (act == "trustee_im") { g_trustee_im = !g_trustee_im; show_trustp_menu(av, chan); return; }
                if (act == "trustee_tp") { g_trustee_tp = !g_trustee_tp; show_trustp_menu(av, chan); return; }
                if (act == "main") {
                    llMessageLinked(LINK_THIS, 510, "main|" + (string)av + "|" + (string)chan, NULL_KEY);
                    s_clear(av);
                    return;
                }
            }
        }
        // Sit targets selection
        if (ctx == "sit_targets")
        {
            integer sel = llListFindList(menuctx, [msg]);
            if (sel != -1)
            {
                key target = (key)llList2String(menuctx, sel);
                do_force_sit(av, target);
                return;
            }
        }
    }

    timer()
    {
        // Timeout/cleanup, if needed
    }
}
/* =============================================================
   BLOCK: MAIN EVENT LOOP END
   ============================================================= */
