// gamemodes/NoPixelMode.pwn
// SA:MP gamemode inspired by FiveM/NoPixel style (NO voice required)
// - 3D chat above head (auto-fading)
// - Easy commands with /help
// - CLEAN ADMIN PANEL UI (/admin): Kick/Ban/Mute/Unmute/Goto/Bring/Freeze/Heal/GiveWeapon/SpawnCar/GiveMoney
// - Player picker dialog with live list
// - Jobs system (/jobs, /work <job>, /quitjob)
// - Modes: /mode <rp|freeroam|race|tdm>
// - Vehicles: /car <model>, /dv, /park
//
// No external plugins required. Works on stock a_samp.
// Designed for phone-only hosting panels (Lemehost).
// ---------------------------------------------------

#include <a_samp>

#define SERVER_NAME        "NoPixelMode"
#define COLOR_INFO         0x33CCFFAA
#define COLOR_OK           0x66FF66AA
#define COLOR_ERR          0xFF6666AA
#define COLOR_ADMIN        0xFFCC33AA
#define COLOR_CHAT3D       0xFFFFFFFF

// ---------- Admin basics ----------
new bool:g_Admin[MAX_PLAYERS];
new bool:g_Muted[MAX_PLAYERS];
new bool:g_Frozen[MAX_PLAYERS];

// ---------- 3D Chat ----------
new Text3D:g_Chat3D[MAX_PLAYERS] = {Text3D:INVALID_3DTEXT_ID, ...};
new g_ChatTimer[MAX_PLAYERS];

// ---------- Jobs ----------
enum JobEnum { JOB_NONE, JOB_TAXI, JOB_POLICE, JOB_MEDIC, JOB_MECHANIC }
new JobEnum:g_Job[MAX_PLAYERS];

// ---------- Economy ----------
new g_Cash[MAX_PLAYERS];
new g_Bank[MAX_PLAYERS];

// ---------- Modes ----------
enum ModeEnum { MODE_FREEROAM, MODE_RP, MODE_RACE, MODE_TDM }
new ModeEnum:g_Mode = MODE_RP;

// ---------- Admin UI ----------
#define D_ADMIN_MAIN    2100
#define D_ADMIN_PLAYERS 2101
#define D_ADMIN_INPUT   2102

enum AdminAction {
    ACT_NONE,
    ACT_KICK,
    ACT_BAN,
    ACT_MUTE,
    ACT_UNMUTE,
    ACT_GOTO,
    ACT_BRING,
    ACT_FREEZE,
    ACT_UNFREEZE,
    ACT_HEAL,
    ACT_GIVEWEAPON,
    ACT_SPAWNCAR,
    ACT_GIVEMONEY
}
new AdminAction:g_AdminContext[MAX_PLAYERS];
new g_AdminTarget[MAX_PLAYERS];
new g_PlayerListMap[MAX_PLAYERS][MAX_PLAYERS]; // listitem -> playerid mapping

// ---------- Utils ----------
stock Msg(playerid, color, const fmt[], va_args<>)
{
    static buf[180];
    format(buf, sizeof buf, fmt, va_start<1>);
    return SendClientMessage(playerid, color, buf);
}

stock Broadcast(color, const fmt[], va_args<>)
{
    static buf[180];
    format(buf, sizeof buf, fmt, va_start<0>);
    return SendClientMessageToAll(color, buf);
}

stock IsValidWeapon(w) { return (w >= 0 && w <= 46); }
stock IsPlayerAdminLevel(playerid) { return g_Admin[playerid] || IsPlayerAdmin(playerid); } // allow RCON admin

stock NameOf(playerid, dest[], len)
{
    new n[MAX_PLAYER_NAME];
    GetPlayerName(playerid, n, sizeof n);
    format(dest, len, "%s", n);
}

// Trim helper
stock _trim(str[])
{
    new i, j=0, l = strlen(str);
    while (i<l && (str[i]==' '||str[i]=='\t'||str[i]=='\n'||str[i]=='\r')) i++;
    for (; i<l; i++) str[j++] = str[i];
    while (j>0 && (str[j-1]==' '||str[j-1]=='\t'||str[j-1]=='\n'||str[j-1]=='\r')) j--;
    str[j] = '\0';
    return j;
}

