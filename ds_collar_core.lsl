/* =============================================================
   TITLE: ds_collar_core - Core logic
   VERSION: 1.4 (Plugin registry soft-reset, re-registration protocol)
   REVISION: 2025-07-28 (Implements plugin re-registration on add/remove)
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
list    g_access_btns;
list    g_access_ctxs;

string  g_relay_state         = "";
integer g_owner_online = FALSE;
integer g_welcome_sent = FALSE;
integer g_was_attached = FALSE;

/* -------- Plugin reset scrupt  -------- */

reset_all_plugins()
{
    if (DEBUG) llOwnerSay("[CORE] Soft-reset: requesting plugins to re-register.");
    // Ask all plugins to re-register. This uses 500 and register_now| as per protocol.
    integer n = llGetInventoryNumber(INVENTORY_SCRIPT);
    integer i;
    for (i = 0; i < n; ++i)
    {
        string script = llGetInventoryName(INVENTORY_SCRIPT, i);
        if (script != llGetScriptName()) // Don't send to self
        {
            llMessageLinked(LINK_THIS, 500, "register_now" + "|" + script, NULL_KEY);
        }
    }
    // Optionally clear the plugin list and queue to force rebuild:
    g_plugins = [];
    g_plugin_queue = [];
    g_registering = FALSE;
}

/* -------- Plugin scanning logic -------- */

scan_for_plugins()
{
    list scripts = [];
    integer n = llGetInventoryNumber(INVENTORY_SCRIPT);
    integer i;
    for (i = 0; i < n; ++i)
        scripts += [llGetInventoryName(INVENTORY_SCRIPT, i)];

    list registered_scripts = [];
    for (i = 0; i < llGetListLength(g_plugins); i += 4)
        registered_scripts += llList2String(g_plugins, i+3); // Assumes 4th element is script name

    // If a plugin script in registry is missing from inventory, trigger soft reset
    integer mismatch = FALSE;
    for (i = 0; i < llGetListLength(registered_scripts); ++i)
    {
        if (llListFindList(scripts, [llList2String(registered_scripts, i)]) == -1)
        {
            mismatch = TRUE;
            jump found_mismatch;
        }
    }
@found_mismatch;
    if (mismatch)
    {
        if (DEBUG) llOwnerSay("[CORE] Plugin script(s) missing. Triggering soft reset.");
        reset_all_plugins(); // Triggers plugin re-registration
    }
}

/* -------- Plugin registration/soft-reset helpers -------- */

integer g_plugin_count = 0;         // Number of registered plugins
integer g_plugins_changed = FALSE;  // Flag for soft-reset trigger
integer g_first_boot = TRUE;        // Suppress soft reset on first load

add_plugin(integer sn, string label, integer min_acl, string ctx)
{
    integer old_count = llGetListLength(g_plugins) / 4;
    integer i;
    for(i=0; i<llGetListLength(g_plugins); i+=4){
        if(llList2Integer(g_plugins, i) == sn)
            g_plugins = llDeleteSubList(g_plugins, i, i+3);
    }
    g_plugins += [sn, label, min_acl, ctx];
    integer new_count = llGetListLength(g_plugins) / 4;
    if(old_count != new_count && !g_first_boot) g_plugins_changed = TRUE;
    g_plugin_count = new_count;
}

remove_plugin(integer sn)
{
    integer old_count = llGetListLength(g_plugins) / 4;
    integer i;
    for(i=0; i<llGetListLength(g_plugins); i+=4){
        if(llList2Integer(g_plugins, i) == sn)
            g_plugins = llDeleteSubList(g_plugins, i, i+3);
    }
    integer new_count = llGetListLength(g_plugins) / 4;
    if(old_count != new_count && !g_first_boot) g_plugins_changed = TRUE;
    g_plugin_count = new_count;
}

list g_plugin_queue = [];
integer g_registering = FALSE;

process_next_plugin()
{
    if (llGetListLength(g_plugin_queue) == 0)
    {
        g_registering = FALSE;
        if(DEBUG) llOwnerSay("[CORE] All plugins registered.");
        llSetTimerEvent(0);
        return;
    }
    
    g_registering = TRUE;
    
    integer sn      = llList2Integer(g_plugin_queue, 0);
    string label    = llList2String(g_plugin_queue, 1);
    integer min_acl = llList2Integer(g_plugin_queue, 2);
    string ctx      = llList2String(g_plugin_queue, 3);
    
    add_plugin(sn, label, min_acl, ctx);
    if (DEBUG) llOwnerSay("[CORE] Registered plugin: " + label + ", serial " + (string)sn);
    
    g_plugin_queue = llDeleteSubList(g_plugin_queue, 0, 3);
    
    llSetTimerEvent(0.1);
}

