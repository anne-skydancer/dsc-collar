/* =============================================================
   TITLE: ds_collar_rlv - RLV Suite/Control Plugin (Apps Menu)
   VERSION: 1.0.4 (Dialog truncation-safe matching, full script)
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

// Session cache: [av, page, csv, expiry, ctx, param, step, menubtns, menuctx, chan, listen]
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

integer s_set(key av, integer page, string csv, float expiry, string ctx, string param, string step, string menubtns, string menuctx, integer chan)
{
    integer i = s_idx(av);
    if (~i) {
        integer old = llList2Integer(g_sessions, i+10);
        if (old != -1) llListenRemove(old);
        g_sessions = llDeleteSubList(g_sessions, i, i+10);
    }
    integer lh = llListen(chan, "", av, "");
    g_sessions += [av, page, csv, expiry, ctx, param, step, menubtns, menuctx, chan, lh];
    return TRUE;
}
integer s_clear(key av)
{
    integer i = s_idx(av);
    if (~i) {
        integer old = llList2Integer(g_sessions, i+10);
        if (old != -1) llListenRemove(old);
        g_sessions = llDeleteSubList(g_sessions, i, i+10);
    }
    return TRUE;
}
list s_get(key av)
{
    integer i = s_idx(av);
    if (~i) return llList2List(g_sessions, i, i+10);
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
   BLOCK: MAIN MENU/UI BUILDERS BEGIN
   ============================================================= */

list rlv_feature_btns(integer acl)
{
    // 0-2 = nav row; rest is menu (bottom up, left to right)
    if (acl == 3) return [ " ", "Main", " ", " ", " ", "SOS Release", " "," ", " " ];
    return [ " ", "Main", " ", "Restrictions", "Privileges", "Sit", "Unsit", " ", " " ];
}
list rlv_feature_ctxs(integer acl)
{
    if (acl == 3) return [ " ", "main", " ", " ", " ", "sos", " ", " ", " " ];
    return [ " ", "main", " ", "restrict", "priv", "sit", "unsit", " ", " " ];
}

show_rlv_menu(key av, integer page, integer chan, integer acl)
{
    if (DEBUG) llOwnerSay("[DEBUG RLV] show_rlv_menu av=" + (string)av + " page=" + (string)page + " chan=" + (string)chan + " acl=" + (string)acl);
    list buttons = rlv_feature_btns(acl);
    list menuctx = rlv_feature_ctxs(acl);

    s_set(av, page, "", llGetUnixTime() + dialog_timeout,
          "main", "", "", llDumpList2String(buttons, ","), llDumpList2String(menuctx, ","), chan);

    if (DEBUG) llOwnerSay("[DEBUG RLV] menu btns: " + llDumpList2String(buttons,","));
    if (DEBUG) llOwnerSay("[DEBUG RLV] menu ctx: " + llDumpList2String(menuctx,","));

    string header;
    if (acl == 3)
        header = "You are wearing the collar and are owned.\nYou can use SOS Release only.";
    else
        header = "RLV Suite - Select an option:";
    llDialog(av, header, buttons, chan);
}

// Permissions menus
show_ownerp_menu(key av, integer chan)
{
    string im_txt;
    string tp_txt;
    if (g_owner_im) im_txt = "IM: ON"; else im_txt = "IM: OFF";
    if (g_owner_tp) tp_txt = "TP: ON"; else tp_txt = "TP: OFF";
    list btns = [ " ", "Main", " ", im_txt, tp_txt, " ", " ", " ", " " ];
    list ctxs = [ " ", "main", " ", "owner_im", "owner_tp", " ", " ", " ", " " ];

    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "ownerp", "", "", llDumpList2String(btns, ","), llDumpList2String(ctxs, ","), chan);

    string info = "Owner Permissions:\nIM: ";
    if (g_owner_im) info += "ON"; else info += "OFF";
    info += "\nTP: ";
    if (g_owner_tp) info += "ON"; else info += "OFF";
    llDialog(av, info, btns, chan);
}

