/**
 * vim: set ts=4 :
 * =============================================================================
 * MapChoices
 * An advanced map voting system for SourceMod
 *
 * MapChoices (C)2015 Powerlord (Ross Bemrose).  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */
#include <sourcemod>

#include <sdktools>
#include <multicolors>

#pragma semicolon 1
#pragma newdecls required

#include "include/mapchoices" // Include our own file to gain access to enums and the like

#define VERSION "1.0.0 alpha 2"

#define ERASE_MAP_NOMINATIONS -1

enum FilterType:
{
	GroupFilter,
	MapFilter,
}

// SM 1.10 enum struct to store nominations data
// Note that NominationsData_Nominators is not used in g_MapNominations
enum struct Nominations
{
	char map[PLATFORM_MAX_PATH];
	char group[MAPCHOICES_MAX_GROUP_LENGTH];
	StringMap mapAttributes;
	StringMap groupAttributes;
	ArrayList nominators;
}

/*
 * SM 1.10 enum-struct
 * Data structure for storing group data
 * Note that groupAttributes may be null if there were no attributes
 * MAPCHOICES_DEFAULTGROUP will have a null GroupAttributes StringMap
 */
enum struct GroupData
{
	char group[MAPCHOICES_MAX_GROUP_LENGTH]; // Must exist for subplugins despite being redundant
	StringMap attributes; // <char[], char[]>
	StringMap mapList; // <char[], StringMap<char[], char[]>>
	
	/*
	 * Copy a GroupData to a MapChoices_GroupDTO
	 */
	void ToDTO(MapChoices_GroupDTO out)
	{
		strcopy(out.group, sizeof(out.group), this.group);
		out.attributes = CopyCharStringMap(this.attributes);
	}

	/*
	 * Clean up all handles used by this enum.
	 *
	 * This includes all map attributes lists
	 *
	 * @noreturn 
	 */
	void Close()
	{
		delete this.attributes;
		
		// We need to close all the map attribute handles before deleting the mapList
		if (this.mapList != null)
		{
			StringMapSnapshot snapshot = this.mapList.Snapshot();
	
			for (int i = 0; i < snapshot.Length; i++)
			{
				int keySize = snapshot.KeyBufferSize(i);
				char[] map = new char[keySize];
				snapshot.GetKey(i, map, keySize);
				
				StringMap mapAttributes;
				this.mapList.GetValue(map, mapAttributes);
				
				delete mapAttributes;
			}

			delete snapshot;
		}
		delete this.mapList;
	}
}

// ArrayList of nominations_t
ArrayList g_Array_NominatedMaps;

Nominations g_MapNominations[MAXPLAYERS+1];

MapChoices_GameFlags g_GameFlags;

//ConVars
//ConVar g_Cvar_Enabled;
ConVar g_Cvar_ExtendCount;
ConVar g_Cvar_ExtendRounds;
ConVar g_Cvar_ExtendFrags;
ConVar g_Cvar_ExtendTime;
ConVar g_Cvar_DontChange;
ConVar g_Cvar_VoteTime;
ConVar g_Cvar_RetryTime;
ConVar g_Cvar_VoteItems;
ConVar g_Cvar_WarningTime;
ConVar g_Cvar_VoteType;
ConVar g_Cvar_Runoffs;
ConVar g_Cvar_RunoffPercent;
ConVar g_Cvar_RunoffTime;
ConVar g_Cvar_NoVote;
ConVar g_Cvar_NoVoteButton;
ConVar g_Cvar_Randomize;
ConVar g_Cvar_Spectators;

// Valve ConVars
//ConVar g_Cvar_Timelimit;

ConVar g_Cvar_BonusTime;
ConVar g_Cvar_Winlimit;
ConVar g_Cvar_FragLimit;
ConVar g_Cvar_MaxRounds;

// ConVar g_Cvar_ChatTime;

// Global Forwards
Handle g_Forward_MapVoteStarted;
Handle g_Forward_MapVoteEnded;
Handle g_Forward_WarningTimerStarted;
Handle g_Forward_WarningTimerTicked;
Handle g_Forward_NominationAdded;
Handle g_Forward_NominationRemoved;

// Private Forwards
Handle g_Forward_HandlerVoteStart;
Handle g_Forward_HandlerCancelVote;
Handle g_Forward_HandlerIsVoteInProgress;
Handle g_Forward_HandlerVoteWon;
Handle g_Forward_HandlerVoteLost;

Handle g_Forward_VoteFinished;

Handle g_Forward_MapFilter;
Handle g_Forward_GroupFilter;

Handle g_Forward_ChangeMap;

// Vote override stuff, may be handled directly by subplugin
int g_OverrideVoteLimit = -1;

// Round End stuff
bool g_bChangeAtRoundEnd = false;
bool g_bTempIgnoreRoundEnd = false;

// Vote completion stuff
bool g_bMapVoteInProgress = false;
bool g_bMapVoteCompleted = false;
bool g_bMapChanged = false;

StringMap g_MapList = null;
int g_Serial = -1;

char g_MapGroup[MAPCHOICES_MAX_GROUP_LENGTH];

MapChoices_VoteType g_MasterVoteType;

bool g_bIsRunoff = false;
MapChoices_MapChange g_When = MapChoicesMapChange_Instant;

//new Handle:m_ListLookup;

int g_Extends = 0;

//Temporary item data during a vote
StringMap g_ItemData;
MapChoices_VoteType g_VoteType;

// Used during and after a vote
char g_NextMapGroup[MAPCHOICES_MAX_GROUP_LENGTH];

#include "mapchoices/parse-mapchoices-config.inc"

public Plugin myinfo = {
	name			= "MapChoices",
	author			= "Powerlord",
	description		= "An advanced map voting system for SourceMod",
	version			= VERSION,
	url				= ""
};

// Native Support
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// Map list manipulation
	CreateNative("MapChoices_ReadMapList", Native_ReadMapList);
	CreateNative("MapChoices_SetMapListCompatBind", Native_SetMapListCompatBind);
	
	// Nominations
	CreateNative("MapChoices_Nominate", Native_Nominate);
	//CreateNative("MapChoices_RemoveNominationByMap", Native_RemoveNominationByMap);
	//CreateNative("MapChoices_RemoveNominationByOwner", Native_RemoveNominationByOwner);
	CreateNative("MapChoices_GetNominatedMapList", Native_GetNominatedMapList);
	CreateNative("MapChoices_GetNominatedMapOwners", Native_GetNominatedMapOwners);

	// Excluded maps
	//CreateNative("MapChoices_GetExcludedMapList", Native_GetExcludedMapList);
	
	// Vote data
	CreateNative("MapChoices_GetCurrentMapGroup", Native_GetCurrentMapGroup);
	CreateNative("MapChoices_GetVoteType", Native_GetVoteType);
	CreateNative("MapChoices_GetMapChoices_MapDTO", Native_GetMapChoices_MapDTO);
	CreateNative("MapChoices_CanStartVote", Native_CanStartVote);
	CreateNative("MapChoices_InitiateVote", Native_InitiateVote);
	
	// Alternate Vote Handlers
	CreateNative("MapChoices_VoteCompleted", Native_VoteCompleted);
	CreateNative("MapChoices_RegisterVoteHandler", Native_RegisterVoteHandler);
	CreateNative("MapChoices_UnregisterVoteHandler", Native_UnregisterVoteHandler);
	
	// Map filter natives
	CreateNative("MapChoices_RegisterMapFilter", Native_RegisterMapFilter);
	CreateNative("MapChoices_RemoveMapFilter", Native_UnregisterMapFilter);
	CreateNative("MapChoices_RegisterGroupFilter", Native_RegisterGroupFilter);
	CreateNative("MapChoices_UnregisterGroupFilter", Native_UnregisterGroupFilter);
	CreateNative("MapChoices_CheckMapFilter", Native_CheckMapFilter);
	CreateNative("MapChoices_CheckGroupFilter", Native_CheckGroupFilter);
	
	// Game plugins
	CreateNative("MapChoices_WillChangeAtRoundEnd", Native_WillChangeAtRoundEnd);
	CreateNative("MapChoices_RegisterChangeMapHandler", Native_RegisterChangeMapHandler);
	CreateNative("MapChoices_UnregisterChangeMapHandler", Native_UnregisterChangeMapHandler);
	
	CreateNative("MapChoices_AddGameFlags", Native_AddGameFlags);
	CreateNative("MapChoices_RemoveGameFlags", Native_RemoveGameFlags);
	CreateNative("MapChoices_GetGameFlags", Native_GetGameFlags);
	
	CreateNative("MapChoices_OverrideConVar", Native_OverrideConVar);
	CreateNative("MapChoices_ResetConVar", Native_ResetConVar);
	CreateNative("MapChoices_GetConVarOverride", Native_GetConVarOverride);
	
	RegPluginLibrary("mapchoices");
}
  
