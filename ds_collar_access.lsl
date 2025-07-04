/* =============================================================
   Title: ds_collar_access - Access Control
   Version: 1.0.0
   Revision: 1
   ============================================================= */

/* =============================================================
   BLOCK: GLOBAL VARIABLES BEGIN
   ============================================================= */
/*
    Persistent configuration and session state for Access plugin.
    - DEBUG: Debugging output toggle.
    - scan_range: Range for avatar detection when adding/removing.
    - dialog_page_size: Number of buttons per dialog page.
    - dialog_timeout: Dialog/session timeout in seconds.
    - g_owner, g_owner_honorific: Owner's key and honorific string.
    - g_trustees, g_trustee_honorifics: Lists for trustees and their titles.
    - g_blacklist: List of blacklisted user keys.
    - g_public_access: Boolean for public menu use.
    - g_locked: Lock state (boolean).
    - g_sessions: Session cache for all open dialogs [av, page, ...]
*/
integer DEBUG = TRUE;

float   scan_range = 10.0;
integer dialog_page_size = 9;
float   dialog_timeout = 180.0;

// ========== Persistent State ==========
key     g_owner = NULL_KEY;
string  g_owner_honorific = "";
list    g_trustees = [];
list    g_trustee_honorifics = [];
list    g_blacklist = [];
integer g_public_access = FALSE;
integer g_locked = FALSE;

// Session cache: [av, page, csv, expiry, context, param, stepdata, menucsv, dialog_chan, listen_handle]
list    g_sessions;
/* =============================================================
   BLOCK: GLOBAL VARIABLES END
   ============================================================= */


/* =============================================================
   BLOCK: HELPERS BEGIN
   ============================================================= */
/*
    Core utility and session helpers:
    - sync_state_to_guh: Sends current state to GUH (core) for cross-plugin sync.
    - s_idx:             Session index for an avatar in g_sessions.
    - g_idx:             Index-of for a key in any list.
    - s_set:             Set/update session for avatar (removes old listen, opens new one).
    - s_clear:           Remove session (and listen) for avatar.
    - s_get:             Return session fields (list) for avatar, or empty if none.
    - get_acl:           Returns user's access level (see inline doc).
    - build_numbered_buttons: Builds ["1","2",...] style dialog buttons.
    - numbered_menu_text: Returns "1. Label\n2. Label..." menu text for number-menus.
    - owner_honorifics:  List of valid owner honorifics.
    - trustee_honorifics: List of valid trustee honorifics.
    - make_uac_nav_row:  Returns ["Cancel", " ", "OK"] row for nav dialogs.
    - make_info_nav_row: Returns [" ", "OK", " "] for info dialogs.
    - show_uac_dialog:   Standard UAC (User Accept/Cancel) dialog.
    - show_info_dialog:  Informational dialog (OK only).
    - show_public_access_dialog: Enable/disable public access dialog.
*/

sync_state_to_guh()
{
    // Compose owner, trustee, blacklist, honorific fields for GUH state packet.
    string owner_hon = g_owner_honorific;
    if (owner_hon == "") owner_hon = " ";
    string trust_csv = llDumpList2String(g_trustees, ",");
    if (trust_csv == "") trust_csv = " ";
    string trust_hon_csv = llDumpList2String(g_trustee_honorifics, ",");
    if (trust_hon_csv == "") trust_hon_csv = " ";
    string bl_csv = llDumpList2String(g_blacklist, ",");
    if (bl_csv == "") bl_csv = " ";

    string pub_str;
    if (g_public_access == TRUE) pub_str = "1";
    else pub_str = "0";

    string lock_str;
    if (g_locked == TRUE) lock_str = "1";
    else lock_str = "0";

    // Send state sync (8 fields) to GUH
    llMessageLinked(
        LINK_THIS,
        520,
        "state_sync|" +
        (string)g_owner + "|" +
        owner_hon + "|" +
        trust_csv + "|" +
        trust_hon_csv + "|" +
        bl_csv + "|" +
        pub_str + "|" +
        lock_str,
        NULL_KEY
    );
    if (DEBUG) llOwnerSay("[Access DEBUG] State sync sent (8 fields)");
}