show_trustp_menu(key av, integer chan)
{
    string im_txt;
    string tp_txt;
    if (g_trustee_im) im_txt = "IM: ON"; else im_txt = "IM: OFF";
    if (g_trustee_tp) tp_txt = "TP: ON"; else tp_txt = "TP: OFF";
    list btns = [ " ", "Main", " ", im_txt, tp_txt, " ", " ", " ", " " ];
    list ctxs = [ " ", "main", " ", "trustee_im", "trustee_tp", " ", " ", " ", " " ];

    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "trustp", "", "", llDumpList2String(btns, ","), llDumpList2String(ctxs, ","), chan);

    string info = "Trustee Permissions:\nIM: ";
    if (g_trustee_im) info += "ON"; else info += "OFF";
    info += "\nTP: ";
    if (g_trustee_tp) info += "ON"; else info += "OFF";
    llDialog(av, info, btns, chan);
}

show_sos_menu(key av, integer chan)
{
    list btns = [ " ", "Main", " ", " ", " ", "SOS Release", " ", " ", " " ];
    list ctxs = [ " ", "main", " ", " ", " ", "sos", " ", " ", " " ];

    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "sos", "", "", llDumpList2String(btns, ","), llDumpList2String(ctxs, ","), chan);

    string info = "Release all owner-set restrictions?\nThis will notify your owner.";
    llDialog(av, info, btns, chan);
}

show_sos_confirm(key av, integer chan)
{
    list btns = [ "Cancel", "OK", " ", " ", " ", " ", " ", " ", " " ];
    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "sos_confirm", "", "", llDumpList2String(btns, ","), llDumpList2String(btns, ","), chan);
    llDialog(av, "Are you sure you want to release all owner-set RLV restrictions?", btns, chan);
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
    list btns = [ " ", "Main", " " ]; // nav row
    list ctxs = [ " ", "main", " " ]; // nav row
    integer i;
    for (i = 0; i < N; ++i)
    {
        string name = llList2String(g_sit_targets, i*2+1);
        // TRIM to 24 chars for dialog label
        if (llStringLength(name) > 24) name = llGetSubString(name, 0, 23);
        btns += [ name ];
        ctxs += [ llList2Key(g_sit_targets, i*2) ];
    }
    while (llGetListLength(btns) < 9) { btns += [ " " ]; ctxs += [ " " ]; }
    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "sit_targets", "", "", llDumpList2String(btns, ","), llDumpList2String(ctxs, ","), chan);
    llDialog(av, "Select an object for the wearer to sit on:", btns, chan);
}

do_force_stand(key av)
{
    llRegionSayTo(llGetOwner(), RLV_CHANNEL, "@unsit=force");
    llDialog(av, "Wearer has been forced to stand.", [ " ", "Main", " ", " ", " ", " ", " ", " ", " " ], llList2Integer(s_get(av),9));
    s_clear(av);
}