public void OnPluginStart()
{
	InitializeConfigurationParser();
	//m_ListLookup = new StringMap();
	
	LoadTranslations("common.phrases");
	LoadTranslations("mapchoices.phrases");
	
	CreateConVar("mapchoices_version", VERSION, "MapChoices version", FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	//MapChoices is not designed to be disabled.  Mainly because it does nothing on its own... disable its subplugins instead.
	//g_Cvar_Enabled = CreateConVar("mapchoices_enable", "1", "Enable MapChoices?", FCVAR_NOTIFY|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	g_Cvar_ExtendCount = CreateConVar("mapchoices_extendcount", "3", "How many extensions are allowed per map", _, true, 0.0);
	g_Cvar_ExtendRounds = CreateConVar("mapchoices_extendrounds", "2", "How many rounds to extend the map by per extension", _, true, 2.0);
	g_Cvar_ExtendFrags = CreateConVar("mapchoices_extendfrags", "10", "How many frags to extend the map by. Only applies to games that use frags (HL2:DM, etc...)", _, true, 5.0);
	g_Cvar_ExtendTime = CreateConVar("mapchoices_extendtime", "10", "How many minutes to extend the map by per extension", _, true, 5.0);
	g_Cvar_DontChange = CreateConVar("mapchoices_dontchange", "1", "Add \"Don't Change\" to instant votes such as rtv? 0 = no, 1 = yes", _, true, 0.0, true, 1.0);
	g_Cvar_VoteTime = CreateConVar("mapchoices_votetime", "20", "Map vote time (in seconds)", _, true, 10.0, true, 60.0);
	g_Cvar_RetryTime = CreateConVar("mapchoices_retrytime", "5.0", "How long (in seconds) to wait before we retry the vote if a vote is already running?", _, true, 5.0, true, 15.0);
	g_Cvar_VoteItems = CreateConVar("mapchoices_voteitems", "6", "How many items should appear in each vote? This may be capped in alternate vote systems (TF2 NativeVotes caps to 5).", _, true, 2.0, true, 8.0);
	g_Cvar_WarningTime = CreateConVar("mapchoices_warningtime", "15", "How many seconds before a vote starts do you want a warning timer to run. 0 = Disable", _, true, 0.0, true, 60.0);
	g_Cvar_VoteType = CreateConVar("mapchoices_votetype", "0", "Vote type MaoChoices will use: 0 = Map, 1 = Group, 2 = Tiered (Group then Map). Takes effect at next map change. This is defined here instead of in each map plugin so that nominations can be handled correctly.", _, true, 0.0, true, 2.0);
	g_Cvar_Runoffs = CreateConVar("mapchoices_runoffs", "1", "Are runoff votes enabled?", _, true, 0.0, true, 1.0);
	g_Cvar_RunoffPercent = CreateConVar("mapchoices_runoffpercent", "50", "If a map doesn't get at least this percent of votes, hold a runoff", _, true, 0.0, true, 100.0);
	g_Cvar_RunoffTime = CreateConVar("mapchoices_runofftime", "5.0", "How long (in seconds) to wait before starting a runoff vote.", _, true, 5.0, true, 15.0);
	g_Cvar_NoVote = CreateConVar("mapchoices_novote", "1", "If no one votes, should MapChoices select a choice at random?", _, true, 0.0, true, 1.0);
	g_Cvar_NoVoteButton = CreateConVar("mapchoices_novotebutton", "0", "Add No Vote button to votes?", _, true, 0.0, true, 1.0);
	g_Cvar_Randomize = CreateConVar("mapchoices_randomize", "1", "Randomize the order of items in the vote?", _, true, 0.0, true, 1.0);
	g_Cvar_Spectators = CreateConVar("mapchoices_allowspectators", "1", "Allow spectators to vote? Disabling this on HL2:DM may have unexpected consequences", _, true, 0.0, true, 1.0);
	
	// Core map vote starting stuff
	
	g_Array_NominatedMaps = new ArrayList(sizeof(Nominations));
	
	// Valve cvars
	// g_Cvar_Timelimit = FindConVar("mp_timelimit");
	// g_Cvar_ChatTime = FindConVar("mp_chattime");
	
	// These 4 cvars may be overridden by game plugins
	g_Cvar_BonusTime = FindConVar("mp_bonusroundtime");
	g_Cvar_Winlimit = FindConVar("mp_winlimit");
	g_Cvar_FragLimit = FindConVar("mp_fraglimit");
	g_Cvar_MaxRounds = FindConVar("mp_maxrounds");
	
	// State change forwards
	g_Forward_MapVoteStarted = CreateGlobalForward("MapChoices_OnMapVoteStarted", ET_Ignore, Param_Cell);
	g_Forward_MapVoteEnded = CreateGlobalForward("MapChoices_OnMapVoteEnded", ET_Ignore, Param_String, Param_String, Param_Cell);
	g_Forward_WarningTimerStarted = CreateGlobalForward("MapChoices_OnWarningTimerStarted", ET_Ignore, Param_Cell, Param_Cell);
	g_Forward_WarningTimerTicked = CreateGlobalForward("MapChoices_OnWarningTimerTicked", ET_Ignore, Param_Cell);
	g_Forward_NominationAdded = CreateGlobalForward("MapChoices_OnNominationAdded", ET_Ignore, Param_String, Param_String, Param_Cell, Param_Cell);
	g_Forward_NominationRemoved = CreateGlobalForward("MapChoices_OnNominationRemoved", ET_Ignore, Param_String, Param_String, Param_Cell, Param_Cell);
	
	g_Forward_HandlerVoteStart = CreateForward(ET_Hook, Param_Array, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Array, Param_Cell, Param_Cell);
	g_Forward_HandlerCancelVote = CreateForward(ET_Hook);
	g_Forward_HandlerIsVoteInProgress = CreateForward(ET_Hook, Param_CellByRef);
	g_Forward_HandlerVoteWon = CreateForward(ET_Hook, Param_Cell, Param_Array);
	g_Forward_HandlerVoteLost = CreateForward(ET_Hook, Param_Cell);
		
	g_Forward_MapFilter = CreateForward(ET_Hook, Param_Array);
	g_Forward_GroupFilter = CreateForward(ET_Hook, Param_Array);
	
	g_Forward_ChangeMap = CreateForward(ET_Single, Param_String, Param_Cell);
	
	g_MapList = new StringMap();
	
	HookEvent("round_end", Event_RoundEnd);
	HookEventEx("round_win", Event_RoundEnd);
	HookEventEx("teamplay_round_win", Event_RoundEnd);
	
	AutoExecConfig(true, "mapchoices");
}

public void OnMapStart()
{
	InternalLoadMapList();
	
	g_Extends = 0;
	
	g_bIsRunoff = false;
	g_bChangeAtRoundEnd = false;
	g_bTempIgnoreRoundEnd = false;
	
	g_bMapVoteInProgress = false;
	g_bMapVoteCompleted = false;
	
	if (g_NextMapGroup[0] != '\0')
	{
		strcopy(g_MapGroup, sizeof(g_MapGroup), g_NextMapGroup);
	}
	
	g_NextMapGroup[0] = '\0';
}

public void OnMapEnd()
{
	g_bMapChanged = true;
}

public void OnConfigsExecuted()
{
	g_MasterVoteType = view_as<MapChoices_VoteType>(g_Cvar_VoteType.IntValue);
}

public void OnClientDisconnect(int client)
{
	// Clear the client's nominations
	RemoveClientMapNomination(client);
}

stock int FindMapInNominations(const char[] group, const char[] map)
{
	if (strlen(group) <= 0 || strlen(map) <= 0)
	{
		return -1;
	}
	
	for (int i = 0; i < g_Array_NominatedMaps.Length; i++)
	{
		Nominations nominationsData;
		g_Array_NominatedMaps.GetArray(i, nominationsData, sizeof(nominationsData));
		
		if (StrEqual(map, nominationsData.map) && StrEqual(group, nominationsData.group))
		{
			return i;
		}
	}
	
	return -1;
}

/**
 * 
 * 
 */
stock bool RemoveMapFromNominations(const char[] group, const char[] map, int client = 0)
{
	if (strlen(group) <= 0 || strlen(map) <= 0)
	{
		return false;
	}
	
	int location = FindMapInNominations(group, map);
	if (location > -1)
	{
		bool removed = false;
		
		Nominations nominationsData;
		g_Array_NominatedMaps.GetArray(location, nominationsData, sizeof(nominationsData));
		
		if (client != ERASE_MAP_NOMINATIONS)
		{
			int pos = nominationsData.nominators.FindValue(client);
			
			// This should always exist unless something went wrong
			if (pos > -1)
			{
				nominationsData.nominators.Erase(pos);

				if (nominationsData.nominators.Length == 0)
				{
					// Whoops, no more nominations for this map, so lets remove it
					delete nominationsData.nominators; // close handle for nominated map
					g_Array_NominatedMaps.Erase(location);
					removed = true;
				}
				
				Forward_NominationRemoved(nominationsData.map, nominationsData.group,
				client, removed);
				
			}

			g_MapNominations[client].map[0] = '\0';
			g_MapNominations[client].group[0] = '\0';
		}
		else
		{
			// Erase all nominations
			int count = nominationsData.nominators.Length;
			int loopClient;
			
			for (int i = count - 1; i >= 0; i--)
			{
				bool last = i == 0 ? true : false;
				loopClient = nominationsData.nominators.Get(i);
				
				Forward_NominationRemoved(nominationsData.group, nominationsData.map,
					loopClient, last);

				g_MapNominations[loopClient].map[0] = '\0';
				g_MapNominations[loopClient].group[0] = '\0';
			}
			
			// Since we removed all client nominations...
			delete nominationsData.nominators; // close handle for nominated map
			g_Array_NominatedMaps.Erase(location);
		}
		
		return true;
	}
	
	return false;
}

stock bool RemoveAllMapNominations(const char[] group, const char[] map)
{
	RemoveMapFromNominations(group, map, ERASE_MAP_NOMINATIONS);
}

stock bool RemoveClientMapNomination(int client)
{
	if (g_MapNominations[client].map[0] != '\0' && g_MapNominations[client].group[0] != '\0')
	{
		RemoveMapFromNominations(g_MapNominations[client].map, g_MapNominations[client].group, client);
	}
	g_MapNominations[client].map[0] = '\0';
	g_MapNominations[client].group[0] = '\0';
}

void InternalLoadMapList()
{
	// We're calling the external function here.  This way, if we move it to a subplugin, we can just copy/paste.
	// TODO Fix all g_MapList references.  At the moment, g_MapList is referring to an old data structure
	if (MapChoices_ReadMapList(g_MapList, g_Serial, "mapchoices", MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_MAPSFOLDER) == null && g_Serial == -1)
	{
		SetFailState("Could not load map list");
	}
	
}

void InitializeVote(MapChoices_MapChange when, ArrayList itemList, MapChoices_VoteType voteType)
{
	// This is set to false here as it is only used after this point
	g_bMapChanged = false;
	if ((g_bIsRunoff && g_Cvar_RunoffTime.IntValue == 0) || (!g_bIsRunoff && g_Cvar_WarningTime.IntValue == 0))
	{
		StartVote(when, itemList, voteType);
	}
	else
	{
		Forward_WarningTimerStarted(g_Cvar_WarningTime.IntValue, g_bIsRunoff);
		DataPack data;
		CreateDataTimer(1.0, Timer_WarningTimer, data, TIMER_REPEAT);
		
		if (g_bIsRunoff)
		{
			data.WriteCell(g_Cvar_RunoffTime.IntValue);
		}
		else
		{
			data.WriteCell(g_Cvar_WarningTime.IntValue);
		}
		data.WriteCell(when);
		data.WriteCell(itemList);
		data.WriteCell(voteType);
	}
}

public Action Timer_WarningTimer(Handle timer, DataPack data)
{
	static int timePassed = 0;
	
	data.Reset();

	int totalTime = data.ReadCell();
	MapChoices_MapChange when = data.ReadCell();
	ArrayList itemList = data.ReadCell();
	MapChoices_VoteType voteType = data.ReadCell();
	
	// Clean up Handle if map changed on us
	if (g_bMapChanged)
	{
		timePassed = 0;
		delete itemList;
		return Plugin_Stop;
	}
	
	timePassed++;
	
	if (totalTime == timePassed)
	{
		// Reset timePassed to 0
		timePassed = 0;
		
		StartVote(when, itemList, voteType);
		return Plugin_Stop;
	}
	
	Forward_WarningTimerTicked(totalTime - timePassed);
	
	return Plugin_Continue;
}

// This should not be called directly, call the command that starts the vote timer instead
void StartVote(MapChoices_MapChange when, ArrayList itemList, MapChoices_VoteType voteType)
{
	if (g_bMapVoteInProgress || g_bMapVoteCompleted)
	{
		return;
	}
	
	if (Core_IsVoteInProgress())
	{
		DataPack data;
		CreateDataTimer(1.0, Timer_WarningTimer, data, TIMER_REPEAT);
		data.WriteCell(g_Cvar_RetryTime.IntValue);
		data.WriteCell(when);
		data.WriteCell(itemList);
		data.WriteCell(voteType);
	}
	
	g_VoteType = voteType;
	
	int limit = GetVoteLimit();
	if (itemList == null || itemList.Length == 0)
	{
		// Figure out which maps we need to fetch
		
		// will involve a call to LoadMapList
		InternalLoadMapList();
		
		if (itemList == null)
			itemList = new ArrayList(sizeof(MapChoices_MapDTO));
		
		// Add Extend or Don't Change to the list
		if (itemList.Length < limit)
		{
			if (when == MapChoicesMapChange_MapEnd && g_Extends < g_Cvar_ExtendCount.IntValue)
			{
				MapChoices_MapDTO mapData;
				strcopy(mapData.map, sizeof(mapData.map), MAPCHOICES_EXTEND);
				strcopy(mapData.group, sizeof(mapData.group), MAPCHOICES_DEFAULTGROUP);
				itemList.PushArray(mapData, sizeof(mapData));
			}
			else if (when != MapChoicesMapChange_MapEnd && g_Cvar_DontChange.BoolValue)
			{
				MapChoices_MapDTO mapData;
				strcopy(mapData.map, sizeof(mapData.map), MAPCHOICES_NOCHANGE);
				strcopy(mapData.group, sizeof(mapData.group), MAPCHOICES_DEFAULTGROUP);
				itemList.PushArray(mapData, sizeof(mapData));
			}
		}
		
		// TODO: Populate the map/group list from nominations
		while (itemList.Length < limit && g_Array_NominatedMaps.Length > 0)
		{
			//TODO Figure out what to do for a group vote.
			Nominations nominationsData;
			MapChoices_MapDTO mapData;
			
			int random = GetRandomInt(0, g_Array_NominatedMaps.Length - 1);
			g_Array_NominatedMaps.GetArray(random, nominationsData, sizeof(nominationsData));
			
			CopyNominationsDataToMapChoices_MapDTO(nominationsData, mapData);
			// We must filter out maps here even if they were OK during the nomination phase
			if (!CheckMapFilter(mapData))
			{
				itemList.PushArray(mapData, sizeof(mapData));
			}
			
			// Remove the map from the nominations list regardless of how many people nominated it.
			RemoveAllMapNominations(nominationsData.group, nominationsData.map);
		}
		
		int neededMaps = limit - itemList.Length;
		
		if (neededMaps > 0)
		{
			ArrayList potentials;
			switch (g_VoteType)
			{
				case MapChoices_MapVote:
				{
					if (g_MasterVoteType == MapChoices_TieredVote)
					{
						// Tiered votes are only maps in the current group
						potentials = MapChoices_GetMapsInGroup(g_MapList, g_NextMapGroup);
					}
					else
					{
						// Shallow clone, deep clone isn't strictly needed (checkfilter will deep clone what it needs)
						// TODO Update this to use a method that flattens the map list
						potentials = MapChoices_GetAllMaps(g_MapList);
					}
					
					while (itemList.Length < limit && potentials.Length > 0)
					{
						int random = GetRandomInt(0, potentials.Length - 1);
						MapChoices_MapDTO mapData;
						potentials.GetArray(random, mapData, sizeof(mapData.attributes));
						
						if (!CheckMapFilter(mapData))
						{
							itemList.PushArray(mapData);
						}
						
						//MapChoices_DeleteMapChoices_MapDTO(mapData);
						potentials.Erase(random);
					}
					
				}
				
				case MapChoices_GroupVote:
				{
					potentials = MapChoices_GetGroupList(g_MapList);
					
					while (itemList.Length < limit && potentials.Length > 0)
					{
						int random = GetRandomInt(0, potentials.Length - 1);
						GroupData groupData;
						potentials.GetArray(random, groupData, sizeof(groupData));
						
						if (!CheckGroupFilter(groupData))
						{
							itemList.PushArray(groupData);
						}
						
						//MapChoices_DeleteGroupData(groupData);
						potentials.Erase(random);
					}
				}
			}
			delete potentials;
		}
	}
	
	// TODO the rest of the logic to start the vote
	
	g_When = when;
	g_bMapVoteInProgress = true;
	
	// Fisher-Yates shuffle the itemList
	if (g_Cvar_Randomize.BoolValue)
		ShuffleItemList(itemList);
	
	Forward_MapVoteStarted();

	int[] voters = new int[MaxClients];
	int voterCount = 0;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			if (!g_Cvar_Spectators.BoolValue || (g_Cvar_Spectators.BoolValue && GetClientTeam(i) > view_as<int>(MapChoices_TeamSpectator)))
			{
				voters[voterCount++] = i;
			}
		}
	}
	
	// TODO Move this down below the section where we prepare the item list
	Action result = Forward_VoteStart(voters, voterCount, g_Cvar_VoteTime.IntValue, voteType, itemList, g_Cvar_NoVoteButton.BoolValue);
	
	if (result == Plugin_Continue)
	{
		// TODO Fire off our internal vote

		// Make a deep copy of the itemList
		if (g_ItemData != null)
			delete g_ItemData;
		
		g_ItemData = new StringMap();
		
		// TODO Rewrite this to use GroupData when it's a group vote
		for (int i = 0; i < itemList.Length; i++)
		{
			MapChoices_MapDTO mapData;
			MapChoices_MapDTO mapDataCopy;
			itemList.GetArray(i, mapData, sizeof(mapData));
			MapChoices_CloneMapDTO(mapData, mapDataCopy);
			
			switch (voteType)
			{
				case MapChoices_MapVote:
				{
					char itemString[PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 1];
					MapChoices_GetItemString(mapDataCopy, itemString, sizeof(itemString));
					
					g_ItemData.SetArray(itemString, mapDataCopy, sizeof(mapDataCopy));
				}
				
				case MapChoices_GroupVote:
				{
					g_ItemData.SetArray(mapDataCopy.group, mapDataCopy, sizeof(mapDataCopy));
				}
			}
		}
		
		Menu vote;
		
		if (voteType == MapChoices_MapVote)
		{
			vote = new Menu(Handler_MapVote, MENU_ACTIONS_DEFAULT|MenuAction_VoteCancel|MenuAction_Display|MenuAction_DisplayItem);
			vote.SetTitle("MapChoices Map Vote Title");
		}
		else
		{
			vote = new Menu(Handler_MapVote, MENU_ACTIONS_DEFAULT|MenuAction_VoteCancel|MenuAction_Display);
			vote.SetTitle("MapChoices Group Vote Title");
		}
		
		vote.NoVoteButton = g_Cvar_NoVoteButton.BoolValue;
		vote.VoteResultCallback = Handler_MapVoteFinish;
		
		vote.DisplayVote(voters, voterCount, g_Cvar_VoteItems.IntValue);
	}
	
	// Clean up itemList here
	delete itemList;
}

