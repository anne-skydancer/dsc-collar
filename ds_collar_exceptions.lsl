/* =============================================================
   TITLE: ds_collar_rlv_exceptions - RLV Owner/Trustee Exception Plugin
   VERSION: 1.0
   REVISION: 2025-07-15
   ============================================================= */

/* ==================== GLOBAL STATE ==================== */
integer DEBUG = TRUE;

// Exceptions state (expand for trustees as needed)
integer ex_owner_im = TRUE;  // Owner IM allowed by default
integer ex_owner_tp = TRUE;  // Owner force TP allowed by default

list g_sessions;
/* ==================== SESSION HELPERS ==================== */
integer s_idx(key av) { return llListFindList(g_sessions, [av]); }
integer s_set(key av, integer page, float expiry, string ctx, string param, integer chan)
{
    integer i = s_idx(av);
    if (~i) {
        integer old = llList2Integer(g_sessions, i+6);
        if (old != -1) llListenRemove(old);
        g_sessions = llDeleteSubList(g_sessions, i, i+6);
    }
    integer lh = llListen(chan, "", av, "");
    g_sessions += [av, page, expiry, ctx, param, chan, lh];
    return TRUE;
}
integer s_clear(key av)
{
    integer i = s_idx(av);
    if (~i) {
        integer old = llList2Integer(g_sessions, i+6);
        if (old != -1) llListenRemove(old);
        g_sessions = llDeleteSubList(g_sessions, i, i+6);
    }
    return TRUE;
}
list s_get(key av)
{
    integer i = s_idx(av);
    if (~i) return llList2List(g_sessions, i, i+6);
    return [];
}
/* ==================== MENU/UI ==================== */
show_main_menu(key av, integer chan)
{
    string im_btn = ex_owner_im ? "Allow IM" : "Deny IM";
    string tp_btn = ex_owner_tp ? "Force TP ON" : "Force TP OFF";
    // Top options first, then Back (index 0), blank (1), Cancel (2)
    list btns = [ "Back", " ", "Cancel", im_btn, tp_btn ];
    while (llGetListLength(btns) % 3 != 0) btns += " ";

    s_set(av, 0, llGetUnixTime()+120.0, "main", "", chan);

    if (DEBUG) llOwnerSay("[DEBUG] show_main_menu → " + (string)av + " btns=" + llDumpList2String(btns, ","));
    llDialog(av, "Exceptions Menu:\nToggle Owner Exceptions.", btns, chan);
}
/* ==================== TIMEOUT ==================== */
timeout_check()
{
    integer now = llGetUnixTime();
    integer i = 0;
    while (i < llGetListLength(g_sessions))
    {
        float exp = llList2Float(g_sessions, i+2);
        key  av  = llList2Key(g_sessions, i);
        if (now > exp)
            s_clear(av);
        else i += 7;
    }
}
/* ==================== MAIN STATE ==================== */
default
{
    state_entry()
    {
        /* Register plugin as rlv_exceptions, serial 1012, min_acl 1 (owner) */
        llMessageLinked(LINK_THIS, 500, "register|1012|Exceptions|1|rlv_exceptions", NULL_KEY);
        llSetTimerEvent(1.0);
        if (DEBUG) llOwnerSay("[RLV] Exceptions plugin ready.");
    }

    link_message(integer sender, integer num, string str, key id)
    {
        // ONLY handle menus and related plugin logic, not reset_owner!
        if (num == 510)
        {
            list a = llParseString2List(str, ["|"], []);
            if (llList2String(a, 0) == "rlv_exceptions" && llGetListLength(a) >= 3)
            {
                key av = (key)llList2String(a, 1);
                integer chan = (integer)llList2String(a, 2);
                show_main_menu(av, chan);
            }
        }
    }

    listen(integer chan, string nm, key av, string msg)
    {
        list s = s_get(av);
        if (llGetListLength(s) == 0) return;
        if (chan != llList2Integer(s, 5)) return;
        string ctx = llList2String(s, 3);

        if (ctx == "main")
        {
            if (msg == "Allow IM" || msg == "Deny IM")
            {
                ex_owner_im = !ex_owner_im;
                // TODO: Actually send @sendim:<uuid>=add/rem to enforce
                if (DEBUG) llOwnerSay("[RLV] Owner IM Exception now: " + (string)ex_owner_im);
                show_main_menu(av, chan);
                return;
            }
            if (msg == "Force TP ON" || msg == "Force TP OFF")
            {
                ex_owner_tp = !ex_owner_tp;
                // TODO: Actually send @accepttp:<uuid>=add/rem to enforce
                if (DEBUG) llOwnerSay("[RLV] Owner TP Exception now: " + (string)ex_owner_tp);
                show_main_menu(av, chan);
                return;
            }
            if (msg == "Back")
            {
                llMessageLinked(LINK_THIS, 510, "rlv|" + (string)av + "|" + (string)chan, NULL_KEY);
                s_clear(av);
                return;
            }
            if (msg == "Cancel")
            {
                s_clear(av);
                return;
            }
        }
    }
    timer() { timeout_check(); }

    changed(integer change)
    {
        /* =============================
           OWNER CHANGE RESET HANDLER
           Resets on owner change.
           ============================= */
        if (change & CHANGED_OWNER)
        {
            llResetScript();
        }
    }
}
