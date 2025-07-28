// =============================================================
//  ds_collar_blacklist - Blacklist Management (v1.0.4, modular, sessioned)
//  UNIVERSAL PLUGIN TEMPLATE - DS Collar Core 1.4+ COMPLIANT
// =============================================================

integer DEBUG = TRUE;
integer PLUGIN_SN = 0;
string  PLUGIN_LABEL = "Blacklist";
integer PLUGIN_MIN_ACL = 3;
string  PLUGIN_CONTEXT = "access_blacklist";

integer SCAN_RANGE = 10;
integer DIALOG_PAGE_SIZE = 9;
float   DIALOG_TIMEOUT = 180.0;

// Session state ([av, page, csv, expiry, ctx, param, step, menucsv, chan, listen])
list    g_sessions;

/* ---- Blacklist state ---- */
list g_blacklist = [];
list g_blacklist_names = [];
key g_owner = NULL_KEY;
list g_trustees = [];
key g_wearer = NULL_KEY;

/* ========== Helpers (Access-style) ========== */
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
list build_numbered_buttons(list labels) {
    list buttons = [];
    integer i;
    for (i = 0; i < llGetListLength(labels); ++i) buttons += (string)(i+1);
    while (llGetListLength(buttons) % 3 != 0) buttons += " ";
    return buttons;
}
string numbered_menu_text(list labels) {
    string text = "";
    integer i;
    for (i = 0; i < llGetListLength(labels); ++i)
        text += (string)(i+1) + ". " + llList2String(labels,i) + "\n";
    return text;
}

/* -------- Blacklist logic -------- */
show_blacklist_menu(key av, integer chan)
{
    string msg = "Blacklisted users:\n";
    integer i;
    for (i = 0; i < llGetListLength(g_blacklist); ++i) {
        msg += "  " + llList2String(g_blacklist_names, i) + "\n";
    }
    if (llGetListLength(g_blacklist) == 0) msg += "  (none)\n";
    list btns = ["Add", "Remove", "Back"];
    while (llGetListLength(btns) % 3 != 0) btns += " ";
    s_set(av, 0, "", llGetUnixTime() + DIALOG_TIMEOUT, "main", "", "", "", chan);
    llDialog(av, msg, btns, chan);
}
begin_add_blacklist(key av, integer chan)
{
    llSensor("", NULL_KEY, AGENT, SCAN_RANGE, TWO_PI);
    s_set(av, 0, "", llGetUnixTime() + DIALOG_TIMEOUT, "blacklist_add", "", "", "", chan);
}
begin_remove_blacklist(key av, integer chan)
{
    if (llGetListLength(g_blacklist) == 0) {
        show_blacklist_menu(av, chan);
        return;
    }
    list display = [];
    integer i;
    for (i=0; i<llGetListLength(g_blacklist); ++i)
        display += llKey2Name(llList2Key(g_blacklist,i));
    string csv = llDumpList2String(g_blacklist, ",");
    float expiry = llGetUnixTime() + DIALOG_TIMEOUT;
    s_set(av, 0, csv, expiry, "blacklist_remove", "", "", csv, chan);
    string dialog_body = "Select avatar to unblacklist:\n" + numbered_menu_text(display);
    list buttons = build_numbered_buttons(display);
    llDialog(av, dialog_body, buttons, chan);
}

send_state_sync()
{
    string trust_csv = " ";
    string trust_hon = " ";
    string bl_csv = llDumpList2String(g_blacklist, ",");
    string pub = " ";
    string locked = " ";
    llMessageLinked(LINK_THIS, 520,
        "state_sync|" +
        (string)g_owner + "|" +
        "" + "|" + // owner honorific
        trust_csv + "|" +
        trust_hon + "|" +
        bl_csv + "|" +
        pub + "|" +
        locked,
        NULL_KEY);
}
update_state(list p)
{
    g_owner = (key)llList2String(p, 1);
    g_trustees = llParseString2List(llList2String(p, 3), [","], []);
    g_blacklist = [];
    g_blacklist_names = [];
    string bl_csv = llList2String(p, 5);
    if (bl_csv != " ") {
        g_blacklist = llParseString2List(bl_csv, [","], []);
        integer i;
        for (i = 0; i < llGetListLength(g_blacklist); ++i) {
            g_blacklist_names += [llKey2Name(llList2Key(g_blacklist, i))];
        }
    }
    g_wearer = llGetOwner();
}

