/* =============================================================
   TITLE: ds_collar_rlv - RLV Suite/Control Plugin (ACL Updated)
   VERSION: 1.3.2
   REVISION: 2025-07-21
   ============================================================= */

integer DEBUG = TRUE;

integer ACL_OWNER   = 1;
integer ACL_TRUSTEE = 2;
integer ACL_WEARER  = 3;
integer ACL_DENY    = 5;

integer MAX_RESTRICTIONS = 32;
integer DIALOG_PAGE_SIZE = 9;

list CAT_INV    = [ "@detachall", "@addoutfit", "@remoutfit", "@remattach", "@addattach", "@attachall", "@showinv", "@viewnote", "@viewscript" ];
list CAT_SPEECH = [ "@sendchat", "@recvim", "@sendim", "@startim", "@chatshout", "@chatwhisper" ];
list CAT_TRAVEL = [ "@tptlm", "@tploc", "@tplure" ];
list CAT_OTHER  = [ "@edit", "@rez", "@touchall", "@touchworld", "@accepttp", "@shownames", "@sit", "@unsit", "@stand" ];

list LABEL_INV    = [ "Det. All:", "+ Outfit:", "- Outfit:", "- Attach:", "+ Attach:", "Att. All:", "Inv:", "Notes:", "Scripts:" ];
list LABEL_SPEECH = [ "Chat:", "Recv IM:", "Send IM:", "Start IM:", "Shout:", "Whisper:" ];
list LABEL_TRAVEL = [ "Map TP:", "Loc. TP:", "TP:" ];
list LABEL_OTHER  = [ "Edit:", "Rez:", "Touch:", "Touch Wld:", "OK TP:", "Names:", "Sit:", "Unsit:", "Stand:" ];

key g_owner = NULL_KEY;
list g_trustees = [];
list g_blacklist = [];
integer g_public_access = FALSE;

list g_restrictions = [];
list g_sessions = [];

string PLUGIN_LABEL = "Restrict";
string PLUGIN_CONTEXT = "rlv_rlvrestrict";
integer PLUGIN_SN = 0;

integer s_idx(key av) {
    return llListFindList(g_sessions, [av]);
}

integer s_set(key av, integer page, string csv, float expiry, string ctx, string param, string step, string menucsv, integer dialog_chan) {
    integer i = s_idx(av);
    if (i != -1) {
        integer old_lh = llList2Integer(g_sessions, i + 9);
        if (old_lh != -1) llListenRemove(old_lh);
        g_sessions = llDeleteSubList(g_sessions, i, i + 9);
    }
    integer lh = llListen(dialog_chan, "", av, "");
    g_sessions += [av, page, csv, expiry, ctx, param, step, menucsv, dialog_chan, lh];
    if (DEBUG) llOwnerSay("[DEBUG][RLV] Session set: av=" + (string)av + " ctx=" + ctx + " chan=" + (string)dialog_chan);
    return TRUE;
}

integer s_clear(key av) {
    integer i = s_idx(av);
    if (i != -1) {
        integer old_lh = llList2Integer(g_sessions, i + 9);
        if (old_lh != -1) llListenRemove(old_lh);
        g_sessions = llDeleteSubList(g_sessions, i, i + 9);
        if (DEBUG) llOwnerSay("[DEBUG][RLV] Session cleared for: " + (string)av);
    }
    return TRUE;
}

list s_get(key av) {
    integer i = s_idx(av);
    if (i != -1) return llList2List(g_sessions, i, i + 9);
    return [];
}

timeout_check() {
    integer now = llGetUnixTime();
    integer i = 0;
    integer len = llGetListLength(g_sessions);
    while (i < len) {
        float expiry = llList2Float(g_sessions, i + 3);
        if (now > expiry) {
            s_clear(llList2Key(g_sessions, i));
            len = llGetListLength(g_sessions);
        } else {
            i += 10;
        }
    }
}

integer g_idx(list userlist, key testid) {
    return llListFindList(userlist, [testid]);
}

