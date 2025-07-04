/* =============================================================
   BLOCK: GLOBAL VARIABLES BEGIN
   ============================================================= */
integer DEBUG = TRUE;

list    g_plugins;
list    g_sessions;

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
integer s_idx(key av) { 
    return llListFindList(g_sessions, [av]); 
}

integer g_idx(list l, key k) { 
    return llListFindList(l, [k]); 
}

integer sess_set(key av, integer page, string csv, float exp, string ctx,
                string param, string step, string mcsv, integer chan)
{
    integer i = s_idx(av);
    if(~i){
        integer old = llList2Integer(g_sessions, i+9);
        if(old != -1) llListenRemove(old);
        g_sessions = llDeleteSubList(g_sessions, i, i+9);
    }
    integer lh = llListen(chan, "", av, "");
    g_sessions += [av, page, csv, exp, ctx, param, step, mcsv, chan, lh];
    return TRUE;
}

integer sess_clear(key av){
    integer i = s_idx(av);
    if(~i){
        integer old = llList2Integer(g_sessions, i+9);
        if(old != -1) llListenRemove(old);
        g_sessions = llDeleteSubList(g_sessions, i, i+9);
    }
    return TRUE;
}

list sess_get(key av){
    integer i = s_idx(av);
    if(~i) return llList2List(g_sessions, i, i+9);
    return [];
}

/*  ACL:
    0 = backend/system (not used in touch/menu, reserved)
    1 = Owner
    2 = Trustee
    3 = Wearer
    4 = Public/Guest
    5 = No Access (Denied, Blacklisted, etc)
*/
integer get_acl(key av){
    if(g_idx(g_blacklist, av) != -1) return 5; // No Access (blacklist)
    if(av == g_owner)             return 1;    // Owner
    if(av == llGetOwner()){
        if(g_owner == NULL_KEY)   return 1;    // Owner (self-owned)
        return 3;                             // "Worn by" user, not the configured owner
    }
    if(g_idx(g_trustees, av) != -1) return 2;  // Trustee
    if(g_public_access)             return 4;  // Public
    return 5;                                  // No access/denied
}
/* =============================================================
   BLOCK: SMALL HELPERS END
   ============================================================= */


/* =============================================================
   BLOCK: PLUGIN REGISTRY HELPERS BEGIN
   ============================================================= */
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
    while(llGetListLength(btns) % 3 != 0) btns += " ";

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
   BLOCK: LOCKING SUPPORT BEGIN
   ============================================================= */
update_lock_state()
{
    // RLV locking: send to local RLV if wearer, lock/unlock attach point
    // Requires the wearer to have RLV enabled and a suitable RLV relay.
    // If g_locked == TRUE, collar cannot be detached via RLV
    if(llGetAttached())
    {
        if(g_locked)
            llOwnerSay("@detach=n");   // Prevent detaching (RLV/RLVa)
        else
            llOwnerSay("@detach=y");   // Allow detaching (RLV/RLVa)
    }
    // Show/hide lock/unlock visual prims
    integer nprims = llGetNumberOfPrims();
    integer i;
    for(i=2; i<=nprims; ++i)
    {
        string primName = llGetLinkName(i);
        if(llToLower(primName) == "locked")
        {
            if(g_locked)
                llSetLinkAlpha(i, 1.0, ALL_SIDES);
            else
                llSetLinkAlpha(i, 0.0, ALL_SIDES);
        }
        else if(llToLower(primName) == "unlocked")
        {
            if(g_locked)
                llSetLinkAlpha(i, 0.0, ALL_SIDES);
            else
                llSetLinkAlpha(i, 1.0, ALL_SIDES);
        }
    }
}
/* =============================================================
   BLOCK: LOCKING SUPPORT END
   ============================================================= */


/* =============================================================
   BLOCK: TIMEOUT CHECK BEGIN
   ============================================================= */
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
default
{
    state_entry(){
        if(DEBUG) llOwnerSay("[DEBUG] GUH state_entry");
        llSetTimerEvent(1.0);
        update_lock_state();
    }

    touch_start(integer n)
    { 
        key toucher = llDetectedKey(0);
        integer acl = get_acl(toucher);

        if (acl == 5) {
            llDialog(toucher, "This collar is restricted.", ["OK"], -1);
            return;
        }
        if (acl == 4 && !g_public_access) {
            llDialog(toucher, "This collar is restricted.", ["OK"], -1);
            return;
        }
        show_main_menu(toucher);
    }

    link_message(integer sn, integer num, string str, key id)
    {
        if(num == 500)
        {
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

        else if(num == 520)
        {
            list p = llParseString2List(str, ["|"], []);
            if(llGetListLength(p) == 8 && llList2String(p, 0) == "state_sync")
            {
                g_owner              = (key)llList2String(p, 1);
                g_owner_honorific    =      llList2String(p, 2);

                string trust_csv     =      llList2String(p, 3);
                string trust_hon     =      llList2String(p, 4);
                string bl_csv        =      llList2String(p, 5);
                string pub_str       =      llList2String(p, 6);
                string lock_str      =      llList2String(p, 7);

                if(trust_csv == " ")   g_trustees           = [];
                else                   g_trustees           = llParseString2List(trust_csv, [","], []);
                if(trust_hon == " ")   g_trustee_honorifics = [];
                else                   g_trustee_honorifics = llParseString2List(trust_hon, [","], []);
                if(bl_csv == " ")      g_blacklist          = [];
                else                   g_blacklist          = llParseString2List(bl_csv, [","], []);

                if(pub_str == "1") g_public_access = TRUE;  else g_public_access = FALSE;
                if(lock_str == "1") g_locked        = TRUE;  else g_locked        = FALSE;

                update_lock_state();

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
        list s = sess_get(av);
        if(llGetListLength(s) == 0) return;
        if(chan != llList2Integer(s, 8)) return;

        string ctx = llList2String(s, 4);
        string menucsv = llList2String(s, 7);

        if(ctx == "main"){
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

            list pi = llParseString2List(act, ["|"], []);
            if(llGetListLength(pi) == 2){
                llMessageLinked(LINK_THIS, 510, llList2String(pi, 0) + "|" + (string)av + "|" + (string)chan, NULL_KEY);
            }
        }
        else if(ctx == "lock_toggle"){
            if(msg == "Lock"){   g_locked = TRUE;  update_lock_state(); }
            if(msg == "Unlock"){ g_locked = FALSE; update_lock_state(); }
            if(msg == "Lock" || msg == "Unlock"){
                // Use a new channel for confirmation
                integer confirm_chan = (integer)(-1000000.0 * llFrand(1.0) - 1.0);
                sess_set(av, 0, "", llGetUnixTime() + dialog_timeout,
                         "lock_confirm", "", "", "", confirm_chan);
                string lock_state = "Collar is now ";
                if(g_locked) lock_state += "LOCKED."; else lock_state += "UNLOCKED.";
                llDialog(av, lock_state, ["OK"], confirm_chan);
                return;
            }
            if(msg == "Cancel"){ sess_clear(av); }
        }
        else if(ctx == "lock_confirm"){
            if(msg == "OK"){ sess_clear(av); }
        }
    }

    timer(){ timeout_check(); }
}
/* =============================================================
   BLOCK: DEFAULT STATE END
   ============================================================= */
