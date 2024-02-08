#include <sourcemod>
#include <sdktools>
#include <clientprefs>

#pragma semicolon 1
#pragma newdecls required

#define ANNOUNCE_DELAY				30.0
#define JOIN_DELAY					2.0

#define MAX_NUM_SETS				255
#define MAX_NUM_KILLS				50

#define PATH_CONFIG_QUAKE_SET		"configs/quake/sets.cfg"
#define PATH_CONFIG_QUAKE_SOUNDS	"configs/quake/sets"

public Plugin myinfo = {
	name = "Quake Sounds",
	author = "Spartan_C001, maxime1907, .Rushaway",
	description = "Plays sounds based on events that happen in game.",
	version = "4.1.1",
	url = "http://steamcommunity.com/id/spartan_c001/",
}

// Sound Sets
int g_iNumSets = 0;
char g_sSetsName[MAX_NUM_SETS][PLATFORM_MAX_PATH];

// Sound Files
char headshotSound[MAX_NUM_SETS][MAX_NUM_KILLS][PLATFORM_MAX_PATH];
char grenadeSound[MAX_NUM_SETS][PLATFORM_MAX_PATH];
char selfkillSound[MAX_NUM_SETS][PLATFORM_MAX_PATH];
char roundplaySound[MAX_NUM_SETS][PLATFORM_MAX_PATH];
char knifeSound[MAX_NUM_SETS][PLATFORM_MAX_PATH];
char killSound[MAX_NUM_SETS][MAX_NUM_KILLS][PLATFORM_MAX_PATH];
char firstbloodSound[MAX_NUM_SETS][PLATFORM_MAX_PATH];
char teamkillSound[MAX_NUM_SETS][PLATFORM_MAX_PATH];
char comboSound[MAX_NUM_SETS][MAX_NUM_KILLS][PLATFORM_MAX_PATH];
char joinSound[MAX_NUM_SETS][PLATFORM_MAX_PATH];

// Sound Configs
int headshotConfig[MAX_NUM_SETS][MAX_NUM_KILLS];
int grenadeConfig[MAX_NUM_SETS];
int selfkillConfig[MAX_NUM_SETS];
int roundplayConfig[MAX_NUM_SETS];
int knifeConfig[MAX_NUM_SETS];
int killConfig[MAX_NUM_SETS][MAX_NUM_KILLS];
int firstbloodConfig[MAX_NUM_SETS];
int teamkillConfig[MAX_NUM_SETS];
int comboConfig[MAX_NUM_SETS][MAX_NUM_KILLS];
int joinConfig[MAX_NUM_SETS];
float g_fVolume = 1.0;

// Kill Streaks
int g_iTotalKills = 0;
int g_iConsecutiveKills[MAXPLAYERS+1];
int g_iComboScore[MAXPLAYERS+1];
int g_iConsecutiveHeadshots[MAXPLAYERS+1];
float g_fLastKillTime[MAXPLAYERS+1];

// Preferences
Handle g_hShowText = INVALID_HANDLE, g_hSound = INVALID_HANDLE, g_hSoundPreset = INVALID_HANDLE;
int g_iShowText[MAXPLAYERS + 1] = {0, ...}, g_iSound[MAXPLAYERS + 1] = {0, ...}, g_iSoundPreset[MAXPLAYERS + 1] = {0, ...};

ConVar g_cvar_Announce;
ConVar g_cvar_Text;
ConVar g_cvar_Sound;
ConVar g_cvar_SoundPreset;
ConVar g_cvar_Volume;
ConVar g_cvar_TeamKillMode;
ConVar g_cvar_ComboTime;

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

	g_hShowText = RegClientCookie("quakesounds_texts", "Display text", CookieAccess_Private);
	g_hSound = RegClientCookie("quakesounds_sounds", "Enable sounds", CookieAccess_Private);
	g_hSoundPreset = RegClientCookie("quakesounds_sound_preset", "Sound preset", CookieAccess_Private);

	SetCookieMenuItem(CookieMenu_QuakeSounds, INVALID_HANDLE, "Quake Sound Settings");

	RegConsoleCmd("sm_quake", Command_QuakeSounds);

	HookGameEvents();

	AutoExecConfig(true);

	// Late load
	if (g_bLate)
	{
		InitializeRound();
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i))
			{
				OnClientPostAdminCheck(i);
			}
		}
	}
}

public void OnMapStart()
{
	LoadQuakeSetConfig();
	if (g_evGameEngine == Engine_HL2DM)
	{
		InitializeRound();
	}
}

public void OnConfigsExecuted()
{
	g_fVolume = g_cvar_Volume.FloatValue;
}

