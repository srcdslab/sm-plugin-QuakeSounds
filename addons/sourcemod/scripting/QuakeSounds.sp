#include <sourcemod>
#include <sdktools>
#include <clientprefs>

#pragma semicolon 1
#pragma newdecls required

#define ANNOUNCE_DELAY				30.0
#define JOIN_DELAY					2.0

#define MAX_NUM_SETS				255
#define MAX_SET_NAME_LENGTH			64

#define PATH_CONFIG_QUAKE_SET		"configs/quake/sets.cfg"
#define PATH_CONFIG_QUAKE_SOUNDS	"configs/quake/sets"

// "config" bits: 1/2/4 play the sound to everyone/attacker/victim, 8/16/32 print the text to the same targets
#define CONFIG_TARGET_BITS			7
#define CONFIG_TEXT_SHIFT			3

public Plugin myinfo = {
	name = "Quake Sounds",
	author = "Spartan_C001, maxime1907, .Rushaway",
	description = "Plays sounds based on events that happen in game.",
	version = "4.3.0",
	url = "http://steamcommunity.com/id/spartan_c001/",
}

// Numbered sounds come first: their section holds one sub-section per streak count
enum SoundType
{
	Sound_Headshot = 0,
	Sound_Kill,
	Sound_Combo,
	Sound_LastNumbered = Sound_Combo,
	Sound_FirstBlood,
	Sound_Grenade,
	Sound_SelfKill,
	Sound_RoundPlay,
	Sound_Knife,
	Sound_TeamKill,
	Sound_Join,
	Sound_Count
}

// Section of each sound type in the set config files
char g_sSoundSections[Sound_Count][] = {
	"headshot",
	"killsound",
	"combo",
	"first blood",
	"grenade",
	"selfkill",
	"round play",
	"knife",
	"teamkill",
	"join server"
};

enum struct SoundEntry
{
	char path[PLATFORM_MAX_PATH];	// Empty for a text only entry
	int config;
}

// Sound Sets
int g_iNumSets = 0;
char g_sSetName[MAX_NUM_SETS][MAX_SET_NAME_LENGTH];
StringMap g_smSetSounds[MAX_NUM_SETS];		// "<type>:<num>" -> SoundEntry, only the configured sounds
ArrayList g_aSetKillNums[MAX_NUM_SETS];		// Configured "killsound" numbers, ascending

// Kill Streaks
int g_iTotalKills = 0;
int g_iConsecutiveKills[MAXPLAYERS+1];
int g_iComboScore[MAXPLAYERS+1];
int g_iConsecutiveHeadshots[MAXPLAYERS+1];
float g_fLastKillTime[MAXPLAYERS+1];

// Preferences
Cookie g_cQuakeSettings;
bool g_bShowText[MAXPLAYERS + 1];
bool g_bSound[MAXPLAYERS + 1];
int g_iSoundPreset[MAXPLAYERS + 1];

ConVar g_cvar_Announce;
ConVar g_cvar_Text;
ConVar g_cvar_Sound;
ConVar g_cvar_SoundPreset;
ConVar g_cvar_Volume;
ConVar g_cvar_TeamKillMode;
ConVar g_cvar_ComboTime;
ConVar g_cvar_SelfKill;
ConVar g_cvar_TeamKill;

EngineVersion g_evGameEngine;

