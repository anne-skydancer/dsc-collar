// =============================================================
//  plg_demook  –  sample collar plugin
//  Shows an "OK" / "BACK" dialog
// =============================================================

// ---------- constants ----------
string FRIENDLY_NAME = "DemoOK";   // ≤ 12 chars
integer MIN_ACL      = 1;          // show to Public and above
integer MAX_ACL      = 4;

// ---------- channel map ----------
integer CHANNEL_BASE;
integer CHAN_CORE;
integer CHAN_AUTH;
integer CHAN_SETTINGS;
integer CHAN_MENU;

integer DIALOG_CHAN;              // private channel for this plugin

// ---------- helper: open plugin dialog ----------
integer dialogDemo(key avatarKey)
{
    list buttons = ["OK", "BACK"];
    llDialog(avatarKey, "Demo Plugin", buttons, DIALOG_CHAN);
    return 0;
}

// -------------------------------------------------------------
default
{
    state_entry()
    {
        // derive shared channel base
        integer tail = (integer)("0x" + llGetSubString((string)llGetKey(), -6, -1));
        CHANNEL_BASE = -4000 - (tail & 0x0FFF);

        CHAN_CORE     = CHANNEL_BASE - 0;
        CHAN_AUTH     = CHANNEL_BASE - 1;
        CHAN_SETTINGS = CHANNEL_BASE - 2;
        CHAN_MENU     = CHANNEL_BASE - 3;

        // unique negative chat channel for this plugin
        DIALOG_CHAN   = CHANNEL_BASE - 200 - llGetLinkNumber();

        // listen for replies on our dialog channel
        llListen(DIALOG_CHAN, "", NULL_KEY, "");

        // register with Core so Menu can list us
        llMessageLinked(LINK_THIS, CHAN_CORE,
                        "REGISTER|" + FRIENDLY_NAME + "|" +
                        (string)MIN_ACL + "|" + (string)MAX_ACL,
                        NULL_KEY);
    }

    // ---------- Menu selection ----------
    link_message(integer sender, integer channel, string msg, key id)
    {
        // Menu tells plugins:  MENU|SELECT|<plugin>|<avatarKey>
        if (channel != CHAN_MENU) return;

        list parts = llParseString2List(msg, ["|"], []);
        if (llGetListLength(parts) < 4) return;

        if (llList2String(parts, 0) != "MENU") return;
        if (llList2String(parts, 1) != "SELECT") return;
        if (llList2String(parts, 2) != FRIENDLY_NAME) return;

        key avatarKey = (key)llList2String(parts, 3);
        dialogDemo(avatarKey);
    }

    // ---------- Dialog responses ----------
    listen(integer chan, string name, key avatarKey, string message)
    {
        if (chan != DIALOG_CHAN) return;

        if (message == "OK")
        {
            // Do nothing; dialog closes automatically.
            return;
        }
        if (message == "BACK")
        {
            // Re-open main menu by simulating a touch
            llMessageLinked(LINK_THIS, CHAN_AUTH,
                            "CORE|TOUCH|" + (string)avatarKey,
                            NULL_KEY);
        }
    }
}