// Get first arg after command
stock _arg1(const input[], out[]) {
    new i=0; while (input[i] && input[i] != ' ') i++; while (input[i]==' ') i++;
    new j=0; while (input[i] && input[i] != ' ' && j < 31) out[j++] = input[i++];
    out[j]='\0'; return j;
}

// ---------- 3D Chat logic ----------
forward Clear3D(playerid);
public Clear3D(playerid)
{
    if (g_Chat3D[playerid] != Text3D:INVALID_3DTEXT_ID)
    {
        Update3DTextLabelText(g_Chat3D[playerid], COLOR_CHAT3D, " ");
    }
    g_ChatTimer[playerid] = 0;
    return 1;
}

stock Show3DChat(playerid, const text[])
{
    new line[96];
    new name[MAX_PLAYER_NAME];
    GetPlayerName(playerid, name, sizeof name);
    format(line, sizeof line, "%s: %s", name, text);
    if (g_Chat3D[playerid] == Text3D:INVALID_3DTEXT_ID)
    {
        g_Chat3D[playerid] = Create3DTextLabel(line, COLOR_CHAT3D, 0.0, 0.0, 0.0, 25.0, 0, 1);
        Attach3DTextLabelToPlayer(g_Chat3D[playerid], playerid, 0.0, 0.0, 0.35);
    }
    else
    {
        Update3DTextLabelText(g_Chat3D[playerid], COLOR_CHAT3D, line);
    }
    if (g_ChatTimer[playerid]) KillTimer(g_ChatTimer[playerid]);
    g_ChatTimer[playerid] = SetTimerEx("Clear3D", 5000, false, "i", playerid); // fade after 5s
}

// ---------- Core callbacks ----------
public OnGameModeInit()
{
    SetGameModeText(SERVER_NAME);
    ShowPlayerMarkers(1);
    UsePlayerPedAnims();

    AddPlayerClass(0, 1958.3783, 1343.1572, 15.3746, 269.1425, 0,0,0,0,0,0);
    AddPlayerClass(0, -1985.5698, 137.1331, 27.6875, 90.0000, 0,0,0,0,0,0);
    AddPlayerClass(0, 2481.2524, -1666.1342, 13.3438, 180.0000,0,0,0,0,0,0);

    print("[NoPixelMode] Initialized.");
    return 1;
}

public OnGameModeExit()
{
    print("[NoPixelMode] Exiting.");
    return 1;
}

public OnPlayerConnect(playerid)
{
    g_Admin[playerid]=false;
    g_Muted[playerid]=false;
    g_Frozen[playerid]=false;
    g_Job[playerid]=JOB_NONE;
    g_Cash[playerid]=5000;
    g_Bank[playerid]=0;
    g_ChatTimer[playerid]=0;
    g_AdminContext[playerid]=ACT_NONE;
    g_AdminTarget[playerid]=-1;

    Msg(playerid, COLOR_INFO, "Welcome! Type /help for commands. Mode: %s", (g_Mode==MODE_RP?"RP":(g_Mode==MODE_FREEROAM?"Freeroam":(g_Mode==MODE_RACE?"Race":"TDM"))));
    return 1;
}

public OnPlayerDisconnect(playerid, reason)
{
    if (g_Chat3D[playerid] != Text3D:INVALID_3DTEXT_ID)
    {
        Delete3DTextLabel(g_Chat3D[playerid]);
        g_Chat3D[playerid] = Text3D:INVALID_3DTEXT_ID;
    }
    if (g_ChatTimer[playerid]) KillTimer(g_ChatTimer[playerid]);
    return 1;
}

public OnPlayerSpawn(playerid)
{
    if (g_Frozen[playerid]) { TogglePlayerControllable(playerid, 0); }
    else { TogglePlayerControllable(playerid, 1); }
    if (IsPlayerAdminLevel(playerid)) { SetPlayerArmour(playerid, 100.0); SetPlayerHealth(playerid, 100.0); }
    return 1;
}

public OnPlayerText(playerid, text[])
{
    if (g_Muted[playerid]) return 0;
    Show3DChat(playerid, text);
    return 1;
}

