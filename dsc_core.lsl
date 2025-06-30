// =============================================================
//  Collar Grand Unified Hub  – strict LSL, plugin-ready
//  Version: 2025-07-05  lock/unlock + 8-field state-sync  (no ternaries)
// =============================================================

integer DEBUG = TRUE;

/*──────── registries & persistent state ────────*/
list    gPlugins;                               // [script, label, minACL, ctx]
list    gSessions;                              // [av,page,csv,exp,ctx,param,step,menucsv,chan,listen]

float   DIALOG_TIMEOUT = 180.0;
integer gListenHandle = 0;

key     gOwner              = NULL_KEY;
string  gOwnerHonorific     = "";
list    gTrustees           = [];
list    gTrusteeHonorifics  = [];
list    gBlacklist          = [];
integer gPublicAccess       = FALSE;
integer gLocked             = FALSE;

/*──────── small helpers ────────*/
integer sIdx(key av){ return llListFindList(gSessions,[av]); }
integer gIdx(list L,key k){ return llListFindList(L,[k]); }

integer sessSet(key av,integer page,string csv,float exp,string ctx,
                string param,string step,string mcsv,integer chan)
{
    integer i = sIdx(av);
    if(~i){
        integer old = llList2Integer(gSessions,i+9);
        if(old!=-1) llListenRemove(old);
        gSessions = llDeleteSubList(gSessions,i,i+9);
    }
    integer lh = llListen(chan,"",av,"");
    gSessions += [av,page,csv,exp,ctx,param,step,mcsv,chan,lh];
    return TRUE;
}
integer sessClear(key av){
    integer i = sIdx(av);
    if(~i){
        integer old = llList2Integer(gSessions,i+9);
        if(old!=-1) llListenRemove(old);
        gSessions = llDeleteSubList(gSessions,i,i+9);
    }
    return TRUE;
}
list sessGet(key av){
    integer i = sIdx(av);
    if(~i) return llList2List(gSessions,i,i+9);
    return [];
}

integer getACL(key av){
    if(gIdx(gBlacklist,av)!=-1) return 6;
    if(av==gOwner)             return 1;
    if(av==llGetOwner()){
        if(gOwner==NULL_KEY)   return 1;
        return 3;
    }
    if(gIdx(gTrustees,av)!=-1) return 2;
    if(gPublicAccess)          return 4;
    return 5;
}

/*──────── plugin registry helpers ────────*/
addPlugin(integer sn,string label,integer min_acl,string ctx){
    integer i;
    for(i=0;i<llGetListLength(gPlugins);i+=4){
        if(llList2Integer(gPlugins,i)==sn)
            gPlugins = llDeleteSubList(gPlugins,i,i+3);
    }
    gPlugins += [sn,label,min_acl,ctx];
}
removePlugin(integer sn){
    integer i;
    for(i=0;i<llGetListLength(gPlugins);i+=4){
        if(llList2Integer(gPlugins,i)==sn)
            gPlugins = llDeleteSubList(gPlugins,i,i+3);
    }
}

/*──────── menu builders ────────*/
list coreBtns(){ return ["Status","Apps"]; }
list coreCtxs(){ return ["status","apps"]; }

showMainMenu(key av)
{
    integer acl = getACL(av);

    list btns = coreBtns();
    list ctxs = coreCtxs();

    if(acl<=3){
        if(gLocked){ btns += ["Unlock"]; ctxs += ["unlock"]; }
        else        { btns += ["Lock"];   ctxs += ["lock"];   }
    }

    integer i;
    for(i=0;i<llGetListLength(gPlugins);i+=4){
        integer min_acl = llList2Integer(gPlugins,i+2);
        if(acl>min_acl) jump skip_p;
        btns += [llList2String(gPlugins,i+1)];
        ctxs += [llList2String(gPlugins,i+3)+"|"+
                 (string)llList2Integer(gPlugins,i)];
        @skip_p;
    }
    while(llGetListLength(btns)%3!=0) btns += " ";

    integer chan = (integer)(-1000000.0*llFrand(1.0)-1.0);
    sessSet(av,0,"",llGetUnixTime()+DIALOG_TIMEOUT,
            "main","","",llDumpList2String(ctxs,","),chan);

    if(gListenHandle) llListenRemove(gListenHandle);
    gListenHandle = llListen(chan,"",av,"");

    if(DEBUG) llOwnerSay("[DEBUG] showMainMenu → "+(string)av+
                         " chan="+(string)chan+" btns="+llDumpList2String(btns,","));
    llDialog(av,"Select an option:",btns,chan);
}

