/* =============================================================
   TITLE: ds_collar_core - Core logic                             
   VERSION: 1.2 (RLV submenu support)
   REVISION: 2025-07-15
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

list    g_apps_btns;
list    g_apps_ctxs;
list    g_rlv_btns;
list    g_rlv_ctxs;

string  g_relay_state         = "";

/* --------- Small helpers --------- */

reset_all_plugins()
{
    llOwnerSay("Collar: resetting all modules...");
    llMessageLinked(LINK_SET, -900, "reset_owner", NULL_KEY);
    // Do not call llResetScript() here; the script will reset itself on receipt.
}
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

integer get_acl(key av){
    if(g_idx(g_blacklist, av) != -1) return 5;
    if(av == g_owner)             return 1;
    if(av == llGetOwner()){
        if(g_owner == NULL_KEY)   return 1;
        return 3;
    }
    if(g_idx(g_trustees, av) != -1) return 2;
    if(g_public_access)             return 4;
    return 5;
}

/* --------- Plugin registry helpers --------- */
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

/* --------- Menu builders --------- */
list core_btns(){ return ["Status","RLV","Apps"]; }
list core_ctxs(){ return ["status","rlv","apps"]; }

show_main_menu(key av)
{
    integer acl = get_acl(av);

    // Initialize menu button/ctx lists for sections
    list core_menu_btns = core_btns();
    list core_menu_ctxs = core_ctxs();
    g_apps_btns = [];
    g_apps_ctxs = [];
    g_rlv_btns = [];
    g_rlv_ctxs = [];

    // Add lock/unlock controls for owners only (ACL 1):
    if(acl == 1){
        if(g_locked){ core_menu_btns += ["Unlock"]; core_menu_ctxs += ["unlock"]; }
        else        { core_menu_btns += ["Lock"];   core_menu_ctxs += ["lock"];   }
    }

    // Place plugins in the correct section based on context (using split)
    integer i;
    for (i = 0; i < llGetListLength(g_plugins); i += 4) {
        integer min_acl = llList2Integer(g_plugins, i+2);
        if (acl > min_acl) jump skip_p;
        string ctx = llList2String(g_plugins, i+3);
        list parts = llParseString2List(ctx, ["_"], []);
        string section = "";
        if (llGetListLength(parts) > 0) section = llList2String(parts, 0);

        if (section == "core" || section == "hub") {
            core_menu_btns += [llList2String(g_plugins, i+1)];
            core_menu_ctxs += [ctx + "|" + (string)llList2Integer(g_plugins, i)];
        }
        else if (section == "apps") {
            g_apps_btns += [llList2String(g_plugins, i+1)];
            g_apps_ctxs += [ctx + "|" + (string)llList2Integer(g_plugins, i)];
        }
        else if (section == "rlv") {
            g_rlv_btns += [llList2String(g_plugins, i+1)];
            g_rlv_ctxs += [ctx + "|" + (string)llList2Integer(g_plugins, i)];
        }
        @skip_p;
    }
    while(llGetListLength(core_menu_btns) % 3 != 0) core_menu_btns += " ";
    integer chan = (integer)(-1000000.0 * llFrand(1.0) - 1.0);
    sess_set(av, 0, "",
            llGetUnixTime() + dialog_timeout,
            "main", "", "",
            llDumpList2String(core_menu_ctxs, ","), chan);

    if(g_listen_handle) llListenRemove(g_listen_handle);
    g_listen_handle = llListen(chan, "", av, "");

    if(DEBUG) llOwnerSay("[DEBUG] show_main_menu → " + (string)av +
                         " chan=" + (string)chan + " btns=" + llDumpList2String(core_menu_btns, ","));
    llDialog(av, "Select an option:", core_menu_btns, chan);
}

// RLV submenu
show_rlv(key av, integer chan){
    if (llGetListLength(g_rlv_btns) == 0) {
        llDialog(av, "No RLV plugins installed.", [" ", "OK", " "], chan);
        return;
    }
    list btns = g_rlv_btns + ["Back"];
    list ctxs = g_rlv_ctxs + ["back"];
    while (llGetListLength(btns) % 3 != 0) btns += " ";
    sess_set(av, 0, "",
        llGetUnixTime() + dialog_timeout,
        "rlv", "", "",
        llDumpList2String(ctxs, ","), chan);
    llDialog(av, "RLV Menu:", btns, chan);
}

// Apps submenu using registered apps
show_apps(key av, integer chan){
    if (llGetListLength(g_apps_btns) == 0) {
        llDialog(av, "No apps installed.", [" ", "OK", " "], chan);
        return;
    }
    list btns = g_apps_btns + ["Back"];
    list ctxs = g_apps_ctxs + ["back"];
    while (llGetListLength(btns) % 3 != 0) btns += " ";
    sess_set(av, 0, "",
        llGetUnixTime() + dialog_timeout,
        "apps", "", "",
        llDumpList2String(ctxs, ","), chan);
    llDialog(av, "Apps Menu:", btns, chan);
}

/* --------- Dialogs --------- */
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

