/* =============================================================
   TITLE: ds_collar_animate - Animation Menu & Playback Plugin
   VERSION: 1.0
   REVISION: 2025-07-06
   ============================================================= */

/* =============================================================
   BLOCK: GLOBAL VARIABLES & CONFIG BEGIN
   ============================================================= */
/*
    Collar Animate Plugin (Strict LSL, 2025-07-06)
    - Handles animation menu, plays animations for the collar wearer.
    - Registers itself as a plugin with the GUH core.
    - Uses consistent session management with other GUH scripts.
*/

integer DEBUG = TRUE;

/* Plugin configuration constants */
integer page_size      = 9;      // Dialog buttons per page
float   dialog_timeout = 180.0;

/* Global animation/plugin state */
list    g_anim_names   = [];     // Sorted animation names
integer g_have_perms   = FALSE;  // TRUE if PERMISSION_TRIGGER_ANIMATION granted
string  g_current_anim = "";     // Name of animation currently playing
string g_queued_anim = "";

/* Session cache: [av, page, csv, expiry, ctx, param, step, menucsv, chan, listen] */
list    g_sessions;
/* =============================================================
   BLOCK: GLOBAL VARIABLES & CONFIG END
   ============================================================= */


/* =============================================================
   BLOCK: SESSION HELPERS BEGIN
   ============================================================= */
/*
    Helpers for session storage, removal, lookup.
    All helpers match conventions in dsc_core and access plugins.
*/

integer s_idx(key av) { return llListFindList(g_sessions, [av]); }

integer s_set(key av, integer page, string csv, float expiry, string ctx,
              string param, string step, string menucsv, integer chan)
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
/* =============================================================
   BLOCK: SESSION HELPERS END
   ============================================================= */


/* =============================================================
   BLOCK: ANIMATION HANDLING BEGIN
   ============================================================= */
/*
    Functions to play, stop, and queue animations, handling permissions.
    Follows strict LSL (no ternaries, explicit if/else).
*/

play_anim(string anim)
{
    if (!g_have_perms)
    {
        /* Queue animation until permissions are granted */
        g_queued_anim = anim;
        llRequestPermissions(llGetOwner(), PERMISSION_TRIGGER_ANIMATION);
        return;
    }

    if (g_current_anim != "")
        llStopAnimation(g_current_anim);

    llStartAnimation(anim);
    g_current_anim = anim;
}
/* =============================================================
   BLOCK: ANIMATION HANDLING END
   ============================================================= */


/* =============================================================
   BLOCK: MENU BUILDING BEGIN
   ============================================================= */
/*
    Dialog/menu utilities for animation pages and navigation.
    - Button order reversed so nav is always on the bottom row.
    - Navigation rows: « Prev | Relax | Next »
    - Pads dialog to multiples of 3.
*/

list reorder_buttons(list buttons)
{
    integer L = llGetListLength(buttons);
    /* Navigation row is always the last three buttons */
    list nav  = llList2List(buttons, L - 3, L - 1);
    list body = llList2List(buttons, 0, L - 4);

    integer rows = llGetListLength(body) / 3;
    list reversed_body = [];
    integer r;
    for (r = rows - 1; r >= 0; --r) {
        reversed_body += llList2List(body, r * 3, r * 3 + 2);
    }
    return nav + reversed_body;
}

list slice(list L, integer start, integer count)
{
    return llList2List(L, start, start + count - 1);
}

show_anim_menu(key av, integer page, integer chan)
{
    integer total = llGetListLength(g_anim_names);
    integer pages = (total + page_size - 1) / page_size;

    integer start = page * page_size;
    list page_anims = slice(g_anim_names, start, page_size);

    list buttons = page_anims;

    /* Navigation row */
    if (page > 0)        buttons += ["« Prev"];
    else                 buttons += [" "];
    buttons += ["Relax"];
    if (page < pages - 1) buttons += ["Next »"];
    else                  buttons += [" "];

    /* Pad to multiple of 3 for llDialog */
    while (llGetListLength(buttons) % 3 != 0)
        buttons += [" "];

    buttons = reorder_buttons(buttons);

    s_set(av, page, "", llGetUnixTime() + dialog_timeout,
          "anim_menu", "", "", "", chan);

    string header = "Select an animation (page " +
                    (string)(page + 1) + "/" + (string)pages + "):";
    llDialog(av, header, buttons, chan);
}
/* =============================================================
   BLOCK: MENU BUILDING END
   ============================================================= */