/* Session helpers */
integer s_idx(key av) { return llListFindList(g_sessions, [av]); }
integer g_idx(list l, key k) { return llListFindList(l, [k]); }

integer s_set(key av, integer page, string csv, float expiry, string context, string param, string stepdata, string menucsv, integer dialog_chan) {
    if (DEBUG) llOwnerSay("[Access DEBUG] s_set: av=" + (string)av + " ctx=" + context + " dialog_chan=" + (string)dialog_chan);
    integer i = s_idx(av);
    integer old_listen = -1;
    if (~i) {
        old_listen = llList2Integer(g_sessions, i+9);
        g_sessions = llDeleteSubList(g_sessions, i, i+9);
    }
    if (old_listen != -1) llListenRemove(old_listen);
    integer listen_handle = llListen(dialog_chan, "", av, "");
    g_sessions += [av, page, csv, expiry, context, param, stepdata, menucsv, dialog_chan, listen_handle];
    return 0;
}

integer s_clear(key av) {
    if (DEBUG) llOwnerSay("[Access DEBUG] s_clear: av=" + (string)av);
    integer i = s_idx(av);
    if (~i) {
        integer old_listen = llList2Integer(g_sessions, i+9);
        if (old_listen != -1) llListenRemove(old_listen);
        g_sessions = llDeleteSubList(g_sessions, i, i+9);
    }
    return 0;
}

list s_get(key av) {
    integer i = s_idx(av);
    if (~i) return llList2List(g_sessions, i, i+9);
    return [];
}

/* Access control:
   Returns: 1=Owner, 2=Trustee, 3=Owned wearer, 4=Public, 5=No access, 6=Blacklisted */
integer get_acl(key av) {
    if (g_idx(g_blacklist, av) != -1) return 6; // Blacklist
    if (av == g_owner) return 1;                // Owner
    if (av == llGetOwner()) {
        if (g_owner == NULL_KEY) return 1;      // Unowned wearer = Owner
        return 3;                               // Owned wearer
    }
    if (g_idx(g_trustees, av) != -1) return 2;  // Trustee
    if (g_public_access == TRUE) return 4;      // Public
    return 5;                                   // No access
}

/* Button/menu helpers */
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
list owner_honorifics() { return [ "Master", "Mistress", "Daddy", "Mommy", "King", "Queen" ]; }
list trustee_honorifics() { return [ "Sir", "Miss", "Mister", "Madam" ]; }
list make_uac_nav_row() { return [ "Cancel", " ", "OK" ]; }
list make_info_nav_row() { return [ " ", "OK", " " ]; }

show_uac_dialog(key av, string message, integer dialog_chan) {
    if (DEBUG) llOwnerSay("[Access DEBUG] show_uac_dialog: " + (string)av + ": " + message + " chan=" + (string)dialog_chan);
    llDialog(av, message, make_uac_nav_row(), dialog_chan);
}
show_info_dialog(key av, string message, integer dialog_chan) {
    if (DEBUG) llOwnerSay("[Access DEBUG] show_info_dialog: " + (string)av + ": " + message + " chan=" + (string)dialog_chan);
    llDialog(av, message, make_info_nav_row(), dialog_chan);
}
show_public_access_dialog(key av, integer dialog_chan) {
    string txt = "Public access is currently ";
    list buttons;
    if (g_public_access == TRUE) {
        txt += "ENABLED.\nDisable public access?";
        buttons = [ "Disable", "Cancel" ];
    } else {
        txt += "DISABLED.\nEnable public access?";
        buttons = [ "Enable", "Cancel" ];
    }
    while (llGetListLength(buttons) % 3 != 0) buttons += " ";
    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "public_toggle_confirm", "", "", "", dialog_chan);
    llDialog(av, txt, buttons, dialog_chan);
}
/* =============================================================
   BLOCK: HELPERS END
   ============================================================= */


/* =============================================================
   BLOCK: MENUS AND FLOWS BEGIN
   ============================================================= */
