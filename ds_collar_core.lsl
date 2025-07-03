/* =============================================================
   BLOCK: GLOBAL VARIABLES BEGIN
   ============================================================= */
/*
    Global variables and persistent state for the D/s Collar core script.
    - g_plugins: List of all registered plugins ([script, label, min_acl, ctx])
    - g_sessions: List of active dialog/menu sessions for users
    - dialog_timeout: Menu/dialog expiration timeout (in seconds)
    - g_listen_handle: Handle for the active listen event (only one allowed)
    - g_owner: Key of the collar's owner
    - g_owner_honorific: Owner's honorific string (e.g., "Mistress")
    - g_trustees: List of trustee user keys
    - g_trustee_honorifics: List of honorifics matching trustees
    - g_blacklist: List of blocked user keys
    - g_public_access: Public use flag (boolean/integer)
    - g_locked: Lock state (boolean/integer)
*/
integer DEBUG = TRUE;

list    g_plugins;           // [script, label, min_acl, ctx]
list    g_sessions;          // [av, page, csv, exp, ctx, param, step, menucsv, chan, listen]

float   dialog_timeout = 180.0;
integer g_listen_handle = 0;

key     g_owner              = NULL_KEY;
string  g_owner_honorific    = "";
list    g_trustees           = [];
list    g_trustee_honorifics = [];
list    g_blacklist          = [];
integer g_public_access      = FALSE;
integer g_locked             = FALSE;
/* =============================================================
   BLOCK: GLOBAL VARIABLES END
   ============================================================= */


/* =============================================================
   BLOCK: SMALL HELPERS BEGIN
   ============================================================= */
/*
    Small helper functions:
    - s_idx:      Get the session index for an avatar key in g_sessions.
    - g_idx:      Generic index lookup for a key in any list.
    - sess_set:   Initialize or update a menu/dialog session for an avatar.
                  Handles listen management and session field setup.
    - sess_clear: Remove an avatar's session (and its listen), if any.
    - sess_get:   Return session details (as a list) for a given avatar.
    - get_acl:    Calculate access control level for an avatar key.
                  (Returns 1=Owner, 2=Trustee, 3=Owned, 4=Public, 5=User, 6=Blacklisted)
*/
integer s_idx(key av) { 
    return llListFindList(g_sessions, [av]); 
}

integer g_idx(list l, key k) { 
    return llListFindList(l, [k]); 
}

integer sess_set(key av, integer page, string csv, float exp, string ctx,
                string param, string step, string mcsv, integer chan)
{
    // Remove previous session and listen (if any)
    integer i = s_idx(av);
    if(~i){
        integer old = llList2Integer(g_sessions, i+9);
        if(old != -1) llListenRemove(old);
        g_sessions = llDeleteSubList(g_sessions, i, i+9);
    }
    // Add new session and create a listen for menu responses
    integer lh = llListen(chan, "", av, "");
    g_sessions += [av, page, csv, exp, ctx, param, step, mcsv, chan, lh];
    return TRUE;
}

integer sess_clear(key av){
    // Remove session and its listen handle, if present
    integer i = s_idx(av);
    if(~i){
        integer old = llList2Integer(g_sessions, i+9);
        if(old != -1) llListenRemove(old);
        g_sessions = llDeleteSubList(g_sessions, i, i+9);
    }
    return TRUE;
}

list sess_get(key av){
    // Return session info as a list, or empty if none
    integer i = s_idx(av);
    if(~i) return llList2List(g_sessions, i, i+9);
    return [];
}

integer get_acl(key av){
    // Returns user's access control level (see above)
    if(g_idx(g_blacklist, av) != -1) return 6; // Blacklisted
    if(av == g_owner)             return 1;    // Owner
    if(av == llGetOwner()){
        if(g_owner == NULL_KEY)   return 1;    // Owner (self-owned)
        return 3;                             // "Worn by" user, not the configured owner
    }
    if(g_idx(g_trustees, av) != -1) return 2;  // Trustee
    if(g_public_access)             return 4;  // Public
    return 5;                                   // Regular user
}
/* =============================================================
   BLOCK: SMALL HELPERS END
   ============================================================= */