void ShuffleItemList(ArrayList itemList)
{
	// Fisher-Yates shuffle
	for (int i = 0; i < itemList.Length - 1; i++)
	{
		int j = GetRandomInt(i, itemList.Length - 1);
		itemList.SwapAt(i, j);
	}
}

public int Handler_MapVote(Menu vote, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			// g_ItemData is copied out when this vote ends
			delete g_ItemData;
			delete vote;
		}
		
		case MenuAction_Display:
		{
			char title[256];
			vote.GetTitle(title, sizeof(title));
			Format(title, sizeof(title), "%T", title, param1);
			Panel panel = view_as<Panel>(param2);
			panel.SetTitle(title);
		}
		
		case MenuAction_VoteCancel:
		{
			
			ArrayList items = new ArrayList(sizeof(MapChoices_MapDTO));
			ArrayList votes = new ArrayList();
			
			switch(param1)
			{
				case VoteCancel_Generic:
				{
					// TODO Display error message?
				}
				
				case VoteCancel_NoVotes:
				{
					// We don't decide what to do here, SetWinner handles that
					for (int i = 0; i < vote.ItemCount; i++)
					{
						char item[PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 1];
						MapChoices_MapDTO mapData;
						vote.GetItem(i, item, sizeof(item));
						
						g_ItemData.GetArray(item, mapData, sizeof(mapData));
						items.PushArray(mapData, sizeof(mapData));
						votes.Push(0);
					}

				}
			}
			
			Internal_VoteCompleted(g_VoteType, items, votes, 0, true);
			delete items;
			delete votes;
		}
		
		// Only runs for Map votes
		case MenuAction_DisplayItem:
		{
			char item[PLATFORM_MAX_PATH];
			char display[256];
			vote.GetItem(param2, item, sizeof(item), _, display, sizeof(display));
			
			// Regular items are map;group, but these are left intact
			if (StrEqual(item, MAPCHOICES_EXTEND) || StrEqual(item, MAPCHOICES_NOCHANGE))
			{
				Format(display, sizeof(display), "%T", display, param1);
				return RedrawMenuItem(display);
			}
		}
	}
	
	return 0;
}