public void OnClientPostAdminCheck(int client)
{
	g_iConsecutiveKills[client] = 0;
	g_fLastKillTime[client] = -1.0;
	g_iConsecutiveHeadshots[client] = 0;

	if (AreClientCookiesCached(client))
		ReadClientCookies(client);

	if (GetConVarBool(g_cvar_Announce))
		CreateTimer(ANNOUNCE_DELAY, Timer_Announce, client);

	CreateTimer(JOIN_DELAY, Timer_JoinCheck, client, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
	SetClientCookies(client);
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
	switch (action)
	{
		case CookieMenuAction_SelectOption:
		{
			DisplayCookieMenu(client);
		}
	}
}

public void DisplayCookieMenu(int client)
{
	Menu menu = new Menu(MenuHandler_QuakeSounds, MENU_ACTIONS_DEFAULT | MenuAction_DisplayItem);
	menu.ExitBackButton = true;
	menu.ExitButton = true;

	char sBuffer[100];
	Format(sBuffer, sizeof(sBuffer), "%T", "quake menu", client);
	SetMenuTitle(menu, sBuffer);

	Format(sBuffer, sizeof(sBuffer), "%T", g_iShowText[client] ? "disable text" : "enable text", client);
	AddMenuItem(menu, "text pref", sBuffer);

	Format(sBuffer, sizeof(sBuffer), "%T",  g_iSound[client] ? "sounds disable" : "sounds enable", client);
	AddMenuItem(menu, "no sounds", sBuffer);

	char sBufferSoundPack[64];
	Format(sBufferSoundPack, sizeof(sBufferSoundPack), "%T", "sound pack", client);
	char sBufferSoundPackOption[64];
	if (g_iSoundPreset[client] < g_iNumSets)
		Format(sBufferSoundPackOption, sizeof(sBufferSoundPackOption), "%T", g_sSetsName[g_iSoundPreset[client]], client);
	else
		Format(sBufferSoundPackOption, sizeof(sBufferSoundPackOption), "%s", "Error");
	Format(sBuffer, sizeof(sBuffer), "%s: %s", sBufferSoundPack, sBufferSoundPackOption);
	AddMenuItem(menu, "sound set", sBuffer);

	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_QuakeSounds(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
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
					g_iShowText[param1] = g_iShowText[param1] ? 0 : 1;
				}
				case 1:
				{
					g_iSound[param1] = g_iSound[param1] ? 0 : 1;
				}
				case 2:
				{
					g_iSoundPreset[param1]++;
					if (g_iSoundPreset[param1] >= g_iNumSets)
						g_iSoundPreset[param1] = 0;
				}
			}
			DisplayMenu(menu, param1, MENU_TIME_FOREVER);
		}
		case MenuAction_DisplayItem:
		{
			char sBuffer[32];
			switch(param2)
			{
				case 0:
				{
					Format(sBuffer, sizeof(sBuffer), "%T", g_iShowText[param1] ? "disable text" : "enable text", param1);
				}
				case 1:
				{
					Format(sBuffer, sizeof(sBuffer), "%T",  g_iSound[param1] ? "sounds disable" : "sounds enable", param1);
				}
				case 2:
				{
					char sBufferSoundPack[64];
					Format(sBufferSoundPack, sizeof(sBufferSoundPack), "%T", "sound pack", param1);
					char sBufferSoundPackOption[64];
					Format(sBufferSoundPack, sizeof(sBufferSoundPack), "%T", "sound pack", param1);
					if (g_iSoundPreset[param1] < g_iNumSets)
						Format(sBufferSoundPackOption, sizeof(sBufferSoundPackOption), "%T", g_sSetsName[g_iSoundPreset[param1]], param1);
					else
						Format(sBufferSoundPackOption, sizeof(sBufferSoundPackOption), "%s", "Error");
					Format(sBuffer, sizeof(sBuffer), "%s: %s", sBufferSoundPack, sBufferSoundPackOption);
				}
			}
			return RedrawMenuItem(sBuffer);
		}
	}
	return 0;
}

// Hooks correct game events
public void HookGameEvents()
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
			HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
		}
		default:
		{
			HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
		}
	}
}

// Loads QuakeSetsList config to check for sound sets
public void LoadQuakeSetConfig()
{
	char sConfigFile[PLATFORM_MAX_PATH];

	KeyValues KvConfig = new KeyValues("SetsList");

	BuildPath(Path_SM, sConfigFile, PLATFORM_MAX_PATH, PATH_CONFIG_QUAKE_SET);

	if (!KvConfig.ImportFromFile(sConfigFile))
	{
		delete KvConfig;
		SetFailState("ImportFromFile() failed!");
		return;
	}
	KvConfig.Rewind();

	if (!KvConfig.GotoFirstSubKey())
	{
		delete KvConfig;
		SetFailState("GotoFirstSubKey() failed!");
		return;
	}

	g_iNumSets = 0;

	do
	{
		char sSection[64];
		KvConfig.GetSectionName(sSection, sizeof(sSection));

		char sSoundSet[64];
		KvConfig.GetString("name", sSoundSet, sizeof(sSoundSet));
		if (!sSoundSet[0])
		{
			LogError("Could not find \"name\" in \"%s\"", sSection);
			continue;
		}

		g_sSetsName[g_iNumSets] = sSoundSet;

		BuildPath(Path_SM, sConfigFile, sizeof(sConfigFile), "%s/%s.cfg", PATH_CONFIG_QUAKE_SOUNDS, g_sSetsName[g_iNumSets]);
		PrintToServer("[SM] Quake Sounds: Loading sound set config '%s'.", sConfigFile);
		LoadSet(sConfigFile, g_iNumSets);
		g_iNumSets++;
	} while(KvConfig.GotoNextKey(false));

	delete KvConfig;
}