/*──────── dialogs ────────*/
showStatus(key av,integer chan)
{
    string t = "";
    if(gOwner!=NULL_KEY)
         t += "Owner: "+gOwnerHonorific+" "+llKey2Name(gOwner)+"\n";
    else t += "Collar is unowned.\n";

    if(llGetListLength(gTrustees)>0){
        integer i;
        t += "Trustees:\n";
        for(i=0;i<llGetListLength(gTrustees);++i)
            t += "  "+llList2String(gTrusteeHonorifics,i)+" "+
                 llKey2Name(llList2Key(gTrustees,i))+"\n";
    }
    if(gPublicAccess) t += "Public Access: ENABLED\n";
    else              t += "Public Access: DISABLED\n";
    if(gLocked)       t += "Locked: YES\n";
    else              t += "Locked: NO\n";

    llDialog(av,t,[" ","OK"," "],chan);
}
showApps(key av,integer chan){
    llDialog(av,"(Stub) Apps list would go here.",[" ","OK"," "],chan);
}
showLockDialog(key av,integer chan){
    string txt;
    list buttons;
    if(gLocked){
        txt = "The collar is currently LOCKED.\nUnlock the collar?";
        buttons = ["Unlock","Cancel"];
    }else{
        txt = "The collar is currently UNLOCKED.\nLock the collar?";
        buttons = ["Lock","Cancel"];
    }
    while(llGetListLength(buttons)%3!=0) buttons += " ";
    sessSet(av,0,"",llGetUnixTime()+DIALOG_TIMEOUT,
            "lock_toggle","","","",chan);
    llDialog(av,txt,buttons,chan);
}

/*──────── timeout check ────────*/
timeoutCheck(){
    integer now = llGetUnixTime();
    integer i=0;
    while(i<llGetListLength(gSessions)){
        if(now>llList2Float(gSessions,i+3))
             sessClear(llList2Key(gSessions,i));
        else i += 10;
    }
}