/*
    Menus and access management flows:
    - show_access_menu:       Entry menu for access (owner/trustee/wearer/public).
    - timeout_check:          Removes expired dialog sessions (and informs users).
    - begin_add_owner, ...:   Handlers for launching add/remove/blacklist flows.
*/

show_access_menu(key av, integer dialog_chan) {
    integer acl = get_acl(av);
    list buttons = [];
    list actions = [];

    // Button set depends on user's ACL
    if (acl == 1) {
        if (g_owner != NULL_KEY && av == g_owner) {
            buttons = [ "Release Sub", "Add Trustee", "Remove Trustee", "Add Blacklist", "Rem Blacklist", "Public" ];
            actions = buttons;
        } else if (g_owner == NULL_KEY && av == llGetOwner()) {
            buttons = [ "Add Owner", "Add Trustee", "Remove Trustee", "Add Blacklist", "Rem Blacklist", "Public" ];
            actions = buttons;
        } else if (av == g_owner) {
            buttons = [ "Release Sub", "Add Trustee", "Remove Trustee", "Add Blacklist", "Rem Blacklist", "Public" ];
            actions = buttons;
        } else {
            buttons = [ "Add Owner", "Add Trustee", "Remove Trustee", "Add Blacklist", "Rem Blacklist", "Public" ];
            actions = buttons;
        }
    }
    else if (acl == 2) {
        buttons = [ "Remove Trustee", "Add Blacklist", "Rem Blacklist" ];
        actions = buttons;
    }
    else if (acl == 3) {
        buttons = [ "Add Blacklist", "Rem Blacklist", "Runaway" ];
        actions = buttons;
    }

    if (llGetListLength(buttons) == 0) {
        show_info_dialog(av, "No access management options available.", dialog_chan);
        return;
    }

    while (llGetListLength(buttons) % 3 != 0) buttons += " ";
    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "access_menu", "", "", llDumpList2String(actions, ","), dialog_chan);
    llDialog(av, "Access Management:", buttons, dialog_chan);
}

/* Checks for timed out sessions and notifies users if expired. */
timeout_check() {
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

/* --- Flows for access management, each with UI and next-step logic --- */

begin_add_owner(key av, integer dialog_chan) {
    llSensor("", NULL_KEY, AGENT, scan_range, TWO_PI);
    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "add_owner", "", "", "", dialog_chan);
}
begin_release_sub(key av, integer dialog_chan) {
    show_uac_dialog(av, "Are you sure you want to release your sub? This will remove your ownership.", dialog_chan);
    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "release_sub_confirm_owner", "", "", "", dialog_chan);
}
begin_add_trustee(key av, integer dialog_chan) {
    llSensor("", NULL_KEY, AGENT, scan_range, TWO_PI);
    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "add_trustee", "", "", "", dialog_chan);
}
begin_remove_trustee(key av, integer dialog_chan) {
    if (llGetListLength(g_trustees) == 0) {
        show_info_dialog(av, "There are no trustees to remove.", dialog_chan);
        return;
    }
    list display = [];
    integer i = 0;
    for (i=0; i<llGetListLength(g_trustees); ++i)
        display += llKey2Name(llList2Key(g_trustees,i));
    string csv = llDumpList2String(g_trustees, ",");
    float expiry = llGetUnixTime() + dialog_timeout;
    s_set(av, 0, csv, expiry, "remove_trustee", "", "", csv, dialog_chan);
    string dialog_body = "Select trustee to remove:\n" + numbered_menu_text(display);
    list buttons = build_numbered_buttons(display);
    llDialog(av, dialog_body, buttons, dialog_chan);
}
begin_blacklist(key av, integer dialog_chan) {
    llSensor("", NULL_KEY, AGENT, scan_range, TWO_PI);
    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "blacklist", "", "", "", dialog_chan);
}
begin_unblacklist(key av, integer dialog_chan) {
    if (llGetListLength(g_blacklist) == 0) {
        show_info_dialog(av, "No one is blacklisted.", dialog_chan);
        return;
    }
    list display = [];
    integer i;
    for (i=0; i<llGetListLength(g_blacklist); ++i)
        display += llKey2Name(llList2Key(g_blacklist,i));
    string csv = llDumpList2String(g_blacklist, ",");
    float expiry = llGetUnixTime() + dialog_timeout;
    s_set(av, 0, csv, expiry, "unblacklist", "", "", csv, dialog_chan);
    string dialog_body = "Select avatar to unblacklist:\n" + numbered_menu_text(display);
    list buttons = build_numbered_buttons(display);
    llDialog(av, dialog_body, buttons, dialog_chan);
}
/* =============================================================
   BLOCK: MENUS AND FLOWS END
   ============================================================= */