bool g_bLate = false;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;
	g_evGameEngine = GetEngineVersion();
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("plugin.quakesounds");

	g_cvar_Announce = CreateConVar("sm_quakesounds_announce", "1", "Sets whether to announcement to clients as they join, 0=Disabled, 1=Enabled.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvar_Text = CreateConVar("sm_quakesounds_text", "1", "Default text display setting for new users, 0=Disabled, 1=Enabled.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvar_Sound = CreateConVar("sm_quakesounds_sound", "1", "Default sound setting for new users, 0=Disable 1=Enable.", FCVAR_NONE, true, 0.0, true, 255.0);
	g_cvar_SoundPreset = CreateConVar("sm_quakesounds_sound_preset", "1", "Default sound set for new users, 1-255=Preset by order in the config file.", FCVAR_NONE, true, 1.0, true, 255.0);
	g_cvar_Volume = CreateConVar("sm_quakesounds_volume", "1.0", "Sound Volume: should be a number between 0.0 and 1.0.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvar_TeamKillMode = CreateConVar("sm_quakesounds_teamkill_mode", "0", "Teamkiller Mode; 0=Normal, 1=Team-Kills count as normal kills.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvar_ComboTime = CreateConVar("sm_quakesounds_combo_time", "2.0", "Max time in seconds between kills to count as combo; 0.0=Minimum, 2.0=Default", FCVAR_NONE, true, 0.0);
	g_cvar_SelfKill = CreateConVar("sm_quakesounds_selfkill", "1", "Enable/Disable selfkill sounds; 0=Disabled, 1=Enabled", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvar_TeamKill = CreateConVar("sm_quakesounds_teamkill", "1", "Enable/Disable teamkill sounds; 0=Disabled, 1=Enabled", FCVAR_NONE, true, 0.0, true, 1.0);

	g_cQuakeSettings = new Cookie("quakesounds_settings", "Quake Sounds Settings", CookieAccess_Private);

	SetCookieMenuItem(CookieMenu_QuakeSounds, 0, "Quake Sound Settings");

	RegConsoleCmd("sm_quake", Command_QuakeSounds);

	HookGameEvents();

	AutoExecConfig(true);
}

public void OnMapStart()
{
	LoadQuakeSetConfig();

	// The set list may have shrunk since the last map
	for (int i = 1; i <= MaxClients; i++)
		g_iSoundPreset[i] = ClampSoundPreset(g_iSoundPreset[i]);

	if (g_evGameEngine == Engine_HL2DM)
	{
		InitializeRound();
	}
}

public void OnConfigsExecuted()
{
	// Late load: the sound sets and the cvars are ready now
	if (!g_bLate)
		return;

	g_bLate = false;
	InitializeRound();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientConnected(i))
			continue;

		OnClientConnected(i);
		if (AreClientCookiesCached(i))
			ReadClientCookies(i);
	}
}

public void OnClientConnected(int client)
{
	g_iConsecutiveKills[client] = 0;
	g_iConsecutiveHeadshots[client] = 0;
	g_fLastKillTime[client] = -1.0;

	// Until the cookies are cached, do not keep the preferences of the previous player in this slot
	LoadDefaultPreferences(client);
}