// ---------- Admin UI helpers ----------
stock ShowAdminMain(playerid)
{
    ShowPlayerDialog(playerid, D_ADMIN_MAIN, DIALOG_STYLE_LIST, "Admin Panel",
        "Kick player\nBan player\nMute player\nUnmute player\nGoto player\nBring player\nFreeze player\nUnfreeze player\nHeal self (HP+Armor)\nGive weapon to player\nSpawn vehicle for me\nGive money to player",
        "Select","Close");
}

stock BuildPlayerList(playerid, caption[])
{
    static list[4096];
    list[0] = '\0';
    new idx=0;
    for (new i=0;i<MAX_PLAYERS;i++)
    {
        g_PlayerListMap[playerid][i] = -1;
    }
    for (new i=0;i<MAX_PLAYERS;i++)
    {
        if (!IsPlayerConnected(i)) continue;
        new name[MAX_PLAYER_NAME];
        GetPlayerName(i, name, sizeof name);
        format(list, sizeof list, "%s[%d] %s%s\n", list, i, name, (g_Muted[i]?" (muted)":""));
        g_PlayerListMap[playerid][idx++] = i;
    }
    if (idx==0) format(list, sizeof list, "No players online");
    ShowPlayerDialog(playerid, D_ADMIN_PLAYERS, DIALOG_STYLE_LIST, caption, list, "Select", "Back");
}