/**
 * Collect vote data and votes to pass to master vote handler
 */
public void Handler_MapVoteFinish(Menu vote,
					int num_votes,
					int num_clients,
					const int[][] client_info,
					int num_items,
					const int[][] item_info)
{
	ArrayList items = new ArrayList(sizeof(MapChoices_MapDTO));
	ArrayList voteData = new ArrayList();
	
	for (int i = 0; i < num_items; i++)
	{
		char item[PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 1];
		MapChoices_MapDTO mapData;
		vote.GetItem(item_info[i][VOTEINFO_ITEM_INDEX], item, sizeof(item));
		
		g_ItemData.GetArray(item, mapData, sizeof(mapData));
		items.PushArray(mapData, sizeof(mapData));
		voteData.Push(item_info[i][VOTEINFO_ITEM_VOTES]);
	}
	
	Internal_VoteCompleted(g_VoteType, items, voteData, num_votes, false);
}

int GetVoteLimit()
{
	int limit = g_Cvar_VoteItems.IntValue;
	if (g_OverrideVoteLimit > -1 && g_OverrideVoteLimit < limit)
	{
		limit = g_OverrideVoteLimit;
	}
	
	return limit;
}

public Action Timer_Retry(Handle timer, DataPack data)
{
	MapChoices_MapChange when = data.ReadCell();
	ArrayList itemList = data.ReadCell();
	MapChoices_VoteType voteType = data.ReadCell();

	// Clean up Handle if map changed on us
	if (g_bMapChanged)
	{
		delete itemList;
		return Plugin_Stop;
	}
	
	StartVote(when, itemList, voteType);
	
	return Plugin_Continue;
}

bool Core_IsVoteInProgress()
{
	bool inProgress = false;
	
	Action result = Forward_IsVoteIsProgress(inProgress);
	
	if (result >= Plugin_Handled)
	{
		return inProgress;
	}
	
	return IsVoteInProgress();
}