/* --------- Welcome messages helpers --------- */

// Send 3 welcome messages to wearer (llGetOwner())
send_welcome_messages()
{
    key wearer = llGetOwner();
    if (wearer == NULL_KEY) return;

    string wearer_name = llKey2Name(wearer);

    // 1. Greeting
    llInstantMessage(wearer, "Hello, " + wearer_name + ", welcome to D/s Collar.");

    // 2. Owner info
    if (g_owner != NULL_KEY)
    {
        string owner_name = llKey2Name(g_owner);
        llInstantMessage(wearer, "You are owned by " + g_owner_honorific + " " + owner_name + ".");
    }
    else
    {
        llInstantMessage(wearer, "You are unowned.");
    }

    // 3. Owner online message, only if known online
    if (g_owner != NULL_KEY && g_owner_online)
    {
        llInstantMessage(wearer, "Your " + g_owner_honorific + " is online.");
    }
}

// Request owner online status
check_owner_online()
{
    if (g_owner != NULL_KEY)
    {
        llRequestAgentData(g_owner, DATA_ONLINE);
    }
    else
    {
        g_owner_online = FALSE;
    }
}

/* --------- Small helpers --------- */

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

/* --------- Menu builders --------- */
list core_btns(){ return ["Status","RLV","Apps","Access"]; }
list core_ctxs(){ return ["status","rlv","apps","access"]; }