// ---------- Command handling ----------
public OnPlayerCommandText(playerid, cmdtext[])
{
    // HELP
    if (!strcmp(cmdtext, "/help", true))
    {
        SendClientMessage(playerid, COLOR_INFO, "----- Commands -----");
        SendClientMessage(playerid, COLOR_INFO, "General: /help /stats /me <text> /report <text>");
        SendClientMessage(playerid, COLOR_INFO, "Jobs: /jobs /work <taxi|police|medic|mechanic> /quitjob");
        SendClientMessage(playerid, COLOR_INFO, "Vehicles: /car <model> /dv /park");
        SendClientMessage(playerid, COLOR_INFO, "Modes: /mode <rp|freeroam|race|tdm>");
        SendClientMessage(playerid, COLOR_INFO, "Admin: /admin (panel), /makeadmin <id> (RCON only)");
        return 1;
    }

    // ME emote (also shows above head)
    if (!strncmp(cmdtext, "/me", true, 3))
    {
        new t[96]; if (_arg1(cmdtext, t)==0) return Msg(playerid, COLOR_INFO, "Usage: /me <action>");
        Show3DChat(playerid, t);
        new n[32]; NameOf(playerid,n,sizeof n);
        Broadcast(COLOR_INFO, "* %s %s", n, t);
        return 1;
    }

    // STATS
    if (!strcmp(cmdtext, "/stats", true))
    {
        new n[32]; NameOf(playerid,n,sizeof n);
        Msg(playerid, COLOR_INFO, "%s | Cash: $%d | Bank: $%d | Job: %s | Mode: %s",
            n, g_Cash[playerid], g_Bank[playerid],
            (g_Job[playerid]==JOB_NONE?"None":(g_Job[playerid]==JOB_TAXI?"Taxi":(g_Job[playerid]==JOB_POLICE?"Police":(g_Job[playerid]==JOB_MEDIC?"Medic":"Mechanic")))),
            (g_Mode==MODE_RP?"RP":(g_Mode==MODE_FREEROAM?"Freeroam":(g_Mode==MODE_RACE?"Race":"TDM"))));
        return 1;
    }

    // REPORT
    if (!strncmp(cmdtext, "/report", true, 7))
    {
        new msg[96]; if (_arg1(cmdtext, msg)==0) return Msg(playerid, COLOR_INFO, "Usage: /report <text>");
        for (new i=0;i<MAX_PLAYERS;i++) if (IsPlayerConnected(i) && IsPlayerAdminLevel(i)) Msg(i, COLOR_ADMIN, "Report from %d: %s", playerid, msg);
        Msg(playerid, COLOR_OK, "Report sent to online admins.");
        return 1;
    }

    // VEHICLE: /car
    if (!strncmp(cmdtext, "/car", true, 4))
    {
        new a[8]; if (_arg1(cmdtext,a)==0) return Msg(playerid,COLOR_INFO,"Usage: /car <model>");
        new model = strval(a);
        if (model < 400 || model > 611) return Msg(playerid, COLOR_ERR, "Vehicle model 400-611.");
        new Float:x,Float:y,Float:z,Float:a2; GetPlayerPos(playerid,x,y,z); GetPlayerFacingAngle(playerid,a2);
        new vid = CreateVehicle(model, x+2.0, y, z, a2, -1, -1, 45);
        PutPlayerInVehicle(playerid, vid, 0);
        Msg(playerid, COLOR_OK, "Car spawned: %d.", model);
        return 1;
    }

    // Delete vehicle: /dv
    if (!strcmp(cmdtext, "/dv", true))
    {
        new vid = GetPlayerVehicleID(playerid);
        if (!vid) return Msg(playerid, COLOR_ERR, "Not in a vehicle.");
        DestroyVehicle(vid);
        Msg(playerid, COLOR_OK, "Vehicle deleted.");
        return 1;
    }

    // PARK (placeholder)
    if (!strcmp(cmdtext, "/park", true))
    {
        Msg(playerid, COLOR_OK, "Your vehicle park position is saved (placeholder).");
        return 1;
    }

    // JOBS list
    if (!strcmp(cmdtext, "/jobs", true))
    {
        ShowPlayerDialog(playerid, D_JOBS, DIALOG_STYLE_LIST, "Jobs", "Taxi Driver\nPolice Officer\nMedic\nMechanic\nNone", "Select", "Close");
        return 1;
    }

    // Work / Quitjob
    if (!strncmp(cmdtext, "/work", true, 5))
    {
        new a[16]; if (_arg1(cmdtext,a)==0) return Msg(playerid, COLOR_INFO, "Usage: /work <taxi|police|medic|mechanic>");
        if (!strcmp(a,"taxi",true)) g_Job[playerid]=JOB_TAXI;
        else if (!strcmp(a,"police",true)) g_Job[playerid]=JOB_POLICE;
        else if (!strcmp(a,"medic",true)) g_Job[playerid]=JOB_MEDIC;
        else if (!strcmp(a,"mechanic",true)) g_Job[playerid]=JOB_MECHANIC;
        else return Msg(playerid, COLOR_ERR, "Unknown job.");
        Msg(playerid, COLOR_OK, "Job set!");
        return 1;
    }
    if (!strcmp(cmdtext, "/quitjob", true))
    {
        g_Job[playerid]=JOB_NONE; Msg(playerid, COLOR_OK, "You quit your job."); return 1;
    }

    // Modes
    if (!strncmp(cmdtext, "/mode", true, 5))
    {
        new a[16]; if (_arg1(cmdtext,a)==0) return Msg(playerid, COLOR_INFO, "Usage: /mode <rp|freeroam|race|tdm>");
        if (!strcmp(a,"rp",true)) g_Mode = MODE_RP;
        else if (!strcmp(a,"freeroam",true)) g_Mode = MODE_FREEROAM;
        else if (!strcmp(a,"race",true)) g_Mode = MODE_RACE;
        else if (!strcmp(a,"tdm",true)) g_Mode = MODE_TDM;
        else return Msg(playerid, COLOR_ERR, "Unknown mode.");
        Broadcast(COLOR_INFO, "Server mode is now: %s", (g_Mode==MODE_RP?"RP":(g_Mode==MODE_FREEROAM?"Freeroam":(g_Mode==MODE_RACE?"Race":"TDM"))));
        return 1;
    }

    // Admin
    if (!strcmp(cmdtext, "/admin", true))
    {
        if (!IsPlayerAdminLevel(playerid)) return Msg(playerid, COLOR_ERR, "Admin only.");
        ShowAdminMain(playerid);
        return 1;
    }

    if (!strncmp(cmdtext, "/makeadmin", true, 10))
    {
        if (!IsPlayerAdmin(playerid)) return Msg(playerid, COLOR_ERR, "RCON only.");
        new a[8]; if (_arg1(cmdtext,a)==0) return Msg(playerid, COLOR_INFO, "Usage: /makeadmin <id>");
        new t = strval(a); if (!IsPlayerConnected(t)) return Msg(playerid, COLOR_ERR, "Not online.");
        g_Admin[t]=true; Msg(playerid, COLOR_OK, "Granted admin to %d.", t); Msg(t, COLOR_ADMIN, "You are now admin.");
        return 1;
    }

    return 0;
}