bool CheckMapFilter(MapChoices_MapDTO mapData)
{
	// Deep copy so that subplugins can't overwrite master data
	MapChoices_MapDTO dataCopy;
	MapChoices_CloneMapDTO(mapData, dataCopy);
	
	Action result = Forward_CheckMapFilter(dataCopy);
	if (result >= Plugin_Handled)
	{
		return false;
	}
	
	return true;
}

bool CheckGroupFilter(GroupData groupData)
{
	MapChoices_GroupDTO dataCopy;
	groupData.ToDTO(dataCopy);
	
	return CheckGroupFilterDTO(dataCopy, false);
}

bool CheckGroupFilterDTO(const MapChoices_GroupDTO groupData, bool deepCopy=true)
{
	// Deep copy so that subplugins can't overwrite master data
	MapChoices_GroupDTO dataCopy;
	
	if (deepCopy)
	{
		MapChoices_CloneGroupDTO(groupData, dataCopy);
	}
	else
	{
		dataCopy = groupData;
	}
	
	Action result = Forward_CheckGroupFilter(dataCopy);
	if (result >= Plugin_Handled)
	{
		return false;
	}
	
	return true;
}

void ExtendMap()
{
	if (g_Cvar_Winlimit != null && g_Cvar_Winlimit.IntValue > 0)
	{
		g_Cvar_Winlimit.IntValue += g_Cvar_ExtendRounds.IntValue;
	}
	
	if (g_Cvar_MaxRounds != null && g_Cvar_MaxRounds.IntValue > 0)
	{
		g_Cvar_MaxRounds.IntValue += g_Cvar_ExtendRounds.IntValue;
	}

	if (g_Cvar_FragLimit != null && g_Cvar_FragLimit.IntValue > 0)
	{
		g_Cvar_FragLimit.IntValue += g_Cvar_ExtendFrags.IntValue;
	}
	
	int time;
	if (GetMapTimeLimit(time) && time > 0)
	{
		ExtendMapTimeLimit(g_Cvar_ExtendTime.IntValue * 60);
	}
}

// Internal implementation of VoteCompleted.
// Called both from MapChoices_VoteCompleted native and from internal vote handlers
void Internal_VoteCompleted(MapChoices_VoteType voteType, ArrayList items, ArrayList votes, int totalVotes, bool canceled)
{
	if (canceled)
	{
		if (items.Length > 0)
		{
			if (g_Cvar_NoVote.BoolValue)
			{
				SelectWinner(voteType, items, votes, totalVotes);
			}
			else
			{
				// TODO: Choose if we want to do anything with result
				Forward_VoteLost(MapChoices_FailedNoVotes);
			}
		}
		
		return;
	}
}

// Select a winner or pass control back
void SelectWinner(MapChoices_VoteType voteType, ArrayList items, ArrayList votes, int totalVotes)
{
	if (items.Length != votes.Length)
	{
		LogError("SelectWinner called with uneven ArrayLists: items: %d, votes: %d", items.Length, votes.Length);
		return;
	}
	
	int itemVotes = votes.Get(0);
	
	int votePercent = RoundFloat(float(itemVotes) / float(totalVotes) * 100.0);
	
	if (g_Cvar_Runoffs.BoolValue && votePercent < g_Cvar_RunoffPercent.IntValue && !g_bIsRunoff)
	{
		// TODO: Choose if we want to do anything with result
		Forward_VoteLost(MapChoices_FailedQuorum);
		
		ArrayList newItems = new ArrayList(sizeof(MapChoices_MapDTO));
		
		int count = 0;
		int previousItemVotes;
		
		for (int i = 0; i < items.Length; i++)
		{
			previousItemVotes = itemVotes;
			itemVotes = votes.Get(count);

			// Break if we are past 2 items and the vote count isn't the same as the previous count.
			if (i >= 2 && itemVotes != previousItemVotes)
			{
				break;
			}
			MapChoices_MapDTO mapData;
			items.GetArray(count, mapData, sizeof(mapData));
			newItems.PushArray(mapData, sizeof(mapData));
		}
		
		// Start the runoff vote
		g_bIsRunoff = true;
		InitializeVote(g_When, newItems, voteType);
		delete newItems;
	}
	else
	{
		g_bIsRunoff = false;
		
		MapChoices_MapDTO mapData;
		items.GetArray(0, mapData, sizeof(mapData));
		
		Forward_VoteWon(g_When, mapData);
		
		if (StrEqual(mapData.map, MAPCHOICES_EXTEND))
		{
			PrintToChatAll("%t", "MapChoices Current Map Extended", votePercent, totalVotes);
			ExtendMap();
			Forward_MapVoteEnded(mapData.group, mapData.map);
			g_Extends++;
		}
		else if (StrEqual(mapData.map, MAPCHOICES_NOCHANGE))
		{
			PrintToChatAll("%t", "MapChoices Current Map Stays", votePercent, totalVotes);
			Forward_MapVoteEnded(mapData.group, mapData.map);
		}
		else if (voteType == MapChoices_GroupVote)
		{
			PrintToChatAll("%t", "MapChoices Group Voting Finished", mapData.group, votePercent, totalVotes);
			
			if (g_MasterVoteType == MapChoices_TieredVote)
			{
				
				ArrayList newItemList = MapChoices_GetMapsInGroup(g_MapList, mapData.group);
				InitializeVote(g_When, newItemList, MapChoices_MapVote);
				// TODO Set up map vote
			}
			else
			{
				char map[PLATFORM_MAX_PATH];
				
				// TODO Select random non-recently played map from group
				
				g_bMapVoteCompleted = true;
				Forward_MapVoteEnded(mapData.group, map);
			}
		}
		else
		{
			char displayString[PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 3];
			MapChoices_GetMapDisplayString(mapData, displayString, sizeof(displayString));
			
			if (StrEqual(mapData.group, MAPCHOICES_DEFAULTGROUP))
			{
				PrintToChatAll("%t", "MapChoices Map Voting Finished Simple", displayString,
					votePercent, totalVotes);
			}
			else
			{
				PrintToChatAll("%t", "MapChoices Map Voting Finished Advanced", displayString,
					mapData.group, votePercent, totalVotes);
			}
			
			g_bMapVoteCompleted = true;
			Forward_MapVoteEnded(mapData.group, mapData.map);
			SetNextMap(mapData.map);
		}
		
		Forward_VoteFinished(voteType);
	}
}

MapChoices_NominateResult InternalNominateMap(const MapChoices_MapDTO mapData, int owner)
{
	if (!IsMapValid(mapData.map))
	{
		return MapChoicesNominateResult_InvalidMap;
	}
	
	RemoveClientMapNomination(owner);
	
	bool newMap = false;
	Nominations nominationsData;

	int pos = FindMapInNominations(mapData.group, mapData.map);
	if (pos > -1)
	{
		g_Array_NominatedMaps.GetArray(pos, nominationsData, sizeof(nominationsData));
		
		nominationsData.nominators.Push(owner);
		
	}
	else
	{
		// Create the data for this nomination
		CopyMapChoices_MapDTOToNominationsData(mapData, nominationsData);
		nominationsData.nominators = new ArrayList();
		nominationsData.nominators.Push(owner);
		
		g_Array_NominatedMaps.PushArray(nominationsData);
		newMap = true;
	}
	
	Forward_NominationAdded(nominationsData.group, nominationsData.map,
		owner, newMap);
	
	return newMap ? MapChoicesNominateResult_Added : MapChoicesNominateResult_AlreadyInVote;
}

void CopyMapChoices_MapDTOToNominationsData(const MapChoices_MapDTO mapData, Nominations nominationsData)
{
	strcopy(nominationsData.map, sizeof(nominationsData.map), mapData.map);
	strcopy(nominationsData.group, sizeof(nominationsData.group), mapData.group);
	
	CopyCharStringMap(mapData.attributes, nominationsData.mapAttributes);
	//CopyCharStringMap(mapData.groupAttributes, nominationsData.groupAttributes);
}

void CopyNominationsDataToMapChoices_MapDTO(const Nominations nominationsData, MapChoices_MapDTO mapData)
{
	strcopy(mapData.map, sizeof(mapData.map), nominationsData.map);
	strcopy(mapData.group, sizeof(mapData.group), nominationsData.group);
	
	CopyCharStringMap(nominationsData.mapAttributes, mapData.attributes);
}

