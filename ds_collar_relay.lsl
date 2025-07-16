/* =============================================================
   TITLE: ds_collar_relay - RLV Relay Plugin (Apps Menu)
   VERSION: 2.1.1 (Reset robust, OC-compatible)
   REVISION: 2025-07-16
   ============================================================= */

integer DEBUG = TRUE;

integer RELAY_CHANNEL   = -1812221819; // RLV relay channel (scan, restrict, info)
integer RLV_RESP_CHANNEL= 4711;        // Legacy fallback
integer MAX_RELAYS      = 5;           // RLV standard

// Modes
integer MODE_OFF     = 0;
integer MODE_ON      = 1;
integer MODE_HARDCORE= 2;

integer g_mode       = MODE_ON;
integer g_hardcore   = FALSE;
list    g_relays     = []; // [obj, name, session_chan, restrictions-csv]
list    g_sessions   = []; // menu/session tracking

key     g_owner = NULL_KEY;
list    g_trustees = [];
list    g_blacklist = [];
integer g_public_access = FALSE;

/* ========== SESSION/HELPERS ========== */
integer s_idx(key av) { return llListFindList(g_sessions, [av]); }
integer g_idx(list l, key k) { return llListFindList(l, [k]); }
integer relay_idx(key obj) {
    integer i;
    for (i=0;i<llGetListLength(g_relays);i+=4)
        if (llList2Key(g_relays,i)==obj) return i;
    return -1;
}
integer relay_count() { return llGetListLength(g_relays)/4; }
string restrict_list(key obj) {
    integer idx = relay_idx(obj);
    if (idx==-1) return "";
    return llList2String(g_relays,idx+3);
}

/* Adds/removes relays */
add_relay_object(key obj, string name, integer session_chan) {
    if (relay_idx(obj)!=-1) return;
    if (relay_count()>=MAX_RELAYS) return;
    g_relays += [obj,name,session_chan,""];
}
remove_relay_object(key obj) {
    integer idx = relay_idx(obj);
    if (idx!=-1) g_relays = llDeleteSubList(g_relays,idx,idx+3);
}
clear_relays() { g_relays = []; }
store_restriction(key obj, string cmd) {
    integer idx = relay_idx(obj);
    if (idx==-1) return;
    string r = llList2String(g_relays,idx+3);
    if (r!="") r += ","+cmd;
    else r = cmd;
    g_relays = llListReplaceList(g_relays, [r], idx+3, idx+3);
}
clear_restrictions(key obj) {
    integer idx = relay_idx(obj);
    if (idx==-1) return;
    g_relays = llListReplaceList(g_relays, [""], idx+3, idx+3);
}

/* Helper: return access level */
integer get_acl(key av) {
    if (g_idx(g_blacklist,av)!=-1) return 5;
    if (av==g_owner) return 1;
    if (av==llGetOwner()) {
        if (g_owner==NULL_KEY) return 1;
        return 3;
    }
    if (g_idx(g_trustees,av)!=-1) return 2;
    if (g_public_access==TRUE) return 4;
    return 5;
}

/* ========== RELAY LOGIC ========== */
integer is_scan_info_cmd(string cmd) {
    if (cmd == "@version") return TRUE;
    if (cmd == "@versionnew") return TRUE;
    if (cmd == "!version") return TRUE;
    if (cmd == "!impl") return TRUE;
    if (cmd == "!release") return TRUE;
    return FALSE;
}

send_relay_response(key sender, integer session_chan, string cmd, integer ok) {
    string result = "deny";
    if (ok==1) result = "ok";
    string msg = "RLV,"+(string)llGetKey()+","+cmd+","+result;
    if (DEBUG) llOwnerSay("[Relay ACK] "+msg);
    llRegionSay(RELAY_CHANNEL,msg);
    llRegionSayTo(sender,session_chan,msg);
}

/* ========== MAIN RELAY COMMAND HANDLER ========== */
handle_relay_command(key sender, string name, integer session_chan, string message) {
    string cmd = message;
    if (llSubStringIndex(message,"RLV,")==0) {
        list parts = llParseString2List(message,[","],[]);
        if (llGetListLength(parts)>=3) cmd=llList2String(parts,2);
    }
    // Info/scan commands, always ACK and auto-register
    if (is_scan_info_cmd(cmd)) {
        if (relay_idx(sender)==-1 && relay_count()<MAX_RELAYS)
            add_relay_object(sender,name,session_chan);
        if (cmd=="!release") {
            clear_restrictions(sender);
            remove_relay_object(sender);
        }
        if (cmd=="@versionnew")
            send_relay_response(sender,session_chan,"@version=1.11",1);
        else
            send_relay_response(sender,session_chan,cmd,1);
        return;
    }
    // Handle furniture failure
    if (cmd=="!release_fail") {
        clear_restrictions(sender);
        remove_relay_object(sender);
        send_relay_response(sender,session_chan,"!release_fail",1);
        if (DEBUG) llOwnerSay("[Relay] Released on fail from "+name);
        return;
    }
    // Actual RLV restrictions
    if (llSubStringIndex(cmd,"@")==0) {
        if (g_mode==MODE_OFF) {
            send_relay_response(sender,session_chan,cmd,0);
            return;
        }
        // ON and HARDCORE both behave as "always allow"
        if (relay_idx(sender)==-1 && relay_count()<MAX_RELAYS)
            add_relay_object(sender,name,session_chan);
        store_restriction(sender,cmd);
        llOwnerSay(cmd);
        send_relay_response(sender,session_chan,cmd,1);
        if (DEBUG) llOwnerSay("[RELAY] Applied (ON/HARDCORE): "+cmd);
        return;
    }
    // Fallback: deny
    send_relay_response(sender,session_chan,cmd,0);
}

