#include <sourcemod>
#include <sdktools>
#include <clientprefs>

#define ANNOUNCE_DELAY				30.0
#define JOIN_DELAY					2.0

#define MAX_NUM_SETS				255
#define MAX_NUM_KILLS				50

#define PATH_CONFIG_QUAKE_SET		"configs/quake/sets.cfg"
#define PATH_CONFIG_QUAKE_SOUNDS	"configs/quake/sets"

public Plugin myinfo = {
	name = "Quake Sounds",
	author = "Spartan_C001, maxime1907",
	description = "Plays sounds based on events that happen in game.",
	version = "4.0.2",
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

bool g_bLate = false

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;
	g_evGameEngine = GetEngineVersion();
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("plugin.quakesounds");

	g_cvar_Announce = CreateConVar("sm_quakesounds_announce", "1", "Sets whether to announcement to clients as they join, 0=Disabled, 1=Enabled.", FCVAR_NONE, true, 0.0, true, 1.0)
	g_cvar_Text = CreateConVar("sm_quakesounds_text", "1", "Default text display setting for new users, 0=Disabled, 1=Enabled.", FCVAR_NONE, true, 0.0, true, 1.0)
	g_cvar_Sound = CreateConVar("sm_quakesounds_sound", "1", "Default sound setting for new users, 0=Disable 1=Enable.", FCVAR_NONE, true, 0.0, true, 255.0)
	g_cvar_SoundPreset = CreateConVar("sm_quakesounds_sound_preset", "1", "Default sound set for new users, 1-255=Preset by order in the config file.", FCVAR_NONE, true, 1.0, true, 255.0)
	g_cvar_Volume = CreateConVar("sm_quakesounds_volume", "1.0", "Sound Volume: should be a number between 0.0 and 1.0.", FCVAR_NONE, true, 0.0, true, 1.0)
	g_cvar_TeamKillMode = CreateConVar("sm_quakesounds_teamkill_mode", "0", "Teamkiller Mode; 0=Normal, 1=Team-Kills count as normal kills.", FCVAR_NONE, true, 0.0, true, 1.0)
	g_cvar_ComboTime = CreateConVar("sm_quakesounds_combo_time", "2.0", "Max time in seconds between kills to count as combo; 0.0=Minimum, 2.0=Default", FCVAR_NONE, true, 0.0)

	g_hShowText = RegClientCookie("quakesounds_texts", "Display text", CookieAccess_Private);
	g_hSound = RegClientCookie("quakesounds_sounds", "Enable sounds", CookieAccess_Private);
	g_hSoundPreset = RegClientCookie("quakesounds_sound_preset", "Sound preset", CookieAccess_Private);

	SetCookieMenuItem(CookieMenu_QuakeSounds, INVALID_HANDLE, "Quake Sound Settings")

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
			HookEvent("dod_round_start", Event_RoundStart, EventHookMode_PostNoCopy)
			HookEvent("dod_round_active", Event_RoundFreezeEnd, EventHookMode_PostNoCopy)
		}
		case Engine_TF2:
		{
			HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy)
			HookEvent("teamplay_round_active", Event_RoundFreezeEnd, EventHookMode_PostNoCopy)
			HookEvent("arena_round_start", Event_RoundFreezeEnd, EventHookMode_PostNoCopy)
		}
		case Engine_HL2DM:
		{
			HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy)
		}
		default:
		{
			HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy)
		}
	}
}