// Loads sound file paths and configs for each sound set
public void LoadSet(char[] setFile, int setNum)
{
	char sBuffer[PLATFORM_MAX_PATH];
	Handle SetFileKV = CreateKeyValues("SoundSet");
	if (FileToKeyValues(SetFileKV, setFile))
	{
		if (KvJumpToKey(SetFileKV, "headshot"))
		{
			if (KvGotoFirstSubKey(SetFileKV))
			{
				do
				{
					KvGetSectionName(SetFileKV, sBuffer, sizeof(sBuffer));
					int killNum = StringToInt(sBuffer);
					if (killNum >= 0)
					{
						KvGetString(SetFileKV, "sound", headshotSound[setNum][killNum], sizeof(sBuffer));
						headshotConfig[setNum][killNum] = KvGetNum(SetFileKV, "config", 9);
						Format(sBuffer, sizeof(sBuffer), "sound/%s", headshotSound[setNum][killNum]);
						if (FileExists(sBuffer, true))
						{
							PrecacheSoundCustom(headshotSound[setNum][killNum], PLATFORM_MAX_PATH);
							AddFileToDownloadsTable(sBuffer);
						}
						else
						{
							headshotConfig[setNum][killNum] = 0;
							PrintToServer("[SM] Quake Sounds: File specified in 'headshot %i' does not exist in '%s', ignoring.", killNum, setFile);
						}
					}
				} while (KvGotoNextKey(SetFileKV));
				KvGoBack(SetFileKV);
			}
			else
			{
				PrintToServer("[SM] Quake Sounds: 'headshot' section not configured correctly in %s.", setFile);
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'headshot' section missing in %s.", setFile);
		}
		KvRewind(SetFileKV);
		if (KvJumpToKey(SetFileKV,"grenade"))
		{
			if (KvGotoFirstSubKey(SetFileKV))
			{
				PrintToServer("[SM] Quake Sounds: 'grenade' section not configured correctly in %s.", setFile);
				KvGoBack(SetFileKV);
			}
			else
			{
				KvGetString(SetFileKV, "sound", grenadeSound[setNum], sizeof(sBuffer));
				grenadeConfig[setNum] = KvGetNum(SetFileKV, "config", 9);
				Format(sBuffer, sizeof(sBuffer), "sound/%s", grenadeSound[setNum]);
				if (FileExists(sBuffer, true))
				{
					PrecacheSoundCustom(grenadeSound[setNum], PLATFORM_MAX_PATH);
					AddFileToDownloadsTable(sBuffer);
				}
				else
				{
					grenadeConfig[setNum] = 0;
					PrintToServer("[SM] Quake Sounds: File specified in 'grenade' does not exist in '%s', ignoring.", setFile);
				}
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'grenade' section missing in %s.", setFile);
		}
		KvRewind(SetFileKV);
		if (KvJumpToKey(SetFileKV, "selfkill"))
		{
			if (KvGotoFirstSubKey(SetFileKV))
			{
				PrintToServer("[SM] Quake Sounds: 'selfkill' section not configured correctly in %s.", setFile);
				KvGoBack(SetFileKV);
			}
			else
			{
				KvGetString(SetFileKV, "sound", selfkillSound[setNum], sizeof(sBuffer));
				selfkillConfig[setNum] = KvGetNum(SetFileKV, "config", 9);
				Format(sBuffer, sizeof(sBuffer), "sound/%s", selfkillSound[setNum]);
				if (FileExists(sBuffer, true))
				{
					PrecacheSoundCustom(selfkillSound[setNum], PLATFORM_MAX_PATH);
					AddFileToDownloadsTable(sBuffer);
				}
				else
				{
					selfkillConfig[setNum] = 0;
					PrintToServer("[SM] Quake Sounds: File specified in 'selfkill' does not exist in '%s', ignoring.", setFile);
				}
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'selfkill' section missing in %s.", setFile);
		}
		KvRewind(SetFileKV);
		if (KvJumpToKey(SetFileKV,"round play"))
		{
			if (KvGotoFirstSubKey(SetFileKV))
			{
				PrintToServer("[SM] Quake Sounds: 'round play' section not configured correctly in %s.", setFile);
				KvGoBack(SetFileKV);
			}
			else
			{
				KvGetString(SetFileKV, "sound", roundplaySound[setNum], sizeof(sBuffer));
				roundplayConfig[setNum] = KvGetNum(SetFileKV, "config", 9);
				Format(sBuffer, sizeof(sBuffer), "sound/%s", roundplaySound[setNum]);
				if (FileExists(sBuffer, true))
				{
					PrecacheSoundCustom(roundplaySound[setNum], PLATFORM_MAX_PATH);
					AddFileToDownloadsTable(sBuffer);
				}
				else
				{
					roundplayConfig[setNum] = 0;
					PrintToServer("[SM] Quake Sounds: File specified in 'round play' does not exist in '%s', ignoring.", setFile);
				}
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'round play' section missing in %s.", setFile);
		}
		KvRewind(SetFileKV);
		if (KvJumpToKey(SetFileKV, "knife"))
		{
			if (KvGotoFirstSubKey(SetFileKV))
			{
				PrintToServer("[SM] Quake Sounds: 'knife' section not configured correctly in %s.", setFile);
				KvGoBack(SetFileKV);
			}
			else
			{
				KvGetString(SetFileKV, "sound", knifeSound[setNum], sizeof(sBuffer));
				knifeConfig[setNum] = KvGetNum(SetFileKV, "config", 9);
				Format(sBuffer, sizeof(sBuffer), "sound/%s", knifeSound[setNum]);
				if (FileExists(sBuffer, true))
				{
					PrecacheSoundCustom(knifeSound[setNum], PLATFORM_MAX_PATH);
					AddFileToDownloadsTable(sBuffer);
				}
				else
				{
					knifeConfig[setNum] = 0;
					PrintToServer("[SM] Quake Sounds: File specified in 'knife' does not exist in '%s', ignoring.", setFile);
				}
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'knife' section missing in %s.", setFile);
		}
		KvRewind(SetFileKV);
		if (KvJumpToKey(SetFileKV, "killsound"))
		{
			if (KvGotoFirstSubKey(SetFileKV))
			{
				do
				{
					KvGetSectionName(SetFileKV, sBuffer, sizeof(sBuffer));
					int killNum = StringToInt(sBuffer);
					if (killNum >= 0)
					{
						KvGetString(SetFileKV, "sound", killSound[setNum][killNum], sizeof(sBuffer));
						killConfig[setNum][killNum] = KvGetNum(SetFileKV, "config", 9);
						Format(sBuffer, sizeof(sBuffer), "sound/%s", killSound[setNum][killNum]);
						if (FileExists(sBuffer, true))
						{
							PrecacheSoundCustom(killSound[setNum][killNum], PLATFORM_MAX_PATH);
							AddFileToDownloadsTable(sBuffer);
						}
						else
						{
							killConfig[setNum][killNum] = 0;
							PrintToServer("[SM] Quake Sounds: File specified in 'killsound %i' does not exist in '%s', ignoring.", killNum, setFile);
						}
					}
				} while (KvGotoNextKey(SetFileKV));
				KvGoBack(SetFileKV);
			}
			else
			{
				PrintToServer("[SM] Quake Sounds: 'killsound' section not configured correctly in %s.", setFile);
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'killsound' section missing in %s.", setFile);
		}
		KvRewind(SetFileKV);
		if (KvJumpToKey(SetFileKV, "first blood"))
		{
			if (KvGotoFirstSubKey(SetFileKV))
			{
				PrintToServer("[SM] Quake Sounds: 'first blood' section not configured correctly in %s.", setFile);
				KvGoBack(SetFileKV);
			}
			else
			{
				KvGetString(SetFileKV, "sound", firstbloodSound[setNum], sizeof(sBuffer));
				firstbloodConfig[setNum] = KvGetNum(SetFileKV, "config", 9);
				Format(sBuffer, sizeof(sBuffer), "sound/%s", firstbloodSound[setNum]);
				if (FileExists(sBuffer, true))
				{
					PrecacheSoundCustom(firstbloodSound[setNum], sizeof(sBuffer));
					AddFileToDownloadsTable(sBuffer);
				}
				else
				{
					firstbloodConfig[setNum] = 0;
					PrintToServer("[SM] Quake Sounds: File specified in 'first blood' does not exist in '%s', ignoring.", setFile);
				}
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'first blood' section missing in %s.", setFile);
		}
		KvRewind(SetFileKV);
		if (KvJumpToKey(SetFileKV,"teamkill"))
		{
			if (KvGotoFirstSubKey(SetFileKV))
			{
				PrintToServer("[SM] Quake Sounds: 'teamkill' section not configured correctly in %s.", setFile);
				KvGoBack(SetFileKV);
			}
			else
			{
				KvGetString(SetFileKV, "sound", teamkillSound[setNum], sizeof(sBuffer));
				teamkillConfig[setNum] = KvGetNum(SetFileKV, "config", 9);
				Format(sBuffer, sizeof(sBuffer), "sound/%s", teamkillSound[setNum]);
				if (FileExists(sBuffer, true))
				{
					PrecacheSoundCustom(teamkillSound[setNum], sizeof(sBuffer));
					AddFileToDownloadsTable(sBuffer);
				}
				else
				{
					teamkillConfig[setNum] = 0;
					PrintToServer("[SM] Quake Sounds: File specified in 'teamkill' does not exist in '%s', ignoring.", setFile);
				}
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'teamkill' section missing in %s.", setFile);
		}
		KvRewind(SetFileKV);
		if (KvJumpToKey(SetFileKV, "combo"))
		{
			if (KvGotoFirstSubKey(SetFileKV))
			{
				do
				{
					KvGetSectionName(SetFileKV, sBuffer, sizeof(sBuffer));
					int killNum = StringToInt(sBuffer);
					if (killNum >= 0)
					{
						KvGetString(SetFileKV, "sound", comboSound[setNum][killNum], sizeof(sBuffer));
						comboConfig[setNum][killNum] = KvGetNum(SetFileKV, "config", 9);
						Format(sBuffer, sizeof(sBuffer), "sound/%s", comboSound[setNum][killNum]);
						if (FileExists(sBuffer, true))
						{
							PrecacheSoundCustom(comboSound[setNum][killNum], sizeof(sBuffer));
							AddFileToDownloadsTable(sBuffer);
						}
						else
						{
							comboConfig[setNum][killNum] = 0;
							PrintToServer("[SM] Quake Sounds: File specified in 'combo %i' does not exist in '%s', ignoring.", killNum, setFile);
						}
					}
				} while (KvGotoNextKey(SetFileKV));
				KvGoBack(SetFileKV);
			}
			else
			{
				PrintToServer("[SM] Quake Sounds: 'combo' section not configured correctly in %s.", setFile);
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'combo' section missing in %s.", setFile);
		}
		KvRewind(SetFileKV);
		if (KvJumpToKey(SetFileKV,"join server"))
		{
			if (KvGotoFirstSubKey(SetFileKV))
			{
				PrintToServer("[SM] Quake Sounds: 'join server' section not configured correctly in %s.", setFile);
				KvGoBack(SetFileKV);
			}
			else
			{
				KvGetString(SetFileKV, "sound", joinSound[setNum], sizeof(sBuffer));
				joinConfig[setNum] = KvGetNum(SetFileKV, "config", 9);
				Format(sBuffer, sizeof(sBuffer), "sound/%s", joinSound[setNum]);
				if (FileExists(sBuffer, true))
				{
					PrecacheSoundCustom(joinSound[setNum], PLATFORM_MAX_PATH);
					AddFileToDownloadsTable(sBuffer);
				}
				else
				{
					joinConfig[setNum] = 0;
					PrintToServer("[SM] Quake Sounds: File specified in 'join server' does not exist in '%s', ignoring.", setFile);
				}
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'join server' section missing in %s.", setFile);
		}
	}
	else
	{
		PrintToServer("[SM] Quake Sounds: Cannot parse '%s', file not found or incorrectly structured!", setFile);
	}
	CloseHandle(SetFileKV);
}

// ##     ##  #######   #######  ##    ##  ######  
// ##     ## ##     ## ##     ## ##   ##  ##    ## 
// ##     ## ##     ## ##     ## ##  ##   ##       
// ######### ##     ## ##     ## #####     ######  
// ##     ## ##     ## ##     ## ##  ##         ## 
// ##     ## ##     ## ##     ## ##   ##  ##    ## 
// ##     ##  #######   #######  ##    ##  ######  

public Action Timer_JoinCheck(Handle timer, any client)
{
	if (!IsClientConnected(client))
		return Plugin_Stop;

	if (IsClientInGame(client) && AreClientCookiesCached(client))
	{
		if (g_iSound[client])
		{
			for (int i = 1; i < MAX_NUM_SETS; i++)
			{
				if (strcmp(joinSound[g_iSoundPreset[client]], "", false) != 0)
				{
					if (joinConfig[g_iSoundPreset[client]] & i)
					{
						EmitSoundCustom(client, joinSound[g_iSoundPreset[client]], _, _, _, _, g_fVolume);
						break;
					}
				}
				else
					break;
			}
		}
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action Timer_Announce(Handle timer, any client)
{
	if (IsClientInGame(client))
	{
		PrintToChat(client, "%t", "announce message");
	}
	return Plugin_Continue;
}

// Plays round play sound depending on each players config and the text display
public void Event_RoundFreezeEnd(Handle event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && g_iSound[i])
		{
			if (strcmp(roundplaySound[g_iSoundPreset[i]], "", false) != 0 && (roundplayConfig[g_iSoundPreset[i]] & 1) || (roundplayConfig[g_iSoundPreset[i]] & 2) || (roundplayConfig[g_iSoundPreset[i]] & 4))
			{
				EmitSoundCustom(i, roundplaySound[g_iSoundPreset[i]], _, _, _, _, g_fVolume);
			}
			if (g_iShowText[i] && (roundplayConfig[g_iSoundPreset[i]] & 8) || (roundplayConfig[g_iSoundPreset[i]] & 16) || (roundplayConfig[g_iSoundPreset[i]] & 32))
			{
				PrintCenterText(i, "%t", "round play");
			}
		}
	}
}

public void Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	if (g_evGameEngine != Engine_HL2DM)
	{
		InitializeRound();
	}
}

// Important bit - does all kill/combo/custom kill sounds and things!
public Action Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int victimClient = GetClientOfUserId(GetEventInt(event,"userid"));

	if (victimClient < 1 || victimClient > MaxClients)
		return Plugin_Continue;

	int attackerClient = GetClientOfUserId(GetEventInt(event,"attacker"));
	if (attackerClient < 0 || attackerClient > MaxClients)
		return Plugin_Continue;

	char victimName[MAX_NAME_LENGTH], attackerName[MAX_NAME_LENGTH], sBuffer[256];
	GetClientName(attackerClient, attackerName, MAX_NAME_LENGTH);
	GetClientName(victimClient, victimName, MAX_NAME_LENGTH);

	if (attackerClient == victimClient || attackerClient == 0)
	{
		g_iConsecutiveKills[attackerClient] = 0;
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i) && 0)
			{
				int soundPreset = g_iSoundPreset[i];
				int soundConfig = selfkillConfig[soundPreset];
				char sound[PLATFORM_MAX_PATH];
				sound = selfkillSound[soundPreset];

				if ((strcmp(sound, "", false) != 0) && (soundConfig & 1) || ((soundConfig & 2) && attackerClient == i) || ((soundConfig & 4) && victimClient == i))
					EmitSoundCustom(i, sound, _, _, _, _, g_fVolume);

				if (g_iShowText[i] && ((soundConfig & 8) || ((soundConfig & 16) && attackerClient == i) || ((soundConfig & 32) && victimClient == i)))
					PrintCenterText(i, "%t", "selfkill", victimName);
			}
		}
	}
	else if (GetClientTeam(attackerClient) == GetClientTeam(victimClient) && !GetConVarBool(g_cvar_TeamKillMode))
	{
		g_iConsecutiveKills[attackerClient] = 0;
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i) && g_iSound[i])
			{
				int soundPreset = g_iSoundPreset[i];
				int soundConfig = selfkillConfig[soundPreset];
				char sound[PLATFORM_MAX_PATH];
				sound = teamkillSound[soundPreset];

				if (strcmp(sound, "", false) != 0 && (soundConfig & 1) || ((soundConfig & 2) && attackerClient == i) || ((soundConfig & 4) && victimClient == i))
					EmitSoundCustom(i, sound, _, _, _, _, g_fVolume);

				if (g_iShowText[i] && ((soundConfig & 8) || ((soundConfig & 16) && attackerClient == i) || ((soundConfig & 32) && victimClient == i)))
					PrintCenterText(i, "%t", "teamkill", attackerName, victimName);
			}
		}
	}
	else
	{
		g_iTotalKills++;
		g_iConsecutiveKills[attackerClient]++;
		bool firstblood = false;
		bool headshot = false;
		bool knife = false;
		bool grenade = false;
		bool combo = false;
		int customkill = -1;

		char weapon[64];
		GetEventString(event, "weapon", weapon, sizeof(weapon));

		if (g_evGameEngine == Engine_CSS || g_evGameEngine == Engine_CSGO)
			headshot = GetEventBool(event,"headshot");
		else if (g_evGameEngine == Engine_TF2)
		{
			customkill = GetEventInt(event,"customkill");
			if (customkill == 1)
				headshot = true;
		}

		if (headshot)
			g_iConsecutiveHeadshots[attackerClient]++;

		float fLastKillTimeTmp = g_fLastKillTime[attackerClient];
		g_fLastKillTime[attackerClient] = GetEngineTime();
		
		if (fLastKillTimeTmp == -1.0 || (g_fLastKillTime[attackerClient] - fLastKillTimeTmp) > GetConVarFloat(g_cvar_ComboTime))
		{
			g_iComboScore[attackerClient] = 1;
			combo = false;
		}
		else
		{
			g_iComboScore[attackerClient]++;
			combo = true;
		}

		if (g_iTotalKills == 1)
			firstblood = true;

		if (g_evGameEngine == Engine_TF2 && customkill == 2)
			knife = true;

		else if (g_evGameEngine == Engine_CSS)
		{
			
			if (strcmp(weapon, "hegrenade", false) == 0 || strcmp(weapon, "smokegrenade", false) == 0 || strcmp(weapon, "flashbang", false) == 0)
				grenade = true;
			else if (StrContains(weapon, "knife", false) != -1)
				knife = true;
		}
		else if (g_evGameEngine == Engine_CSGO)
		{
			if (strcmp(weapon, "inferno", false) == 0 || strcmp(weapon, "hegrenade", false) == 0 || strcmp(weapon, "flashbang", false) == 0 || strcmp(weapon, "decoy", false) == 0 || strcmp(weapon, "smokegrenade", false) == 0)
				grenade = true;
			else if (StrContains(weapon, "knife", false) != -1 || StrContains(weapon, "bayonet", false) != -1)
				knife = true;
		}
		else if (g_evGameEngine == Engine_DODS)
		{
			
			if (strcmp(weapon, "riflegren_ger", false) == 0 || strcmp(weapon, "riflegren_us", false) == 0 || strcmp(weapon, "frag_ger", false) == 0 || strcmp(weapon, "frag_us", false) == 0 || strcmp(weapon, "smoke_ger", false) == 0 || strcmp(weapon, "smoke_us", false) == 0)
				grenade = true;
			else if (strcmp(weapon, "spade", false) == 0 || strcmp(weapon, "amerknife", false) == 0 || strcmp(weapon, "punch", false) == 0)
				knife = true;
		}
		else if (g_evGameEngine == Engine_HL2DM)
		{
			if (strcmp(weapon, "grenade_frag", false) == 0)
				grenade = true;
			else if (strcmp(weapon,"stunstick", false) == 0 || strcmp(weapon,"crowbar", false) == 0)
				knife = true;
		}
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i) && g_iSound[i])
			{
				int iComboScore = g_iComboScore[attackerClient];
				int iConsecutiveKills = g_iConsecutiveKills[attackerClient];
				int soundPreset = g_iSoundPreset[i];
				int iFirstBConfig = firstbloodConfig[soundPreset];
				int iHeadShotConfig = headshotConfig[soundPreset][iConsecutiveKills];
				int iConsecutiveHeadshots = g_iConsecutiveHeadshots[attackerClient];
				int iConsecutiveHSConfig = headshotConfig[soundPreset][iConsecutiveHeadshots];
				int iKnifeConfig = knifeConfig[soundPreset];
				int iGrenadeConfig = grenadeConfig[soundPreset];
				int iKillConfig = killConfig[soundPreset][iConsecutiveKills];
				int iComboConfig = comboConfig[soundPreset][iComboScore];

				char sFirstBSound[PLATFORM_MAX_PATH], sHeadShotSound[PLATFORM_MAX_PATH], sComboSound[PLATFORM_MAX_PATH];
				char sKnifeSound[PLATFORM_MAX_PATH], sGrenadeSound[PLATFORM_MAX_PATH], sKillSound[PLATFORM_MAX_PATH];
				sFirstBSound = firstbloodSound[soundPreset];
				sHeadShotSound = headshotSound[soundPreset][iConsecutiveHeadshots];
				sComboSound = comboSound[soundPreset][iComboScore];
				sKnifeSound = knifeSound[soundPreset];
				sGrenadeSound = grenadeSound[soundPreset];
				sKillSound = killSound[soundPreset][iConsecutiveKills];

				if (firstblood && iFirstBConfig > 0)
				{
					if (strcmp(sFirstBSound, "", false) != 0 && (iFirstBConfig & 1) || ((iFirstBConfig & 2) && attackerClient == i) || ((iFirstBConfig & 4) && victimClient == i))
						EmitSoundCustom(i, sFirstBSound, _, _, _, _, g_fVolume);

					if (g_iShowText[i] && ((iFirstBConfig & 8) || ((iFirstBConfig & 16) && attackerClient == i) || ((iFirstBConfig & 32) && victimClient == i)))
						PrintCenterText(i, "%t", "first blood", attackerName);
				}

				else if (headshot && iHeadShotConfig > 0)
				{
					if (strcmp(sHeadShotSound, "", false) != 0 && (iHeadShotConfig & 1) || ((iHeadShotConfig & 2) && attackerClient == i) || ((iHeadShotConfig & 4) && victimClient == i))
						EmitSoundCustom(i, sHeadShotSound, _, _, _, _, g_fVolume);
					
					if (g_iShowText[i] && ((iHeadShotConfig & 8) || ((iHeadShotConfig & 16) && attackerClient == i) || ((iHeadShotConfig & 32) && victimClient == i)))
						PrintCenterText(i, "%t", "headshot", attackerName);
				}

				else if (headshot && iConsecutiveHeadshots < MAX_NUM_KILLS && iConsecutiveHSConfig > 0)
				{
					if (strcmp(sHeadShotSound, "", false) != 0 && (iConsecutiveHSConfig & 1) || ((iConsecutiveHSConfig & 2) && attackerClient == i) || ((iConsecutiveHSConfig & 4) && victimClient == i))
						EmitSoundCustom(i, sHeadShotSound, _, _, _, _, g_fVolume);

					if (g_iShowText[i] && iConsecutiveHeadshots < MAX_NUM_KILLS && ((iConsecutiveHSConfig & 8) || ((iConsecutiveHSConfig & 16) && attackerClient == i) || ((iConsecutiveHSConfig & 32) && victimClient == i)))
					{
						Format(sBuffer, sizeof(sBuffer), "headshot %i", iConsecutiveHeadshots);
						PrintCenterText(i, "%t", sBuffer, attackerName);
					}
				}

				else if (knife && iKnifeConfig > 0)
				{
					if (strcmp(sKnifeSound, "", false) != 0 && (iKnifeConfig & 1) || ((iKnifeConfig & 2) && attackerClient == i) || ((iKnifeConfig & 4) && victimClient == i))
						EmitSoundCustom(i, sKnifeSound, _, _, _, _, g_fVolume);

					if (g_iShowText[i] && ((iKnifeConfig & 8) || ((iKnifeConfig & 16) && attackerClient == i) || ((iKnifeConfig & 32) && victimClient == i)))
						PrintCenterText(i, "%t", "knife", attackerName, victimName);
				}

				else if (grenade && iGrenadeConfig > 0)
				{
					if (strcmp(sGrenadeSound, "", false) != 0 && (iGrenadeConfig & 1) || ((iGrenadeConfig & 2) && attackerClient == i) || ((iGrenadeConfig & 4) && victimClient == i))
						EmitSoundCustom(i, sGrenadeSound, _, _, _, _, g_fVolume);

					if (g_iShowText[i] && ((iGrenadeConfig & 8) || ((iGrenadeConfig & 16) && attackerClient == i) || ((iGrenadeConfig & 32) && victimClient == i)))
						PrintCenterText(i, "%t", "grenade", attackerName, victimName);
				}

				else if (combo && iComboScore < MAX_NUM_KILLS && iComboConfig > 0)
				{
					if (strcmp(sComboSound, "", false) != 0 && (iComboConfig & 1) || ((iComboConfig & 2) && attackerClient == i) || ((iComboConfig & 4) && victimClient == i))
						EmitSoundCustom(i, sComboSound, _, _, _, _, g_fVolume);

					if (g_iShowText[i] && g_iComboScore[attackerClient] < MAX_NUM_KILLS && ((iComboConfig & 8) || ((iComboConfig & 16) && attackerClient == i) || ((iComboConfig & 32) && victimClient == i)))
					{
						Format(sBuffer, sizeof(sBuffer), "combo %i", g_iComboScore[attackerClient]);
						PrintCenterText(i, "%t", sBuffer, attackerName);
					}
				}

				else
				{
					if (iConsecutiveKills < MAX_NUM_KILLS && strcmp(sKillSound, "", false) != 0 && (iKillConfig & 1) || ((iKillConfig & 2) && attackerClient == i) || ((iKillConfig & 4) && victimClient == i))
						EmitSoundCustom(i, sKillSound, _, _, _, _, g_fVolume);

					if (g_iShowText[i] && g_iConsecutiveKills[attackerClient] < MAX_NUM_KILLS && ((iKillConfig & 8) || ((iKillConfig & 16) && attackerClient == i) || ((iKillConfig & 32) && victimClient == i)))
					{
						Format(sBuffer, sizeof(sBuffer), "killsound %i", g_iConsecutiveKills[attackerClient]);
						PrintCenterText(i, "%t", sBuffer, attackerName);
					}
				}
			}
		}
	}
	g_iConsecutiveKills[victimClient] = 0;
	g_iConsecutiveHeadshots[victimClient] = 0;

	return Plugin_Continue;
}

