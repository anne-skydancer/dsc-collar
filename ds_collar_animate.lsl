/* =============================================================
   TITLE: ds_collar_animate - Avatar posing (Universal Template)
   VERSION: 1.1-U (Universal Template, dynamic serial, best practices)
   REVISION: 2025-07-18
   ============================================================= */

/* ================= UNIVERSAL HEADER ================= */

integer DEBUG = TRUE;
integer PLUGIN_SN = 0;  // Will be set in state_entry()
string  PLUGIN_LABEL = "Animate";
integer PLUGIN_MIN_ACL = 4;
string  PLUGIN_CONTEXT = "apps_animate";

integer g_has_perm = FALSE;

// Session management variables
list    g_sessions;

// Animate plugin specific globals
integer g_page_size = 8; // 8 anims per page (indices 4-11)
list    g_anims;

/* ----------------- SESSION HELPERS ----------------- */
integer s_idx(key av) { return llListFindList(g_sessions, [av]); }

integer s_set(key av, integer page, string csv, float expiry, string ctx, string param, string step, string menucsv, integer chan)
{
    integer i = s_idx(av);
    if (~i) {
        integer old_listen = llList2Integer(g_sessions, i+9);
        if (old_listen != -1) llListenRemove(old_listen);
        g_sessions = llDeleteSubList(g_sessions, i, i+9);
    }
    integer listen_handle = llListen(chan, "", av, "");
    g_sessions += [av, page, csv, expiry, ctx, param, step, menucsv, chan, listen_handle];
    return TRUE;
}