/* =============================================================
   BLOCK: TIMEOUT MANAGEMENT BEGIN
   ============================================================= */
/*
    Dialog timeout logic, clearing expired sessions and notifying avatars.
*/

timeout_check()
{
    integer now = llGetUnixTime();
    integer i = 0;
    while (i < llGetListLength(g_sessions))
    {
        float exp = llList2Float(g_sessions, i+3);
        key  av  = llList2Key(g_sessions, i);
        if (now > exp)
        {
            llInstantMessage(av, "Menu timed out.");
            s_clear(av);
        }
        else i += 10;
    }
}
/* =============================================================
   BLOCK: TIMEOUT MANAGEMENT END
   ============================================================= */


/* =============================================================
   BLOCK: MAIN EVENT LOOP BEGIN
   ============================================================= */
/*
    Main state and event handling for GUH Animate plugin:
    - state_entry:     Inventory scan, permission request, GUH registration.
    - run_time_permissions: Handles queued animation play after perms arrive.
    - link_message:    GUH plugin invocation opens anim menu.
    - listen:          Handles menu navigation, anim trigger, relax.
    - timer:           Calls timeout_check.
    - changed:         Requests permission again if collar owner changes.
*/

default
{
    state_entry()
    {
        /* Gather all animations from inventory */
        integer count = llGetInventoryNumber(INVENTORY_ANIMATION);
        integer i;
        for (i = 0; i < count; i++)
            g_anim_names += llGetInventoryName(INVENTORY_ANIMATION, i);
        g_anim_names = llListSort(g_anim_names, 1, TRUE);

        /* Request animation perms pre-emptively */
        llRequestPermissions(llGetOwner(), PERMISSION_TRIGGER_ANIMATION);

        /* Register plugin with GUH: serial 1002, ACL 4 (anyone not blacklisted) */
        llMessageLinked(LINK_THIS, 500, "register|1002|Animate|4|animate", NULL_KEY);

        llSetTimerEvent(1.0);
        if (DEBUG) llOwnerSay("[Animate] ready, " + (string)count + " anims.");
    }

    run_time_permissions(integer perms)
    {
        if (perms & PERMISSION_TRIGGER_ANIMATION)
        {
            g_have_perms = TRUE;
            string queued = llGetObjectDesc();
            if (queued != "")
            {
                llStartAnimation(queued);
                g_current_anim = queued;
                llSetObjectDesc("");
            }
        }
    }

    link_message(integer sender, integer num, string str, key id)
    {
        if (num == 510)
        {
            list a = llParseString2List(str, ["|"], []);
            if (llList2String(a, 0) == "animate" && llGetListLength(a) >= 3)
            {
                key av   = (key)llList2String(a, 1);
                integer chan = (integer)llList2String(a, 2);
                show_anim_menu(av, 0, chan);
            }
        }
    }

    listen(integer chan, string nm, key av, string msg)
    {
        list s = s_get(av);
        if (llGetListLength(s) == 0) return;
        integer session_chan = llList2Integer(s, 8);
        if (chan != session_chan) return;

        integer page = llList2Integer(s, 1);

        /* NAVIGATION */
        if (msg == "« Prev") { show_anim_menu(av, page - 1, chan); return; }
        if (msg == "Next »") { show_anim_menu(av, page + 1, chan); return; }
        if (msg == "Relax")
        {
            if (g_current_anim != "") llStopAnimation(g_current_anim);
            g_current_anim = "";
            s_clear(av);
            return;
        }

        /* Animation buttons */
        if (llListFindList(g_anim_names, [msg]) != -1)
        {
            play_anim(msg);
            // Redraw the menu to remain open after animation starts
            show_anim_menu(av, page, chan);
            return;
        }
    }

    timer() { timeout_check(); }

    changed(integer c)
    {
        if (c & CHANGED_OWNER)
        {
            g_have_perms = FALSE;
            g_current_anim = "";
            llRequestPermissions(llGetOwner(), PERMISSION_TRIGGER_ANIMATION);
        }
    }
}
/* =============================================================
   BLOCK: MAIN EVENT LOOP END
   ============================================================= */