// Loads QuakeSetsList config to check for sound sets
public void LoadQuakeSetConfig()
{
	char sConfigFile[PLATFORM_MAX_PATH];

	KeyValues KvConfig = new KeyValues("SetsList");

	BuildPath(Path_SM, sConfigFile, PLATFORM_MAX_PATH, PATH_CONFIG_QUAKE_SET);

	if(!KvConfig.ImportFromFile(sConfigFile))
	{
		delete KvConfig;
		SetFailState("ImportFromFile() failed!");
		return;
	}
	KvConfig.Rewind();

	if(!KvConfig.GotoFirstSubKey())
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
public LoadSet(char[] setFile, int setNum)
{
	char bufferString[PLATFORM_MAX_PATH]
	Handle SetFileKV = CreateKeyValues("SoundSet")
	if(FileToKeyValues(SetFileKV,setFile))
	{
		if(KvJumpToKey(SetFileKV,"headshot"))
		{
			if(KvGotoFirstSubKey(SetFileKV))
			{
				do
				{
					KvGetSectionName(SetFileKV,bufferString,PLATFORM_MAX_PATH)
					int killNum = StringToInt(bufferString)
					if(killNum >= 0)
					{
						KvGetString(SetFileKV,"sound",headshotSound[setNum][killNum],PLATFORM_MAX_PATH)
						headshotConfig[setNum][killNum] = KvGetNum(SetFileKV,"config",9)
						Format(bufferString,PLATFORM_MAX_PATH,"sound/%s",headshotSound[setNum][killNum])
						if(FileExists(bufferString,true))
						{
							PrecacheSoundCustom(headshotSound[setNum][killNum],PLATFORM_MAX_PATH)
							AddFileToDownloadsTable(bufferString)
						}
						else
						{
							headshotConfig[setNum][killNum] = 0
							PrintToServer("[SM] Quake Sounds: File specified in 'headshot %i' does not exist in '%s', ignoring.",killNum,setFile)
						}
					}
				} while (KvGotoNextKey(SetFileKV))
				KvGoBack(SetFileKV)
			}
			else
			{
				PrintToServer("[SM] Quake Sounds: 'headshot' section not configured correctly in %s.",setFile)
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'headshot' section missing in %s.",setFile)
		}
		KvRewind(SetFileKV)
		if(KvJumpToKey(SetFileKV,"grenade"))
		{
			if(KvGotoFirstSubKey(SetFileKV))
			{
				PrintToServer("[SM] Quake Sounds: 'grenade' section not configured correctly in %s.",setFile)
				KvGoBack(SetFileKV)
			}
			else
			{
				KvGetString(SetFileKV,"sound",grenadeSound[setNum],PLATFORM_MAX_PATH)
				grenadeConfig[setNum] = KvGetNum(SetFileKV,"config",9)
				Format(bufferString,PLATFORM_MAX_PATH,"sound/%s",grenadeSound[setNum])
				if(FileExists(bufferString,true))
				{
					PrecacheSoundCustom(grenadeSound[setNum],PLATFORM_MAX_PATH)
					AddFileToDownloadsTable(bufferString)
				}
				else
				{
					grenadeConfig[setNum] = 0
					PrintToServer("[SM] Quake Sounds: File specified in 'grenade' does not exist in '%s', ignoring.",setFile)
				}
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'grenade' section missing in %s.",setFile)
		}
		KvRewind(SetFileKV)
		if(KvJumpToKey(SetFileKV,"selfkill"))
		{
			if(KvGotoFirstSubKey(SetFileKV))
			{
				PrintToServer("[SM] Quake Sounds: 'selfkill' section not configured correctly in %s.",setFile)
				KvGoBack(SetFileKV)
			}
			else
			{
				KvGetString(SetFileKV,"sound",selfkillSound[setNum],PLATFORM_MAX_PATH)
				selfkillConfig[setNum] = KvGetNum(SetFileKV,"config",9)
				Format(bufferString,PLATFORM_MAX_PATH,"sound/%s",selfkillSound[setNum])
				if(FileExists(bufferString,true))
				{
					PrecacheSoundCustom(selfkillSound[setNum],PLATFORM_MAX_PATH)
					AddFileToDownloadsTable(bufferString)
				}
				else
				{
					selfkillConfig[setNum] = 0
					PrintToServer("[SM] Quake Sounds: File specified in 'selfkill' does not exist in '%s', ignoring.",setFile)
				}
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'selfkill' section missing in %s.",setFile)
		}
		KvRewind(SetFileKV)
		if(KvJumpToKey(SetFileKV,"round play"))
		{
			if(KvGotoFirstSubKey(SetFileKV))
			{
				PrintToServer("[SM] Quake Sounds: 'round play' section not configured correctly in %s.",setFile)
				KvGoBack(SetFileKV)
			}
			else
			{
				KvGetString(SetFileKV,"sound",roundplaySound[setNum],PLATFORM_MAX_PATH)
				roundplayConfig[setNum] = KvGetNum(SetFileKV,"config",9)
				Format(bufferString,PLATFORM_MAX_PATH,"sound/%s",roundplaySound[setNum])
				if(FileExists(bufferString,true))
				{
					PrecacheSoundCustom(roundplaySound[setNum],PLATFORM_MAX_PATH)
					AddFileToDownloadsTable(bufferString)
				}
				else
				{
					roundplayConfig[setNum] = 0
					PrintToServer("[SM] Quake Sounds: File specified in 'round play' does not exist in '%s', ignoring.",setFile)
				}
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'round play' section missing in %s.",setFile)
		}
		KvRewind(SetFileKV)
		if(KvJumpToKey(SetFileKV,"knife"))
		{
			if(KvGotoFirstSubKey(SetFileKV))
			{
				PrintToServer("[SM] Quake Sounds: 'knife' section not configured correctly in %s.",setFile)
				KvGoBack(SetFileKV)
			}
			else
			{
				KvGetString(SetFileKV,"sound",knifeSound[setNum],PLATFORM_MAX_PATH)
				knifeConfig[setNum] = KvGetNum(SetFileKV,"config",9)
				Format(bufferString,PLATFORM_MAX_PATH,"sound/%s",knifeSound[setNum])
				if(FileExists(bufferString,true))
				{
					PrecacheSoundCustom(knifeSound[setNum],PLATFORM_MAX_PATH)
					AddFileToDownloadsTable(bufferString)
				}
				else
				{
					knifeConfig[setNum] = 0
					PrintToServer("[SM] Quake Sounds: File specified in 'knife' does not exist in '%s', ignoring.",setFile)
				}
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'knife' section missing in %s.",setFile)
		}
		KvRewind(SetFileKV)
		if(KvJumpToKey(SetFileKV,"killsound"))
		{
			if(KvGotoFirstSubKey(SetFileKV))
			{
				do
				{
					KvGetSectionName(SetFileKV,bufferString,PLATFORM_MAX_PATH)
					int killNum = StringToInt(bufferString)
					if(killNum >= 0)
					{
						KvGetString(SetFileKV,"sound",killSound[setNum][killNum],PLATFORM_MAX_PATH)
						killConfig[setNum][killNum] = KvGetNum(SetFileKV,"config",9)
						Format(bufferString,PLATFORM_MAX_PATH,"sound/%s",killSound[setNum][killNum])
						if(FileExists(bufferString,true))
						{
							PrecacheSoundCustom(killSound[setNum][killNum],PLATFORM_MAX_PATH)
							AddFileToDownloadsTable(bufferString)
						}
						else
						{
							killConfig[setNum][killNum] = 0
							PrintToServer("[SM] Quake Sounds: File specified in 'killsound %i' does not exist in '%s', ignoring.",killNum,setFile)
						}
					}
				} while (KvGotoNextKey(SetFileKV))
				KvGoBack(SetFileKV)
			}
			else
			{
				PrintToServer("[SM] Quake Sounds: 'killsound' section not configured correctly in %s.",setFile)
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'killsound' section missing in %s.",setFile)
		}
		KvRewind(SetFileKV)
		if(KvJumpToKey(SetFileKV,"first blood"))
		{
			if(KvGotoFirstSubKey(SetFileKV))
			{
				PrintToServer("[SM] Quake Sounds: 'first blood' section not configured correctly in %s.",setFile)
				KvGoBack(SetFileKV)
			}
			else
			{
				KvGetString(SetFileKV,"sound",firstbloodSound[setNum],PLATFORM_MAX_PATH)
				firstbloodConfig[setNum] = KvGetNum(SetFileKV,"config",9)
				Format(bufferString,PLATFORM_MAX_PATH,"sound/%s",firstbloodSound[setNum])
				if(FileExists(bufferString,true))
				{
					PrecacheSoundCustom(firstbloodSound[setNum],PLATFORM_MAX_PATH)
					AddFileToDownloadsTable(bufferString)
				}
				else
				{
					firstbloodConfig[setNum] = 0
					PrintToServer("[SM] Quake Sounds: File specified in 'first blood' does not exist in '%s', ignoring.",setFile)
				}
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'first blood' section missing in %s.",setFile)
		}
		KvRewind(SetFileKV)
		if(KvJumpToKey(SetFileKV,"teamkill"))
		{
			if(KvGotoFirstSubKey(SetFileKV))
			{
				PrintToServer("[SM] Quake Sounds: 'teamkill' section not configured correctly in %s.",setFile)
				KvGoBack(SetFileKV)
			}
			else
			{
				KvGetString(SetFileKV,"sound",teamkillSound[setNum],PLATFORM_MAX_PATH)
				teamkillConfig[setNum] = KvGetNum(SetFileKV,"config",9)
				Format(bufferString,PLATFORM_MAX_PATH,"sound/%s",teamkillSound[setNum])
				if(FileExists(bufferString,true))
				{
					PrecacheSoundCustom(teamkillSound[setNum],PLATFORM_MAX_PATH)
					AddFileToDownloadsTable(bufferString)
				}
				else
				{
					teamkillConfig[setNum] = 0
					PrintToServer("[SM] Quake Sounds: File specified in 'teamkill' does not exist in '%s', ignoring.",setFile)
				}
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'teamkill' section missing in %s.",setFile)
		}
		KvRewind(SetFileKV)
		if(KvJumpToKey(SetFileKV,"combo"))
		{
			if(KvGotoFirstSubKey(SetFileKV))
			{
				do
				{
					KvGetSectionName(SetFileKV,bufferString,PLATFORM_MAX_PATH)
					int killNum = StringToInt(bufferString)
					if(killNum >= 0)
					{
						KvGetString(SetFileKV,"sound",comboSound[setNum][killNum],PLATFORM_MAX_PATH)
						comboConfig[setNum][killNum] = KvGetNum(SetFileKV,"config",9)
						Format(bufferString,PLATFORM_MAX_PATH,"sound/%s",comboSound[setNum][killNum])
						if(FileExists(bufferString,true))
						{
							PrecacheSoundCustom(comboSound[setNum][killNum],PLATFORM_MAX_PATH)
							AddFileToDownloadsTable(bufferString)
						}
						else
						{
							comboConfig[setNum][killNum] = 0
							PrintToServer("[SM] Quake Sounds: File specified in 'combo %i' does not exist in '%s', ignoring.",killNum,setFile)
						}
					}
				} while (KvGotoNextKey(SetFileKV))
				KvGoBack(SetFileKV)
			}
			else
			{
				PrintToServer("[SM] Quake Sounds: 'combo' section not configured correctly in %s.",setFile)
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'combo' section missing in %s.",setFile)
		}
		KvRewind(SetFileKV)
		if(KvJumpToKey(SetFileKV,"join server"))
		{
			if(KvGotoFirstSubKey(SetFileKV))
			{
				PrintToServer("[SM] Quake Sounds: 'join server' section not configured correctly in %s.",setFile)
				KvGoBack(SetFileKV)
			}
			else
			{
				KvGetString(SetFileKV,"sound",joinSound[setNum],PLATFORM_MAX_PATH)
				joinConfig[setNum] = KvGetNum(SetFileKV,"config",9)
				Format(bufferString,PLATFORM_MAX_PATH,"sound/%s",joinSound[setNum])
				if(FileExists(bufferString,true))
				{
					PrecacheSoundCustom(joinSound[setNum],PLATFORM_MAX_PATH)
					AddFileToDownloadsTable(bufferString)
				}
				else
				{
					joinConfig[setNum] = 0
					PrintToServer("[SM] Quake Sounds: File specified in 'join server' does not exist in '%s', ignoring.",setFile)
				}
			}
		}
		else
		{
			PrintToServer("[SM] Quake Sounds: 'join server' section missing in %s.",setFile)
		}
	}
	else
	{
		PrintToServer("[SM] Quake Sounds: Cannot parse '%s', file not found or incorrectly structured!",setFile)
	}
	CloseHandle(SetFileKV)
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
				if (!StrEqual(joinSound[g_iSoundPreset[client]], ""))
				{
					if (joinConfig[g_iSoundPreset[client]] & i)
					{
						EmitSoundCustom(client, joinSound[g_iSoundPreset[client]], _, _, _, _, GetConVarFloat(g_cvar_Volume));
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
			if (!StrEqual(roundplaySound[g_iSoundPreset[i]],"")  && (roundplayConfig[g_iSoundPreset[i]] & 1) || (roundplayConfig[g_iSoundPreset[i]] & 2) || (roundplayConfig[g_iSoundPreset[i]] & 4))
			{
				EmitSoundCustom(i, roundplaySound[g_iSoundPreset[i]], _, _, _, _, GetConVarFloat(g_cvar_Volume));
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
		InitializeRound()
	}
}

// Important bit - does all kill/combo/custom kill sounds and things!
public Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int attackerClient = GetClientOfUserId(GetEventInt(event,"attacker"));
	char attackerName[MAX_NAME_LENGTH];
	GetClientName(attackerClient,attackerName,MAX_NAME_LENGTH);
	int victimClient = GetClientOfUserId(GetEventInt(event,"userid"));
	char victimName[MAX_NAME_LENGTH];
	GetClientName(victimClient,victimName,MAX_NAME_LENGTH);
	char bufferString[256];
	if(victimClient < 1 || victimClient > MaxClients)
	{
		return
	}
	else
	{
		if(attackerClient == victimClient || attackerClient == 0)
		{
			g_iConsecutiveKills[attackerClient] = 0
			for(int i = 1; i <= MaxClients; i++)
			{
				if(IsClientInGame(i) && !IsFakeClient(i) && g_iSound[i])
				{
					if(!StrEqual(selfkillSound[g_iSoundPreset[i]],""))
					{
						if(selfkillConfig[g_iSoundPreset[i]] & 1)
						{
							EmitSoundCustom(i,selfkillSound[g_iSoundPreset[i]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
						}
						else if((selfkillConfig[g_iSoundPreset[i]] & 2) && attackerClient == i)
						{
							EmitSoundCustom(i,selfkillSound[g_iSoundPreset[i]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
						}
						else if((selfkillConfig[g_iSoundPreset[i]] & 4) && victimClient == i)
						{
							EmitSoundCustom(i,selfkillSound[g_iSoundPreset[i]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
						}
					}
					if(g_iShowText[i])
					{
						if(selfkillConfig[g_iSoundPreset[i]] & 8)
						{
							PrintCenterText(i,"%t","selfkill",victimName)
						}
						else if((selfkillConfig[g_iSoundPreset[i]] & 16) && attackerClient == i)
						{
							PrintCenterText(i,"%t","selfkill",victimName)
						}
						else if((selfkillConfig[g_iSoundPreset[i]] & 32) && victimClient == i)
						{
							PrintCenterText(i,"%t","selfkill",victimName)
						}
					}
				}
			}
		}
		else if(GetClientTeam(attackerClient) == GetClientTeam(victimClient) && !GetConVarBool(g_cvar_TeamKillMode))
		{
			g_iConsecutiveKills[attackerClient] = 0
			for(int i = 1; i <= MaxClients; i++)
			{
				if(IsClientInGame(i) && !IsFakeClient(i) && g_iSound[i])
				{
					if(!StrEqual(teamkillSound[g_iSoundPreset[i]],""))
					{
						if(teamkillConfig[g_iSoundPreset[i]] & 1)
						{
							EmitSoundCustom(i,teamkillSound[g_iSoundPreset[i]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
						}
						else if((teamkillConfig[g_iSoundPreset[i]] & 2) && attackerClient == i)
						{
							EmitSoundCustom(i,teamkillSound[g_iSoundPreset[i]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
						}
						else if((teamkillConfig[g_iSoundPreset[i]] & 4) && victimClient == i)
						{
							EmitSoundCustom(i,teamkillSound[g_iSoundPreset[i]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
						}
					}
					if(g_iShowText[i])
					{
						if(teamkillConfig[g_iSoundPreset[i]] & 8)
						{
							PrintCenterText(i,"%t","teamkill",attackerName,victimName)
						}
						else if((teamkillConfig[g_iSoundPreset[i]] & 16) && attackerClient == i)
						{
							PrintCenterText(i,"%t","teamkill",attackerName,victimName)
						}
						else if((teamkillConfig[g_iSoundPreset[i]] & 32) && victimClient == i)
						{
							PrintCenterText(i,"%t","teamkill",attackerName,victimName)
						}
					}
				}
			}
		}
		else
		{
			g_iTotalKills++;
			g_iConsecutiveKills[attackerClient]++;
			bool firstblood;
			bool headshot;
			bool knife;
			bool grenade;
			bool combo;

			int customkill;
			
			char weapon[32];

			GetEventString(event, "weapon", weapon, sizeof(weapon));

			if (g_evGameEngine == Engine_CSS || g_evGameEngine == Engine_CSGO)
			{
				headshot = GetEventBool(event,"headshot")
			}
			else if(g_evGameEngine == Engine_TF2)
			{
				customkill = GetEventInt(event,"customkill")
				if(customkill == 1)
				{
					headshot = true
				}
			}
			else
			{
				headshot = false
			}
			if(headshot)
			{
				g_iConsecutiveHeadshots[attackerClient]++
			}
			float fLastKillTimeTmp = g_fLastKillTime[attackerClient]
			g_fLastKillTime[attackerClient] = GetEngineTime()			
			if(fLastKillTimeTmp == -1.0 || (g_fLastKillTime[attackerClient] - fLastKillTimeTmp) > GetConVarFloat(g_cvar_ComboTime))
			{
				g_iComboScore[attackerClient] = 1
				combo = false
			}
			else
			{
				g_iComboScore[attackerClient]++
				combo = true
			}
			if(g_iTotalKills == 1)
			{
				firstblood = true
			}
			if(g_evGameEngine == Engine_TF2)
			{
				if(customkill == 2)
				{
					knife = true
				}
			}
			else if(g_evGameEngine == Engine_CSS)
			{
				if(StrEqual(weapon,"hegrenade") || StrEqual(weapon,"smokegrenade") || StrEqual(weapon,"flashbang"))
				{
					grenade = true
				}
				else if(StrEqual(weapon,"knife"))
				{
					knife = true
				}
			}
			else if(g_evGameEngine == Engine_CSGO)
			{
				if(StrEqual(weapon,"inferno") || StrEqual(weapon,"hegrenade") || StrEqual(weapon,"flashbang") || StrEqual(weapon,"decoy") || StrEqual(weapon,"smokegrenade"))
				{
					grenade = true
				}
				else if(StrEqual(weapon,"knife_default_ct") || StrEqual(weapon,"knife_default_t") || StrEqual(weapon,"knifegg") || StrEqual(weapon,"knife_flip") || StrEqual(weapon,"knife_gut") || StrEqual(weapon,"knife_karambit") || StrEqual(weapon,"bayonet") || StrEqual(weapon,"knife_m9_bayonet"))
				{
					knife = true
				}
			}
			else if(g_evGameEngine == Engine_DODS)
			{
				if(StrEqual(weapon,"riflegren_ger") || StrEqual(weapon,"riflegren_us") || StrEqual(weapon,"frag_ger") || StrEqual(weapon,"frag_us") || StrEqual(weapon,"smoke_ger") || StrEqual(weapon,"smoke_us"))
				{
					grenade = true
				}
				else if((StrEqual(weapon,"spade") || StrEqual(weapon,"amerknife") || StrEqual(weapon,"punch")))
				{
					knife = true
				}
			}
			else if(g_evGameEngine == Engine_HL2DM)
			{
				if(StrEqual(weapon,"grenade_frag"))
				{
					grenade = true
				}
				else if((StrEqual(weapon,"stunstick") || StrEqual(weapon,"crowbar")))
				{
					knife = true
				}
			}
			for(int i = 1; i <= MaxClients; i++)
			{
				if(IsClientInGame(i) && !IsFakeClient(i) && g_iSound[i])
				{
					if(firstblood && firstbloodConfig[g_iSoundPreset[i]] > 0)
					{
						if(!StrEqual(firstbloodSound[g_iSoundPreset[i]],""))
						{
							if(firstbloodConfig[g_iSoundPreset[i]] & 1)
							{
								EmitSoundCustom(i,firstbloodSound[g_iSoundPreset[i]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
							else if((firstbloodConfig[g_iSoundPreset[i]] & 2) && attackerClient == i)
							{
								EmitSoundCustom(i,firstbloodSound[g_iSoundPreset[i]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
							else if((firstbloodConfig[g_iSoundPreset[i]] & 4) && victimClient == i)
							{
								EmitSoundCustom(i,firstbloodSound[g_iSoundPreset[i]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
						}
						if(g_iShowText[i])
						{
							if(firstbloodConfig[g_iSoundPreset[i]] & 8)
							{
								PrintCenterText(i,"%t","first blood",attackerName)
							}
							else if((firstbloodConfig[g_iSoundPreset[i]] & 16) && attackerClient == i)
							{
								PrintCenterText(i,"%t","first blood",attackerName)
							}
							else if((firstbloodConfig[g_iSoundPreset[i]] & 32) && victimClient == i)
							{
								PrintCenterText(i,"%t","first blood",attackerName)
							}
						}
					}
					else if(headshot && headshotConfig[g_iSoundPreset[i]][0] > 0)
					{
						if(!StrEqual(headshotSound[g_iSoundPreset[i]][0],""))
						{
							if(headshotConfig[g_iSoundPreset[i]][0] & 1)
							{
								EmitSoundCustom(i,headshotSound[g_iSoundPreset[i]][0],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
							else if((headshotConfig[g_iSoundPreset[i]][0] & 2) && attackerClient == i)
							{
								EmitSoundCustom(i,headshotSound[g_iSoundPreset[i]][0],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
							else if((headshotConfig[g_iSoundPreset[i]][0] & 4) && victimClient == i)
							{
								EmitSoundCustom(i,headshotSound[g_iSoundPreset[i]][0],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
						}
						if(g_iShowText[i])
						{
							if(headshotConfig[g_iSoundPreset[i]][0] & 8)
							{
								PrintCenterText(i,"%t","headshot",attackerName)
							}
							else if((headshotConfig[g_iSoundPreset[i]][0] & 16) && attackerClient == i)
							{
								PrintCenterText(i,"%t","headshot",attackerName)
							}
							else if((headshotConfig[g_iSoundPreset[i]][0] & 32) && victimClient == i)
							{
								PrintCenterText(i,"%t","headshot",attackerName)
							}
						}
					}
					else if(headshot && g_iConsecutiveHeadshots[attackerClient] < MAX_NUM_KILLS && headshotConfig[g_iSoundPreset[i]][g_iConsecutiveHeadshots[attackerClient]] > 0)
					{
						if(!StrEqual(headshotSound[g_iSoundPreset[i]][g_iConsecutiveHeadshots[attackerClient]],""))
						{
							if(headshotConfig[g_iSoundPreset[i]][g_iConsecutiveHeadshots[attackerClient]] & 1)
							{
								EmitSoundCustom(i,headshotSound[g_iSoundPreset[i]][g_iConsecutiveHeadshots[attackerClient]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
							else if((headshotConfig[g_iSoundPreset[i]][g_iConsecutiveHeadshots[attackerClient]] & 2) && attackerClient == i)
							{
								EmitSoundCustom(i,headshotSound[g_iSoundPreset[i]][g_iConsecutiveHeadshots[attackerClient]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
							else if((headshotConfig[g_iSoundPreset[i]][g_iConsecutiveHeadshots[attackerClient]] & 4) && victimClient == i)
							{
								EmitSoundCustom(i,headshotSound[g_iSoundPreset[i]][g_iConsecutiveHeadshots[attackerClient]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
						}
						if(g_iShowText[i] && g_iConsecutiveHeadshots[attackerClient] < MAX_NUM_KILLS)
						{
							if(headshotConfig[g_iSoundPreset[i]][g_iConsecutiveHeadshots[attackerClient]] & 8)
							{
								Format(bufferString,256,"headshot %i",g_iConsecutiveHeadshots[attackerClient])
								PrintCenterText(i,"%t",bufferString,attackerName)
							}
							else if((headshotConfig[g_iSoundPreset[i]][g_iConsecutiveHeadshots[attackerClient]] & 16) && attackerClient == i)
							{
								Format(bufferString,256,"headshot %i",g_iConsecutiveHeadshots[attackerClient])
								PrintCenterText(i,"%t",bufferString,attackerName)
							}
							else if((headshotConfig[g_iSoundPreset[i]][g_iConsecutiveHeadshots[attackerClient]] & 32) && victimClient == i)
							{
								Format(bufferString,256,"headshot %i",g_iConsecutiveHeadshots[attackerClient])
								PrintCenterText(i,"%t",bufferString,attackerName)
							}
						}
					}
					else if(knife && knifeConfig[g_iSoundPreset[i]] > 0)
					{
						if(!StrEqual(knifeSound[g_iSoundPreset[i]],""))
						{
							if(knifeConfig[g_iSoundPreset[i]] & 1)
							{
								EmitSoundCustom(i,knifeSound[g_iSoundPreset[i]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
							else if((knifeConfig[g_iSoundPreset[i]] & 2) && attackerClient == i)
							{
								EmitSoundCustom(i,knifeSound[g_iSoundPreset[i]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
							else if((knifeConfig[g_iSoundPreset[i]] & 4) && victimClient == i)
							{
								EmitSoundCustom(i,knifeSound[g_iSoundPreset[i]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
						}
						if(g_iShowText[i])
						{
							if(knifeConfig[g_iSoundPreset[i]] & 8)
							{
								PrintCenterText(i,"%t","knife",attackerName,victimName)
							}
							else if((knifeConfig[g_iSoundPreset[i]] & 16) && attackerClient == i)
							{
								PrintCenterText(i,"%t","knife",attackerName,victimName)
							}
							else if((knifeConfig[g_iSoundPreset[i]] & 32) && victimClient == i)
							{
								PrintCenterText(i,"%t","knife",attackerName,victimName)
							}
						}
					}
					else if(grenade && grenadeConfig[g_iSoundPreset[i]] > 0)
					{
						if(!StrEqual(grenadeSound[g_iSoundPreset[i]],""))
						{
							if(grenadeConfig[g_iSoundPreset[i]] & 1)
							{
								EmitSoundCustom(i,grenadeSound[g_iSoundPreset[i]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
							else if((grenadeConfig[g_iSoundPreset[i]] & 2) && attackerClient == i)
							{
								EmitSoundCustom(i,grenadeSound[g_iSoundPreset[i]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
							else if((grenadeConfig[g_iSoundPreset[i]] & 4) && victimClient == i)
							{
								EmitSoundCustom(i,grenadeSound[g_iSoundPreset[i]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
						}
						if(g_iShowText[i])
						{
							if(grenadeConfig[g_iSoundPreset[i]] & 8)
							{
								PrintCenterText(i,"%t","grenade",attackerName,victimName)
							}
							else if((grenadeConfig[g_iSoundPreset[i]] & 16) && attackerClient == i)
							{
								PrintCenterText(i,"%t","grenade",attackerName,victimName)
							}
							else if((grenadeConfig[g_iSoundPreset[i]] & 32) && victimClient == i)
							{
								PrintCenterText(i,"%t","grenade",attackerName,victimName)
							}
						}
					}
					else if(combo && g_iComboScore[attackerClient] < MAX_NUM_KILLS && comboConfig[g_iSoundPreset[i]][g_iComboScore[attackerClient]] > 0)
					{
						if(!StrEqual(comboSound[g_iSoundPreset[i]][g_iComboScore[attackerClient]],""))
						{
							if(comboConfig[g_iSoundPreset[i]][g_iComboScore[attackerClient]] & 1)
							{
								EmitSoundCustom(i,comboSound[g_iSoundPreset[i]][g_iComboScore[attackerClient]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
							else if((comboConfig[g_iSoundPreset[i]][g_iComboScore[attackerClient]] & 2) && attackerClient == i)
							{
								EmitSoundCustom(i,comboSound[g_iSoundPreset[i]][g_iComboScore[attackerClient]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
							else if((comboConfig[g_iSoundPreset[i]][g_iComboScore[attackerClient]] & 4) && victimClient == i)
							{
								EmitSoundCustom(i,comboSound[g_iSoundPreset[i]][g_iComboScore[attackerClient]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
						}
						if(g_iShowText[i] && g_iComboScore[attackerClient] < MAX_NUM_KILLS)
						{
							if(comboConfig[g_iSoundPreset[i]][g_iComboScore[attackerClient]] & 8)
							{
								Format(bufferString,256,"combo %i",g_iComboScore[attackerClient])
								PrintCenterText(i,"%t",bufferString,attackerName)
							}
							else if((comboConfig[g_iSoundPreset[i]][g_iComboScore[attackerClient]] & 16) && attackerClient == i)
							{
								Format(bufferString,256,"combo %i",g_iComboScore[attackerClient])
								PrintCenterText(i,"%t",bufferString,attackerName)
							}
							else if((comboConfig[g_iSoundPreset[i]][g_iComboScore[attackerClient]] & 32) && victimClient == i)
							{
								Format(bufferString,256,"combo %i",g_iComboScore[attackerClient])
								PrintCenterText(i,"%t",bufferString,attackerName)
							}
						}
					}
					else
					{
						if(g_iConsecutiveKills[attackerClient] < MAX_NUM_KILLS && !StrEqual(killSound[g_iSoundPreset[i]][g_iConsecutiveKills[attackerClient]],""))
						{
							if(killConfig[g_iSoundPreset[i]][g_iConsecutiveKills[attackerClient]] & 1)
							{
								EmitSoundCustom(i,killSound[g_iSoundPreset[i]][g_iConsecutiveKills[attackerClient]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
							else if((killConfig[g_iSoundPreset[i]][g_iConsecutiveKills[attackerClient]] & 2) && attackerClient == i)
							{
								EmitSoundCustom(i,killSound[g_iSoundPreset[i]][g_iConsecutiveKills[attackerClient]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
							else if((killConfig[g_iSoundPreset[i]][g_iConsecutiveKills[attackerClient]] & 4) && victimClient == i)
							{
								EmitSoundCustom(i,killSound[g_iSoundPreset[i]][g_iConsecutiveKills[attackerClient]],_,_,_,_,GetConVarFloat(g_cvar_Volume))
							}
						}
						if(g_iShowText[i] && g_iConsecutiveKills[attackerClient] < MAX_NUM_KILLS)
						{
							if(killConfig[g_iSoundPreset[i]][g_iConsecutiveKills[attackerClient]] & 8)
							{
								Format(bufferString,256,"killsound %i",g_iConsecutiveKills[attackerClient])
								PrintCenterText(i,"%t",bufferString,attackerName)
							}
							else if((killConfig[g_iSoundPreset[i]][g_iConsecutiveKills[attackerClient]] & 16) && attackerClient == i)
							{
								Format(bufferString,256,"killsound %i",g_iConsecutiveKills[attackerClient])
								PrintCenterText(i,"%t",bufferString,attackerName)
							}
							else if((killConfig[g_iSoundPreset[i]][g_iConsecutiveKills[attackerClient]] & 32) && victimClient == i)
							{
								Format(bufferString,256,"killsound %i",g_iConsecutiveKills[attackerClient])
								PrintCenterText(i,"%t",bufferString,attackerName)
							}
						}
					}
				}
			}
		}
	}
	g_iConsecutiveKills[victimClient] = 0
	g_iConsecutiveHeadshots[victimClient] = 0
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
	g_iTotalKills = 0
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
		Format(soundFile, maxLength, "*%s", soundFile)
		AddToStringTable(FindStringTable("soundprecache"), soundFile)
	}
	else
	{
		PrecacheSound(soundFile, true)
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