/* ========== SESSION MENU AND STATE ========== */
integer s_set(key av, integer page, string csv, float expiry, string ctx, string param, string step, string menucsv, integer dialog_chan) {
    integer i = s_idx(av); integer old=-1;
    if (~i) { old=llList2Integer(g_sessions,i+9); g_sessions=llDeleteSubList(g_sessions,i,i+9);}
    if (old!=-1) llListenRemove(old);
    integer lh=llListen(dialog_chan,"",av,"");
    g_sessions += [av,page,csv,expiry,ctx,param,step,menucsv,dialog_chan,lh];
    return TRUE;
}
integer s_clear(key av) {
    integer i = s_idx(av); if (~i) {
        integer old=llList2Integer(g_sessions,i+9); if (old!=-1) llListenRemove(old);
        g_sessions = llDeleteSubList(g_sessions,i,i+9);}
    return TRUE;
}
list s_get(key av) {
    integer i = s_idx(av); if (~i) return llList2List(g_sessions,i,i+9); return [];
}

/* ========== MENU/UI (BOTTOM-UP ORDER) ========== */
list relay_menu_btns(integer acl)
{
    // Build bottom-up for LSL dialog layout
    list btns = [ " ", "Back", " " ]; // Bottom row: Back centered
    string third_btn = " ";
    if (acl == 1 || acl == 2) third_btn = "Unbind";
    else if (acl == 3 && g_hardcore == FALSE) third_btn = "Safeword";
    btns += [ "Mode", "Active Objects", third_btn ]; // Row above
    return btns;
}
list relay_menu_ctxs(integer acl)
{
    list c = [ " ", "back", " " ];
    string third_ctx = " ";
    if (acl == 1 || acl == 2) third_ctx = "unbind";
    else if (acl == 3 && g_hardcore == FALSE) third_ctx = "safeword";
    c += [ "mode", "objects", third_ctx ];
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
    if(g_mode == 1)
        mode_str = "ON";
    else if(g_mode == 2)
        mode_str = "HARDCORE";

    string hc_str;
    if(g_hardcore == TRUE)
        hc_str = "Hardcore ON";
    else
        hc_str = "Hardcore OFF";

    llDialog(av, "RLV Relay\nMode: "+mode_str+"\n"+hc_str, btns, chan);
}
list mode_menu_btns()
{
    // Bottom row: Cancel centered
    list btns = [ " ", "Cancel", " " ];
    // Row above: Set Off, Set On, Hardcore toggle
    string hc_btn;
    if (g_hardcore == TRUE) hc_btn = "Hardcore OFF";
    else hc_btn = "Hardcore ON";
    btns += [ "Set Off", "Set On", hc_btn ];
    return btns;
}
show_mode_menu(key av, integer chan)
{
    string mode_str = "Current mode: ";
    if(g_mode == 1) mode_str += "ON";
    else if(g_mode == 2) mode_str += "HARDCORE";
    else mode_str += "OFF";
    string hc_str = "\nHardcore: ";
    if(g_hardcore == TRUE) hc_str += "ON"; else hc_str += "OFF";
    list btns = mode_menu_btns();
    s_set(av, 0, "", llGetUnixTime()+60.0, "mode_menu", "", "", "", chan);
    llDialog(av, mode_str+hc_str, btns, chan);
}
show_mode_info_dialog(key av, integer mode, integer chan)
{
    string txt = "Relay mode is now ";
    if(mode == MODE_OFF) txt += "OFF.";
    else if(mode == MODE_ON) txt += "ON.";
    else if(mode == MODE_HARDCORE) txt += "HARDCORE.";
    llDialog(av, txt, [ " ", "OK", " " ], chan);
}
show_hardcore_changed_info(key av, integer hc, integer chan)
{
    string txt = "Hardcore relay mode is now ";
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
        for(i=0;i<llGetListLength(g_relays);i+=4)
            s += (string)((i/4)+1)+". "+llList2String(g_relays,i+1)+"\n";
    }
    llDialog(av, "Active relay objects:\n"+s, [ " ", "OK", " " ], chan);
}
show_hardcore_confirm_owner(key av, integer chan)
{
    s_set(av, 0, "", llGetUnixTime()+60.0, "hardcore_owner", "", "", "", chan);
    llDialog(av,
        "WARNING - Activating hardcore mode will leave the sub unable to extricate from any restraining furniture. Are you sure?",
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
unbind_all()
{
    integer i;
    for (i = 0; i < llGetListLength(g_relays); i += 4)
    {
        key obj          = llList2Key(g_relays, i);
        integer session_chan = llList2Integer(g_relays, i + 2);
        send_relay_response(obj, session_chan, "!release", 1);
        llOwnerSay("@clear");
        if (DEBUG)
        {
            llOwnerSay("[RELAY] Cleared relay object " + llKey2Name(obj));
        }
    }
    clear_relays();
}
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
save_state()
{
    string msg = "relay_save|" + (string)g_mode + "|" + (string)g_hardcore;
    llMessageLinked(LINK_THIS, 530, msg, NULL_KEY);
    if (DEBUG) llOwnerSay("[Relay] State saved: " + msg);
}
load_state(list p)
{
    g_mode = (integer)llList2String(p,1);
    g_hardcore = (integer)llList2String(p,2);
    if (DEBUG) llOwnerSay("[Relay] State loaded: mode=" + (string)g_mode + " hc=" + (string)g_hardcore);
}

/* ========== MAIN EVENT LOOP ========== */
default
{
    state_entry()
    {
        llListen(RELAY_CHANNEL, "", NULL_KEY, "");
        llSetTimerEvent(1.0);
        llMessageLinked(LINK_THIS, 500, "register|1010|Relay|3|rlv_relay", NULL_KEY);
        llMessageLinked(LINK_THIS, 530, "relay_load", NULL_KEY);
        if(DEBUG) llOwnerSay("[Relay] Plugin ready.");
    }

    link_message(integer sn, integer num, string str, key id)
    {
        if (num == -900 && str == "reset_owner")
        {
            llResetScript();
            return;
        }        
        if(num==510)
        {
            list p = llParseString2List(str, ["|"], []);
            if(llList2String(p,0)=="rlv_relay" && llGetListLength(p)>=3)
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
        // Standard relay: "command|session_chan"
        if(chan==RELAY_CHANNEL)
        {
            list p = llParseString2List(msg, ["|"], []);
            string rlv_msg = llList2String(p,0);
            integer session_chan;
            if (llGetListLength(p) > 1)
                session_chan = (integer)llList2String(p, 1);
            else
                session_chan = RLV_RESP_CHANNEL;
            if (DEBUG) llOwnerSay("[Relay] Got relay command: " + rlv_msg + " from " + llKey2Name(av) + " @chan " + (string)session_chan);
            handle_relay_command(av, llKey2Name(av), session_chan, rlv_msg);
            return;
        }
        // == Menu system ==
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
                llMessageLinked(LINK_THIS, 510, "rlv|" + (string)av + "|" + (string)chan, NULL_KEY);
                s_clear(av);
                return;
            }
        }
        if(ctx == "mode_menu")
        {
            if(msg == "Set Off"){
                g_mode=MODE_OFF; g_hardcore=FALSE; save_state();
                show_mode_info_dialog(av, g_mode, chan);
                s_clear(av); return;
            }
            if(msg == "Set On"){
                g_mode=MODE_ON; g_hardcore=FALSE; save_state();
                show_mode_info_dialog(av, g_mode, chan);
                s_clear(av); return;
            }
            if(msg == "Hardcore ON"){
                show_hardcore_confirm_owner(av, chan); return;
            }
            if(msg == "Hardcore OFF"){
                g_hardcore = FALSE; g_mode=MODE_ON; save_state();
                show_hardcore_changed_info(av, g_hardcore, chan);
                if(g_owner != NULL_KEY && llGetOwner() != av) {
                    llDialog(llGetOwner(), "Hardcore relay mode has been DISABLED by your owner.", [ " ", "OK", " " ], chan);
                }
                s_clear(av); return;
            }
            if(msg == "Cancel"){ s_clear(av); return; }
        }
        if(ctx == "hardcore_owner")
        {
            // Owner confirms enabling hardcore
            if(msg == "OK") {
                g_hardcore = TRUE;
                g_mode = MODE_HARDCORE;
                save_state();
                show_hardcore_changed_info(av, g_hardcore, chan);
                if(g_owner != NULL_KEY && llGetOwner() != av) {
                    llDialog(llGetOwner(), "WARNING - Hardcore mode is now enabled.", [ " ", "OK", " " ], chan);
                }
                s_clear(av); 
                return;
            }
            if(msg == "Cancel"){ s_clear(av); return; }
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

    timer()
    { timeout_check(); }

    changed(integer change)
    {
        /* Block-style: handle ownership change */
        if (change & CHANGED_OWNER)
        {
            llResetScript();
        }
    }
}
/* ==================== END ==================== */
