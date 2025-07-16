/* =============================================================
   TITLE: ds_collar_animate - Animation Menu & Playback Plugin
   VERSION: 1.1
   REVISION: 2025-07-06
   ============================================================= */

integer DEBUG = TRUE;
integer PLUGIN_SN = 1002;
string  PLUGIN_LABEL = "Animate";
integer PLUGIN_MIN_ACL = 4;
string  PLUGIN_CONTEXT = "apps_animate";

integer g_has_perm = FALSE;
integer g_menu_chan = 0;
key     g_menu_user = NULL_KEY;
integer g_anim_page = 0;
integer g_page_size = 8;
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
    g_anim_page = page;
    integer start = page * g_page_size;
    integer end = start + g_page_size - 1;
    if (end >= total) end = total - 1;

    list btns = [];
    integer i = start;
    while (i <= end && i < total)
    {
        btns += llList2String(g_anims, i);
        i += 1;
    }
    // Pad for dialog (LSL: max 12 per dialog)
    while (llGetListLength(btns) < g_page_size) btns += " ";

    list nav = [];
    if (page > 0) nav += ["Prev"];
    else nav += [" "];
    nav += ["Stop All"];
    if (end < total - 1) nav += ["Next"];
    else nav += [" "];

    btns += nav;
    btns += ["Back"];
    while (llGetListLength(btns) % 3 != 0) btns += " ";

    g_menu_chan = (integer)(-1000000.0 * llFrand(1.0) - 1.0);
    g_menu_user = user;
    llListenRemove(g_menu_chan);
    llListen(g_menu_chan, "", user, "");
    llDialog(user, "Animations (Page " + (string)(page + 1) + "):", btns, g_menu_chan);
}

start_anim(string anim)
{
    if (g_has_perm)
    {
        llStartAnimation(anim);
        if (DEBUG) llOwnerSay("[DEBUG] Playing animation: " + anim);
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

// ----- DEFAULT STATE -----
default
{
    state_entry()
    {
        llRequestPermissions(llGetOwner(), PERMISSION_TRIGGER_ANIMATION);
        llMessageLinked(LINK_THIS, 500,
            "register|" + (string)PLUGIN_SN + "|" + PLUGIN_LABEL + "|" +
            (string)PLUGIN_MIN_ACL + "|" + PLUGIN_CONTEXT,
            NULL_KEY);
        if (DEBUG) llOwnerSay("[ANIMATE] Plugin ready.");
    }

    run_time_permissions(integer perm)
    {
        if (perm & PERMISSION_TRIGGER_ANIMATION) g_has_perm = TRUE;
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
        if (chan == g_menu_chan && id == g_menu_user)
        {
            if (msg == "Prev") { show_anim_menu(g_menu_user, g_anim_page - 1); return; }
            if (msg == "Next") { show_anim_menu(g_menu_user, g_anim_page + 1); return; }
            if (msg == "Stop All") { stop_all_anims(); show_anim_menu(g_menu_user, g_anim_page); return; }
            if (msg == "Back") { return; }
            integer idx = llListFindList(g_anims, [msg]);
            if (idx != -1) start_anim(msg);
        }
    }
}