/* =============================================================
   BLOCK: PLUGIN REGISTRY HELPERS BEGIN
   ============================================================= */
/*
    Plugin registry helpers:
    - add_plugin:      Register a plugin (by serial number, label, ACL, and context)
                       Ensures no duplicates, replaces if already present.
    - remove_plugin:   Remove a plugin from the registry by serial number.
*/
add_plugin(integer sn, string label, integer min_acl, string ctx){
    integer i;
    for(i=0; i<llGetListLength(g_plugins); i+=4){
        if(llList2Integer(g_plugins, i) == sn)
            g_plugins = llDeleteSubList(g_plugins, i, i+3);
    }
    g_plugins += [sn, label, min_acl, ctx];
}

remove_plugin(integer sn){
    integer i;
    for(i=0; i<llGetListLength(g_plugins); i+=4){
        if(llList2Integer(g_plugins, i) == sn)
            g_plugins = llDeleteSubList(g_plugins, i, i+3);
    }
}
/* =============================================================
   BLOCK: PLUGIN REGISTRY HELPERS END
   ============================================================= */


/* =============================================================
   BLOCK: MENU BUILDERS BEGIN
   ============================================================= */
/*
    Menu building and display:
    - core_btns/core_ctxs:  Static main menu button/callback sets.
    - show_main_menu:       Composes the menu according to access level, plugins, and lock state.
                            Assigns a unique channel and session for the user's menu.
*/
list core_btns(){ return ["Status","Apps"]; }
list core_ctxs(){ return ["status","apps"]; }

show_main_menu(key av)
{
    integer acl = get_acl(av);

    list btns = core_btns();
    list ctxs = core_ctxs();

    // Add lock/unlock controls for owner/trustee/wearer
    if(acl <= 3){
        if(g_locked){ btns += ["Unlock"]; ctxs += ["unlock"]; }
        else        { btns += ["Lock"];   ctxs += ["lock"];   }
    }

    // Add plugin buttons user has ACL for
    integer i;
    for(i = 0; i < llGetListLength(g_plugins); i += 4){
        integer min_acl = llList2Integer(g_plugins, i+2);
        if(acl > min_acl) jump skip_p;
        btns += [llList2String(g_plugins, i+1)];
        ctxs += [llList2String(g_plugins, i+3) + "|" + (string)llList2Integer(g_plugins, i)];
        @skip_p;
    }
    // Pad buttons to multiple of 3 for llDialog
    while(llGetListLength(btns) % 3 != 0) btns += " ";

    // Open a session and listen for this menu
    integer chan = (integer)(-1000000.0 * llFrand(1.0) - 1.0);
    sess_set(av, 0, "", llGetUnixTime() + dialog_timeout,
            "main", "", "", llDumpList2String(ctxs, ","), chan);

    if(g_listen_handle) llListenRemove(g_listen_handle);
    g_listen_handle = llListen(chan, "", av, "");

    if(DEBUG) llOwnerSay("[DEBUG] show_main_menu → " + (string)av +
                         " chan=" + (string)chan + " btns=" + llDumpList2String(btns, ","));
    llDialog(av, "Select an option:", btns, chan);
}
/* =============================================================
   BLOCK: MENU BUILDERS END
   ============================================================= */


/* =============================================================
   BLOCK: DIALOGS BEGIN
   ============================================================= */