// Events
// Note: These are just the shared events.  Game-specific events will be in game plugins.

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bTempIgnoreRoundEnd)
	{
		return;
	}
	
	if (g_bChangeAtRoundEnd)
	{
		ChangeMap(true);
	}
}

void ChangeMap(bool isRoundEnd)
{
	char map[PLATFORM_MAX_PATH];
	
	GetNextMap(map, sizeof(map));
	
	Action result = Forward_ChangeMap(map, isRoundEnd);
	
	if (result < Plugin_Handled)
	{
		if (!isRoundEnd)
		{
			EndRound();
		}
		
		if (g_Cvar_BonusTime != null)
		{
			CreateTimer(g_Cvar_BonusTime.FloatValue - 0.2, Timer_EndGame, _, TIMER_FLAG_NO_MAPCHANGE);
		}
		else
		{
			EndGame();
		}
	}
}

public Action Timer_EndGame(Handle timer)
{
	EndGame();
}

// Note: This is the generic version.  Other games have better ways of doing this, such as CSS/CSGO's CS_TerminateRound method
// and TF2's team_control_point_master's SetWinner or game_round_win entity
void EndRound()
{
	Event roundEndEvent = CreateEvent("round_end");
	if (roundEndEvent != null)
	{
		g_bTempIgnoreRoundEnd = true;
		roundEndEvent.SetInt("winner", view_as<int>(MapChoices_TeamUnassigned)); // This won't work for HL2:DM, which expects a player for non-team games
		roundEndEvent.SetInt("reason", 0); // Usually time ran out
		roundEndEvent.SetString("message", "Map Change");
		roundEndEvent.Fire();
	}
}

void EndGame()
{
	int entity = -1;
	
	entity = FindEntityByClassname(-1, "game_end");
	
	if (entity == -1)
	{
		entity = CreateEntityByName("game_end");
		if (entity > -1)
		{
			if (DispatchSpawn(entity))
			{
				AcceptEntityInput(entity, "EndGame");
				return;
			}
		}
	}
	
	//Event gameEndEvent = CreateEvent("game_end");
	//gameEndEvent.SetInt("winner", view_as<int>(MapChoices_TeamUnassigned)); // This won't work for HL2:DM, which expects a player for non-team games
	//gameEndEvent.Fire();
	
//	CreateTimer(g_Cvar_ChatTime.FloatValue, Timer_End, _, TIMER_FLAG_NO_MAPCHANGE);
}

//public Action Timer_End(Handle timer)
//{
//	char map[PLATFORM_MAX_PATH];
//	GetNextMap(map, sizeof(map));
//	
//	ForceChangeLevel(map, "Map Vote");
//}

////////////////////////////////////////////////////////////////////////
// Forwards

// Public

void Forward_MapVoteStarted()
{
	Call_StartForward(g_Forward_MapVoteStarted);
	Call_PushCell(g_bIsRunoff);
	Call_Finish();
}

void Forward_MapVoteEnded(const char[] group, const char[] map)
{
	Call_StartForward(g_Forward_MapVoteEnded);
	Call_PushString(group);
	Call_PushString(map);
	Call_Finish();
	
	// This needs to be deleted every time a full vote finished
	delete g_Forward_VoteFinished;	
}

void Forward_WarningTimerStarted(int seconds, bool runoff)
{
	Call_StartForward(g_Forward_WarningTimerStarted);
	Call_PushCell(seconds);
	Call_PushCell(runoff);
	Call_Finish();
}

void Forward_WarningTimerTicked(int seconds)
{
	Call_StartForward(g_Forward_WarningTimerTicked);
	Call_PushCell(seconds);
	Call_Finish();
}

void Forward_NominationAdded(const char[] group, const char[] map, int owner, bool newMap)
{
	Call_StartForward(g_Forward_NominationAdded);
	Call_PushString(group);
	Call_PushString(map);
	Call_PushCell(owner);
	Call_PushCell(newMap);
	Call_Finish();
}

void Forward_NominationRemoved(const char[] group, const char[] map, int owner, bool removed)
{
	Call_StartForward(g_Forward_NominationRemoved);
	Call_PushString(group);
	Call_PushString(map);
	Call_PushCell(owner);
	Call_PushCell(removed);
	Call_Finish();
}

// Private

Action Forward_VoteStart(int[] voters, int voterCount, int duration, MapChoices_VoteType voteType, ArrayList itemList, bool noVoteOption)
{
	Action result = Plugin_Continue;
	Call_StartForward(g_Forward_HandlerVoteStart);
	Call_PushArray(voters, voterCount);
	Call_PushCell(voterCount);
	Call_PushCell(duration);
	Call_PushCell(voteType);
	Call_PushCell(itemList);
	Call_PushCell(noVoteOption);
	Call_Finish(result);
	
	return result;
}

Action Forward_VoteCancel()
{
	Action result = Plugin_Continue;
	Call_StartForward(g_Forward_HandlerCancelVote);
	Call_Finish(result);
	
	return result;
}

Action Forward_IsVoteIsProgress(bool &isInProgress)
{
	Action result = Plugin_Continue;
	
	Call_StartForward(g_Forward_HandlerIsVoteInProgress);
	Call_PushCellRef(isInProgress);
	Call_Finish(result);
	
	return result;
}

Action Forward_VoteLost(MapChoices_VoteFailedType failType)
{
	Action result = Plugin_Continue;
	Call_StartForward(g_Forward_HandlerVoteLost);
	Call_PushCell(failType);
	Call_Finish(result);
	
	return result;
}

Action Forward_VoteWon(MapChoices_MapChange when, const MapChoices_MapDTO mapData)
{
	Action result = Plugin_Continue;
	Call_StartForward(g_Forward_HandlerVoteWon);
	Call_PushCell(when);
	Call_PushArray(mapData, sizeof(mapData));
	Call_Finish(result);
	
	return result;
}

Action Forward_CheckMapFilter(MapChoices_MapDTO mapData)
{
	Action result = Plugin_Continue;

	Call_StartForward(g_Forward_MapFilter);
	Call_PushArray(mapData, sizeof(mapData));
	Call_Finish(result);
	
	return result;
}

Action Forward_CheckGroupFilter(MapChoices_GroupDTO groupData)
{
	Action result = Plugin_Continue;

	Call_StartForward(g_Forward_GroupFilter);
	Call_PushArray(groupData, sizeof(groupData));
	Call_Finish(result);
	
	return result;
}

Action Forward_ChangeMap(const char[] map, bool isRoundEnd)
{
	Action result = Plugin_Continue;
	Call_StartForward(g_Forward_ChangeMap);
	Call_PushString(map);
	Call_PushCell(isRoundEnd);
	Call_Finish(result);
	
	return result;
}

void Forward_VoteFinished(MapChoices_VoteType voteType)
{
	if (g_Forward_VoteFinished != null)
	{
		Call_StartForward(g_Forward_VoteFinished);
		Call_PushCell(voteType);
		Call_Finish();
	}
}


////////////////////////////////////////////////////////////////////////
// Natives

// native MapChoices_NominateResult MapChoices_Nominate(const char[] group, const char[] map, int owner);
public int Native_Nominate(Handle plugin, int numParams)
{
	MapChoices_MapDTO mapData;
	GetNativeArray(1, mapData, sizeof(mapData));
	
	return view_as<int>(InternalNominateMap(mapData, GetNativeCell(2)));
}

// native ArrayList MapChoices_GetNominatedMapList();
public int Native_GetNominatedMapList(Handle plugin, int numParams)
{
	ArrayList maparray = new ArrayList(sizeof(MapChoices_MapDTO));
	
	for (int i = 0; i < g_Array_NominatedMaps.Length; i++)
	{
		Nominations nominationsData;
		g_Array_NominatedMaps.GetArray(i, nominationsData, sizeof(nominationsData));
		
		MapChoices_MapDTO mapData;
		strcopy(mapData.map, sizeof(mapData.map), nominationsData.map);
		strcopy(mapData.group, sizeof(mapData.group), nominationsData.group);
		
		maparray.PushArray(mapData, sizeof(mapData));
	}
	
	return view_as<int>(maparray);
}