integer s_clear(key av)
{
    integer i = s_idx(av);
    if (~i) {
        integer old_listen = llList2Integer(g_sessions, i+9);
        if (old_listen != -1) llListenRemove(old_listen);
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

/* =============== ANIMATE PLUGIN HELPERS =============== */

get_anims()
{
    g_anims = [];
    integer n = llGetInventoryNumber(INVENTORY_ANIMATION);
    integer i = 0;
    while (i < n)
    {
        g_anims += [llGetInventoryName(INVENTORY_ANIMATION, i)];
        i += 1;
    }
    g_anims = llListSort(g_anims, 1, TRUE); // Alphabetical order
}

show_anim_menu(key user, integer page)
{
    get_anims();
    integer total = llGetListLength(g_anims);
    if (total == 0)
    {
        llDialog(user, "No animations in collar.", ["OK"], -1);
        return;
    }

    // Calculate anims for this page
    integer start = page * g_page_size;
    integer end = start + g_page_size - 1;
    if (end >= total) end = total - 1;

    list anim_btns = [];
    integer i = start;
    while (i <= end && i < total)
    {
        anim_btns += llList2String(g_anims, i);
        i += 1;
    }
    // Pad to 8 entries (so anims always fill 4-11)
    while (llGetListLength(anim_btns) < g_page_size) anim_btns += " ";

    // Build nav row (0–3)
    string nav_back = " ";
    if (page > 0) nav_back = "<<";
    string nav_next = " ";
    if (end < total - 1) nav_next = ">>";

    list btns = [nav_back, "Main", nav_next, "Relax"] + anim_btns;

    // Ensure exactly 12 buttons (indices 0–11)
    while (llGetListLength(btns) < 12) btns += " ";

    integer dialog_chan = (integer)(-1000000.0 * llFrand(1.0) - 1.0);
    float expiry = llGetUnixTime() + 180.0;

    // Store session with current page as 'page' and context as PLUGIN_CONTEXT
    s_set(user, page, "", expiry, PLUGIN_CONTEXT, "", "", "", dialog_chan);

    llDialog(user,
        "Animations (Page " + (string)(page + 1) + "):\n"
        + "Select an animation to play or Relax to stop all.\n"
        + "Navigation: << prev | Main | next >>",
        btns, dialog_chan);

    if (DEBUG) llOwnerSay("[Animate] Menu → " + (string)user
        + " page=" + (string)page + " chan=" + (string)dialog_chan
        + " btns=" + llDumpList2String(btns, ","));
}

start_anim(key av, string anim)
{
    if (g_has_perm)
    {
        llStartAnimation(anim);
        if (DEBUG) llOwnerSay("[DEBUG] Playing animation: " + anim);
        // Refresh menu for user
        list sess = s_get(av);
        integer page = 0;
        if (llGetListLength(sess) > 0) page = llList2Integer(sess,1);
        show_anim_menu(av, page);
    }
    else
    {
        llOwnerSay("Collar needs permission to animate you. Touch again after accepting.");
        llRequestPermissions(llGetOwner(), PERMISSION_TRIGGER_ANIMATION);
    }
}

stop_all_anims()
{
    integer i;
    integer n = llGetInventoryNumber(INVENTORY_ANIMATION);
    for (i = 0; i < n; ++i)
    {
        llStopAnimation(llGetInventoryName(INVENTORY_ANIMATION, i));
    }
    if (DEBUG) llOwnerSay("[DEBUG] Stopped all animations.");
}

timeout_check()
{
    integer now = llGetUnixTime();
    integer i = 0;
    while (i < llGetListLength(g_sessions)) {
        float expiry = llList2Float(g_sessions, i+3);
        key av = llList2Key(g_sessions, i);
        if (now > expiry) {
            llInstantMessage(av, "Menu timed out. Please try again.");
            s_clear(av);
        } else {
            i += 10;
        }
    }
}

/* ================== MAIN EVENT LOOP ================== */
default
{
    state_entry()
    {
        PLUGIN_SN = 100000 + (integer)(llFrand(899999));
        llMessageLinked(LINK_THIS, 500,
            "register"  "|" + (string)PLUGIN_SN + "|" + PLUGIN_LABEL + "|" +
            (string)PLUGIN_MIN_ACL + "|" + PLUGIN_CONTEXT,
            NULL_KEY);
        llRequestPermissions(llGetOwner(), PERMISSION_TRIGGER_ANIMATION);
        if (DEBUG) llOwnerSay("[ANIMATE] Plugin ready. Serial: " + (string)PLUGIN_SN);
        llSetTimerEvent(1.0);
    }

    run_time_permissions(integer perm)
    {
        if (perm & PERMISSION_TRIGGER_ANIMATION)
            g_has_perm = TRUE;
    }

    link_message(integer sn, integer num, string str, key id)
    {
        // GUH: "apps_animate|user|chan"
        list p = llParseString2List(str, ["|"], []);
        if (llList2String(p, 0) == PLUGIN_CONTEXT && llGetListLength(p) >= 3)
        {
            key user = (key)llList2String(p, 1);
            show_anim_menu(user, 0);
        }
    }

    listen(integer chan, string name, key id, string msg)
    {
        list sess = s_get(id);
        if (llGetListLength(sess) == 0) return;
        integer dialog_chan = llList2Integer(sess, 8);
        if (chan != dialog_chan) return;

        integer page = llList2Integer(sess, 1);

        if (msg == "<<") { show_anim_menu(id, page - 1); return; }
        if (msg == ">>") { show_anim_menu(id, page + 1); return; }
        if (msg == "Main")
        {
            // Return to main menu in GUH (link_message 510 is the plugin signal used)
            llMessageLinked(LINK_THIS, 510, "apps" + "|" + (string)id + "|" + "0", NULL_KEY);
            return;
        }
        if (msg == "Relax")
        {
            stop_all_anims();
            show_anim_menu(id, page);
            return;
        }
        integer idx = llListFindList(g_anims, [msg]);
        if (idx != -1)
        {
            start_anim(id, msg);
            return;
        }
    }

    timer()
    {
        timeout_check();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            llOwnerSay("[ANIMATE] Owner changed. Resetting animate plugin.");
            llResetScript();
        }
    }
}
