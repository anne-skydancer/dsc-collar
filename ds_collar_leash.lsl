// =============================================================
//  D/s Collar Leashing Plugin – strict LSL, GUH conventions, ACLs
//  Version: 2025-07-08  (ACLs, GUH sync, NO nav row/buttons, Unclip only for LV3)
// =============================================================

integer debug = TRUE;

/*──────── persistent state ────────*/
integer g_leashed        = FALSE;
key     g_leasher        = NULL_KEY;
integer g_leash_length   = 2;     // 1–20 meters, default 2
integer g_follow_mode    = TRUE;  // Always on
integer g_controls_ok    = FALSE;
integer g_turn_to        = FALSE;
vector  g_anchor         = ZERO_VECTOR;
integer lg_channel       = -9119; // lockguard
integer lm_channel       = -8888; // lockmeister
key     g_lg_anchor      = NULL_KEY; // current lockguard anchor (object/avatar)
string  g_chain_texture  = "4d3b6c6f-52e2-da9d-f7be-cccb1e535aca"; // example chain

// --- GUH ACL state (live, synced from core) ---
key    g_owner = NULL_KEY;
list   g_trustees = [];
list   g_blacklist = [];
integer g_public_access = FALSE;

/*──────── session helpers ────────*/
list    g_sessions;

integer sidx(key av){ return llListFindList(g_sessions,[av]); }
integer sset(key av,integer page,string csv,float exp,string ctx,string param,string step,string mcsv,integer chan)
{
    integer i = sidx(av);
    if(~i){
        integer old = llList2Integer(g_sessions,i+9);
        if(old!=-1) llListenRemove(old);
        g_sessions = llDeleteSubList(g_sessions,i,i+9);
    }
    integer lh = llListen(chan,"",av,"");
    g_sessions += [av,page,csv,exp,ctx,param,step,mcsv,chan,lh];
    return TRUE;
}
integer sclear(key av){
    integer i = sidx(av);
    if(~i){
        integer old = llList2Integer(g_sessions,i+9);
        if(old!=-1) llListenRemove(old);
        g_sessions = llDeleteSubList(g_sessions,i,i+9);
    }
    return TRUE;
}
list sget(key av){
    integer i = sidx(av);
    if(~i) return llList2List(g_sessions,i,i+9);
    return [];
}

/*──────── ACL helpers (live, from GUH) ────────*/
integer get_acl(key av)
{
    if(llListFindList(g_blacklist, [av]) != -1) return 5; // Blacklist
    if(av == g_owner) return 1;                // Owner
    if(av == llGetOwner()){
        if(g_owner == NULL_KEY) return 1;
        return 3;                              // Owned wearer
    }
    if(llListFindList(g_trustees, [av]) != -1) return 2;  // Trustee
    if(g_public_access == TRUE) return 4;                 // Public
    return 5;                                             // No access
}

/*──────── menu buttons by ACL ────────*/
list leash_menu_btns(integer acl)
{
    list btns = [];
    if(acl == 1) // LV1: owner
    {
        btns += ["Leash", "Unleash", "Set Length", "Turn", "Pass Leash"];
    }
    else if(acl == 2) // LV2: trustee
    {
        btns += ["Leash", "Unleash", "Set Length", "Pass Leash"];
    }
    else if(acl == 3) // LV3: wearer
    {
        btns += ["Unclip", "Give Leash"];
    }
    else if(acl == 4) // LV4: public
    {
        btns += ["Leash", "Unleash"];
    }
    while(llGetListLength(btns)%3!=0) btns += [" "];
    return btns;
}

/*──────── leash anchor ────────*/
vector leash_anchor_point()
{
    integer nprims = llGetNumberOfPrims();
    integer i;
    for(i=2;i<=nprims;++i)
    {
        string nm = llGetLinkName(i);
        string desc = llList2String(llGetLinkPrimitiveParams(i,[PRIM_DESC]),0);
        if(llToLower(nm) == "leashring" || llToLower(desc) == "leash:ring")
        {
            vector child_local = llList2Vector(llGetLinkPrimitiveParams(i, [PRIM_POS_LOCAL]), 0);
            vector root_pos = llGetRootPosition();
            rotation root_rot = llGetRootRotation();
            return root_pos + (child_local * root_rot);
        }
    }
    return llGetRootPosition();
}

/*──────── main menu ────────*/
show_leash_menu(key av,integer chan){
    integer acl = get_acl(av);
    list btns = leash_menu_btns(acl);
    sset(av,0,"",llGetUnixTime()+180.0,"menu","","","",chan);

    string st = "Leash state:\n";
    if(g_leashed) st += "Leashed to: "+llKey2Name(g_leasher)+"\n";
    else st += "Not leashed\n";
    st += "Length: "+(string)g_leash_length+" m";
    if(g_turn_to) st += "\nTurn: ON";
    else st += "\nTurn: OFF";
    llDialog(av,st,btns,chan);
}