// native ArrayList MapChoices_GetNominatedMapOwners(const char[] group, const char[] map);
public int Native_GetNominatedMapOwners(Handle plugin, int numParams)
{
	int stringLength;
	GetNativeStringLength(1, stringLength);
	char[] group = new char[stringLength + 1];
	GetNativeString(1, group, stringLength + 1);

	GetNativeStringLength(2, stringLength);
	char[] map = new char[stringLength + 1];
	GetNativeString(2, map, stringLength + 1);
	
	int pos = FindMapInNominations(group, map);
	
	if (pos == -1)
		return view_as<int>(INVALID_HANDLE);
	
	Nominations mapData;
	
	g_Array_NominatedMaps.GetArray(pos, mapData, sizeof(mapData));
	
	ArrayList returnList = null;
	if (mapData.nominators == null)
		return view_as<int>(INVALID_HANDLE);
		
	ArrayList tempList = mapData.nominators.Clone();
	returnList = view_as<ArrayList>(CloneHandle(tempList, plugin));
	delete tempList;
	
	return view_as<int>(returnList);
}

// native void MapChoices_GetCurrentMapGroup(char[] group, int maxlength);
public int Native_GetCurrentMapGroup(Handle plugin, int numParams)
{
	SetNativeString(1, g_MapGroup, GetNativeCell(2));
}

// native MapChoices_VoteType MapChoices_GetVoteType();
public int Native_GetVoteType(Handle plugin, int numParams)
{
	return view_as<int>(g_MasterVoteType);
}

// native bool MapChoices_GetMapChoices_MapDTO(const char[] group, const char[] map, int mapData[MapChoices_MapDTO]);
public int Native_GetMapChoices_MapDTO(Handle plugin, int numParams)
{
	// TODO: Implement this
}

// native bool MapChoices_CanStartVote();
public int Native_CanStartVote(Handle plugin, int numParams)
{
	if (Core_IsVoteInProgress())
	{
		return false;
	}
	// TODO: Implement this
	
	return true;
}

//native void MapChoices_InitiateVote(MapChoices_MapChange when, ArrayList itemList, const char[] module, MapChoices_VoteFinished finishedFunction = INVALID_FUNCTION);
public int Native_InitiateVote(Handle plugin, int numParams)
{
	MapChoices_MapChange when = GetNativeCell(1);
	ArrayList mapList = view_as<ArrayList>(GetNativeCell(2));
	
	int stringLength;
	GetNativeStringLength(3, stringLength);
	
	char[] module = new char[stringLength +1];
	GetNativeString(3, module, stringLength);
	
	Function finishedFunction = GetNativeFunction(4);

	if (finishedFunction != INVALID_FUNCTION)
	{
		g_Forward_VoteFinished = CreateForward(ET_Ignore, Param_Cell);
		AddToForward(g_Forward_VoteFinished, plugin, finishedFunction);
	}
	
	MapChoices_VoteType voteType = view_as<MapChoices_VoteType>(g_Cvar_VoteType.IntValue);
	
	InitializeVote(when, mapList.Clone(), voteType);
}

public int Native_VoteCompleted(Handle plugin, int numParams)
{
	MapChoices_VoteType voteType = view_as<MapChoices_VoteType>(GetNativeCell(1));
	
	ArrayList items = view_as<ArrayList>(GetNativeCell(2));
	ArrayList votes = view_as<ArrayList>(GetNativeCell(3));
	int totalVotes = GetNativeCell(4);
	bool canceled = GetNativeCell(5);
	
	Internal_VoteCompleted(voteType, items, votes, totalVotes, canceled);
}

// native bool MapChoices_RegisterVoteHandler(MapChoices_HandlerStartVote startVote, MapChoices_HandlerCancelVote cancelVote, MapChoices_HandlerIsVoteInProgress isVoteInProgress, int voteLimit=-1);
public int Native_RegisterVoteHandler(Handle plugin, int numParams)
{
	Function startVote = GetNativeFunction(1);
	Function cancelVote = GetNativeFunction(2);
	Function isVoteInProgress = GetNativeFunction(3);
	int voteLimit = GetNativeCell(4);
	
	AddToForward(g_Forward_HandlerVoteStart, plugin, startVote);
	AddToForward(g_Forward_HandlerCancelVote, plugin, cancelVote);
	AddToForward(g_Forward_HandlerIsVoteInProgress, plugin, isVoteInProgress);
	
	g_OverrideVoteLimit = voteLimit;
}

// native bool MapChoices_UnregisterVoteHandler(MapChoices_HandlerStartVote startVote, MapChoices_HandlerCancelVote cancelVote, MapChoices_HandlerIsVoteInProgress isVoteInProgress);
public int Native_UnregisterVoteHandler(Handle plugin, int numParams)
{
	Function startVote = GetNativeFunction(1);
	Function cancelVote = GetNativeFunction(2);
	Function isVoteInProgress = GetNativeFunction(3);
	
	RemoveFromForward(g_Forward_HandlerVoteStart, plugin, startVote);
	RemoveFromForward(g_Forward_HandlerCancelVote, plugin, cancelVote);
	RemoveFromForward(g_Forward_HandlerIsVoteInProgress, plugin, isVoteInProgress);
	
	g_OverrideVoteLimit = -1;
}

// native bool MapChoices_RegisterMapFilter(MapChoices_MapFilter filter);
public int Native_RegisterMapFilter(Handle plugin, int numParams)
{
	Function func = GetNativeFunction(1);
	
	return AddToForward(g_Forward_MapFilter, plugin, func);
}

// native bool MapChoices_UnregisterMapFilter(MapChoices_MapFilter filter);
public int Native_UnregisterMapFilter(Handle plugin, int numParams)
{
	Function func = GetNativeFunction(1);
	
	return RemoveFromForward(g_Forward_MapFilter, plugin, func);
}

// native bool MapChoices_RegisterGroupFilter(MapChoices_GroupFilter filter);
public int Native_RegisterGroupFilter(Handle plugin, int numParams)
{
	Function func = GetNativeFunction(1);
	
	return AddToForward(g_Forward_GroupFilter, plugin, func);
}

// native bool MapChoices_UnregisterGroupFilter(MapChoices_GroupFilter filter);
public int Native_UnregisterGroupFilter(Handle plugin, int numParams)
{
	Function func = GetNativeFunction(1);
	
	return RemoveFromForward(g_Forward_GroupFilter, plugin, func);
}

// native bool MapChoices_CheckMapFilter(const int mapData[MapChoices_MapDTO]);
public int Native_CheckMapFilter(Handle plugin, int numParams)
{
	MapChoices_MapDTO mapData;
	GetNativeArray(1, mapData, sizeof(mapData));
	
	return CheckMapFilter(mapData);
}

// native bool MapChoices_CheckGroupFilter(const int groupData[groupdata_t]);
public int Native_CheckGroupFilter(Handle plugin, int numParams)
{
	MapChoices_GroupDTO groupData;
	GetNativeArray(1, groupData, sizeof(groupData));
	
	return CheckGroupFilterDTO(groupData);
}

// native bool MapChoices_WillChangeAtRoundEnd();
public int Native_WillChangeAtRoundEnd(Handle plugin, int numParams)
{
	return g_bChangeAtRoundEnd;
}

// native bool MapChoices_RegisterChangeMapHandler(MapChoices_ChangeMapForward changeMapHandler);
public int Native_RegisterChangeMapHandler(Handle plugin, int numParams)
{
	Function func = GetNativeFunction(1);
	
	return AddToForward(g_Forward_ChangeMap, plugin, func);
}

// native bool MapChoices_UnregisterChangeMapHandler(MapChoices_ChangeMapForward changeMapHandler);
public int Native_UnregisterChangeMapHandler(Handle plugin, int numParams)
{
	Function func = GetNativeFunction(1);
	
	return RemoveFromForward(g_Forward_ChangeMap, plugin, func);
}

// native void MapChoices_AddGameFlags(MapChoices_GameFlags flags);
public int Native_AddGameFlags(Handle plugin, int numParams)
{
	MapChoices_GameFlags newFlags = view_as<MapChoices_GameFlags>(GetNativeCell(1));
	
	g_GameFlags |= newFlags;
}