show_main_menu(key av)
{
    integer acl = get_acl(av);

    list core_menu_btns = core_btns();
    list core_menu_ctxs = core_ctxs();
    g_apps_btns = [];
    g_apps_ctxs = [];
    g_rlv_btns = [];
    g_rlv_ctxs = [];
    g_access_btns = [];
    g_access_ctxs = [];

    if(acl == 1){
        if(g_locked){ core_menu_btns += ["Unlock"]; core_menu_ctxs += ["unlock"]; }
        else        { core_menu_btns += ["Lock"];   core_menu_ctxs += ["lock"];   }
    }

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
        else if (section == "access") {
            g_access_btns += [llList2String(g_plugins, i + 1)];
            g_access_ctxs += [ctx + "|" + (string)llList2Integer(g_plugins, i)];
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

show_rlv(key av, integer chan){
    if (llGetListLength(g_rlv_btns) == 0) {
        llDialog(av, "No RLV plugins installed.", [ " ", "OK", " " ], chan);
        return;
    }
    list btns = [" ", "Back", " "] + g_rlv_btns;
    list ctxs = [" ", "back", " "] + g_rlv_ctxs;
    while (llGetListLength(btns) % 3 != 0) btns += " ";
    sess_set(av, 0, "",
        llGetUnixTime() + dialog_timeout,
        "rlv", "", "",
        llDumpList2String(ctxs, ","), chan);
    llDialog(av, "RLV Menu:", btns, chan);
}

show_apps(key av, integer chan){
    if (llGetListLength(g_apps_btns) == 0) {
        llDialog(av, "No apps installed.", [ " ", "OK", " " ], chan);
        return;
    }
    list btns = [" ", "Back", " "] + g_apps_btns;
    list ctxs = [" ", "back", " "] + g_apps_ctxs;
    while (llGetListLength(btns) % 3 != 0) btns += " ";
    sess_set(av, 0, "",
        llGetUnixTime() + dialog_timeout,
        "apps", "", "",
        llDumpList2String(ctxs, ","), chan);
    llDialog(av, "Apps Menu:", btns, chan);
}

show_access(key av, integer chan){
    if (llGetListLength(g_access_btns) == 0) {
        llDialog(av, "No Access plugins installed.", [ " ", "OK", " " ], chan);
        return;
    }
    list btns = [" ", "Back", " "] + g_access_btns;
    list ctxs = [" ", "back", " "] + g_access_ctxs;
    while (llGetListLength(btns) % 3 != 0) btns += " ";
    sess_set(av, 0, "",
        llGetUnixTime() + dialog_timeout,
        "access", "", "",
        llDumpList2String(ctxs, ","), chan);
    llDialog(av, "Access Menu:", btns, chan);
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

    llDialog(av, t, [ " ", "OK", " " ], chan);
}

show_lock_dialog(key av, integer chan){
    string txt;
    list buttons;
    if(g_locked){
        txt = "The collar is currently LOCKED.\nUnlock the collar?";
        buttons = [ "Unlock", " ", "Cancel" ];
    }else{
        txt = "The collar is currently UNLOCKED.\nLock the collar?";
        buttons = [ "Lock", " ", "Cancel" ];
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
    dataserver(key query_id, string data)
    {
        if (data == "1")
        {
            if (!g_owner_online)
            {
                g_owner_online = TRUE;
                if (DEBUG) llOwnerSay("[DEBUG] Owner is online.");

                key wearer = llGetOwner();
                if (wearer != NULL_KEY && g_owner != NULL_KEY)
                {
                    llInstantMessage(wearer, "Your " + g_owner_honorific + " is online.");
                }
            }
        }
        else
        {
            if (g_owner_online)
            {
                g_owner_online = FALSE;
                if (DEBUG) llOwnerSay("[DEBUG] Owner is offline.");

                key wearer = llGetOwner();
                if (wearer != NULL_KEY && g_owner != NULL_KEY)
                {
                    llInstantMessage(wearer, "Your " + g_owner_honorific + " is offline.");
                }
            }
        }
    }
    
    state_entry()
    {
        if(DEBUG) llOwnerSay("[DEBUG] Core state_entry");
        llSetTimerEvent(1.0);
        update_lock_state();
        llMessageLinked(LINK_THIS, 530, "relay_load", NULL_KEY);
        integer n = llGetInventoryNumber(INVENTORY_SCRIPT);
        integer i;
        for (i= 0; i < n; ++i)
        {
            string script = llGetInventoryName(INVENTORY_SCRIPT, i);
            if (script != llGetScriptName())
            {
                llMessageLinked(LINK_THIS, 500, "register_now" + "|" + script, NULL_KEY);
                if (DEBUG) llOwnerSay("[CORE} register_now sent: register_now" + "|" + script);
            }
        }
        g_was_attached = (llGetAttached() !=0);
        if (g_was_attached && !g_welcome_sent)
        {
            send_welcome_messages();
            g_welcome_sent = TRUE;
            if(DEBUG) llOwnerSay("[DEBUG] Welcome messages sent on attach (timer detection).");
        }
    }

    touch_start(integer n)
    { 
        key toucher = llDetectedKey(0);
        integer acl = get_acl(toucher);

        if (acl == 5) {
            llDialog(toucher, "This collar is restricted.", [ " ", "OK", " " ], -1);
            return;
        }
        if (acl == 4 && !g_public_access) {
            llDialog(toucher, "This collar is restricted.", [ " ", "OK", " " ], -1);
            return;
        }
        show_main_menu(toucher);
    }

    link_message(integer sn, integer num, string str, key id)
    {
        // Plugin registration (plugin -> core)
        if(num == 501)
        {
            if(str == "core_soft_reset") return; // Ignore our own message sent to plugins
            list p = llParseStringKeepNulls(str, ["|"], []);
            if(llGetListLength(p) >= 5 && llList2String(p, 0) == "register")
            {
                integer rsn      = (integer)llList2String(p, 1);
                string  label    = llList2String(p, 2);
                integer min_acl  = (integer)llList2String(p, 3);
                string  ctx      = llList2String(p, 4);

                add_plugin(rsn, label, min_acl, ctx);
                if(DEBUG) llOwnerSay("[CORE] Registered plugin: " + label + " (" + (string)rsn + ")");
            }
        }
        // Plugin unregistration (plugin -> core)
        else if(num == 502)
        {
            list p = llParseStringKeepNulls(str, ["|"], []);
            if(llGetListLength(p) >= 2 && llList2String(p, 0) == "unregister")
            {
                integer rsn = (integer)llList2String(p, 1);
                remove_plugin(rsn);
                if(DEBUG) llOwnerSay("[CORE] Unregistered plugin SN: " + (string)rsn);
            }
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
            if (llSubStringIndex(str, "relay_save") == 0)
            {
                g_relay_state = str;
                if (DEBUG) llOwnerSay("[CORE] relay_save received: " + str);
            }
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

            if(DEBUG) llOwnerSay("[DEBUG] listen main menu: user=" + (string)av + ", msg=" + msg + ", resolved action=" + act);

            if(act == "status"){ show_status(av, llList2Integer(s,8)); return; }
            if(act == "rlv"){ show_rlv(av, llList2Integer(s,8)); return; }
            if(act == "apps"){   show_apps(av, llList2Integer(s,8));   return; }
            if(act == "access"){ show_access(av, llList2Integer(s,8)); return; }
            if(act == "lock" || act == "unlock"){ show_lock_dialog(av, llList2Integer(s,8)); return; }

            list pi = llParseString2List(act, ["|"], []);
            if(llGetListLength(pi) == 2){
                llMessageLinked(LINK_THIS, 510, llList2String(pi, 0) + "|" + (string)av + "|" + (string)llList2Integer(s,8), NULL_KEY);
            }
        }
        else if(ctx == "rlv"){
            list ctxs = llParseString2List(menucsv, [","], []);
            list btns = [" ", "Back", " "] + g_rlv_btns;
            while(llGetListLength(btns) % 3 != 0) btns += " ";
            integer sel = llListFindList(btns, [msg]);
            if(sel == -1) return;
            string act = llList2String(ctxs, sel);

            if(DEBUG) llOwnerSay("[DEBUG] listen rlv: user=" + (string)av + ", msg=" + msg + ", action resolved='" + act + "'");

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
            list ctxs = llParseString2List(menucsv, [","], []);
            list btns = [" ", "Back", " "] + g_apps_btns;
            while(llGetListLength(btns) % 3 != 0) btns += " ";
            integer sel = llListFindList(btns, [msg]);
            if(sel == -1) return;
            string act = llList2String(ctxs, sel);

            if(DEBUG) llOwnerSay("[DEBUG] listen apps: user=" + (string)av + ", msg=" + msg + ", action resolved='" + act + "'");

            if(act == "back"){
                show_main_menu(av);
                return;
            }
            list pi = llParseString2List(act, ["|"], []);
            if(llGetListLength(pi) == 2){
                llMessageLinked(LINK_THIS, 510, llList2String(pi, 0) + "|" + (string)av + "|" + (string)llList2Integer(s,8), NULL_KEY);
            }
        }
        else if(ctx == "access"){
            list ctxs = llParseString2List(menucsv, [","], []);
            list btns = [" ", "Back", " "] + g_access_btns;
            while(llGetListLength(btns) % 3 != 0) btns += " ";
            integer sel = llListFindList(btns, [msg]);
            if(sel == -1) return;
            string act = llList2String(ctxs, sel);

            if(DEBUG) llOwnerSay("[DEBUG] listen access: user=" + (string)av + ", msg=" + msg + ", action resolved='" + act + "'");

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
                llDialog(av, lock_state, [ " ", "OK", " " ], confirm_chan);
                return;
            }
            if(msg == "Cancel"){ sess_clear(av); }
        }
        else if(ctx == "lock_confirm"){
            if(msg == "OK"){ sess_clear(av); }
        }
    }

    timer()
    {
        integer attached = (llGetAttached() != 0);
        if (attached && !g_was_attached)
        {
            if(!g_welcome_sent)
            {
                send_welcome_messages();
                g_welcome_sent = TRUE;
                if (DEBUG) llOwnerSay("[DEBUG] Welcome messages sent on attach (timer detection).");
            }
        }
        if (g_registering)
        {
            process_next_plugin();
        }
        else
        {
            timeout_check();
        }
        // Soft reset: if plugin list changed, request all plugins to reregister
        if(g_plugins_changed)
        {
            g_plugins_changed = FALSE;
            llMessageLinked(LINK_SET, 501, "core_soft_reset", NULL_KEY);
            if(DEBUG) llOwnerSay("[CORE] Plugins changed, soft reset: requesting plugin re-registration.");
        }
        if(g_first_boot && llGetTime() > 5.0)
            g_first_boot = FALSE;
    }

    changed(integer change)
    {
        integer attached = (llGetAttached() != 0);
        if (attached && !g_welcome_sent)
        {
            if (DEBUG) llOwnerSay("[DEBUG] Collar attached detected in changed(), sending welcome messages.");
            send_welcome_messages();
            g_welcome_sent = TRUE;
            check_owner_online();
        }
        else if (!attached)
        {
            g_welcome_sent = FALSE; // reset on detach
        }
    
        if (change & CHANGED_OWNER)
        {
            llOwnerSay("[CORE] Collar owner changed. Resetting core.");
            llResetScript();
        }
        // No registry logic in changed()—handled by plugin add/remove
    }
}