/*──────── leash length dialog (vertical) ────────*/
show_leash_length_menu(key av, integer chan)
{
    // "Back","OK","Cancel" on nav row (top), numbers go DOWN below nav row
    list buttons = ["10", "15", "20", "1", "2", "5"];
    sset(av, 0, "", llGetUnixTime() + 180.0, "set_length", "", "", "", chan);
    string info = "Select leash length (meters):\nCurrent: " + (string)g_leash_length + " m";
    llDialog(av, info, buttons, chan);
}

/*──────── leash visual particles ────────*/
draw_leash_particles(key to)
{
    // Settings for realistic ribbon leash
    vector leash_size = <0.07, 0.07, 0>;     // Slightly thicker ribbon
    vector leash_color = <1.0, 1.0, 1.0>;    // White, adjust for tinted chains
    float gravity = -1.25;                   // Sag strength (lower = more droop)
    float part_age = 2.6;                    // Longer life for smooth arc
    float burst_rate = 0.00;                 // As fast as allowed
    integer part_flags = PSYS_PART_INTERP_COLOR_MASK
                      | PSYS_PART_FOLLOW_SRC_MASK
                      | PSYS_PART_TARGET_POS_MASK
                      | PSYS_PART_FOLLOW_VELOCITY_MASK
                      | PSYS_PART_RIBBON_MASK;  // <-- RIBBON MODE

    // Use your leash texture UUID here (must be full-perm and present in prim)
    string leash_tex = g_chain_texture;

    if (to == NULL_KEY) { llParticleSystem([]); return; }

    list psys = [
        PSYS_SRC_PATTERN, PSYS_SRC_PATTERN_DROP,
        PSYS_SRC_TEXTURE, leash_tex,
        PSYS_SRC_BURST_RATE, burst_rate,
        PSYS_SRC_BURST_PART_COUNT, 1,
        PSYS_PART_MAX_AGE, part_age,
        PSYS_PART_START_SCALE, leash_size,
        PSYS_PART_END_SCALE, leash_size,
        PSYS_PART_START_COLOR, leash_color,
        PSYS_PART_END_COLOR, leash_color,
        PSYS_SRC_ACCEL, <0,0,gravity>,
        PSYS_PART_FLAGS, part_flags,
        PSYS_SRC_TARGET_KEY, to
    ];

    llParticleSystem(psys);
}

stop_leash_particles()
{
    llParticleSystem([]);
}

/*──────── timeout check ────────*/
timeout_check(){
    integer now = llGetUnixTime();
    integer i=0;
    while(i<llGetListLength(g_sessions)){
        if(now>llList2Float(g_sessions,i+3))
             sclear(llList2Key(g_sessions,i));
        else i += 10;
    }
}

/*──────── leash logic: keep wearer in leash range ────────*/
leash_follow_logic()
{
    if(!g_leashed || g_leasher == NULL_KEY) return;

    key wearer = llGetOwner();
    key leasher = g_leasher;
    vector wearer_pos = llGetRootPosition();
    vector anchor = leash_anchor_point();
    vector leash_point = anchor;

    if(leasher != wearer)
    {
        list det = llGetObjectDetails(leasher,[OBJECT_POS]);
        if(llGetListLength(det)>0)
            leash_point = llList2Vector(det,0);
    }

    float max_len = (float)g_leash_length;
    vector offset = wearer_pos - leash_point;
    float dist = llVecMag(offset);

    if(dist > max_len)
    {
        if(g_controls_ok)
        {
            vector tgt = leash_point + llVecNorm(offset) * max_len * 0.98;
            llMoveToTarget(tgt, 0.5);
            if(g_turn_to)
            {
                vector v = leash_point - wearer_pos;
                float strength = 1.5;
                float damping = 0.6;
                float angle = llAtan2(v.x, v.y);
                llLookAt(leash_point, strength, damping);
            }
        }
    }
    draw_leash_particles(leasher);
}