// native void MapChoices_RemoveGameFlags(MapChoices_GameFlags flags);
public int Native_RemoveGameFlags(Handle plugin, int numParams)
{
	MapChoices_GameFlags removeFlags = view_as<MapChoices_GameFlags>(GetNativeCell(1));
	
	g_GameFlags &= ~removeFlags;
}

// native MapChoices_GameFlags MapChoices_GetGameFlags();
public int Native_GetGameFlags(Handle plugin, int numParams)
{
	return view_as<int>(g_GameFlags);
}

// MapChoices_OverrideConVar(MapChoices_ConVarOverride overrideConVar, ConVar conVar)
public int Native_OverrideConVar(Handle plugin, int numParams)
{
	MapChoices_ConVarOverride overrideConVar = GetNativeCell(1);
	ConVar conVar = GetNativeCell(2);
	
	if (conVar == null)
	{
		return false;
	}
	
	switch (overrideConVar)
	{
		case MapChoicesConVar_BonusTime:
		{
			g_Cvar_BonusTime = conVar;
			return true;
		}
		
		case MapChoicesConVar_Winlimit:
		{
			g_Cvar_Winlimit = conVar;
			return true;
		}
		
		case MapChoicesConVar_FragLimit:
		{
			g_Cvar_FragLimit = conVar;
			return true;
		}
		
		case MapChoicesConVar_MaxRounds:
		{
			g_Cvar_MaxRounds = conVar;
			return true;
		}
	}
	
	return false;
}

// native void MapChoices_ResetConVar(MapChoices_ConVarOverride overrideConVar);
public int Native_ResetConVar(Handle plugin, int numParams)
{
	MapChoices_ConVarOverride overrideConVar = GetNativeCell(1);
	
	switch(overrideConVar)
	{
		case MapChoicesConVar_BonusTime:
		{
			g_Cvar_BonusTime = FindConVar("mp_bonusroundtime");
		}
		
		case MapChoicesConVar_Winlimit:
		{
			g_Cvar_Winlimit = FindConVar("mp_winlimit");
		}
		
		case MapChoicesConVar_FragLimit:
		{
			g_Cvar_FragLimit = FindConVar("mp_fraglimit");
		}
		
		case MapChoicesConVar_MaxRounds:
		{
			g_Cvar_MaxRounds = FindConVar("mp_maxrounds");
		}
	}
}

// native ConVar MapChoices_GetConVarOverride(MapChoices_ConVarOverride overrideConVar);
public int Native_GetConVarOverride(Handle plugin, int numParams)
{
	MapChoices_ConVarOverride overrideConVar = GetNativeCell(1);
	
	ConVar out;
	
	switch(overrideConVar)
	{
		case MapChoicesConVar_BonusTime:
		{
			out = g_Cvar_BonusTime;
		}
		
		case MapChoicesConVar_Winlimit:
		{
			out = g_Cvar_Winlimit;
		}
		
		case MapChoicesConVar_FragLimit:
		{
			out = g_Cvar_FragLimit;
		}
		
		case MapChoicesConVar_MaxRounds:
		{
			out = g_Cvar_MaxRounds;
		}
	}
	
	return view_as<int>(out);
}

////////////////////////////////////////////////////////////////////////
// Stocks

/**
 * Given an itemList and group name, return an ArrayList of all MapDTO items with the matching group
 * 
 * @param itemList      A list returned from MapChoices_ReadMapList
 * @param groupName     The group name to look for
 * 
 * @deprecated          Will be removed when the mapdata rewrite is finished
 * @return ArrayList    An ArrayList of MapChoices_MapChoices_MapDTO of the matching items.
 */
stock ArrayList MapChoices_GetMapsInGroup(StringMap itemList, const char[] groupName)
{
	if (itemList == null)
		ThrowError("Null itemList not allowed.");
		
	ArrayList newItems = new ArrayList(sizeof(MapChoices_MapDTO));
	GroupData groupData;
	
	if (!itemList.GetArray(groupName, groupData, sizeof(groupData)))
	{
		LogError("itemList does not have a group named \"%s\"", groupName);
		return newItems;
	}
	
	if (groupData.mapList == null)
	{
		LogError("itemList group \"%s\" has no map list", groupName);
		return newItems;
	}
	
	StringMapSnapshot snapshot = groupData.mapList.Snapshot();
	
	for (int i = 0; i < snapshot.Length; i++)
	{
		int keySize = snapshot.KeyBufferSize(i);
		char[] key = new char[keySize];
		snapshot.GetKey(i, key, keySize);
		
		MapChoices_MapDTO mapData;
		strcopy(mapData.map, sizeof(mapData.map), key);
		strcopy(mapData.group, sizeof(mapData.group), groupName);
		groupData.mapList.GetValue(key, mapData.attributes);
		
		newItems.PushArray(mapData, sizeof(mapData));
	}
	
	return newItems;
}

/**
 * Get a list of all maps in the itemList
 * 
 * @param itemList          A list returned from MapChoices_ReadMapList
 * @return ArrayList        An ArrayList of MapChoices_MapDTO items.
 */
stock ArrayList MapChoices_GetAllMaps(StringMap itemList)
{
	if (itemList == null)
		ThrowError("Null itemList not allowed.");
	
	ArrayList newItems = new ArrayList(sizeof(MapChoices_MapDTO));
	
	StringMapSnapshot groupSnapshot = itemList.Snapshot();
	
	for (int i = 0; i < groupSnapshot.Length; i++)
	{
		int groupKeySize = groupSnapshot.KeyBufferSize(i);
		char[] groupName = new char[groupKeySize];
		groupSnapshot.GetKey(i, groupName, groupKeySize);
		
		GroupData groupData;

		itemList.GetArray(groupName, groupData, sizeof(groupData));
		
		if (groupData.mapList == null)
		{
			LogError("itemList group \"%s\" has no map list", groupName);
			continue;
		}
			
		StringMapSnapshot snapshot = groupData.mapList.Snapshot();
		
		for (int j = 0; j < snapshot.Length; j++)
		{
			int keySize = snapshot.KeyBufferSize(j);
			char[] key = new char[keySize];
			snapshot.GetKey(j, key, keySize);
			
			MapChoices_MapDTO mapData;
			MapChoices_MapDTO mapDataCopy;
			groupData.mapList.GetArray(key, mapData, sizeof(mapData));
			MapChoices_CloneMapDTO(mapData, mapDataCopy);
			
			newItems.PushArray(mapDataCopy, sizeof(mapDataCopy));
		}
		
		delete snapshot;
	}
	
	delete groupSnapshot;
	
	return newItems;
}

/*
 * Deep Copy a GroupData
 * This can't be a method on the enum struct or else you'll get a 
 * "error 087: enum struct "GroupData" cannot refer to itself"
 *
 * @param groupData     GroupData to copy
 * @param plugin        Handle of plugin to set as owner or null for no change
 * @param includeMaps   Deep copy the mapList
 *
 * @return              A deep copy (mapList optional) of this GroupData
 */
stock void CloneGroupData(const GroupData groupData, GroupData groupDataCopy, Handle plugin = null, bool includeMaps = true)
{
	strcopy(groupDataCopy.group, sizeof(groupDataCopy.group), groupData.group);
	
	groupDataCopy.attributes = CopyCharStringMap(groupData.attributes, plugin);
	
	if (includeMaps && groupData.mapList != null)
	{
		groupDataCopy.mapList = new StringMap();
		if (plugin != null)
		{
			StringMap tempCopy = groupDataCopy.mapList;
			groupDataCopy.mapList = view_as<StringMap>(CloneHandle(tempCopy, plugin));
			delete tempCopy;
		}
		
		StringMapSnapshot snapshot = groupData.mapList.Snapshot();
		
		for (int i = 0; i < snapshot.Length; i++)
		{
			int keySize = snapshot.KeyBufferSize(i);
			char[] map = new char[keySize];
			snapshot.GetKey(i, map, keySize);
			
			StringMap attributes;
			groupData.mapList.GetValue(map, attributes);
			
			StringMap mapAttributes = CopyCharStringMap(attributes, plugin);
			groupDataCopy.mapList.SetValue(map, mapAttributes);
		}
		
		delete snapshot;
	}
}