integer get_acl(key av) {
    if (g_idx(g_blacklist, av) != -1) {
        if (DEBUG) llOwnerSay("[DEBUG][ACL] " + (string)av + " BLACKLISTED (DENIED)");
        return ACL_DENY;
    }
    if (g_owner == NULL_KEY && av == llGetOwner()) {
        if (DEBUG) llOwnerSay("[DEBUG][ACL] " + (string)av + " OWNER FALLBACK (wearer)");
        return ACL_OWNER;
    }
    if (av == g_owner) {
        if (DEBUG) llOwnerSay("[DEBUG][ACL] " + (string)av + " OWNER");
        return ACL_OWNER;
    }
    if (av == llGetOwner()) {
        if (DEBUG) llOwnerSay("[DEBUG][ACL] " + (string)av + " WEARER");
        return ACL_WEARER;
    }
    if (g_idx(g_trustees, av) != -1) {
        if (DEBUG) llOwnerSay("[DEBUG][ACL] " + (string)av + " TRUSTEE");
        return ACL_TRUSTEE;
    }
    if (g_public_access) {
        if (DEBUG) llOwnerSay("[DEBUG][ACL] " + (string)av + " PUBLIC");
        return 4;
    }
    if (DEBUG) llOwnerSay("[DEBUG][ACL] " + (string)av + " DENIED (DEFAULT)");
    return ACL_DENY;
}

integer restriction_idx(string cmd) {
    return llListFindList(g_restrictions, [cmd]);
}

toggle_restriction(string restr_cmd, integer acl) {
    integer idx = restriction_idx(restr_cmd);
    if (idx != -1) {
        g_restrictions = llDeleteSubList(g_restrictions, idx, idx);
        llOwnerSay(restr_cmd + "=rem");
        if (DEBUG) llOwnerSay("[DEBUG][RLV] Removed restriction: " + restr_cmd);
    } else if (llGetListLength(g_restrictions) < MAX_RESTRICTIONS) {
        g_restrictions += [restr_cmd];
        llOwnerSay(restr_cmd + "=n");
        if (DEBUG) llOwnerSay("[DEBUG][RLV] Added restriction: " + restr_cmd);
    }
    if (DEBUG) llOwnerSay("[DEBUG][RLV] Restrictions now: " + llDumpList2String(g_restrictions, ","));
}

list get_category_list(string catname) {
    if (catname == "Inventory") return CAT_INV;
    if (catname == "Speech") return CAT_SPEECH;
    if (catname == "Travel") return CAT_TRAVEL;
    if (catname == "Other") return CAT_OTHER;
    return [];
}

list get_category_labels(string catname) {
    if (catname == "Inventory") return LABEL_INV;
    if (catname == "Speech") return LABEL_SPEECH;
    if (catname == "Travel") return LABEL_TRAVEL;
    if (catname == "Other") return LABEL_OTHER;
    return [];
}

string get_label_for_command(string cmd, list cat_cmds, list cat_labels) {
    integer idx = llListFindList(cat_cmds, [cmd]);
    if (idx != -1) return llList2String(cat_labels, idx);
    return cmd + ":";
}

string get_short_label(string cmd, integer is_active, list cat_cmds, list cat_labels) {
    string label = get_label_for_command(cmd, cat_cmds, cat_labels);
    if (is_active) label += "OFF";
    else label += "ON";
    return label;
}

string label_to_command(string label, list cat_cmds, list cat_labels) {
    integer n = llGetListLength(cat_labels);
    integer i = 0;
    while (i < n) {
        string base_label = llList2String(cat_labels, i);
        if (label == base_label + "ON" || label == base_label + "OFF") {
            return llList2String(cat_cmds, i);
        }
        i++;
    }
    return "";
}

