/* =============================================================
   TITLE: ds_collar_chat - Chat Command & Prefix Plugin
   VERSION: 1.1-U (Universal Template, dynamic serial, best practices)
   REVISION: 2025-07-18
   ============================================================= */

/* ================= UNIVERSAL HEADER ================= */

integer DEBUG = TRUE;
integer PLUGIN_SN = 0;  // Will be set in state_entry()
string  PLUGIN_LABEL = "Chat";
integer PLUGIN_MIN_ACL = 3;
string  PLUGIN_CONTEXT = "core_chat";

float   dialog_timeout = 180.0;
string  g_prefix = "";
integer g_public_listener = FALSE;
integer g_public_listen_handle = -1;
integer g_prefix_listen_handle = -1;

list    g_modules = [];
list    g_sessions; // Session cache: [av,page,csv,expiry,ctx,param,step,menucsv,chan,listen]

// ----------------- SESSION HELPERS -----------------
integer s_idx(key av) { return llListFindList(g_sessions, [av]); }

integer s_set(key av, integer page, string csv, float expiry,
              string ctx, string param, string step, string menucsv, integer chan)
{
    integer i = s_idx(av);
    integer old_listen = -1;
    if (i != -1) {
        old_listen = llList2Integer(g_sessions, i+9);
        if (old_listen != -1) llListenRemove(old_listen);
        g_sessions = llDeleteSubList(g_sessions, i, i+9);
    }
    integer lh = llListen(chan, "", av, "");
    g_sessions += [av, page, csv, expiry, ctx, param, step, menucsv, chan, lh];
    return TRUE;
}

integer s_clear(key av) {
    integer i = s_idx(av);
    if (i != -1) {
        integer old_listen = llList2Integer(g_sessions, i+9);
        if (old_listen != -1) llListenRemove(old_listen);
        g_sessions = llDeleteSubList(g_sessions, i, i+9);
    }
    return TRUE;
}

list s_get(key av) {
    integer i = s_idx(av);
    if (i != -1) return llList2List(g_sessions, i, i+9);
    return [];
}
// ----------------- SESSION HELPERS END -----------------

// ----------------- CHAT MENU DEFINITIONS -----------------
list chat_menu_buttons() { return [ "Change Prefix", "Toggle Public" ]; }
list chat_menu_ctxs()    { return [ "set_prefix", "toggle_public" ]; }

show_chat_menu(key av, integer chan)
{
    integer acl = get_acl(av);
    if ((acl == 1 || acl == 3) && g_prefix == "")
    {
        prompt_prefix_setup(av, chan);
        return;
    }
    list btns = chat_menu_buttons() + [ "Back" ];
    while (llGetListLength(btns) % 3 != 0)
        btns += " ";
    string public_status;
    if (g_public_listener == TRUE)
        public_status = "ENABLED";
    else
        public_status = "DISABLED";
    s_set(av, 0, " ",
          llGetUnixTime() + dialog_timeout,
          "chat_main", "", "",
          llDumpList2String(chat_menu_ctxs() + [ "back" ], ","), chan);
    if (DEBUG)
        llOwnerSay("[Chat] show_chat_menu for " + (string)av + " chan=" + (string)chan + " btns=" + llDumpList2String(btns, ","));
    llDialog(av, "Chat Plugin Options:\nPrefix: " + g_prefix +
                 "\nPublic chat: " + public_status,
             btns, chan);
}

prompt_prefix_setup(key av, integer chan)
{
    s_set(av, 0, " ",
          llGetUnixTime() + dialog_timeout,
          "set_prefix", "", "", "", chan);
    llTextBox(av, "Enter a chat command prefix (2-5 letters):", chan);
}

// Dummy ACL for now; replace with real ACL as needed
integer get_acl(key av)
{
    return 1; // Always owner for now
}

// ----------------- PUBLIC LISTENER TOGGLE & PERMISSIONS -----------------
enable_public_listener()
{
    if (g_public_listen_handle == -1)
    {
        g_public_listen_handle = llListen(PUBLIC_CHANNEL, "", NULL_KEY, "");
        if (DEBUG) llOwnerSay("[Chat] Public chat listener ENABLED");
    }
    g_public_listener = TRUE;
}