/*
    Dialogs and informational panels:
    - show_status:     Shows collar owner, trustees, and lock/public status.
    - show_apps:       Placeholder for future plugin/app listing dialog.
    - show_lock_dialog: Presents the lock/unlock dialog and sets session for response.
*/
show_status(key av, integer chan)
{
    string t = "";
    if(g_owner != NULL_KEY)
         t += "Owner: " + g_owner_honorific + " " + llKey2Name(g_owner) + "\n";
    else t += "Collar is unowned.\n";

    if(llGetListLength(g_trustees) > 0){
        integer i;
        t += "Trustees:\n";
        for(i = 0; i < llGetListLength(g_trustees); ++i)
            t += "  " + llList2String(g_trustee_honorifics, i) + " " +
                 llKey2Name(llList2Key(g_trustees, i)) + "\n";
    }
    if(g_public_access) t += "Public Access: ENABLED\n";
    else                t += "Public Access: DISABLED\n";
    if(g_locked)        t += "Locked: YES\n";
    else                t += "Locked: NO\n";

    llDialog(av, t, [" ", "OK", " "], chan);
}

show_apps(key av, integer chan){
    // TODO: Replace with plugin menu when implemented
    llDialog(av, "(Stub) Apps list would go here.", [" ", "OK", " "], chan);
}

show_lock_dialog(key av, integer chan){
    string txt;
    list buttons;
    if(g_locked){
        txt = "The collar is currently LOCKED.\nUnlock the collar?";
        buttons = ["Unlock", "Cancel"];
    }else{
        txt = "The collar is currently UNLOCKED.\nLock the collar?";
        buttons = ["Lock", "Cancel"];
    }
    while(llGetListLength(buttons) % 3 != 0) buttons += " ";
    sess_set(av, 0, "", llGetUnixTime() + dialog_timeout,
            "lock_toggle", "", "", "", chan);
    llDialog(av, txt, buttons, chan);
}
/* =============================================================
   BLOCK: DIALOGS END
   ============================================================= */


/* =============================================================
   BLOCK: TIMEOUT CHECK BEGIN
   ============================================================= */
/*
    Periodically check for expired sessions (by timestamp),
    and remove any whose expiration has passed.
*/
timeout_check(){
    integer now = llGetUnixTime();
    integer i = 0;
    while(i < llGetListLength(g_sessions)){
        if(now > llList2Float(g_sessions, i+3))
             sess_clear(llList2Key(g_sessions, i));
        else i += 10;
    }
}
/* =============================================================
   BLOCK: TIMEOUT CHECK END
   ============================================================= */


/* =============================================================
   BLOCK: DEFAULT STATE BEGIN
   ============================================================= */
