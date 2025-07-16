/* =============================================================
   TITLE: ds_collar_leash - Leashing & Movement Restraint Plugin
   VERSION: 1.1.1 (Plugin-local reset, no rebroadcast)
   REVISION: 2025-07-16
   ============================================================= */

/* =============================================================
   BLOCK: GLOBAL VARIABLES & CONFIG BEGIN
   ============================================================= */

integer DEBUG              = TRUE;
integer PLUGIN_SN         = 1004;
string  PLUGIN_LABEL      = "Leashing";
integer PLUGIN_MIN_ACL    = 4;
string  PLUGIN_CONTEXT    = "apps_leash";

integer g_leashed          = FALSE;
key     g_leasher          = NULL_KEY;
integer g_leash_length     = 2;
integer g_follow_mode      = TRUE;
integer g_controls_ok      = FALSE;
integer g_turn_to          = FALSE;
vector  g_anchor           = ZERO_VECTOR;
integer lg_channel         = -9119;
integer lm_channel         = -8888;
key     g_lg_anchor        = NULL_KEY;
string  g_chain_texture    = "4d3b6c6f-52e2-da9d-f7be-cccb1e535aca";

key     g_owner            = NULL_KEY;
list    g_trustees         = [];
list    g_blacklist        = [];
integer g_public_access    = FALSE;

/* Session state: [av, page, csv, exp, ctx, param, step, mcsv, chan, listen] */
list    g_sessions;
/* =============================================================
   BLOCK: GLOBAL VARIABLES & CONFIG END
   ============================================================= */

/* =============================================================
   BLOCK: SESSION HELPERS
   ============================================================= */