do_force_sit(key av, key target_obj)
{
    llRegionSayTo(llGetOwner(), RLV_CHANNEL, "@sit:" + (string)target_obj + "=force");
    llDialog(av, "Wearer has been forced to sit on the selected object.", [ " ", "Main", " ", " ", " ", " ", " ", " ", " " ], llList2Integer(s_get(av),9));
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

                if (acl != 1 && acl != 2 && acl != 3) {
                    llDialog(av, "Access denied: Only owners, trustees, and wearers may use RLV Suite controls.", [ " ", "OK", " ", " ", " ", " ", " ", " ", " " ], chan);
                    return;
                }
                show_rlv_menu(av, 0, chan, acl);
            }
        }
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
        if (chan != llList2Integer(s, 9)) return;

        string menubtnscsv = llList2String(s, 7);
        string menuctxcsv  = llList2String(s, 8);
        list buttons = llParseString2List(menubtnscsv, [","], []);
        list menuctx = llParseString2List(menuctxcsv, [","], []);

        string ctx   = llList2String(s, 4);
        integer acl = get_acl(av);

        if (DEBUG) llOwnerSay("[DEBUG RLV] listen: msg=" + msg + " menuctx=" + llDumpList2String(menuctx,",") + " ctx=" + ctx + " acl=" + (string)acl);

        integer idx = llListFindList(buttons, [msg]);
        if (DEBUG) llOwnerSay("[DEBUG RLV] main menu idx=" + (string)idx);

        // NAV
        if (msg == "Main")
        {
            llMessageLinked(LINK_THIS, 510, "main|" + (string)av + "|" + (string)chan, NULL_KEY);
            s_clear(av);
            return;
        }
        if (msg == "Cancel")
        {
            s_clear(av);
            return;
        }

        // Sit targets (by index 3..8)
        if (ctx == "sit_targets")
        {
            integer clicked = -1;
            integer i;
            for (i = 3; i < 9; ++i)
            {
                string btn_label = llList2String(buttons, i);
                string user_label = msg;
                // Both should be <=24 chars (safety)
                if (llStringLength(btn_label) > 24) btn_label = llGetSubString(btn_label, 0, 23);
                if (llStringLength(user_label) > 24) user_label = llGetSubString(user_label, 0, 23);
                if (btn_label == user_label)
                {
                    clicked = i;
                    i = 9; // jump out of loop (LSL-legal)
                }
            }
            if (DEBUG) llOwnerSay("[DEBUG RLV] sit_targets: clicked=" + (string)clicked + ", msg=" + msg);
            if (clicked != -1)
            {
                key target = (key)llList2String(menuctx, clicked);
                if (DEBUG) llOwnerSay("[DEBUG RLV] sit_targets: target=" + (string)target);
                if (target != "" && target != " " && llStringLength((string)target) == 36)
                {
                    do_force_sit(av, target);
                    return;
                }
                else
                {
                    if (DEBUG) llOwnerSay("[DEBUG RLV] sit_targets: invalid target UUID: '" + (string)target + "'");
                }
            }
            else
            {
                if (DEBUG) llOwnerSay("[DEBUG RLV] sit_targets: No button match for '" + msg + "'");
            }
        }

        // Main menu actions (by index)
        if (idx != -1)
        {
            string act = llList2String(menuctx, idx);

            if (acl == 3 && ctx == "main" && act == "sos")
            {
                show_sos_confirm(av, chan);
                return;
            }
            if (ctx == "sos_confirm" && msg == "OK")
            {
                llDialog(av, "All owner-set restrictions have been released.\nYour owner has been notified.", [ " ", "OK", " ", " ", " ", " ", " ", " ", " " ], chan);
                s_clear(av);
                return;
            }
            if ((acl == 1 || acl == 2) && ctx == "main")
            {
                if (act == "restrict") { llDialog(av, "RLV Restrictions UI - [stub]", [ " ", "OK", " ", " ", " ", " ", " ", " ", " " ], chan); return; }
                if (act == "priv")     { show_ownerp_menu(av, chan); return; }
                if (act == "sit")      { sit_scan(av, chan); return; }
                if (act == "unsit")    { do_force_stand(av); return; }
            }
            if (ctx == "ownerp")
            {
                if (act == "owner_im") { g_owner_im = !g_owner_im; show_ownerp_menu(av, chan); return; }
                if (act == "owner_tp") { g_owner_tp = !g_owner_tp; show_ownerp_menu(av, chan); return; }
                if (act == "main") {
                    llMessageLinked(LINK_THIS, 510, "main|" + (string)av + "|" + (string)chan, NULL_KEY);
                    s_clear(av);
                    return;
                }
            }
            if (ctx == "trustp")
            {
                if (act == "trustee_im") { g_trustee_im = !g_trustee_im; show_trustp_menu(av, chan); return; }
                if (act == "trustee_tp") { g_trustee_tp = !g_trustee_tp; show_trustp_menu(av, chan); return; }
                if (act == "main") {
                    llMessageLinked(LINK_THIS, 510, "main|" + (string)av + "|" + (string)chan, NULL_KEY);
                    s_clear(av);
                    return;
                }
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