disable_public_listener()
{
    if (g_public_listen_handle != -1)
    {
        llListenRemove(g_public_listen_handle);
        g_public_listen_handle = -1;
        if (DEBUG) llOwnerSay("[Chat] Public chat listener DISABLED");
    }
    g_public_listener = FALSE;
}

enable_prefix_listener()
{
    disable_prefix_listener();
    if (g_prefix != "")
    {
        g_prefix_listen_handle = llListen(1, "", NULL_KEY, "");
        if (DEBUG) llOwnerSay("[Chat] Prefix listen on channel 1 ENABLED");
    }
}

disable_prefix_listener()
{
    if (g_prefix_listen_handle != -1)
    {
        llListenRemove(g_prefix_listen_handle);
        g_prefix_listen_handle = -1;
        if (DEBUG) llOwnerSay("[Chat] Prefix listen on channel 1 DISABLED");
    }
}

// ----------------- CHAT VERB HANDLING -----------------
list chat_verbs() { return [ "prefix", "pubchat" ]; }

integer handle_chat_command(string cmd, key av, integer chan)
{
    integer acl = get_acl(av);

    if (cmd == "prefix")
    {
        prompt_prefix_setup(av, chan);
        return TRUE;
    }
    else
    {
        if (cmd == "pubchat")
        {
            string status;
            if (g_public_listener == TRUE) status = "ENABLED";
            else status = "DISABLED";

            string dialog = "Public chat is currently " + status + ".\n\nDo you want to ";
            if (g_public_listener == TRUE) dialog += "disable";
            else dialog += "enable";
            dialog += " public chat listening?";

            list buttons;
            if (g_public_listener == TRUE)
                buttons = [ "Disable", " ", "Cancel" ];
            else
                buttons = [ "Enable", " ", "Cancel" ];

            s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "toggle_public_confirm", "", "", "", chan);
            llDialog(av, dialog, buttons, chan);
            return TRUE;
        }
    }
    return FALSE;
}

// ----------------- TIMEOUT MANAGEMENT -----------------
timeout_check()
{
    integer now = llGetUnixTime();
    integer i = 0;
    while (i < llGetListLength(g_sessions))
    {
        float expiry = llList2Float(g_sessions, i+3);
        key av = llList2Key(g_sessions, i);
        if (now > expiry)
        {
            llInstantMessage(av, "Chat menu timed out.");
            s_clear(av);
        }
        else
        {
            i += 10;
        }
    }
}