/*──────── default state ────────*/
default
{
    state_entry(){ if(DEBUG) llOwnerSay("[DEBUG] GUH state_entry");
                   llSetTimerEvent(1.0); }

    touch_start(integer n)
    { 
        key toucher = (llDetectedKey(0));
        integer acl=getACL(toucher);
        string role;
        if (acl == 1) role = "Owner";
        else if (acl == 2) role = "Trustee";
        else if (acl == 3) role = "Owned wearer";
        else if (acl == 4) role = "Public";
        else               role = "No access";
        llOwnerSay("[DEBUG] Toucher " + (string)toucher + " has ACL level " + (string)acl + " (" + role = ")");

        showMainMenu(toucher);
    }
    link_message(integer sn,integer num,string str,key id)
    {
        /* plugin register/unregister */
        if(num == 500)
        {
            // expect: "register|<sn>|<label>|<min_acl>|<ctx>"
            list p = llParseStringKeepNulls(str,["|"],[]);
            if(llGetListLength(p)>=5 && llList2String(p,0) == "register")
            {
                integer sn = (integer)llList2Integer(p, 1);
                string label = llList2String(p, 2);
                integer minACL = (integer)llList2Integer(p,3);
                string ctx = llList2String(p, 4);
 
 
                addPlugin(sn, label, minACL, ctx);
                if(DEBUG) llOwnerSay("[PLUGIN] Registered "+ "named " + label + " serial " + llList2String(p,1) + " with min. ACL= "+ (string)minACL + " context " + ctx);
            }
        }
        else if(num==501 && str=="unregister"){ removePlugin(sn); }

        /* state-sync from Access (8 fields, NO ternaries) */
else if (num == 520)
{
    list p = llParseString2List(str, ["|"], []);
    /* state_sync|owner|ownerHon|trust_csv|trustHon_csv|blacklist_csv|pub|lock */
    if (llGetListLength(p) == 8 && llList2String(p,0) == "state_sync")
    {
        gOwner           = (key)  llList2String(p,1);
        gOwnerHonorific  =         llList2String(p,2);

        string trust_csv =         llList2String(p,3);
        string trustHon  =         llList2String(p,4);
        string bl_csv    =         llList2String(p,5);
        string pub_str   =         llList2String(p,6);
        string lock_str  =         llList2String(p,7);          // <── NEW

        /* convert comma-lists, using blanks (" ") to mean “empty” */
        if (trust_csv == " ")   gTrustees          = [];
        else                    gTrustees          = llParseString2List(trust_csv,[","],[]);
        if (trustHon  == " ")   gTrusteeHonorifics = [];
        else                    gTrusteeHonorifics = llParseString2List(trustHon,[","],[]);
        if (bl_csv    == " ")   gBlacklist         = [];
        else                    gBlacklist         = llParseString2List(bl_csv,[","],[]);

        if (pub_str  == "1") gPublicAccess = TRUE;  else gPublicAccess = FALSE;
        if (lock_str == "1") gLocked       = TRUE;  else gLocked       = FALSE;

        if (DEBUG)
        {
            llOwnerSay("[GUH] State sync recv:"
                + " owner="     + (string)gOwner
                + " ownerHon="  + gOwnerHonorific
                + " trust="     + llDumpList2String(gTrustees,",")
                + " trustHon="  + llDumpList2String(gTrusteeHonorifics,",")
                + " blacklist=" + llDumpList2String(gBlacklist,",")
                + " pub="       + pub_str
                + " lock="      + lock_str);
                }
            }
        }
    }   


    listen(integer chan,string nm,key av,string msg)
    {
        list s = sessGet(av);
        if(llGetListLength(s)==0) return;
        if(chan!=llList2Integer(s,8)) return;

        string ctx = llList2String(s,4);
        string menucsv = llList2String(s,7);

        if(ctx=="main"){
            /* decode button pressed */
            list ctxs = llParseString2List(menucsv,[","],[]);
            list btns = coreBtns();
            if(getACL(av)<=3){
                if(gLocked) btns += ["Unlock"]; else btns += ["Lock"];
            }
            integer i;
            for(i=0;i<llGetListLength(gPlugins);i+=4){
                if(getACL(av)<=llList2Integer(gPlugins,i+2))
                    btns += [llList2String(gPlugins,i+1)];
            }
            while(llGetListLength(btns)%3!=0) btns += " ";

            integer sel = llListFindList(btns,[msg]);
            if(sel==-1) return;
            string act = llList2String(ctxs,sel);

            if(act=="status"){ showStatus(av,chan); return; }
            if(act=="apps"){   showApps(av,chan);   return; }
            if(act=="lock" || act=="unlock"){ showLockDialog(av,chan); return; }

            list pi = llParseString2List(act,["|"],[]);
            if(llGetListLength(pi)==2){
                llMessageLinked(LINK_THIS,510,llList2String(pi,0) + "|" + (string)av + "|" + (string)chan,NULL_KEY);
            }
           }
           return;

        if(ctx=="lock_toggle"){
            if(msg=="Lock"){   gLocked = TRUE;  }
            if(msg=="Unlock"){ gLocked = FALSE; }
            if(msg=="Lock" || msg=="Unlock"){
                llDialog(av,"Done.",[" ","OK"," "],chan);
                sessClear(av);
                return;
            }
            if(msg=="Cancel"){ sessClear(av); }
        }
    }

    timer(){ timeoutCheck(); }
}