list make_category_buttons(list cat_cmds, list cat_labels, integer page) {
    list btns = [];
    integer count = llGetListLength(cat_cmds);
    integer start = page * DIALOG_PAGE_SIZE;
    integer end = start + DIALOG_PAGE_SIZE - 1;
    if (end >= count) end = count - 1;
    integer i;
    for (i = start; i <= end; i++) {
        string cmd = llList2String(cat_cmds, i);
        integer is_active = (restriction_idx(cmd) != -1);
        btns += [get_short_label(cmd, is_active, cat_cmds, cat_labels)];
    }
    while (llGetListLength(btns) < DIALOG_PAGE_SIZE) btns += [" "];
    if (llGetListLength(btns) > DIALOG_PAGE_SIZE) btns = llList2List(btns, 0, DIALOG_PAGE_SIZE - 1);
    return btns;
}

show_main_menu(key av, integer chan) {
    integer acl = get_acl(av);
    if (DEBUG) llOwnerSay("[DEBUG][RLV] show_main_menu ACL for " + (string)av + " is " + (string)acl);
    if (acl > ACL_WEARER) {
        if (DEBUG) llOwnerSay("[DEBUG][RLV] Access denied to " + (string)av + " due to ACL");
        return;
    }

    list btns;

    // Restrict wearer with assigned owner to only Safeword + Back
    if (acl == ACL_WEARER && g_owner != NULL_KEY) {
        btns = [
            " ", "    Back    ", " ",
            " ", "Safeword", " ",
            " ", " ", " "
        ];
    } else {
        btns = [
            " ", "    Back    ", " ",
            "Other", "Safeword", "Exceptions",
            "Inventory", "Speech", "Travel"
        ];
    }

    s_set(av, 0, "", llGetUnixTime() + 180.0, "main", "", "", "", chan);

    if (DEBUG) llOwnerSay("[DEBUG][RLV] show_main_menu → " + (string)av + " chan=" + (string)chan + " buttons=" + llDumpList2String(btns, ","));

    llDialog(av, "RLV Restriction Menu:\nSelect a category:", btns, chan);
}

show_category_menu(key av, integer chan, string catname, integer page) {
    integer acl = get_acl(av);
    if (DEBUG) llOwnerSay("[DEBUG][RLV] show_category_menu ACL for " + (string)av + " is " + (string)acl);
    if (acl > ACL_WEARER) {
        if (DEBUG) llOwnerSay("[DEBUG][RLV] Access denied to " + (string)av + " due to ACL");
        return;
    }

    list cat_cmds = get_category_list(catname);
    list cat_labels = get_category_labels(catname);
    integer num_items = llGetListLength(cat_cmds);
    integer max_page = (num_items - 1) / DIALOG_PAGE_SIZE;

    string prev = " ";
    string next = " ";
    if (page > 0) prev = "<<";
    if (page < max_page) next = ">>";

    list btns = [prev, "    Back    ", next];
    btns += make_category_buttons(cat_cmds, cat_labels, page);

    s_set(av, page, catname, llGetUnixTime() + 120.0, "cat", catname + "|" + (string)page, "", llDumpList2String(cat_cmds, ","), chan);

    if (DEBUG) llOwnerSay("[DEBUG][RLV] show_category_menu: " + catname + " page " + (string)page + " buttons=" + llDumpList2String(btns, ","));

    llDialog(av, catname + " Restrictions:\nClick to toggle.", btns, chan);
}

register_plugin() {
    PLUGIN_SN = 100000 + (integer)llFrand(899999);
    llMessageLinked(LINK_THIS, 500, "register|" + (string)PLUGIN_SN + "|" + PLUGIN_LABEL + "|3|" + PLUGIN_CONTEXT, NULL_KEY);
    if (DEBUG) llOwnerSay("[DEBUG][RLV] Plugin registered with SN " + (string)PLUGIN_SN);
}