// ================== MAIN EVENT LOOP ==================
default
{
    state_entry()
    {
        if (DEBUG) llOwnerSay("[Chat] state_entry");
        llSetTimerEvent(1.0);

        // Generate random serial for plugin registration
        PLUGIN_SN = 100000 + (integer)(llFrand(899999));
        llMessageLinked(LINK_THIS, 500,
            "register|" + (string)PLUGIN_SN + "|" + PLUGIN_LABEL + "|" +
            (string)PLUGIN_MIN_ACL + "|" + PLUGIN_CONTEXT,
            NULL_KEY);

        disable_public_listener();
        disable_prefix_listener();
        g_prefix = "";
    }

    link_message(integer sender, integer num, string str, key id)
    {
        if (num == -900 && str == "reset_owner")
        {
            llResetScript();
            return;
        }
        if (num == 500)
        {
            list p = llParseStringKeepNulls(str, ["|"], []);
            if (llGetListLength(p) >= 5 && llList2String(p, 0) == "register")
            {
                string ctx = llList2String(p, 4);
                if (llListFindList(g_modules, [ctx]) == -1)
                {
                    g_modules += [ctx];
                    if (DEBUG) llOwnerSay("[Chat] learned module: " + ctx);
                }
            }
            return;
        }
        if (num == 510)
        {
            list a = llParseString2List(str, ["|"], []);
            if (llGetListLength(a) >= 3 && llList2String(a, 0) == "core_chat")
            {
                key av = (key) llList2String(a, 1);
                integer chan = (integer) llList2String(a, 2);
                if (DEBUG) llOwnerSay("[Chat] opening menu for " + (string)av);
                show_chat_menu(av, chan);
            }
        }
    }

    listen(integer chan, string name, key av, string msg)
    {
        if ((chan == PUBLIC_CHANNEL || chan == 1) && g_prefix != "")
        {
            if (llGetSubString(msg, 0, llStringLength(g_prefix) - 1) == g_prefix)
            {
                string arg = llStringTrim(llGetSubString(msg, llStringLength(g_prefix) + 1, -1), STRING_TRIM);
                list verbs = chat_verbs();
                integer i;
                for (i = 0; i < llGetListLength(verbs); ++i)
                {
                    if (llToLower(arg) == llToLower(llList2String(verbs, i)))
                    {
                        if (DEBUG) llOwnerSay("[Chat] chat verb detected: " + arg);
                        handle_chat_command(llToLower(arg), av, chan);
                        return;
                    }
                }
            }
        }

        list sess = s_get(av);
        if (llGetListLength(sess) == 0) return;
        integer session_chan = llList2Integer(sess, 8);
        if (chan != session_chan) return;

        string ctx = llList2String(sess, 4);
        string menucsv = llList2String(sess, 7);

        if (ctx == "chat_main")
        {
            list allowed = llParseString2List(menucsv, [","], []);
            integer sel = llListFindList(allowed, [msg]);
            string action = "";
            if (sel != -1 && sel < llGetListLength(allowed))
                action = llList2String(allowed, sel);

            if (DEBUG) llOwnerSay("[DEBUG] chat_main menu click: '" + msg + "'");
            if (DEBUG) llOwnerSay("[DEBUG] allowed actions: " + llDumpList2String(allowed, "|"));

            if (action == "set_prefix")
            {
                prompt_prefix_setup(av, chan);
                return;
            }
            if (action == "toggle_public")
            {
                string status;
                if (g_public_listener == TRUE) status = "ENABLED";
                else status = "DISABLED";

                string dialog = "Public chat is currently " + status + ".\n\nDo you want to ";
                if (g_public_listener == TRUE) dialog += "disable";
                else dialog += "enable";
                dialog += " public chat listening?";

                list buttons;
                if (g_public_listener == TRUE)
                    buttons = [ "Disable", " ", "Cancel" ];
                else
                    buttons = [ "Enable", " ", "Cancel" ];

                s_set(av, 0, "", llGetUnixTime() + dialog_timeout, "toggle_public_confirm", "", "", "", chan);
                llDialog(av, dialog, buttons, chan);
                return;
            }
            if (action == "back")
            {
                llMessageLinked(LINK_THIS, 510, "core|" + (string)av + "|" + (string)chan, NULL_KEY);
                s_clear(av);
                return;
            }
            return;
        }

        if (ctx == "toggle_public_confirm")
        {
            if (msg == "Enable")
            {
                enable_public_listener();
                llDialog(av, "Public chat is now ENABLED.", [ " ", "OK", " " ], chan);
                s_clear(av);
                return;
            }
            if (msg == "Disable")
            {
                disable_public_listener();
                llDialog(av, "Public chat is now DISABLED.", [ " ", "OK", " " ], chan);
                s_clear(av);
                return;
            }
            if (msg == "Cancel")
            {
                s_clear(av);
                return;
            }
        }

        if (ctx == "set_prefix")
        {
            string new_prefix = llStringTrim(msg, STRING_TRIM);
            integer len = llStringLength(new_prefix);
            if (len >= 2 && len <= 5)
            {
                g_prefix = new_prefix;
                llOwnerSay("Prefix set to: " + g_prefix);
                enable_prefix_listener();
                enable_public_listener();
                llDialog(av, "Prefix set to: " + g_prefix + "\n\nYou may now use public chat commands.", [ " ", "OK", " " ], chan);
                s_clear(av);
            }
            else
            {
                llDialog(av, "Prefix must be 2-5 characters. Try again.", [ " ", "OK", " " ], chan);
            }
            return;
        }
    }

    timer()
    {
        timeout_check();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            llOwnerSay("[Chat] Owner changed. Resetting chat plugin.");
            llResetScript();
        }
    }
}
// =============================================================
