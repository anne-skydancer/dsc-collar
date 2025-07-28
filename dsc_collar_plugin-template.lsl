// =============================================================
//  UNIVERSAL PLUGIN TEMPLATE - Linden Script Language (LSL)
//  Compliant with DS Collar Core 1.4+
// =============================================================

integer DEBUG = TRUE;
integer PLUGIN_SN = 0;  // Will be set in state_entry()
string  PLUGIN_LABEL = "PluginName";
integer PLUGIN_MIN_ACL = 3;   // Default minimum access
string  PLUGIN_CONTEXT = "apps_pluginname";

// Session state ([av, page, csv, expiry, ctx, param, step, menucsv, chan, listen])
list    g_sessions;

/* ----------------- SESSION HELPERS ----------------- */
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
/* ----------------- SESSION HELPERS END ----------------- */

/* ----------------- MAIN EVENT LOOP ----------------- */
default
{
    state_entry()
    {
        // Generate a random 6-digit plugin serial number at runtime
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
        // Unregistration protocol, if you implement dynamic remove
        if ((num == 502) && llSubStringIndex(str, "unregister" + "|") == 0)
        {
            llMessageLinked(LINK_THIS, 502,
                "unregister" + "|" + (string)PLUGIN_SN,
                NULL_KEY);
            if (DEBUG) llOwnerSay("[PLUGIN] (" + PLUGIN_LABEL + ") Unregister notification sent to core (502).");
            return;
        }
        // Plugin-specific logic here
    }

    listen(integer chan, string nm, key av, string msg)
    {
        list s = s_get(av);
        if (llGetListLength(s) == 0) return;
        if (chan != llList2Integer(s,8)) return;
        string ctx = llList2String(s,4);
        // Add plugin dialog/menu logic here
    }

    timer()
    {
        // Session timeout logic
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
        if (change & CHANGED_OWNER)
        {
            llResetScript();
        }
    }
}
/* ============================================================= */