public void OnClientPostAdminCheck(int client)
{
	if (IsFakeClient(client))
		return;

	int iUserID = GetClientUserId(client);

	if (g_cvar_Announce.BoolValue)
		CreateTimer(ANNOUNCE_DELAY, Timer_Announce, iUserID, TIMER_FLAG_NO_MAPCHANGE);

	CreateTimer(JOIN_DELAY, Timer_JoinCheck, iUserID, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientCookiesCached(int client)
{
	ReadClientCookies(client);
}

//   .d8888b.   .d88888b.  888b     d888 888b     d888        d8888 888b    888 8888888b.   .d8888b.
//  d88P  Y88b d88P" "Y88b 8888b   d8888 8888b   d8888       d88888 8888b   888 888  "Y88b d88P  Y88b
//  888    888 888     888 88888b.d88888 88888b.d88888      d88P888 88888b  888 888    888 Y88b.
//  888        888     888 888Y88888P888 888Y88888P888     d88P 888 888Y88b 888 888    888  "Y888b.
//  888        888     888 888 Y888P 888 888 Y888P 888    d88P  888 888 Y88b888 888    888     "Y88b.
//  888    888 888     888 888  Y8P  888 888  Y8P  888   d88P   888 888  Y88888 888    888       "888
//  Y88b  d88P Y88b. .d88P 888   "   888 888   "   888  d8888888888 888   Y8888 888  .d88P Y88b  d88P
//   "Y8888P"   "Y88888P"  888       888 888       888 d88P     888 888    Y888 8888888P"   "Y8888P"

public Action Command_QuakeSounds(int client, int args)
{
	if (client)
		DisplayCookieMenu(client);
	return Plugin_Handled;
}

//  888b     d888 8888888888 888b    888 888     888
//  8888b   d8888 888        8888b   888 888     888
//  88888b.d88888 888        88888b  888 888     888
//  888Y88888P888 8888888    888Y88b 888 888     888
//  888 Y888P 888 888        888 Y88b888 888     888
//  888  Y8P  888 888        888  Y88888 888     888
//  888   "   888 888        888   Y8888 Y88b. .d88P
//  888       888 8888888888 888    Y888  "Y88888P"

public void CookieMenu_QuakeSounds(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	if (action == CookieMenuAction_SelectOption)
		DisplayCookieMenu(client);
}

void DisplayCookieMenu(int client)
{
	Menu menu = new Menu(MenuHandler_QuakeSounds, MENU_ACTIONS_DEFAULT | MenuAction_DisplayItem);
	menu.ExitBackButton = true;
	menu.ExitButton = true;
	menu.SetTitle("%T", "quake menu", client);

	char sBuffer[128];
	for (int item = 0; item < 3; item++)
	{
		FormatMenuItem(client, item, sBuffer, sizeof(sBuffer));
		menu.AddItem("", sBuffer);
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

void FormatMenuItem(int client, int item, char[] buffer, int maxlen)
{
	switch (item)
	{
		case 0:
		{
			FormatEx(buffer, maxlen, "%T", g_bShowText[client] ? "disable text" : "enable text", client);
		}
		case 1:
		{
			FormatEx(buffer, maxlen, "%T", g_bSound[client] ? "sounds disable" : "sounds enable", client);
		}
		case 2:
		{
			char sSetName[MAX_SET_NAME_LENGTH];
			int set = g_iSoundPreset[client];
			if (set >= g_iNumSets)
				strcopy(sSetName, sizeof(sSetName), "Error");
			else if (TranslationPhraseExists(g_sSetName[set]))
				FormatEx(sSetName, sizeof(sSetName), "%T", g_sSetName[set], client);
			else
				strcopy(sSetName, sizeof(sSetName), g_sSetName[set]);

			FormatEx(buffer, maxlen, "%T: %s", "sound pack", client, sSetName);
		}
	}
}

public int MenuHandler_QuakeSounds(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			if (param1 != MenuEnd_Selected)
				delete menu;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				ShowCookieMenu(param1);
		}
		case MenuAction_Select:
		{
			switch (param2)
			{
				case 0:
				{
					g_bShowText[param1] = !g_bShowText[param1];
				}
				case 1:
				{
					g_bSound[param1] = !g_bSound[param1];
				}
				case 2:
				{
					g_iSoundPreset[param1]++;
					if (g_iSoundPreset[param1] >= g_iNumSets)
						g_iSoundPreset[param1] = 0;
				}
			}
			SaveClientCookies(param1);
			menu.Display(param1, MENU_TIME_FOREVER);
		}
		case MenuAction_DisplayItem:
		{
			char sBuffer[128];
			FormatMenuItem(param1, param2, sBuffer, sizeof(sBuffer));
			return RedrawMenuItem(sBuffer);
		}
	}
	return 0;
}

// ##     ##  #######   #######  ##    ##  ######
// ##     ## ##     ## ##     ## ##   ##  ##    ##
// ##     ## ##     ## ##     ## ##  ##   ##
// ######### ##     ## ##     ## #####     ######
// ##     ## ##     ## ##     ## ##  ##         ##
// ##     ## ##     ## ##     ## ##   ##  ##    ##
// ##     ##  #######   #######  ##    ##  ######

// Hooks correct game events
void HookGameEvents()
{
	HookEvent("player_death", Event_PlayerDeath);
	switch (g_evGameEngine)
	{
		case Engine_CSS, Engine_CSGO:
		{
			HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
			HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
		}
		case Engine_DODS:
		{
			HookEvent("dod_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
			HookEvent("dod_round_active", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
		}
		case Engine_TF2:
		{
			HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
			HookEvent("teamplay_round_active", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
			HookEvent("arena_round_start", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
		}
		case Engine_HL2DM:
		{
			// A round lasts the whole map, see OnMapStart()
		}
		default:
		{
			HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
		}
	}
}

public Action Timer_JoinCheck(Handle timer, int iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if (!client || !IsClientInGame(client) || !AreClientCookiesCached(client) || !g_bSound[client])
		return Plugin_Stop;

	int set = g_iSoundPreset[client];
	SoundEntry entry;
	if (set < g_iNumSets && GetSetSound(set, Sound_Join, 0, entry) && entry.path[0] && (entry.config & CONFIG_TARGET_BITS))
		EmitSoundToClient(client, entry.path, .volume = g_cvar_Volume.FloatValue);

	return Plugin_Stop;
}

public Action Timer_Announce(Handle timer, int iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if (!client || !IsClientInGame(client))
		return Plugin_Stop;

	PrintToChat(client, "%t", "announce message");
	return Plugin_Stop;
}

// Plays round play sound depending on each players config and the text display
public void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
	SoundEntry entry;
	for (int set = 0; set < g_iNumSets; set++)
	{
		if (!GetSetSound(set, Sound_RoundPlay, 0, entry))
			continue;

		// There is no attacker nor victim here, any target means everyone
		if (entry.config & CONFIG_TARGET_BITS)
			entry.config |= 1;
		if ((entry.config >> CONFIG_TEXT_SHIFT) & CONFIG_TARGET_BITS)
			entry.config |= 1 << CONFIG_TEXT_SHIFT;

		AnnounceToSet(set, entry, "round play", 0, 0, "", "");
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	InitializeRound();
}

// Important bit - does all kill/combo/custom kill sounds and things!
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!victim)
		return;

	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	char victimName[MAX_NAME_LENGTH], attackerName[MAX_NAME_LENGTH];
	GetClientName(victim, victimName, sizeof(victimName));
	if (attacker)
		GetClientName(attacker, attackerName, sizeof(attackerName));

	if (attacker == victim || !attacker)
	{
		if (g_cvar_SelfKill.BoolValue)
			AnnounceToAllSets(Sound_SelfKill, "selfkill", attacker, victim, victimName, "");
	}
	else if (!g_cvar_TeamKillMode.BoolValue && GetClientTeam(attacker) == GetClientTeam(victim))
	{
		g_iConsecutiveKills[attacker] = 0;

		if (g_cvar_TeamKill.BoolValue)
			AnnounceToAllSets(Sound_TeamKill, "teamkill", attacker, victim, attackerName, victimName);
	}
	else
	{
		OnEnemyKilled(event, attacker, victim, attackerName, victimName);
	}

	g_iConsecutiveKills[victim] = 0;
	g_iConsecutiveHeadshots[victim] = 0;
}

// ######## ##     ## ##    ##  ######  ######## ####  #######  ##    ##  ######
// ##       ##     ## ###   ## ##    ##    ##     ##  ##     ## ###   ## ##    ##
// ##       ##     ## ####  ## ##          ##     ##  ##     ## ####  ## ##
// ######   ##     ## ## ## ## ##          ##     ##  ##     ## ## ## ##  ######
// ##       ##     ## ##  #### ##          ##     ##  ##     ## ##  ####       ##
// ##       ##     ## ##   ### ##    ##    ##     ##  ##     ## ##   ### ##    ##
// ##        #######  ##    ##  ######     ##    ####  #######  ##    ##  ######

// Updates the streaks of the attacker, then announces the kill to each sound set
void OnEnemyKilled(Event event, int attacker, int victim, const char[] attackerName, const char[] victimName)
{
	g_iTotalKills++;
	g_iConsecutiveKills[attacker]++;

	bool headshot = false;
	bool knife = false;
	bool grenade = false;

	if (g_evGameEngine == Engine_TF2)
	{
		int customkill = event.GetInt("customkill");
		headshot = customkill == 1;
		knife = customkill == 2;
	}
	else
	{
		if (g_evGameEngine == Engine_CSS || g_evGameEngine == Engine_CSGO)
			headshot = event.GetBool("headshot");

		char weapon[64];
		event.GetString("weapon", weapon, sizeof(weapon));
		GetWeaponKind(weapon, knife, grenade);
	}

	if (headshot)
		g_iConsecutiveHeadshots[attacker]++;

	float fNow = GetEngineTime();
	bool combo = g_fLastKillTime[attacker] != -1.0 && (fNow - g_fLastKillTime[attacker]) <= g_cvar_ComboTime.FloatValue;
	g_fLastKillTime[attacker] = fNow;
	g_iComboScore[attacker] = combo ? g_iComboScore[attacker] + 1 : 1;

	bool firstblood = g_iTotalKills == 1;

	SoundEntry entry;
	char phrase[32];
	for (int set = 0; set < g_iNumSets; set++)
	{
		if (FindKillSound(set, attacker, firstblood, headshot, knife, grenade, combo, entry, phrase, sizeof(phrase)))
			AnnounceToSet(set, entry, phrase, attacker, victim, attackerName, victimName);
	}
}

// Picks the sound of a set announcing a kill, by priority:
// first blood, headshot streak, headshot, knife, grenade, combo, kill streak
bool FindKillSound(int set, int attacker, bool firstblood, bool headshot, bool knife, bool grenade, bool combo, SoundEntry entry, char[] phrase, int maxlen)
{
	if (firstblood && GetSetSound(set, Sound_FirstBlood, 0, entry))
	{
		strcopy(phrase, maxlen, "first blood");
		return true;
	}

	if (headshot)
	{
		int headshots = g_iConsecutiveHeadshots[attacker];
		if (GetSetSound(set, Sound_Headshot, headshots, entry))
		{
			FormatEx(phrase, maxlen, "headshot %d", headshots);
			return true;
		}

		// "0" is the headshot without a streak sound
		if (GetSetSound(set, Sound_Headshot, 0, entry))
		{
			strcopy(phrase, maxlen, "headshot");
			return true;
		}
	}

	if (knife && GetSetSound(set, Sound_Knife, 0, entry))
	{
		strcopy(phrase, maxlen, "knife");
		return true;
	}

	if (grenade && GetSetSound(set, Sound_Grenade, 0, entry))
	{
		strcopy(phrase, maxlen, "grenade");
		return true;
	}

	if (combo && GetSetSound(set, Sound_Combo, g_iComboScore[attacker], entry))
	{
		FormatEx(phrase, maxlen, "combo %d", g_iComboScore[attacker]);
		return true;
	}

	int kills = g_iConsecutiveKills[attacker];
	if (!GetSetSound(set, Sound_Kill, kills, entry))
	{
		// Past the last kill streak sound, replay a random one every 2 kills
		ArrayList killNums = g_aSetKillNums[set];
		int count = killNums.Length;
		if (!count || kills % 2 != 0 || kills < killNums.Get(count - 1))
			return false;

		kills = killNums.Get(GetRandomInt(0, count - 1));
		GetSetSound(set, Sound_Kill, kills, entry);
	}

	FormatEx(phrase, maxlen, "killsound %d", kills);
	return true;
}

// Tells whether the weapon of a kill makes it a knife or a grenade kill on this game
void GetWeaponKind(const char[] weapon, bool &knife, bool &grenade)
{
	switch (g_evGameEngine)
	{
		case Engine_CSS:
		{
			grenade = StrEqual(weapon, "hegrenade", false) || StrEqual(weapon, "smokegrenade", false) || StrEqual(weapon, "flashbang", false);
			knife = !grenade && StrContains(weapon, "knife", false) != -1;
		}
		case Engine_CSGO:
		{
			grenade = StrEqual(weapon, "inferno", false) || StrEqual(weapon, "hegrenade", false) || StrEqual(weapon, "flashbang", false) || StrEqual(weapon, "decoy", false) || StrEqual(weapon, "smokegrenade", false);
			knife = !grenade && (StrContains(weapon, "knife", false) != -1 || StrContains(weapon, "bayonet", false) != -1);
		}
		case Engine_DODS:
		{
			grenade = StrEqual(weapon, "riflegren_ger", false) || StrEqual(weapon, "riflegren_us", false) || StrEqual(weapon, "frag_ger", false) || StrEqual(weapon, "frag_us", false) || StrEqual(weapon, "smoke_ger", false) || StrEqual(weapon, "smoke_us", false);
			knife = !grenade && (StrEqual(weapon, "spade", false) || StrEqual(weapon, "amerknife", false) || StrEqual(weapon, "punch", false));
		}
		case Engine_HL2DM:
		{
			grenade = StrEqual(weapon, "grenade_frag", false);
			knife = !grenade && (StrEqual(weapon, "stunstick", false) || StrEqual(weapon, "crowbar", false));
		}
	}
}

// Announces a sound without streaks (selfkill, teamkill) to every sound set
void AnnounceToAllSets(SoundType type, const char[] phrase, int attacker, int victim, const char[] arg1, const char[] arg2)
{
	SoundEntry entry;
	for (int set = 0; set < g_iNumSets; set++)
	{
		if (GetSetSound(set, type, 0, entry))
			AnnounceToSet(set, entry, phrase, attacker, victim, arg1, arg2);
	}
}

// Plays the sound and prints the text of an entry to the human players using its set, as its config targets
void AnnounceToSet(int set, const SoundEntry entry, const char[] phrase, int attacker, int victim, const char[] arg1, const char[] arg2)
{
	int soundTargets = entry.path[0] ? entry.config & CONFIG_TARGET_BITS : 0;
	int textTargets = (entry.config >> CONFIG_TEXT_SHIFT) & CONFIG_TARGET_BITS;
	if (textTargets && !TranslationPhraseExists(phrase))
	{
		LogError("Missing translation phrase \"%s\", no text printed.", phrase);
		textTargets = 0;
	}

	if (!soundTargets && !textTargets)
		return;

	int clients[MAXPLAYERS];
	int numClients = 0;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (g_iSoundPreset[client] != set || !IsClientInGame(client) || IsFakeClient(client))
			continue;

		if (g_bSound[client] && IsTarget(soundTargets, client, attacker, victim))
			clients[numClients++] = client;

		if (g_bShowText[client] && IsTarget(textTargets, client, attacker, victim))
			PrintCenterText(client, "%t", phrase, arg1, arg2);
	}

	if (numClients)
		EmitSound(clients, numClients, entry.path, .volume = g_cvar_Volume.FloatValue);
}

bool IsTarget(int targets, int client, int attacker, int victim)
{
	return (targets & 1) || ((targets & 2) && client == attacker) || ((targets & 4) && client == victim);
}

// Resets combo/headshot streaks (not kill streaks though) on new round
void InitializeRound()
{
	g_iTotalKills = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_iConsecutiveHeadshots[i] = 0;
		g_fLastKillTime[i] = -1.0;
	}
}

// Loads QuakeSetsList config to check for sound sets
void LoadQuakeSetConfig()
{
	for (int i = 0; i < g_iNumSets; i++)
	{
		delete g_smSetSounds[i];
		delete g_aSetKillNums[i];
	}
	g_iNumSets = 0;

	char sConfigFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sConfigFile, sizeof(sConfigFile), PATH_CONFIG_QUAKE_SET);

	KeyValues kv = new KeyValues("SetsList");
	if (!kv.ImportFromFile(sConfigFile))
	{
		delete kv;
		SetFailState("ImportFromFile() failed!");
	}

	if (!kv.GotoFirstSubKey())
	{
		delete kv;
		SetFailState("GotoFirstSubKey() failed!");
	}

	do
	{
		char sSection[64];
		kv.GetSectionName(sSection, sizeof(sSection));

		if (g_iNumSets >= MAX_NUM_SETS)
		{
			LogError("Too many sound sets, \"%s\" and the next ones are ignored (max %d).", sSection, MAX_NUM_SETS);
			break;
		}

		kv.GetString("name", g_sSetName[g_iNumSets], sizeof(g_sSetName[]));
		if (!g_sSetName[g_iNumSets][0])
		{
			LogError("Could not find \"name\" in \"%s\"", sSection);
			continue;
		}

		BuildPath(Path_SM, sConfigFile, sizeof(sConfigFile), "%s/%s.cfg", PATH_CONFIG_QUAKE_SOUNDS, g_sSetName[g_iNumSets]);
		PrintToServer("[SM] Quake Sounds: Loading sound set config '%s'.", sConfigFile);
		LoadSet(sConfigFile, g_iNumSets);
		g_iNumSets++;
	} while (kv.GotoNextKey(false));

	delete kv;
}

// Loads sound file paths and configs for each sound set
void LoadSet(const char[] setFile, int set)
{
	g_smSetSounds[set] = new StringMap();
	g_aSetKillNums[set] = new ArrayList();

	KeyValues kv = new KeyValues("SoundSet");
	if (!kv.ImportFromFile(setFile))
	{
		PrintToServer("[SM] Quake Sounds: Cannot parse '%s', file not found or incorrectly structured!", setFile);
		delete kv;
		return;
	}

	char sNum[16];
	for (SoundType type = Sound_Headshot; type < Sound_Count; type++)
	{
		kv.Rewind();
		if (!kv.JumpToKey(g_sSoundSections[type]))
		{
			PrintToServer("[SM] Quake Sounds: '%s' section missing in %s.", g_sSoundSections[type], setFile);
			continue;
		}

		bool numbered = type <= Sound_LastNumbered;
		if (kv.GotoFirstSubKey() != numbered)
		{
			PrintToServer("[SM] Quake Sounds: '%s' section not configured correctly in %s.", g_sSoundSections[type], setFile);
			continue;
		}

		if (!numbered)
		{
			LoadSound(kv, set, type, 0, setFile);
			continue;
		}

		do
		{
			kv.GetSectionName(sNum, sizeof(sNum));
			int num;
			if (!StringToIntEx(sNum, num) || num < 0)
			{
				PrintToServer("[SM] Quake Sounds: invalid '%s' sub-section '%s' in %s.", g_sSoundSections[type], sNum, setFile);
				continue;
			}

			if (LoadSound(kv, set, type, num, setFile) && type == Sound_Kill)
				g_aSetKillNums[set].Push(num);
		} while (kv.GotoNextKey());
	}

	g_aSetKillNums[set].Sort(Sort_Ascending, Sort_Integer);
	delete kv;
}

// Stores the sound of the current key, precached and added to the downloads.
// Sounds turned off (config 0) are skipped, so they are not downloaded either.
bool LoadSound(KeyValues kv, int set, SoundType type, int num, const char[] setFile)
{
	SoundEntry entry;
	entry.config = kv.GetNum("config", 9);
	if (!entry.config)
		return false;

	kv.GetString("sound", entry.path, sizeof(entry.path));
	if (entry.path[0])
	{
		char sDownload[PLATFORM_MAX_PATH];
		FormatEx(sDownload, sizeof(sDownload), "sound/%s", entry.path);
		if (!FileExists(sDownload, true))
		{
			PrintToServer("[SM] Quake Sounds: File '%s' specified in '%s' does not exist in '%s', ignoring.", sDownload, g_sSoundSections[type], setFile);
			return false;
		}

		AddFileToDownloadsTable(sDownload);
		PrecacheSoundCustom(entry.path, sizeof(entry.path));
	}

	char sKey[16];
	FormatSoundKey(sKey, sizeof(sKey), type, num);
	g_smSetSounds[set].SetArray(sKey, entry, sizeof(entry));
	return true;
}

bool GetSetSound(int set, SoundType type, int num, SoundEntry entry)
{
	char sKey[16];
	FormatSoundKey(sKey, sizeof(sKey), type, num);
	return g_smSetSounds[set].GetArray(sKey, entry, sizeof(entry));
}

void FormatSoundKey(char[] buffer, int maxlen, SoundType type, int num)
{
	FormatEx(buffer, maxlen, "%d:%d", type, num);
}

// Adds specified sound to cache (and for CSGO)
void PrecacheSoundCustom(char[] soundFile, int maxLength)
{
	if (g_evGameEngine == Engine_CSGO)
	{
		Format(soundFile, maxLength, "*%s", soundFile);
		AddToStringTable(FindStringTable("soundprecache"), soundFile);
	}
	else
	{
		PrecacheSound(soundFile, true);
	}
}

void LoadDefaultPreferences(int client)
{
	g_bShowText[client] = g_cvar_Text.BoolValue;
	g_bSound[client] = g_cvar_Sound.BoolValue;
	g_iSoundPreset[client] = ClampSoundPreset(g_cvar_SoundPreset.IntValue - 1);
}

int ClampSoundPreset(int preset)
{
	return (preset >= 0 && preset < g_iNumSets) ? preset : 0;
}

void ReadClientCookies(int client)
{
	char sValue[32];
	g_cQuakeSettings.Get(client, sValue, sizeof(sValue));

	// Format is "0|0|0"
	char sParts[3][16];
	if (ExplodeString(sValue, "|", sParts, sizeof(sParts), sizeof(sParts[])) != 3)
	{
		LoadDefaultPreferences(client);
		return;
	}

	g_bShowText[client] = StringToInt(sParts[0]) != 0;
	g_bSound[client] = StringToInt(sParts[1]) != 0;
	g_iSoundPreset[client] = ClampSoundPreset(StringToInt(sParts[2]));
}

void SaveClientCookies(int client)
{
	if (!AreClientCookiesCached(client) || IsFakeClient(client))
		return;

	char sValue[32];
	FormatEx(sValue, sizeof(sValue), "%d|%d|%d", g_bShowText[client], g_bSound[client], g_iSoundPreset[client]);
	g_cQuakeSettings.Set(client, sValue);
}