/*──────── default state ────────*/
default
{
    state_entry(){
        llListen(lg_channel, "", NULL_KEY, "");
        llListen(lm_channel, "", NULL_KEY, "");
        if(debug) llOwnerSay("[leash] Ready.");
        llMessageLinked(LINK_THIS,500,"register|1004|Leashing|4|leash",NULL_KEY);
        llSetTimerEvent(1.0);
        llRequestPermissions(llGetOwner(), PERMISSION_TAKE_CONTROLS);
    }

    run_time_permissions(integer perm)
    {
        if(perm & PERMISSION_TAKE_CONTROLS) g_controls_ok = TRUE;
        else g_controls_ok = FALSE;
    }

    link_message(integer sn,integer num,string str,key id)
    {
        if(num == 510)
        {
            list a = llParseString2List(str, ["|"], []);
            if(llList2String(a,0) == "leash" && llGetListLength(a) >= 3)
            {
                key av   = (key)llList2String(a, 1);
                integer chan = (integer)llList2String(a, 2);
                show_leash_menu(av, chan);
            }
        }
        // --- ACL state sync from GUH/Access plugin:
        if(num == 520)
        {
            list p = llParseString2List(str, ["|"], []);
            if(llGetListLength(p) == 8 && llList2String(p,0) == "state_sync")
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
    }

    listen(integer chan, string nm, key av, string msg)
    {
        list s = sget(av);
        if(llGetListLength(s)==0) return;
        if(chan!=llList2Integer(s,8)) return;

        string ctx = llList2String(s,4);

        if(ctx == "menu")
        {
            integer acl = get_acl(av);
            if(msg == "Leash"){
                if(acl==1 || acl==2 || acl==4){
                    g_leashed = TRUE;
                    g_leasher = av;
                    llOwnerSay("[leash] "+llKey2Name(av)+" leashed you.");
                    sclear(av);
                }
            return;
        }
        if(msg == "Unleash"){
            if(acl==1 || acl==2 || acl==4){
                g_leashed = FALSE;
                g_leasher = NULL_KEY;
                stop_leash_particles();
                llStopMoveToTarget();
                llStopLookAt();
                llOwnerSay("[leash] Leash released.");
                sclear(av);
            }
            return;
        }
        if(msg == "Set Length"){
            if(acl==1 || acl==2){
                show_leash_length_menu(av, chan);
                }
            return;
        }
        if(msg == "Turn"){
            if(acl==1){
                g_turn_to = !g_turn_to;
                show_leash_menu(av, chan);
            }
            return;
        }
        if(msg == "Unclip"){
            if(acl==3){
                g_leashed = FALSE;
                g_leasher = NULL_KEY;
                stop_leash_particles();
                llStopMoveToTarget();
                llStopLookAt();
                llOwnerSay("[leash] Unclipped.");
                sclear(av);
            }
            return;
        }
        if(msg == "Give Leash"){
            if(acl==3){
                // To be implemented: Scan for nearby avs and offer leash
                llOwnerSay("[leash] Give Leash (to nearby agent, not yet implemented)");
                sclear(av);
                }
            return;
        }
        if(msg == "Pass Leash"){
               if(acl==1 || acl==2){
                     // To be implemented: Scan for nearby avs and pass leash
                    llOwnerSay("[leash] Pass Leash (to nearby agent, not yet implemented)");
                   sclear(av);
                    }
               return;
               }
        }

        if(ctx == "set_length")
        {
            if(msg == "1" || msg == "2" || msg == "5" || msg == "10" || msg == "15" || msg == "20")
            {
                g_leash_length = (integer)msg;
                llOwnerSay("Leash length set to " + msg + " meters.");
                sclear(av);
                return;
            }
        }

        // --- lockguard leash integration ---
        if (chan == lg_channel)
        {
            list parts = llParseString2List(msg, [" "], []);
            if (llGetListLength(parts) >= 4 && llList2String(parts, 0) == "lockguard")
                {
                    key target_av = llList2Key(parts, 1);
                    string point = llList2String(parts, 2);
                    string cmd = llList2String(parts, 3);
                    if (target_av == llGetOwner())
                    {
                        if (cmd == "link" && llGetListLength(parts) >= 5)
                        {
                            key anchor = llList2Key(parts, 4);
                            g_leashed = TRUE;
                            g_leasher = anchor;
                            g_lg_anchor = anchor;
                            llOwnerSay("[leash] leashed via lockguard to: " + (string)anchor);
                        }
                        else if (cmd == "unlink")
                        {
                            g_leashed = FALSE;
                            g_leasher = NULL_KEY;
                            g_lg_anchor = NULL_KEY;
                            stop_leash_particles();
                            llStopMoveToTarget();
                            llStopLookAt();
                            llOwnerSay("[leash] unleashed via lockguard.");
                        }
                    }
                }
            }

            // --- lockmeister integration (simple reply) ---
            if (chan == lm_channel)
             {
                list parts = llParseString2List(msg, ["|"], []);
                if (llGetListLength(parts) >= 4 && llList2String(parts, 1) == "LMV2" && llList2String(parts, 2) == "RequestPoint")
                    {
                    string point = llList2String(parts, 3);
                    if (point == "collar")
                    {
                        llRegionSayTo(av, lm_channel, (string)llGetOwner() + "|LMV2|ReplyPoint|collar|" + (string)llGetKey());
                    }
                }
            }
        }

    timer()
    {
        timeout_check();
        if(g_leashed)
            leash_follow_logic();
        else
            stop_leash_particles();
    }
}