// ######## ##     ## ##    ##  ######  ######## ####  #######  ##    ##  ######  
// ##       ##     ## ###   ## ##    ##    ##     ##  ##     ## ###   ## ##    ## 
// ##       ##     ## ####  ## ##          ##     ##  ##     ## ####  ## ##       
// ######   ##     ## ## ## ## ##          ##     ##  ##     ## ## ## ##  ######  
// ##       ##     ## ##  #### ##          ##     ##  ##     ## ##  ####       ## 
// ##       ##     ## ##   ### ##    ##    ##     ##  ##     ## ##   ### ##    ## 
// ##        #######  ##    ##  ######     ##    ####  #######  ##    ##  ######

// Resets combo/headshot streaks (not kill streaks though) on new round
public void InitializeRound()
{
	g_iTotalKills = 0;
	for (int i = 1; i <= MaxClients; i++) 
	{
		g_iConsecutiveHeadshots[i] = 0;
		g_fLastKillTime[i] = -1.0;
	}
}

// Adds specified sound to cache (and for CSGO)
stock void PrecacheSoundCustom(char[] soundFile, int maxLength)
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

// Custom EmitSound to allow compatibility with all game engines
stock void EmitSoundCustom(int client, const char[] sound, int entity=SOUND_FROM_PLAYER, int channel=SNDCHAN_AUTO, int level=SNDLEVEL_NORMAL, int flags=SND_NOFLAGS, float volume=SNDVOL_NORMAL, int pitch=SNDPITCH_NORMAL, int speakerentity=-1, const float origin[3]=NULL_VECTOR, const float dir[3]=NULL_VECTOR, bool updatePos=true, float soundtime=0.0)
{
	int iClients[1];
	iClients[0] = client;
	EmitSound(iClients, 1, sound, entity, channel, level, flags, volume, pitch, speakerentity, origin, dir, updatePos, soundtime);
}

public void ReadClientCookies(int client)
{
	char sValue[8];
	GetClientCookie(client, g_hShowText, sValue, sizeof(sValue));
	g_iShowText[client] = (sValue[0] == '\0' ? GetConVarInt(g_cvar_Text) : StringToInt(sValue));

	GetClientCookie(client, g_hSound, sValue, sizeof(sValue));
	g_iSound[client] = (sValue[0] == '\0' ? GetConVarInt(g_cvar_Sound) : StringToInt(sValue));

	GetClientCookie(client, g_hSoundPreset, sValue, sizeof(sValue));
	g_iSoundPreset[client] = (sValue[0] == '\0' ? (GetConVarInt(g_cvar_SoundPreset) - 1) : StringToInt(sValue));
}

public void SetClientCookies(int client)
{
	char sValue[8];

	Format(sValue, sizeof(sValue), "%i", g_iShowText[client]);
	SetClientCookie(client, g_hShowText, sValue);

	Format(sValue, sizeof(sValue), "%i", g_iSound[client]);
	SetClientCookie(client, g_hSound, sValue);

	Format(sValue, sizeof(sValue), "%i", g_iSoundPreset[client]);
	SetClientCookie(client, g_hSoundPreset, sValue);
}