/*
    Default LSL state: handles events for touch/menu, plugin messaging,
    menu/listen responses, periodic session expiration.
*/
default
{
    state_entry(){
        if(DEBUG) llOwnerSay("[DEBUG] GUH state_entry");
        llSetTimerEvent(1.0);
    }

    touch_start(integer n)
    { 
        key toucher = (llDetectedKey(0));
        integer acl = get_acl(toucher);
        string role;
        if(acl == 1)      role = "Owner";
        else if(acl == 2) role = "Trustee";
        else if(acl == 3) role = "Owned wearer";
        else if(acl == 4) role = "Public";
        else              role = "No access";
        llOwnerSay("[DEBUG] Toucher " + (string)toucher + " has ACL level " + (string)acl + " (" + role + ")");
        show_main_menu(toucher);
    }

    link_message(integer sn, integer num, string str, key id)
    {
        /* Handle plugin registration/unregistration from other scripts */
        if(num == 500)
        {
            // expect: "register|<sn>|<label>|<min_acl>|<ctx>"
            list p = llParseStringKeepNulls(str, ["|"], []);
            if(llGetListLength(p) >= 5 && llList2String(p, 0) == "register")
            {
                integer sn = (integer)llList2Integer(p, 1);
                string label = llList2String(p, 2);
                integer min_acl = (integer)llList2Integer(p, 3);
                string ctx = llList2String(p, 4);

                add_plugin(sn, label, min_acl, ctx);
                if(DEBUG) llOwnerSay("[PLUGIN] Registered " + "named " + label + " serial " + llList2String(p, 1) + " with min. ACL= " + (string)min_acl + " context " + ctx);
            }
        }
        else if(num == 501 && str == "unregister"){ 
            remove_plugin(sn); 
        }

        /* Handle state-sync message from Access plugin (8 fields, no ternaries) */
        else if(num == 520)
        {
            list p = llParseString2List(str, ["|"], []);
            /* state_sync|owner|ownerHon|trust_csv|trustHon_csv|blacklist_csv|pub|lock */
            if(llGetListLength(p) == 8 && llList2String(p, 0) == "state_sync")
            {
                g_owner              = (key)llList2String(p, 1);
                g_owner_honorific    =      llList2String(p, 2);

                string trust_csv     =      llList2String(p, 3);
                string trust_hon     =      llList2String(p, 4);
                string bl_csv        =      llList2String(p, 5);
                string pub_str       =      llList2String(p, 6);
                string lock_str      =      llList2String(p, 7);

                // Convert comma-lists, using blank (" ") to mean empty
                if(trust_csv == " ")   g_trustees           = [];
                else                   g_trustees           = llParseString2List(trust_csv, [","], []);
                if(trust_hon == " ")   g_trustee_honorifics = [];
                else                   g_trustee_honorifics = llParseString2List(trust_hon, [","], []);
                if(bl_csv == " ")      g_blacklist          = [];
                else                   g_blacklist          = llParseString2List(bl_csv, [","], []);

                if(pub_str == "1") g_public_access = TRUE;  else g_public_access = FALSE;
                if(lock_str == "1") g_locked        = TRUE;  else g_locked        = FALSE;

                if(DEBUG)
                {
                    llOwnerSay("[GUH] State sync recv:" +
                        " owner="     + (string)g_owner +
                        " ownerHon="  + g_owner_honorific +
                        " trust="     + llDumpList2String(g_trustees, ",") +
                        " trustHon="  + llDumpList2String(g_trustee_honorifics, ",") +
                        " blacklist=" + llDumpList2String(g_blacklist, ",") +
                        " pub="       + pub_str +
                        " lock="      + lock_str);
                }
            }
        }
    }   

    listen(integer chan, string nm, key av, string msg)
    {
        // Handle all dialog/listen events for active user sessions
        list s = sess_get(av);
        if(llGetListLength(s) == 0) return;
        if(chan != llList2Integer(s, 8)) return;

        string ctx = llList2String(s, 4);
        string menucsv = llList2String(s, 7);

        if(ctx == "main"){
            // Button logic for main menu
            list ctxs = llParseString2List(menucsv, [","], []);
            list btns = core_btns();
            if(get_acl(av) <= 3){
                if(g_locked) btns += ["Unlock"]; else btns += ["Lock"];
            }
            integer i;
            for(i = 0; i < llGetListLength(g_plugins); i += 4){
                if(get_acl(av) <= llList2Integer(g_plugins, i+2))
                    btns += [llList2String(g_plugins, i+1)];
            }
            while(llGetListLength(btns) % 3 != 0) btns += " ";

            integer sel = llListFindList(btns, [msg]);
            if(sel == -1) return;
            string act = llList2String(ctxs, sel);

            if(act == "status"){ show_status(av, chan); return; }
            if(act == "apps"){   show_apps(av, chan);   return; }
            if(act == "lock" || act == "unlock"){ show_lock_dialog(av, chan); return; }

            // Plugin-specific handler
            list pi = llParseString2List(act, ["|"], []);
            if(llGetListLength(pi) == 2){
                llMessageLinked(LINK_THIS, 510, llList2String(pi, 0) + "|" + (string)av + "|" + (string)chan, NULL_KEY);
            }
        }
        return;

        if(ctx == "lock_toggle"){
            // Lock/unlock responses
            if(msg == "Lock"){   g_locked = TRUE;  }
            if(msg == "Unlock"){ g_locked = FALSE; }
            if(msg == "Lock" || msg == "Unlock"){
                llDialog(av, "Done.", [" ", "OK", " "], chan);
                sess_clear(av);
                return;
            }
            if(msg == "Cancel"){ sess_clear(av); }
        }
    }

    timer(){ timeout_check(); }
}
/* =============================================================
   BLOCK: DEFAULT STATE END
   ============================================================= */