default
{
    state_entry() {
        register_plugin();
        llSetTimerEvent(1.0);
        if (DEBUG) llOwnerSay("[DEBUG][RLV] Plugin ready.");
    }

    link_message(integer sn, integer num, string str, key id) {
        if (num == -900 && str == "reset_owner") {
            llResetScript();
            return;
        }

        if (num == 520) {
            list p = llParseString2List(str, ["|"], []);
            if (llGetListLength(p) == 8 && llList2String(p, 0) == "state_sync") {
                g_owner = (key)llList2String(p, 1);
                string trust_csv = llList2String(p, 3);
                string bl_csv = llList2String(p, 5);
                string pub_str = llList2String(p, 6);

                if (trust_csv == " ") g_trustees = [];
                else g_trustees = llParseString2List(trust_csv, [","], []);

                if (bl_csv == " ") g_blacklist = [];
                else g_blacklist = llParseString2List(bl_csv, [","], []);

                if (pub_str == "1") g_public_access = TRUE;
                else g_public_access = FALSE;

                if (DEBUG) llOwnerSay("[DEBUG][RLV] State sync received: owner=" + (string)g_owner);
                return;
            }
        }

        if (num == 510) {
            list p = llParseString2List(str, ["|"], []);
            if (llList2String(p, 0) == PLUGIN_CONTEXT && llGetListLength(p) >= 3) {
                key av = (key)llList2String(p, 1);
                integer chan = (integer)llList2String(p, 2);
                if (DEBUG) llOwnerSay("[DEBUG][RLV] show_main_menu called for: " + (string)av + " chan: " + (string)chan);
                show_main_menu(av, chan);
                return;
            }
        }
    }

    listen(integer chan, string nm, key av, string msg) {
        list sess = s_get(av);
        if (llGetListLength(sess) == 0) return;
        if (chan != llList2Integer(sess, 8)) return;

        string ctx = llList2String(sess, 4);
        string param = llList2String(sess, 5);

        integer acl = get_acl(av);

        if (ctx == "main") {
            if (msg == "Inventory") {
                show_category_menu(av, chan, "Inventory", 0);
                return;
            }
            if (msg == "Speech") {
                show_category_menu(av, chan, "Speech", 0);
                return;
            }
            if (msg == "Travel") {
                show_category_menu(av, chan, "Travel", 0);
                return;
            }
            if (msg == "Other") {
                show_category_menu(av, chan, "Other", 0);
                return;
            }
            if (msg == "Exceptions") {
                // Exceptions submenu placeholder
                return;
            }
            if (msg == "Safeword" && acl <= ACL_WEARER) {
                g_restrictions = [];
                llOwnerSay("@clear");
                llDialog(av, "All restrictions cleared by Safeword.", ["    Back    "], chan);
                return;
            }
            if (msg == "    Back    ") {
                llMessageLinked(LINK_THIS, 510, "apps|" + (string)av + "|" + (string)chan, NULL_KEY);
                s_clear(av);
                return;
            }
        }
        else if (ctx == "cat") {
            list params = llParseString2List(param, ["|"], []);
            string catname = llList2String(params, 0);
            integer page = (integer)llList2String(params, 1);

            list cat_cmds = get_category_list(catname);
            list cat_labels = get_category_labels(catname);
            integer num_items = llGetListLength(cat_cmds);
            integer max_page = (num_items - 1) / DIALOG_PAGE_SIZE;

            if (msg == "    Back    ") {
                show_main_menu(av, chan);
                return;
            }
            if (msg == "<<" && page > 0) {
                show_category_menu(av, chan, catname, page - 1);
                return;
            }
            if (msg == ">>" && page < max_page) {
                show_category_menu(av, chan, catname, page + 1);
                return;
            }

            string cmd = label_to_command(msg, cat_cmds, cat_labels);
            if (cmd != "" && acl <= ACL_TRUSTEE) {
                if (DEBUG) llOwnerSay("[DEBUG][RLV] Toggle restriction: " + cmd + " by " + (string)av);
                toggle_restriction(cmd, acl);
                show_category_menu(av, chan, catname, page);
                return;
            }
        }
    }

    timer() {
        timeout_check();
    }

    changed(integer change) {
        if (change & CHANGED_OWNER) {
            llResetScript();
        }
    }
}