integer s_idx(key av) { return llListFindList(g_sessions, [av]); }
integer s_set(key av, integer page, string csv, float exp, string ctx, string param, string step, string mcsv, integer chan)
{
    integer i = s_idx(av);
    if (~i) {
        integer old = llList2Integer(g_sessions, i+9);
        if (old != -1) llListenRemove(old);
        g_sessions = llDeleteSubList(g_sessions, i, i+9);
    }
    integer lh = llListen(chan, "", av, "");
    g_sessions += [av, page, csv, exp, ctx, param, step, mcsv, chan, lh];
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
   BLOCK: ACL/ACCESS CONTROL HELPERS
   ============================================================= */
integer get_acl(key av)
{
    if (llListFindList(g_blacklist, [av]) != -1) return 5;
    if (av == g_owner) return 1;
    if (av == llGetOwner()) {
        if (g_owner == NULL_KEY) return 1;
        return 3;
    }
    if (llListFindList(g_trustees, [av]) != -1) return 2;
    if (g_public_access == TRUE) return 4;
    return 5;
}
/* =============================================================
   BLOCK: ACL/ACCESS CONTROL HELPERS END
   ============================================================= */

/* =============================================================
   BLOCK: MENU BUILDERS & UI
   ============================================================= */
list leash_menu_btns(integer acl)
{
    list btns = [];
    if (acl == 1)      btns += ["Leash", "Unleash", "Set Length", "Turn", "Pass Leash", "Anchor Leash"];
    else if (acl == 2) btns += ["Leash", "Unleash", "Set Length", "Pass Leash", "Anchor Leash"];
    else if (acl == 3) btns += ["Unclip", "Give Leash"];
    else if (acl == 4) btns += ["Leash", "Unleash"];
    while (llGetListLength(btns) % 3 != 0) btns += [" "];
    return btns;
}

show_leash_menu(key av, integer chan)
{
    integer acl = get_acl(av);
    list btns = leash_menu_btns(acl);
    s_set(av, 0, "", llGetUnixTime()+180.0, "leash_menu", "", "", "", chan);

    string st = "Leash state:\n";
    if (g_leashed)
        st += "Leashed to: " + llKey2Name(g_leasher) + "\n";
    else
        st += "Not leashed\n";
    st += "Length: " + (string)g_leash_length + " m";
    if (g_turn_to)
        st += "\nTurn: ON";
    else
        st += "\nTurn: OFF";
    llDialog(av, st, btns, chan);
}

show_leash_length_menu(key av, integer chan)
{
    list buttons = ["10", "15", "20", "1", "2", "5"];
    s_set(av, 0, "", llGetUnixTime() + 180.0, "leash_set_length", "", "", "", chan);
    string info = "Select leash length (meters):\nCurrent: " + (string)g_leash_length + " m";
    llDialog(av, info, buttons, chan);
}
/* =============================================================
   BLOCK: MENU BUILDERS & UI END
   ============================================================= */

/* =============================================================
   BLOCK: LEASH TRANSFER & PASS LOGIC (SENSORS & HANDLERS)
   ============================================================= */
give_leash_scan(key av, integer chan)
{
    llSensor("", NULL_KEY, AGENT, 10.0, TWO_PI);
    s_set(av, 0, "", llGetUnixTime() + 30.0, "leash_give_scan", "", "", "", chan);
}
pass_leash_scan(key av, integer chan)
{
    llSensor("", NULL_KEY, AGENT, 10.0, TWO_PI);
    s_set(av, 0, "", llGetUnixTime() + 30.0, "leash_pass_scan", "", "", "", chan);
}
anchor_leash_scan(key av, integer chan)
{
    llSensor("", NULL_KEY, ACTIVE | PASSIVE, 10.0, TWO_PI);
    s_set(av, 0, "", llGetUnixTime() + 30.0, "leash_anchor_scan", "", "", "", chan);
}

handle_avatar_scan(key av, string ctx, integer n, integer chan)
{
    list cands = [];
    integer i;
    for (i = 0; i < n; ++i)
    {
        key found = llDetectedKey(i);
        if (found == av) jump skip;
        if (llListFindList(g_blacklist, [found]) != -1) jump skip;
        cands += found;
        @skip;
    }
    if (llGetListLength(cands) == 0)
    {
        llDialog(av, "No avatars found within 10m.", ["OK"], chan);
        s_clear(av);
        return;
    }
    list labels = [];
    for (i = 0; i < llGetListLength(cands); ++i) labels += llKey2Name(llList2Key(cands, i));
    list buttons;
    for (i = 0; i < llGetListLength(labels); ++i) buttons += [(string)(i+1)];
    while (llGetListLength(buttons) % 3 != 0) buttons += [" "];

    string prompt = "";
    if(ctx == "leash_give_scan") prompt = "Give leash to:\n";
    else prompt = "Pass leash to:\n";

    s_set(av, 0, llDumpList2String(cands, ","), llGetUnixTime() + 30.0, ctx + "_pick", "", "", "", chan);
    llDialog(av, prompt + llDumpList2String(labels, "\n"), buttons, chan);
}

handle_object_scan(key av, integer n, integer chan)
{
    list cands = [];
    integer i;
    for (i = 0; i < n; ++i)
    {
        key found = llDetectedKey(i);
        cands += found;
    }
    if (llGetListLength(cands) == 0)
    {
        llDialog(av, "No anchorable objects found within 10m.", ["OK"], chan);
        s_clear(av);
        return;
    }
    list labels;
    for (i = 0; i < llGetListLength(cands); ++i) labels += llDetectedName(i);
    list buttons;
    for (i = 0; i < llGetListLength(labels); ++i) buttons += [(string)(i+1)];
    while (llGetListLength(buttons) % 3 != 0) buttons += [" "];
    s_set(av, 0, llDumpList2String(cands, ","), llGetUnixTime() + 30.0, "leash_anchor_pick", "", "", "", chan);
    llDialog(av, "Anchor leash to object:\n" + llDumpList2String(labels, "\n"), buttons, chan);
}
/* =============================================================
   BLOCK: LEASH TRANSFER & PASS LOGIC END
   ============================================================= */

/* =============================================================
   BLOCK: LEASH ANCHOR & PARTICLE EFFECTS
   ============================================================= */
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

draw_leash_particles(key to)
{
    vector leash_size = <0.07, 0.07, 0>;
    vector leash_color = <1.0, 1.0, 1.0>;
    float gravity = -1.25;
    float part_age = 2.6;
    float burst_rate = 0.00;
    integer part_flags = PSYS_PART_INTERP_COLOR_MASK
                      | PSYS_PART_FOLLOW_SRC_MASK
                      | PSYS_PART_TARGET_POS_MASK
                      | PSYS_PART_FOLLOW_VELOCITY_MASK
                      | PSYS_PART_RIBBON_MASK;
    string leash_tex = g_chain_texture;
    if (to == NULL_KEY)
    {
        llParticleSystem([]);
        return;
    }
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
/* =============================================================
   BLOCK: LEASH ANCHOR & PARTICLE EFFECTS END
   ============================================================= */

/* =============================================================
   BLOCK: TURNING AND MOVEMENT LOGIC
   ============================================================= */
turn_to_leasher(key leasher)
{
    if(leasher == NULL_KEY) return;
    vector wearer_pos = llGetRootPosition();
    list det = llGetObjectDetails(leasher, [OBJECT_POS]);
    if(llGetListLength(det) < 1) return;
    vector leasher_pos = llList2Vector(det, 0);
    vector fwd = llVecNorm(leasher_pos - wearer_pos);
    rotation rot = llRotBetween(<1,0,0>, fwd);
    llOwnerSay("@setrot:" + (string)rot + "=force");
}

clear_turn() { llOwnerSay("@setrot=clear"); }

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
            if(g_turn_to && g_leasher != NULL_KEY)
                turn_to_leasher(g_leasher);
        }
    }
    draw_leash_particles(leasher);
}
/* =============================================================
   BLOCK: TURNING AND MOVEMENT LOGIC END
   ============================================================= */