/* ----------------- MAIN EVENT LOOP ----------------- */
default
{
    state_entry()
    {
        if (PLUGIN_SN == 0)
            PLUGIN_SN = 100000 + (integer)(llFrand(899999));
        if (DEBUG) llOwnerSay("[PLUGIN] (" + PLUGIN_LABEL + ") Ready. Serial: " + (string)PLUGIN_SN);
        llSetTimerEvent(1.0);
    }
    link_message(integer sn, integer num, string str, key id)
    {
        // Registration protocol: respond to poll (500)
        if ((num == 500) && llSubStringIndex(str, "register_now" + "|") == 0)
        {
            string script_req = llGetSubString(str, 13, -1);
            if (script_req == llGetScriptName())
            {
                llMessageLinked(LINK_THIS, 501,
                    "register" + "|" + (string)PLUGIN_SN + "|" + PLUGIN_LABEL + "|" +
                    (string)PLUGIN_MIN_ACL + "|" + PLUGIN_CONTEXT + "|" + llGetScriptName(),
                    NULL_KEY);
                if (DEBUG) llOwnerSay("[PLUGIN] (" + PLUGIN_LABEL + ") Registration reply sent to core (501).");
            }
            return;
        }
        // Receive state sync from core
        if (num == 520)
        {
            list p = llParseString2List(str, ["|"], []);
            if (llGetListLength(p) == 8 && llList2String(p, 0) == "state_sync") {
                update_state(p);
            }
            return;
        }
        // Plugin menu dispatch from core
        if (num == 510)
        {
            list p = llParseString2List(str, ["|"], []);
            if (llGetListLength(p) != 3) return;
            string ctx = llList2String(p, 0);
            key user = (key)llList2String(p, 1);
            integer chan = (integer)llList2String(p, 2);
            if (ctx == PLUGIN_CONTEXT) {
                show_blacklist_menu(user, chan);
            }
            return;
        }
    }
    listen(integer chan, string nm, key av, string msg)
    {
        list sess = s_get(av);
        if (llGetListLength(sess) == 0) return;
        integer dialog_chan = llList2Integer(sess, 8);
        if (chan != dialog_chan) return;
        string ctx = llList2String(sess, 4);

        if (ctx == "main")
        {
            if (msg == "Back") {
                llMessageLinked(LINK_THIS, 510, "access|" + (string)av + "|" + (string)chan, NULL_KEY);
                return;
            }
            if (msg == "Add") {
                begin_add_blacklist(av, chan);
                return;
            }
            if (msg == "Remove") {
                begin_remove_blacklist(av, chan);
                return;
            }
        }
        // --- Blacklist add selection ---
        if (ctx == "blacklist_add_pick")
        {
            list keys = llParseString2List(llList2String(sess,2), [","], []);
            integer sel = (integer)msg;
            if (sel > 0 && sel <= llGetListLength(keys)) {
                key picked = llList2Key(keys, sel-1);
                if (llListFindList(g_blacklist, [picked]) == -1 &&
                    picked != g_owner && picked != g_wearer)
                {
                    g_blacklist += [picked];
                    g_blacklist_names += [llKey2Name(picked)];
                    send_state_sync();
                }
                show_blacklist_menu(av, dialog_chan);
                s_clear(av);
                return;
            }
        }
        // --- Blacklist remove selection ---
        if (ctx == "blacklist_remove")
        {
            list keys = llParseString2List(llList2String(sess,2), [","], []);
            integer sel = (integer)msg;
            if (sel > 0 && sel <= llGetListLength(keys)) {
                key picked = llList2Key(keys, sel-1);
                integer idx = llListFindList(g_blacklist, [picked]);
                if (idx != -1) {
                    g_blacklist = llDeleteSubList(g_blacklist, idx, idx);
                    g_blacklist_names = llDeleteSubList(g_blacklist_names, idx, idx);
                    send_state_sync();
                }
                show_blacklist_menu(av, dialog_chan);
                s_clear(av);
                return;
            }
        }
    }
    sensor(integer n)
    {
        integer i;
        for (i = 0; i < llGetListLength(g_sessions); i += 10)
        {
            key av = llList2Key(g_sessions, i);
            string ctx = llList2String(g_sessions, i + 4);
            integer dialog_chan = llList2Integer(g_sessions, i + 8);
            if (ctx == "blacklist_add")
            {
                list cands = [];
                integer j;
                for (j = 0; j < n; ++j)
                {
                    key k = llDetectedKey(j);
                    if (k == av) jump skip_current;
                    if (llListFindList(g_blacklist, [k]) != -1) jump skip_current;
                    if (k == g_owner) jump skip_current;
                    if (k == g_wearer) jump skip_current;
                    cands += k;
                    @skip_current;
                }

                if (llGetListLength(cands) == 0)
                {
                    llDialog(av, "No avatars found within 10 meters.", [ " ", "OK", " " ], dialog_chan);
                    s_clear(av);
                    return;
                }
                list labels = [];
                integer k;
                for (k = 0; k < llGetListLength(cands); ++k)
                    labels += llKey2Name(llList2Key(cands, k));
                string dialog_body = "Blacklist an avatar:\n" + numbered_menu_text(labels);
                list buttons = build_numbered_buttons(labels);
                string cands_csv = llDumpList2String(cands, ",");
                s_set(av, 0, cands_csv, llGetUnixTime() + DIALOG_TIMEOUT, "blacklist_add_pick", "", "", cands_csv, dialog_chan);
                llDialog(av, dialog_body, buttons, dialog_chan);
                return;
            }
        }
    }
    no_sensor()
    {
        integer i;
        for (i = 0; i < llGetListLength(g_sessions); i += 10)
        {
            key av = llList2Key(g_sessions, i);
            string ctx = llList2String(g_sessions, i + 4);
            integer dialog_chan = llList2Integer(g_sessions, i + 8);
            if (ctx == "blacklist_add")
            {
                llDialog(av, "No avatars found within 10 meters.", [ " ", "OK", " " ], dialog_chan);
                s_clear(av);
            }
        }
    }
    timer()
    {
        integer now = llGetUnixTime();
        integer i = 0;
        while (i < llGetListLength(g_sessions)) {
            if (now > llList2Float(g_sessions, i+3))
                s_clear(llList2Key(g_sessions, i));
            else i += 10;
        }
    }
    changed(integer change)
    {
        if (change & CHANGED_OWNER) {
            llResetScript();
        }
    }
}
// =============================================================