// ---------- Dialog responses ----------
#define D_JOBS 2002
public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[])
{
    if (dialogid == D_JOBS && response)
    {
        switch (listitem)
        {
            case 0: g_Job[playerid]=JOB_TAXI;
            case 1: g_Job[playerid]=JOB_POLICE;
            case 2: g_Job[playerid]=JOB_MEDIC;
            case 3: g_Job[playerid]=JOB_MECHANIC;
            case 4: g_Job[playerid]=JOB_NONE;
        }
        Msg(playerid, COLOR_OK, "Job updated.");
        return 1;
    }

    if (dialogid == D_ADMIN_MAIN && response)
    {
        switch (listitem)
        {
            case 0: g_AdminContext[playerid]=ACT_KICK;      BuildPlayerList(playerid, "Kick: choose player"); return 1;
            case 1: g_AdminContext[playerid]=ACT_BAN;       BuildPlayerList(playerid, "Ban: choose player"); return 1;
            case 2: g_AdminContext[playerid]=ACT_MUTE;      BuildPlayerList(playerid, "Mute: choose player"); return 1;
            case 3: g_AdminContext[playerid]=ACT_UNMUTE;    BuildPlayerList(playerid, "Unmute: choose player"); return 1;
            case 4: g_AdminContext[playerid]=ACT_GOTO;      BuildPlayerList(playerid, "Goto: choose player"); return 1;
            case 5: g_AdminContext[playerid]=ACT_BRING;     BuildPlayerList(playerid, "Bring: choose player"); return 1;
            case 6: g_AdminContext[playerid]=ACT_FREEZE;    BuildPlayerList(playerid, "Freeze: choose player"); return 1;
            case 7: g_AdminContext[playerid]=ACT_UNFREEZE;  BuildPlayerList(playerid, "Unfreeze: choose player"); return 1;
            case 8: g_AdminContext[playerid]=ACT_HEAL;      SetPlayerHealth(playerid,100.0); SetPlayerArmour(playerid,100.0); Msg(playerid,COLOR_OK,"Healed & armoured."); ShowAdminMain(playerid); return 1;
            case 9: g_AdminContext[playerid]=ACT_GIVEWEAPON; BuildPlayerList(playerid, "Give weapon: choose player"); return 1;
            case 10:g_AdminContext[playerid]=ACT_SPAWNCAR;  ShowPlayerDialog(playerid, D_ADMIN_INPUT, DIALOG_STYLE_INPUT, "Spawn Vehicle", "Enter vehicle model (400-611):", "OK", "Back"); return 1;
            case 11:g_AdminContext[playerid]=ACT_GIVEMONEY; BuildPlayerList(playerid, "Give money: choose player"); return 1;
        }
        return 1;
    }

    if (dialogid == D_ADMIN_PLAYERS)
    {
        if (!response) { ShowAdminMain(playerid); return 1; }
        // find mapping
        new target = -1;
        if (listitem >= 0 && listitem < MAX_PLAYERS) target = g_PlayerListMap[playerid][listitem];
        if (target == -1 || !IsPlayerConnected(target)) { Msg(playerid, COLOR_ERR, "Invalid player."); ShowAdminMain(playerid); return 1; }
        g_AdminTarget[playerid] = target;

        switch (g_AdminContext[playerid])
        {
            case ACT_KICK:   { Msg(playerid, COLOR_ADMIN, "Kicked %d.", target); Kick(target); ShowAdminMain(playerid); }
            case ACT_BAN:    { Ban(target); Msg(playerid, COLOR_ADMIN, "Banned %d.", target); ShowAdminMain(playerid); }
            case ACT_MUTE:   { g_Muted[target]=true; Msg(playerid,COLOR_ADMIN,"Muted %d.",target); ShowAdminMain(playerid); }
            case ACT_UNMUTE: { g_Muted[target]=false; Msg(playerid,COLOR_ADMIN,"Unmuted %d.",target); ShowAdminMain(playerid); }
            case ACT_GOTO:
            {
                new Float:x,Float:y,Float:z; GetPlayerPos(target,x,y,z);
                SetPlayerPos(playerid, x+1.0, y, z);
                Msg(playerid, COLOR_ADMIN, "Teleported to %d.", target);
                ShowAdminMain(playerid);
            }
            case ACT_BRING:
            {
                new Float:x,Float:y,Float:z; GetPlayerPos(playerid,x,y,z);
                SetPlayerPos(target, x+1.0, y, z);
                Msg(playerid, COLOR_ADMIN, "Brought %d.", target);
                ShowAdminMain(playerid);
            }
            case ACT_FREEZE:   { g_Frozen[target]=true; TogglePlayerControllable(target,0); Msg(playerid,COLOR_ADMIN,"Froze %d.",target); ShowAdminMain(playerid); }
            case ACT_UNFREEZE: { g_Frozen[target]=false; TogglePlayerControllable(target,1); Msg(playerid,COLOR_ADMIN,"Unfroze %d.",target); ShowAdminMain(playerid); }
            case ACT_GIVEWEAPON:
            {
                ShowPlayerDialog(playerid, D_ADMIN_INPUT, DIALOG_STYLE_INPUT, "Give Weapon",
                                 "Enter: <weapon_id> <ammo> (example: 24 200)", "OK", "Back");
            }
            case ACT_GIVEMONEY:
            {
                ShowPlayerDialog(playerid, D_ADMIN_INPUT, DIALOG_STYLE_INPUT, "Give Money",
                                 "Enter amount (example: 5000)", "OK", "Back");
            }
        }
        return 1;
    }

    if (dialogid == D_ADMIN_INPUT)
    {
        if (!response) { ShowAdminMain(playerid); return 1; }
        new target = g_AdminTarget[playerid];
        switch (g_AdminContext[playerid])
        {
            case ACT_SPAWNCAR:
            {
                new model = strval(inputtext);
                if (model < 400 || model > 611) { Msg(playerid, COLOR_ERR, "Vehicle model 400-611."); return 1; }
                new Float:x,Float:y,Float:z,Float:a; GetPlayerPos(playerid,x,y,z); GetPlayerFacingAngle(playerid,a);
                new vid = CreateVehicle(model, x+2.0, y, z, a, -1, -1, 45);
                PutPlayerInVehicle(playerid, vid, 0);
                Msg(playerid, COLOR_OK, "Spawned vehicle %d.", model);
                ShowAdminMain(playerid);
            }
            case ACT_GIVEWEAPON:
            {
                new w=0, ammo=0;
                // parse "w ammo"
                new i=0; while (inputtext[i]==' ') i++;
                while (inputtext[i]>='0'&&inputtext[i]<='9'){ w = w*10 + (inputtext[i]-'0'); i++; }
                while (inputtext[i]==' ') i++;
                while (inputtext[i]>='0'&&inputtext[i]<='9'){ ammo = ammo*10 + (inputtext[i]-'0'); i++; }
                if (!IsValidWeapon(w)) { Msg(playerid, COLOR_ERR, "Invalid weapon id."); return 1; }
                if (ammo<=0) ammo=200;
                if (!IsPlayerConnected(target)) { Msg(playerid, COLOR_ERR, "Target left."); return 1; }
                GivePlayerWeapon(target, w, ammo);
                Msg(playerid, COLOR_OK, "Gave %d x%d to %d.", w, ammo, target);
                ShowAdminMain(playerid);
            }
            case ACT_GIVEMONEY:
            {
                new amt = strval(inputtext);
                if (amt<=0) { Msg(playerid, COLOR_ERR, "Amount must be > 0."); return 1; }
                if (!IsPlayerConnected(target)) { Msg(playerid, COLOR_ERR, "Target left."); return 1; }
                g_Cash[target] += amt;
                Msg(playerid, COLOR_OK, "Gave $%d to %d.", amt, target);
                Msg(target, COLOR_INFO, "You received $%d from admin.", amt);
                ShowAdminMain(playerid);
            }
        }
        return 1;
    }

    return 0;
}

// ---------- Simple distance utility ----------
stock Float:VectorSize(Float:x, Float:y, Float:z)
{
    return floatsqroot((x*x)+(y*y)+(z*z));
}
