/* =============================================================
   TITLE: ds_collar_relay - RLV Relay Plugin (Apps Menu)
   VERSION: 1.7
   REVISION: 2025-07-09
   ============================================================= */

/* =============================================================
   BLOCK: GLOBAL VARIABLES & CONFIG BEGIN
   ============================================================= */
integer DEBUG = TRUE;
integer RELAY_CHANNEL = 723;      // RLV relay channel

integer MODE_OFF     = 0;
integer MODE_CONSENT = 1;
integer MODE_AUTO    = 2;

integer g_relay_mode = 0;
integer g_hardcore   = FALSE;
list    g_relays     = [];

key     g_owner = NULL_KEY;
list    g_trustees = [];
list    g_blacklist = [];
integer g_public_access = FALSE;

list    g_sessions;
/* =============================================================
   BLOCK: GLOBAL VARIABLES & CONFIG END
   ============================================================= */

/* =============================================================
   BLOCK: SESSION & ACCESS HELPERS BEGIN
   ============================================================= */
integer s_idx(key av) { return llListFindList(g_sessions, [av]); }
integer g_idx(list l, key k) { return llListFindList(l, [k]); }

integer s_set(key av, integer page, string csv, float expiry, string ctx, string param, string step, string menucsv, integer dialog_chan)
{
    integer i = s_idx(av);
    integer old = -1;
    if (~i) {
        old = llList2Integer(g_sessions, i+9);
        g_sessions = llDeleteSubList(g_sessions, i, i+9);
    }
    if (old != -1) llListenRemove(old);
    integer lh = llListen(dialog_chan, "", av, "");
    g_sessions += [av, page, csv, expiry, ctx, param, step, menucsv, dialog_chan, lh];
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
integer get_acl(key av)
{
    if (g_idx(g_blacklist, av) != -1) return 5;
    if (av == g_owner) return 1;
    if (av == llGetOwner()) {
        if (g_owner == NULL_KEY) return 1;
        return 3;
    }
    if (g_idx(g_trustees, av) != -1) return 2;
    if (g_public_access == TRUE) return 4;
    return 5;
}
/* =============================================================
   BLOCK: SESSION & ACCESS HELPERS END
   ============================================================= */

/* =============================================================
   BLOCK: PERSISTENCE BEGIN
   ============================================================= */
save_state()
{
    string msg = "relay_save|" + (string)g_relay_mode + "|" + (string)g_hardcore;
    llMessageLinked(LINK_THIS, 530, msg, NULL_KEY);
    if (DEBUG) llOwnerSay("[Relay] State saved: " + msg);
}
load_state(list p)
{
    g_relay_mode = (integer)llList2String(p,1);
    g_hardcore   = (integer)llList2String(p,2);
    if (DEBUG) llOwnerSay("[Relay] State loaded: mode=" + (string)g_relay_mode + " hc=" + (string)g_hardcore);
}
/* =============================================================
   BLOCK: PERSISTENCE END
   ============================================================= */

/* =============================================================
   BLOCK: RELAY OBJECT HANDLING BEGIN
   ============================================================= */
integer relay_idx(key obj)
{
    integer i;
    for(i=0;i<llGetListLength(g_relays);i+=2)
        if(llList2Key(g_relays,i)==obj) return i;
    return -1;
}
integer relay_count() { return llGetListLength(g_relays)/2; }
add_relay_object(key obj, string name)
{
    if (relay_idx(obj) != -1) return;
    if (relay_count() >= 5) return;
    g_relays += [obj, name];
}
remove_relay_object(key obj)
{
    integer i = relay_idx(obj);
    if (i != -1)
        g_relays = llDeleteSubList(g_relays, i, i+1);
}
clear_relays()
{
    g_relays = [];
}
/* =============================================================
   BLOCK: RELAY OBJECT HANDLING END
   ============================================================= */

/* =============================================================
   BLOCK: MENU/UI BUILDERS BEGIN
   ============================================================= */
list relay_menu_btns(integer acl)
{
    list btns = [ "Mode", "Active Objects" ];
    if(acl == 1) btns += [ "Unbind", " " ];
    else if(acl == 2) btns += [ "Unbind", " " ];
    else if(acl == 3) btns += [ "Safeword", " " ];
    btns += [ "Back" ];
    while(llGetListLength(btns)%3!=0) btns += [ " " ];
    return btns;
}
list relay_menu_ctxs(integer acl)
{
    list c = [ "mode", "objects" ];
    if(acl == 1) c += [ "unbind", " " ];
    else if(acl == 2) c += [ "unbind", " " ];
    else if(acl == 3) c += [ "safeword", " " ];
    c += [ "back" ];
    return c;
}
show_relay_menu(key av, integer chan)
{
    integer acl = get_acl(av);
    if(acl > 3) return;

    list btns = relay_menu_btns(acl);
    list ctxs = relay_menu_ctxs(acl);

    s_set(av, 0, "", llGetUnixTime()+180.0, "menu", "", "", llDumpList2String(ctxs, ","), chan);

    string mode_str = "OFF";
    if(g_relay_mode == 1)
        mode_str = "ASK";
    else if(g_relay_mode == 2)
        mode_str = "AUTO";

    string hc_str;
    if(g_hardcore == TRUE)
        hc_str = "HARDCORE ON";
    else
        hc_str = "hardcore off";

    llDialog(av, "RLV Relay\nMode: "+mode_str+"\nHardcore: "+hc_str, btns, chan);
}

show_mode_menu(key av, integer chan)
{
    string mode_str = "Current mode: ";
    if(g_relay_mode == 1) mode_str += "ASK";
    else if(g_relay_mode == 2) mode_str += "AUTO";
    else mode_str += "OFF";
    string hc_str = "\nHardcore: ";
    if(g_hardcore == TRUE) hc_str += "ON"; else hc_str += "off";
    list btns = [ "Set Off", "Set Ask", "Set Auto" ];
    if (g_hardcore == TRUE)
        btns += [ "Hardcore OFF" ];
    else
        btns += [ "Hardcore ON" ];
    btns += [ "Cancel" ];
    while(llGetListLength(btns)%3!=0) btns += [ " " ];
    s_set(av, 0, "", llGetUnixTime()+60.0, "mode_menu", "", "", "", chan);
    llDialog(av, mode_str+hc_str, btns, chan);
}
show_mode_info_dialog(key av, integer mode, integer chan)
{
    string txt = "Relay mode is now ";
    if(mode == MODE_OFF) txt += "OFF.";
    else if(mode == MODE_CONSENT) txt += "ASK.";
    else if(mode == MODE_AUTO) txt += "AUTO.";
    llDialog(av, txt, [ " ", "OK", " " ], chan);
}
show_hardcore_changed_info(key av, integer hc, integer chan)
{
    string txt = "HARDCORE relay mode is now ";
    if(hc == TRUE) txt += "ENABLED.";
    else txt += "OFF.";
    llDialog(av, txt, [ " ", "OK", " " ], chan);
}
show_objects_menu(key av, integer chan)
{
    string s = "";
    if(relay_count() == 0)
        s = "No active relay objects.";
    else{
        integer i;
        for(i=0;i<llGetListLength(g_relays);i+=2)
            s += (string)((i/2)+1)+". "+llList2String(g_relays,i+1)+"\n";
    }
    llDialog(av, "Active relay objects:\n"+s, [ " ", "OK", " " ], chan);
}
show_hardcore_confirm_owner(key av, integer chan)
{
    s_set(av, 0, "", llGetUnixTime()+60.0, "hardcore_owner", "", "", "", chan);
    llDialog(av,
        "WARNING - Activating hard core mode will leave the sub unable to extricate from any restraining furniture. Are you sure?",
        [ "Cancel", "OK", " " ], chan);
}
show_safeword_confirm(key av, integer chan)
{
    if(g_hardcore == TRUE){
        llDialog(av, "Safeword is DISABLED (hardcore mode).", [ " ", "OK", " " ], chan);
        s_clear(av);
        return;
    }
    s_set(av, 0, "", llGetUnixTime()+30.0, "safeword_confirm", "", "", "", chan);
    llDialog(av, "This action will safeword you out of the restraints holding you. Please confirm your choice:", [ "Cancel", "OK", " " ], chan);
}
show_unbind_confirm(key av, integer chan)
{
    s_set(av, 0, "", llGetUnixTime()+30.0, "unbind_confirm", "", "", "", chan);
    llDialog(av, "This action will unbind the sub from their predicament. Please confirm your choice:", [ "Cancel", "OK", " " ], chan);
}
/* =============================================================
   BLOCK: MENU/UI BUILDERS END
   ============================================================= */

/* =============================================================
   BLOCK: RLV PROCESSING LOGIC BEGIN
   ============================================================= */
integer relay_allowed(key sender)
{
    if(g_relay_mode == MODE_OFF) return FALSE;
    if(relay_idx(sender) != -1) return TRUE;
    if(g_relay_mode == MODE_AUTO && relay_count() < 5) return TRUE;
    if(g_relay_mode == MODE_CONSENT && relay_count() < 5) return FALSE;
    return FALSE;
}
process_rly_command(key sender, string name, string message)
{
    integer idx = relay_idx(sender);

    if(g_relay_mode == MODE_OFF) return;

    if(idx != -1){
        llOwnerSay(message);
        if(DEBUG) llOwnerSay("[RELAY] "+llKey2Name(sender)+": "+message);
        return;
    }
    if(g_relay_mode == MODE_AUTO && relay_count() < 5){
        add_relay_object(sender, name);
        llOwnerSay(message);
        if(DEBUG) llOwnerSay("[RELAY] AUTO-accepted "+llKey2Name(sender)+": "+message);
        return;
    }
    if(g_relay_mode == MODE_CONSENT && relay_count() < 5){
        integer temp_chan = (integer)(-1000000.0 * llFrand(1.0) - 1.0);
        s_set(llGetOwner(), 0, (string)sender+"|"+name+"|"+message, llGetUnixTime()+30.0, "consent", "", "", "", temp_chan);
        llDialog(llGetOwner(), "Object \""+name+"\" requests to relay RLV commands to you.\nAllow?", [ "Cancel", "Allow", " " ], temp_chan);
        return;
    }
}
unbind_all()
{
    integer i;
    for(i=0;i<llGetListLength(g_relays);i+=2)
    {
        key obj = llList2Key(g_relays,i);
        llOwnerSay("@clear");
        if(DEBUG) llOwnerSay("[RELAY] Cleared relay object "+llKey2Name(obj));
    }
    clear_relays();
    save_state();
}
/* =============================================================
   BLOCK: RLV PROCESSING LOGIC END
   ============================================================= */

/* =============================================================
   BLOCK: TIMEOUT MANAGEMENT BEGIN
   ============================================================= */
timeout_check()
{
    integer now = llGetUnixTime();
    integer i = 0;
    while(i < llGetListLength(g_sessions)){
        if(now > llList2Float(g_sessions,i+3))
            s_clear(llList2Key(g_sessions,i));
        else i += 10;
    }
}
/* =============================================================
   BLOCK: TIMEOUT MANAGEMENT END
   ============================================================= */

/* =============================================================
   BLOCK: MAIN EVENT LOOP BEGIN
   ============================================================= */
default
{
    state_entry()
    {
        llListen(RELAY_CHANNEL, "", NULL_KEY, "");
        llSetTimerEvent(1.0);
        llMessageLinked(LINK_THIS, 500, "register|1010|Relay|3|apps_relay", NULL_KEY);
        llMessageLinked(LINK_THIS, 530, "relay_load", NULL_KEY);
        if(DEBUG) llOwnerSay("[Relay] Plugin ready.");
    }

    link_message(integer sn, integer num, string str, key id)
    {
        if(num==510)
        {
            list p = llParseString2List(str, ["|"], []);
            if(llList2String(p,0)=="apps_relay" && llGetListLength(p)>=3)
            {
                key av=(key)llList2String(p,1);
                integer chan=(integer)llList2String(p,2);
                show_relay_menu(av, chan);
            }
        }
        if(num==520)
        {
            list p = llParseString2List(str, ["|"], []);
            if(llGetListLength(p)==8 && llList2String(p,0)=="state_sync")
            {
                g_owner = (key)llList2String(p,1);
                string trust_csv = llList2String(p,3);
                string bl_csv = llList2String(p,5);
                string pub_str = llList2String(p,6);

                if(trust_csv == " ") g_trustees = [];
                else g_trustees = llParseString2List(trust_csv, [","], []);
                if(bl_csv == " ") g_blacklist = [];
                else g_blacklist = llParseString2List(bl_csv, [","], []);
                if(pub_str == "1") g_public_access = TRUE;
                else g_public_access = FALSE;
            }
        }
        if(num==530)
        {
            if (llSubStringIndex(str, "relay_save") == 0)
            {
                // Nothing to do
            }
            else if (llSubStringIndex(str, "relay_load") == 0)
            {
                // GUH/Core should respond with relay_save|...; handled on receive
            }
            else
            {
                list p = llParseString2List(str, ["|"], []);
                if(llGetListLength(p) >= 3 && llList2String(p,0) == "relay_save")
                {
                    load_state(p);
                }
            }
        }
    }

    listen(integer chan, string nm, key av, string msg)
    {
        if(chan==RELAY_CHANNEL && llSubStringIndex(msg, "@") == 0)
        {
            if(DEBUG) llOwnerSay("[Relay] Got relay command: "+msg+" from "+llKey2Name(av));
            process_rly_command(av, llKey2Name(av), msg);
            return;
        }
        list s = s_get(av);
        if(llGetListLength(s)==0) return;
        if(chan != llList2Integer(s,8)) return;
        string ctx = llList2String(s,4);
        string param = llList2String(s,5);
        string menucsv = llList2String(s,7);

        if (DEBUG) llOwnerSay("[Relay DEBUG] listen: ctx=" + ctx + " msg=" + msg + " menucsv=" + menucsv);

        if(ctx == "menu")
        {
            list btns = relay_menu_btns(get_acl(av));
            list ctxs = relay_menu_ctxs(get_acl(av));
            integer sel = llListFindList(btns, [msg]);
            if(sel == -1) return;
            string action = llList2String(ctxs, sel);

            if(action == "mode"){ show_mode_menu(av, chan); return; }
            if(action == "objects"){ show_objects_menu(av, chan); return; }
            if(action == "unbind"){ show_unbind_confirm(av, chan); return; }
            if(action == "safeword"){ show_safeword_confirm(av, chan); return; }
            if(action == "back"){
                llMessageLinked(LINK_THIS, 510, "apps|" + (string)av + "|" + (string)chan, NULL_KEY);
                s_clear(av);
                return;
            }
        }
        if(ctx == "mode_menu")
        {
            // No confirmation: mode is set immediately, then info dialog.
            if(msg == "Set Off"){
                g_relay_mode=MODE_OFF; save_state();
                show_mode_info_dialog(av, g_relay_mode, chan);
                s_clear(av); return;
            }
            if(msg == "Set Ask"){
                g_relay_mode=MODE_CONSENT; save_state();
                show_mode_info_dialog(av, g_relay_mode, chan);
                s_clear(av); return;
            }
            if(msg == "Set Auto"){
                g_relay_mode=MODE_AUTO; save_state();
                show_mode_info_dialog(av, g_relay_mode, chan);
                s_clear(av); return;
            }
            // Only owner (ACL1) can set hardcore, and confirms
            if(msg == "Hardcore ON"){
                show_hardcore_confirm_owner(av, chan); return;
            }
            if(msg == "Hardcore OFF"){
                g_hardcore = FALSE; save_state();
                show_hardcore_changed_info(av, g_hardcore, chan);
                llDialog(llGetOwner(), "Hardcore relay mode has been DISABLED by your owner.", [ " ", "OK", " " ], chan);
                s_clear(av); return;
            }
            if(msg == "Cancel"){ s_clear(av); return; }
        }
        if(ctx == "hardcore_owner")
        {
            // Owner confirms enabling hardcore
            if(msg == "OK"){
                g_hardcore = TRUE; save_state();
                show_hardcore_changed_info(av, g_hardcore, chan);
                llDialog(llGetOwner(), "WARNING: Hardcore relay mode is now ENABLED. You will be unable to use safeword or unbind until it is disabled.", [ " ", "OK", " " ], chan);
                s_clear(av); return;
            }
            if(msg == "Cancel"){ s_clear(av); return; }
        }
        if(ctx == "consent")
        {
            list args = llParseString2List(param, ["|"], []);
            key obj = (key)llList2String(args, 0);
            string name = llList2String(args, 1);
            string origmsg = llList2String(args, 2);
            if(msg == "Allow"){
                add_relay_object(obj, name);
                llOwnerSay(origmsg);
                if(DEBUG) llOwnerSay("[RELAY] Consent allowed "+name);
            }
            s_clear(av);
            return;
        }
        if(ctx == "unbind_confirm")
        {
            if(msg == "OK"){
                unbind_all();
                llDialog(av, "All relay objects have been unbound. All relay RLV restrictions cleared.", [ " ", "OK", " " ], chan);
                s_clear(av);
                return;
            }
            if(msg == "Cancel"){
                s_clear(av);
                return;
            }
        }
        if(ctx == "safeword_confirm")
        {
            if(msg == "OK"){
                if(g_hardcore == FALSE){
                    unbind_all();
                    llDialog(av, "All relay objects have been unbound. All relay RLV restrictions cleared.", [ " ", "OK", " " ], chan);
                }
                s_clear(av);
                return;
            }
            if(msg == "Cancel"){
                s_clear(av);
                return;
            }
        }
    }

    timer(){ timeout_check(); }
}
/* =============================================================
   BLOCK: MAIN EVENT LOOP END
   ============================================================= */