/* --------- Locking support --------- */
update_lock_state()
{
    if(llGetAttached())
    {
        if(g_locked)
            llOwnerSay("@detach=n");
        else
            llOwnerSay("@detach=y");
    }
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

/* --------- Timeout check --------- */
timeout_check(){
    integer now = llGetUnixTime();
    integer i = 0;
    while(i < llGetListLength(g_sessions)){
        if(now > llList2Float(g_sessions, i+3))
             sess_clear(llList2Key(g_sessions, i));
        else i += 10;
    }
}

/* --------- Default state --------- */
default
{
    state_entry(){
        if(DEBUG) llOwnerSay("[DEBUG] Core state_entry");
        llSetTimerEvent(1.0);
        update_lock_state();
        llMessageLinked(LINK_THIS, 530, "relay_load", NULL_KEY);
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
        // -- Reset handler: accept broadcast, do not rebroadcast --
        if(num == -900 && str == "reset_owner")
        {
            llResetScript();
            return;
        }

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
                    llOwnerSay("[CORE] State sync recv:" +
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
        else if (num == 530)
        {
            // Relay plugin sends its persistent state as "relay_save|<mode>|<hardcore>"
            if (llSubStringIndex(str, "relay_save") == 0)
            {
                g_relay_state = str;
                if (DEBUG) llOwnerSay("[CORE] relay_save received: " + str);
            }
            // Relay plugin is requesting previously saved state as "relay_load"
            else if (str == "relay_load")
            {
                if (g_relay_state != "")
                    llMessageLinked(LINK_THIS, 530, g_relay_state, NULL_KEY);
                else 
                    llMessageLinked(LINK_THIS, 530, "relay_save|0|0", NULL_KEY);
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
            if(get_acl(av) == 1){
                if(g_locked) btns += ["Unlock"]; else btns += ["Lock"];
            }
            // Add core plugins for this user
            integer i;
            for(i = 0; i < llGetListLength(g_plugins); i += 4){
                integer min_acl = llList2Integer(g_plugins, i+2);
                if(get_acl(av) > min_acl) jump skip_p2;
                string ctx_val = llList2String(g_plugins, i+3);
                list parts = llParseString2List(ctx_val, ["_"], []);
                if(llGetListLength(parts) > 0 && llList2String(parts, 0) == "core")
                    btns += [llList2String(g_plugins, i+1)];
                @skip_p2;
            }
            while(llGetListLength(btns) % 3 != 0) btns += " ";

            integer sel = llListFindList(btns, [msg]);
            if(sel == -1) return;
            string act = llList2String(ctxs, sel);

            if(act == "status"){ show_status(av, llList2Integer(s,8)); return; }
            if(act == "rlv"){ show_rlv(av, llList2Integer(s,8)); return; }
            if(act == "apps"){   show_apps(av, llList2Integer(s,8));   return; }
            if(act == "lock" || act == "unlock"){ show_lock_dialog(av, llList2Integer(s,8)); return; }

            list pi = llParseString2List(act, ["|"], []);
            if(llGetListLength(pi) == 2){
                llMessageLinked(LINK_THIS, 510, llList2String(pi, 0) + "|" + (string)av + "|" + (string)llList2Integer(s,8), NULL_KEY);
            }
        }
        else if(ctx == "rlv"){
            // RLV submenu
            list ctxs = llParseString2List(menucsv, [","], []);
            list btns = g_rlv_btns + ["Back"];
            while(llGetListLength(btns) % 3 != 0) btns += " ";
            integer sel = llListFindList(btns, [msg]);
            if(sel == -1) return;
            string act = llList2String(ctxs, sel);

            if(act == "back"){
                show_main_menu(av);
                return;
            }
            list pi = llParseString2List(act, ["|"], []);
            if(llGetListLength(pi) == 2){
                llMessageLinked(LINK_THIS, 510, llList2String(pi, 0) + "|" + (string)av + "|" + (string)llList2Integer(s,8), NULL_KEY);
            }
        }
        else if(ctx == "apps"){
            // Apps submenu
            list ctxs = llParseString2List(menucsv, [","], []);
            list btns = g_apps_btns + ["Back"];
            while(llGetListLength(btns) % 3 != 0) btns += " ";
            integer sel = llListFindList(btns, [msg]);
            if(sel == -1) return;
            string act = llList2String(ctxs, sel);

            if(act == "back"){
                show_main_menu(av);
                return;
            }
            list pi = llParseString2List(act, ["|"], []);
            if(llGetListLength(pi) == 2){
                llMessageLinked(LINK_THIS, 510, llList2String(pi, 0) + "|" + (string)av + "|" + (string)llList2Integer(s,8), NULL_KEY);
            }
        }
        else if(ctx == "lock_toggle"){
            if(msg == "Lock"){   g_locked = TRUE;  update_lock_state(); }
            if(msg == "Unlock"){ g_locked = FALSE; update_lock_state(); }
            if(msg == "Lock" || msg == "Unlock"){
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

    changed(integer change)
    {
        /* ============================================================
           BLOCK: OWNER CHANGE RESET HANDLER
           Resets on owner change, no rebroadcast.
           ============================================================ */
        if (change & CHANGED_OWNER)
        {
            llOwnerSay("[GUH] Collar owner changed. Resetting core.");
            llResetScript();
        }
    }
}
