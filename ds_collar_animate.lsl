// Animate Plugin: GUH logic, navigation at 0-2, Relax at 3, anims at 4-11, Main returns to GUH

integer DEBUG = TRUE;
integer PLUGIN_SN = 1002;
string  PLUGIN_LABEL = "Animate";
integer PLUGIN_MIN_ACL = 4;
string  PLUGIN_CONTEXT = "apps_animate";

integer g_has_perm = FALSE;
integer g_menu_chan = 0;
key     g_menu_user = NULL_KEY;
integer g_anim_page = 0;
integer g_page_size = 8; // 8 anims per page (indices 4-11)
list    g_anims;

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
        // Spec fix: informational dialog puts OK in center
        llDialog(user, "No animations in collar.", [ " ", "OK", " " ], -1);
        return;
    }
    g_anim_page = page;

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

    g_menu_chan = (integer)(-1000000.0 * llFrand(1.0) - 1.0);
    g_menu_user = user;
    llListenRemove(g_menu_chan);
    llListen(g_menu_chan, "", user, "");
    llDialog(user,
        "Animations (Page " + (string)(page + 1) + "):\n"
        + "Select an animation to play or Relax to stop all.\n"
        + "Navigation: << prev | Main | next >>",
        btns, g_menu_chan);

    if (DEBUG) llOwnerSay("[Animate] Menu → " + (string)user
        + " page=" + (string)page + " chan=" + (string)g_menu_chan
        + " btns=" + llDumpList2String(btns, ","));
}

start_anim(string anim)
{
    if (g_has_perm)
    {
        llStartAnimation(anim);
        if (DEBUG) llOwnerSay("[DEBUG] Playing animation: " + anim);
        // Keep menu open for user
        show_anim_menu(g_menu_user, g_anim_page);
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

default
{
    state_entry()
    {
        llRequestPermissions(llGetOwner(), PERMISSION_TRIGGER_ANIMATION);
        llMessageLinked(LINK_THIS, 500,
            "register|" + (string)PLUGIN_SN + "|" + PLUGIN_LABEL + "|"
            + (string)PLUGIN_MIN_ACL + "|" + PLUGIN_CONTEXT,
            NULL_KEY);
        if (DEBUG) llOwnerSay("[ANIMATE] Plugin ready.");
    }

    run_time_permissions(integer perm)
    {
        if (perm & PERMISSION_TRIGGER_ANIMATION) g_has_perm = TRUE;
    }

    link_message(integer sn, integer num, string str, key id)
    {
        // PATCHED: Only respond to reset, do not broadcast further
        if (num == -900 && str == "reset_owner")
        {
            llResetScript();
            return;
        }
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
        if (chan == g_menu_chan && id == g_menu_user)
        {
            if (msg == "<<") { show_anim_menu(g_menu_user, g_anim_page - 1); return; }
            if (msg == ">>") { show_anim_menu(g_menu_user, g_anim_page + 1); return; }
            if (msg == "Main")
            {
                // Return to main menu in GUH (link_message 510 is the plugin signal used)
                llMessageLinked(LINK_THIS, 510, "main|" + (string)g_menu_user + "|0", NULL_KEY);
                return;
            }
            if (msg == "Relax")
            {
                stop_all_anims();
                show_anim_menu(g_menu_user, g_anim_page);
                return;
            }
            integer idx = llListFindList(g_anims, [msg]);
            if (idx != -1)
            {
                start_anim(msg);
                return;
            }
        }
    }

    changed(integer change)
    {
        /* ============================================================
           BLOCK: OWNER CHANGE RESET HANDLER
           Resets on owner change, no rebroadcast.
           ============================================================ */
        if (change & CHANGED_OWNER)
        {
            llOwnerSay("[ANIMATE] Owner changed. Resetting animate plugin.");
            llResetScript();
        }
    }
}