/* =============================================================
   BLOCK: TIMEOUT/SESSION MAINTENANCE
   ============================================================= */
timeout_check()
{
    integer now = llGetUnixTime();
    integer i=0;
    while(i<llGetListLength(g_sessions)){
        if(now>llList2Float(g_sessions,i+3))
             s_clear(llList2Key(g_sessions,i));
        else i += 10;
    }
}
/* =============================================================
   BLOCK: TIMEOUT/SESSION MAINTENANCE END
   ============================================================= */

/* =============================================================
   BLOCK: MAIN EVENT STATE
   ============================================================= */
default
{
    state_entry()
    {
        llListen(lg_channel, "", NULL_KEY, "");
        llListen(lm_channel, "", NULL_KEY, "");
        llMessageLinked(LINK_THIS, 500,
            "register|" + (string)PLUGIN_SN + "|" + PLUGIN_LABEL + "|" + (string)PLUGIN_MIN_ACL + "|" + PLUGIN_CONTEXT,
            NULL_KEY);
        if(DEBUG) llOwnerSay("[leash] Ready.");
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
        /* ============================================================
           BLOCK: RESET HANDLER
           Resets on 'reset_owner' link_message, no rebroadcast.
           ============================================================ */
        if (num == -900 && str == "reset_owner")
        {
            llResetScript();
            return;
        }
        if(num == 510)
        {
            list a = llParseString2List(str, ["|"], []);
            if(llList2String(a,0) == PLUGIN_CONTEXT && llGetListLength(a) >= 3)
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

    sensor(integer n)
    {
        integer i;
        for (i = 0; i < llGetListLength(g_sessions); i += 10)
        {
            key av = llList2Key(g_sessions, i);
            string ctx = llList2String(g_sessions, i+4);
            integer chan = llList2Integer(g_sessions, i+8);

            if (ctx == "leash_give_scan" || ctx == "leash_pass_scan")
                handle_avatar_scan(av, ctx, n, chan);
            else if (ctx == "leash_anchor_scan")
                handle_object_scan(av, n, chan);
        }
    }

    no_sensor()
    {
        integer i;
        for (i = 0; i < llGetListLength(g_sessions); i += 10)
        {
            key av = llList2Key(g_sessions, i);
            string ctx = llList2String(g_sessions, i+4);
            integer chan = llList2Integer(g_sessions, i+8);
            if (ctx == "leash_give_scan" || ctx == "leash_pass_scan" || ctx == "leash_anchor_scan")
            {
                llDialog(av, "Nothing found within 10m.", ["OK"], chan);
                s_clear(av);
            }
        }
    }

    listen(integer chan, string nm, key av, string msg)
    {
        list s = s_get(av);
        if(llGetListLength(s)==0) return;
        if(chan!=llList2Integer(s,8)) return;
        string ctx = llList2String(s,4);

        // Main leash menu handling
        if(ctx == "leash_menu")
        {
            integer acl = get_acl(av);
            if(msg == "Leash"){
                if(acl==1 || acl==2 || acl==4){
                    g_leashed = TRUE;
                    g_leasher = av;
                    llOwnerSay("[leash] "+llKey2Name(av)+" leashed you.");
                    s_clear(av);
                }
                return;
            }
            if(msg == "Unleash"){
                if(acl==1 || acl==2 || acl==4){
                    g_leashed = FALSE;
                    g_leasher = NULL_KEY;
                    stop_leash_particles();
                    clear_turn();
                    llStopMoveToTarget();
                    llOwnerSay("[leash] Leash released.");
                    s_clear(av);
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
                    if (g_turn_to == TRUE) g_turn_to = FALSE;
                    else g_turn_to = TRUE;
                    show_leash_menu(av, chan);
                }
                return;
            }
            if(msg == "Unclip"){
                if(acl==3){
                    g_leashed = FALSE;
                    g_leasher = NULL_KEY;
                    stop_leash_particles();
                    clear_turn();
                    llStopMoveToTarget();
                    llOwnerSay("[leash] Unclipped.");
                    s_clear(av);
                }
                return;
            }
            if(msg == "Give Leash"){
                if(acl==3){
                    give_leash_scan(av, chan);
                }
                return;
            }
            if(msg == "Pass Leash"){
                if(acl==1 || acl==2){
                    pass_leash_scan(av, chan);
                }
                return;
            }
            if(msg == "Anchor Leash"){
                if(acl==1 || acl==2){
                    anchor_leash_scan(av, chan);
                }
                return;
            }
        }

        // Avatar selection after scan for give/pass
        if (ctx == "leash_give_scan_pick" || ctx == "leash_pass_scan_pick")
        {
            list keys = llParseString2List(llList2String(s,2), [","], []);
            integer sel = (integer)msg;
            if (sel > 0 && sel <= llGetListLength(keys)) {
                key picked = llList2Key(keys, sel-1);
                g_leashed = TRUE;
                g_leasher = picked;
                if(ctx == "leash_give_scan_pick")
                    llOwnerSay("[leash] Gave leash to " + llKey2Name(picked));
                else if(ctx == "leash_pass_scan_pick")
                    llOwnerSay("[leash] Passed leash to " + llKey2Name(picked));
                s_clear(av);
            }
            return;
        }
        // Anchor leash to object
        if(ctx == "leash_anchor_pick")
        {
            list keys = llParseString2List(llList2String(s,2), [","], []);
            integer sel = (integer)msg;
            if (sel > 0 && sel <= llGetListLength(keys)) {
                key picked = llList2Key(keys, sel-1);
                g_leashed = TRUE;
                g_leasher = picked;
                llOwnerSay("[leash] Leashed to anchor object: " + (string)picked);
                s_clear(av);
            }
            return;
        }

        // Set leash length
        if(ctx == "leash_set_length")
        {
            if(msg == "1" || msg == "2" || msg == "5" || msg == "10" || msg == "15" || msg == "20")
            {
                g_leash_length = (integer)msg;
                llOwnerSay("Leash length set to " + msg + " meters.");
                s_clear(av);
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

    changed(integer change)
    {
        /* ============================================================
           BLOCK: OWNER CHANGE RESET HANDLER
           Resets on owner change, no rebroadcast.
           ============================================================ */
        if (change & CHANGED_OWNER)
        {
            llResetScript();
        }
    }
}
/* =============================================================
   BLOCK: MAIN EVENT STATE END
   ============================================================= */