/* =============================================================
   BLOCK: EVENTS AND STATE HANDLERS BEGIN
   ============================================================= */
/*
    Main event loop for the access plugin.
    - state_entry:      Registers the plugin with GUH and sets periodic timer.
    - link_message:     Handles requests from GUH (core) for access dialog.
    - sensor:           Handles avatar detection flows (add owner/trustee/blacklist).
    - no_sensor:        Handles sensor timeout (no avatars found).
    - listen:           Processes all dialog/menu responses and flow logic.
    - timer:            Triggers timeout_check every second.
*/

default
{
    state_entry()
    {
        // Register this plugin with the GUH core
        llMessageLinked(LINK_THIS, 500, "register|1001|Access|3|core", NULL_KEY);
        llSetTimerEvent(1.0);
        if (DEBUG) llOwnerSay("[Access DEBUG] Plugin ready.");
    }

    link_message(integer sn, integer num, string str, key id)
    {
        // GUH sends: num=510, str="core|<avatar>|<dialog_chan>"
        if (num == 510) {
            list args = llParseString2List(str, ["|"], []);
            if (llList2String(args,0) == "core" && llGetListLength(args) >= 3) {
                key av = (key)llList2String(args,1);
                integer dialog_chan = (integer)llList2String(args,2);
                show_access_menu(av, dialog_chan);
                return;
            }
        }
    }

    sensor(integer n)
    {
        // Used for picking avatars for owner/trustee/blacklist flows.
        integer i;
        for (i=0; i<llGetListLength(g_sessions); i+=10)
        {
            key av = llList2Key(g_sessions,i);
            string ctx = llList2String(g_sessions,i+4);
            integer dialog_chan = llList2Integer(g_sessions,i+8);
            if (ctx == "add_owner" || ctx == "add_trustee" || ctx == "blacklist") {
                list cands = [];
                integer j;
                for (j=0; j<n; ++j)
                {
                    key k = llDetectedKey(j);
                    if (k == av) jump skip_current;
                    if (ctx == "add_owner" && k == g_owner) jump skip_current;
                    if (ctx == "add_trustee" && g_idx(g_trustees, k) != -1) jump skip_current;
                    if (ctx == "blacklist" && g_idx(g_blacklist, k) != -1) jump skip_current;
                    cands += k;
                    @skip_current;
                }
                if (llGetListLength(cands) == 0) {
                    show_info_dialog(av, "No avatars found within 10 meters.", dialog_chan);
                    s_clear(av);
                    return;
                }
                list labels = [];
                integer k;
                for (k=0; k<llGetListLength(cands); ++k)
                    labels += llKey2Name(llList2Key(cands,k));
                string dialog_body = "";
                if (ctx == "add_owner") dialog_body = "Select your new primary owner:\n";
                else if (ctx == "add_trustee") dialog_body = "Select a trustee:\n";
                else if (ctx == "blacklist") dialog_body = "Blacklist an avatar:\n";
                dialog_body += numbered_menu_text(labels);
                list buttons = build_numbered_buttons(labels);
                string cands_csv = llDumpList2String(cands, ",");
                s_set(av, 0, cands_csv, llGetUnixTime() + dialog_timeout, ctx, "", "", cands_csv, dialog_chan);
                llDialog(av, dialog_body, buttons, dialog_chan);
                return;
            }
        }
    }

    no_sensor()
    {
        // No avatars detected within scan range
        integer i;
        for (i=0; i<llGetListLength(g_sessions); i+=10) {
            key av = llList2Key(g_sessions, i);
            string ctx = llList2String(g_sessions, i+4);
            integer dialog_chan = llList2Integer(g_sessions, i+8);
            if (ctx == "add_owner" || ctx == "add_trustee" || ctx == "blacklist") {
                show_info_dialog(av, "No avatars found within 10 meters.", dialog_chan);
                s_clear(av);
            }
        }
    }

    listen(integer chan, string nm, key av, string msg)
    {
        /*
            Handles all menu/dialog/button flows by session context.
            Decodes session and button context, advancing flow logic accordingly.
        */
        list sess = s_get(av);
        if (llGetListLength(sess) == 0) return;
        integer dialog_chan = llList2Integer(sess, 8);
        if (chan != dialog_chan) return;

        integer page = llList2Integer(sess, 1);
        string csv = llList2String(sess, 2);
        float expiry = llList2Float(sess, 3);
        string ctx = llList2String(sess, 4);
        string param = llList2String(sess, 5);
        string stepdata = llList2String(sess, 6);
        string menucsv = llList2String(sess, 7);

        // --- Access menu logic ---
        list allowed = llParseString2List(menucsv, [","], []);
        integer sel = llListFindList(allowed, [msg]);
        string action = "";
        if (sel != -1 && sel < llGetListLength(allowed)) {
            action = llList2String(allowed, sel);

            if (ctx == "access_menu") {
                if (action == "Add Owner")        { begin_add_owner(av, dialog_chan); return; }
                if (action == "Release Sub")      { begin_release_sub(av, dialog_chan); return; }
                if (action == "Add Trustee")      { begin_add_trustee(av, dialog_chan); return; }
                if (action == "Remove Trustee")   { begin_remove_trustee(av, dialog_chan); return; }
                if (action == "Add Blacklist")    { begin_blacklist(av, dialog_chan); return; }
                if (action == "Rem Blacklist")    { begin_unblacklist(av, dialog_chan); return; }
                if (action == "Public")           { show_public_access_dialog(av, dialog_chan); return; }
                if (action == "Runaway") {
                    show_uac_dialog(av, "This will forcibly remove your primary owner and restore your access.", dialog_chan);
                    s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "runaway_confirm", "", "", "", dialog_chan);
                    return;
                }
                return;
            }
        }

        // --- ADD OWNER ---
        if (ctx == "add_owner") {
            list keys = llParseString2List(csv, [","], []);
            integer sel = (integer)msg;
            if (sel > 0 && sel <= llGetListLength(keys)) {
                key picked = llList2Key(keys, sel-1);
                list honors = owner_honorifics();
                string honor_dialog = "Select an honorific for your owner:\n" + numbered_menu_text(honors);
                s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "add_owner_honorific", (string)picked, "", "", dialog_chan);
                llDialog(av, honor_dialog, build_numbered_buttons(honors), dialog_chan);
                return;
            }
        }
        if (ctx == "add_owner_honorific") {
            list honors = owner_honorifics();
            integer sel = (integer)msg;
            if (sel > 0 && sel <= llGetListLength(honors)) {
                key picked = (key)param;
                string honorific = llList2String(honors, sel-1);
                s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "add_owner_confirm_wearer", (string)picked, honorific, "", dialog_chan);
                show_uac_dialog(av, "Are you sure you wish to assign " + honorific + " " + llKey2Name(picked) + " as your new owner?", dialog_chan);
                return;
            }
        }
        if (ctx == "add_owner_confirm_wearer") {
            if (msg == "OK") {
                key picked = (key)param;
                string honorific = stepdata;
                s_set(picked, 0, "", llGetUnixTime() + dialog_timeout, "add_owner_confirm_candidate", (string)av, honorific, "", dialog_chan);
                llDialog(picked, llKey2Name(av) + " wishes to assign you as their collar owner.\nHonorific: " + honorific + "\nDo you accept?", make_uac_nav_row(), dialog_chan);
                return;
            }
            if (msg == "Cancel") { s_clear(av); return; }
        }
        if (ctx == "add_owner_confirm_candidate") {
            if (msg == "OK") {
                key wearer = (key)param;
                string honorific = stepdata;
                g_owner = av;
                g_owner_honorific = honorific;
                show_info_dialog(wearer, "You are now property of " + honorific + " " + llKey2Name(av), dialog_chan);
                show_info_dialog(av, "You are now owner of " + llKey2Name(wearer) + ".", dialog_chan);
                s_clear(av);      // candidate
                s_clear(wearer);  // initiator
                sync_state_to_guh();
                return;
            }
            if (msg == "Cancel") { s_clear(av); s_clear((key)param); return; }
        }

        // --- RELEASE SUB ---
        if (ctx == "release_sub_confirm_owner") {
            if (msg == "OK") {
                key wearer = llGetOwner();
                s_set(wearer, 0, "", llGetUnixTime() + dialog_timeout, "release_sub_confirm_wearer", (string)av, "", "", dialog_chan);
                llDialog(wearer, llKey2Name(av) + " wishes to release you from their collar. Do you accept?", make_uac_nav_row(), dialog_chan);
                return;
            }
            if (msg == "Cancel") { s_clear(av); return; }
        }
        if (ctx == "release_sub_confirm_wearer") {
            if (msg == "OK") {
                g_owner = NULL_KEY;
                g_owner_honorific = "";
                show_info_dialog(av, "You are no longer owned.", dialog_chan);
                show_info_dialog(llGetOwner(), "Collar is now unowned.", dialog_chan);
                s_clear(av); // candidate
                s_clear(llGetOwner()); // initiator
                sync_state_to_guh();
                return;
            }
            if (msg == "Cancel") { s_clear(av); s_clear((key)param); return; }
        }

        // --- ADD TRUSTEE ---
        if (ctx == "add_trustee") {
            list keys = llParseString2List(csv, [","], []);
            integer sel = (integer)msg;
            if (sel > 0 && sel <= llGetListLength(keys)) {
                key picked = llList2Key(keys, sel-1);
                list honors = trustee_honorifics();
                string honor_dialog = "Select an honorific for your trustee:\n" + numbered_menu_text(honors);
                s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "add_trustee_honorific", (string)picked, "", "", dialog_chan);
                llDialog(av, honor_dialog, build_numbered_buttons(honors), dialog_chan);
                return;
            }
        }
        if (ctx == "add_trustee_honorific") {
            list honors = trustee_honorifics();
            integer sel = (integer)msg;
            if (sel > 0 && sel <= llGetListLength(honors)) {
                key picked = (key)param;
                string honorific = llList2String(honors, sel-1);
                s_set(picked, 0, "", llGetUnixTime() + dialog_timeout, "add_trustee_confirm_candidate", (string)av, honorific, "", dialog_chan);
                llDialog(picked, llKey2Name(av) + " wishes to add you as trustee to their collar.\nHonorific: " + honorific + "\nDo you accept?", make_uac_nav_row(), dialog_chan);
                return;
            }
        }
        if (ctx == "add_trustee_confirm_candidate") {
            if (msg == "OK") {
                key wearer = (key)param;
                string honorific = stepdata;
                g_trustees += av;
                g_trustee_honorifics += honorific;
                show_info_dialog(wearer, llKey2Name(av) + " is now your trustee.", dialog_chan);
                show_info_dialog(av, "You are now a trustee for " + llKey2Name(wearer) + ".", dialog_chan);
                s_clear(av); // candidate
                s_clear(wearer); // initiator
                sync_state_to_guh();
                return;
            }
            if (msg == "Cancel") { s_clear(av); s_clear((key)param); return; }
        }

        // --- REMOVE TRUSTEE ---
        if (ctx == "remove_trustee") {
            list keys = llParseString2List(csv, [","], []);
            integer sel = (integer)msg;
            if (sel > 0 && sel <= llGetListLength(keys)) {
                key picked = llList2Key(keys, sel-1);
                s_set(picked, 0, "", llGetUnixTime() + dialog_timeout, "remove_trustee_confirm_candidate", (string)av, "", "", dialog_chan);
                llDialog(picked, llKey2Name(av) + " wishes to remove you as a trustee. Do you accept?", make_uac_nav_row(), dialog_chan);
                return;
            }
        }
        if (ctx == "remove_trustee_confirm_candidate") {
            if (msg == "OK") {
                key initiator = (key)param;
                integer idx = g_idx(g_trustees, av);
                if (idx != -1) {
                    g_trustees = llDeleteSubList(g_trustees, idx, idx);
                    g_trustee_honorifics = llDeleteSubList(g_trustee_honorifics, idx, idx);
                    show_info_dialog(initiator, "Trustee removed.", dialog_chan);
                    show_info_dialog(av, "You have been removed as a trustee.", dialog_chan);
                }
                s_clear(av); // candidate
                s_clear(initiator); // initiator
                sync_state_to_guh();
                return;
            }
            if (msg == "Cancel") { s_clear(av); s_clear((key)param); return; }
        }

        // --- BLACKLIST ---
        if (ctx == "blacklist") {
            list keys = llParseString2List(csv, [","], []);
            integer sel = (integer)msg;
            if (sel > 0 && sel <= llGetListLength(keys)) {
                key picked = llList2Key(keys, sel-1);
                s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "blacklist_confirm", (string)picked, "", "", dialog_chan);
                show_uac_dialog(av, "You are about to blacklist " + llKey2Name(picked) + ". Continue?", dialog_chan);
                return;
            }
        }
        if (ctx == "blacklist_confirm") {
            if (msg == "OK") {
                key picked = (key)param;
                g_blacklist += picked;
                show_info_dialog(av, "You have blacklisted " + llKey2Name(picked) + ".", dialog_chan);
                s_clear(av);
                sync_state_to_guh();
                return;
            }
            if (msg == "Cancel") { s_clear(av); return; }
        }

        // --- UNBLACKLIST ---
        if (ctx == "unblacklist") {
            list keys = llParseString2List(csv, [","], []);
            integer sel = (integer)msg;
            if (sel > 0 && sel <= llGetListLength(keys)) {
                key picked = llList2Key(keys, sel-1);
                s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "unblacklist_confirm", (string)picked, "", "", dialog_chan);
                show_uac_dialog(av, "Remove " + llKey2Name(picked) + " from blacklist?", dialog_chan);
                return;
            }
        }
        if (ctx == "unblacklist_confirm") {
            if (msg == "OK") {
                key picked = (key)param;
                integer idx = g_idx(g_blacklist, picked);
                if (idx != -1) {
                    g_blacklist = llDeleteSubList(g_blacklist, idx, idx);
                    show_info_dialog(av, llKey2Name(picked) + " has been removed from the blacklist.", dialog_chan);
                }
                s_clear(av);
                sync_state_to_guh();
                return;
            }
            if (msg == "Cancel") { s_clear(av); return; }
        }

        // --- PUBLIC ACCESS TOGGLE ---
        if (ctx == "public_toggle_confirm") {
            if (msg == "Enable") {
                g_public_access = TRUE;
                show_info_dialog(av, "Public access is now ENABLED.", dialog_chan);
                s_clear(av);
                sync_state_to_guh();                
                return;
            }
            if (msg == "Disable") {
                g_public_access = FALSE;
                show_info_dialog(av, "Public access is now DISABLED.", dialog_chan);
                s_clear(av);
                sync_state_to_guh();
                return;
            }
            if (msg == "Cancel") { s_clear(av); return; }
        }

        // --- RUNAWAY (owned wearer only) ---
        if (ctx == "runaway_confirm") {
            if (msg == "OK") {
                g_owner = NULL_KEY;
                g_owner_honorific = "";
                show_info_dialog(av, "You have run away and are now unowned.", dialog_chan);
                s_clear(av);
                sync_state_to_guh();
                return;
            }
            if (msg == "Cancel") { s_clear(av); return; }
        }
    }

    timer() { timeout_check(); }
}
/* =============================================================
   BLOCK: EVENTS AND STATE HANDLERS END
   ============================================================= */
