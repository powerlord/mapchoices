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

#include "include/mapchoices" // Include our own file to gain access to enums and the like
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required
#define VERSION "1.0.0 alpha 1"

// SM 1.6 style array to store nominations data
// Note that NominationsData_Nominators is not used in g_MapNominations
enum nominations_t
{
	String:NominationsData_Map[PLATFORM_MAX_PATH],
	String:NominationsData_MapGroup[MAPCHOICES_MAX_GROUP_LENGTH],
	ArrayList:NominationsData_Nominators
}

// ArrayList of nominations_t
ArrayList g_Array_NominatedMaps;

int g_MapNominations[MAXPLAYERS+1][nominations_t];

//ConVars
ConVar g_Cvar_Enabled;
ConVar g_Cvar_RetryTime;
ConVar g_Cvar_VoteItems;
ConVar g_Cvar_WarningTime;

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
Handle g_Forward_NominationAdded;
Handle g_Forward_NominationRemoved;

// Private Forwards
Handle g_Forward_HandlerVoteStart;
Handle g_Forward_HandlerCancelVote;
Handle g_Forward_HandlerIsVoteInProgress;

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

int g_VoteStartRound = 0;

ArrayList g_MapList = null;
int g_Serial = -1;

char g_MapGroup[MAPCHOICES_MAX_GROUP_LENGTH];

//new Handle:m_ListLookup;

Handle g_hTimeLimitVote;

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
	
	// Map filter natives
	CreateNative("MapChoices_RegisterMapFilter", Native_AddMapFilter);
	CreateNative("MapChoices_RemoveMapFilter", Native_RemoveMapFilter);
	CreateNative("MapChoices_RegisterGroupFilter", Native_AddGroupFilter);
	CreateNative("MapChoices_UnregisterGroupFilter", Native_RemoveGroupFilter);
	
	CreateNative("MapChoices_WillChangeAtRoundEnd", Native_WillChangeAtRoundEnd);
	
	CreateNative("MapChoices_OverrideConVar", Native_OverrideConVar);
	CreateNative("MapChoices_ResetConVar", Native_ResetConVar);
	
	CreateNative("MapChoices_GetCurrentMapGroup", Native_GetCurrentMapGroup);
	
	CreateNative("MapChoices_GetNominatedMapList", Native_GetNominatedMapList);
	CreateNative("MapChoices_GetNominatedMapOwners", Native_GetNominatedMapOwners);
	
	RegPluginLibrary("mapchoices");
}
  
public void OnPluginStart()
{
	InitializeConfigurationParser();
	//m_ListLookup = new StringMap();
	
	LoadTranslations("common.phrases");
	LoadTranslations("mapchoices.phrases");
	
	CreateConVar("mapchoices_version", VERSION, "MapChoices version", FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	g_Cvar_Enabled = CreateConVar("mapchoices_enable", "1", "Enable MapChoices?", FCVAR_NOTIFY|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	g_Cvar_RetryTime = CreateConVar("mapchoices_retrytime", "5.0", "How long (in seconds) to wait before we retry the vote if a vote is already running?", _, true, 1.0, true, 15.0);
	g_Cvar_VoteItems = CreateConVar("mapchoices_voteitems", "6", "How many items should appear in each vote? This may be capped in alternate vote systems (TF2 NativeVotes caps to 5).", _, true, 2.0, true, 8.0);
	g_Cvar_WarningTime = CreateConVar("mapchoices_warningtime", "15", "How many seconds before a vote starts do you want a warning timer to run. 0 = Disable", _, true, 0.0, true, 60.0);
	
	// Core map vote starting stuff
	
	g_Array_NominatedMaps = new ArrayList(nominations_t);
	
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
	g_Forward_NominationAdded = CreateGlobalForward("MapChoices_OnNominationAdded", ET_Ignore, Param_String, Param_String, Param_Cell, Param_Cell);
	g_Forward_NominationRemoved = CreateGlobalForward("MapChoices_OnNominationRemoved", ET_Ignore, Param_String, Param_String, Param_Cell, Param_Cell);
	
	g_Forward_HandlerVoteStart = CreateForward(ET_Hook, Param_Cell);
	g_Forward_HandlerCancelVote = CreateForward(ET_Hook);
	g_Forward_HandlerIsVoteInProgress = CreateForward(ET_Hook);
		
	g_Forward_MapFilter = CreateForward(ET_Hook, Param_String, Param_String, Param_Cell, Param_Cell);
	g_Forward_GroupFilter = CreateForward(ET_Hook, Param_String, Param_Cell);
	
	g_Forward_ChangeMap = CreateForward(ET_Single, Param_String, Param_Cell);
	
	g_MapList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	
	HookEvent("round_end", Event_RoundEnd);
	HookEventEx("round_win", Event_RoundEnd);
	HookEventEx("teamplay_round_win", Event_RoundEnd);
	
	AutoExecConfig(true, "mapchoices");
}

public void OnMapStart()
{
	InternalLoadMapList();
	
	g_bChangeAtRoundEnd = false;
	g_bTempIgnoreRoundEnd = false;
	
	g_bMapVoteInProgress = false;
	g_bMapVoteCompleted = false;
}

public void OnClientDisconnect(int client)
{
	// Clear the client's nominations
	RemoveClientMapNomination(client);
}

int FindMapInNominations(const char[] group, const char[] map)
{
	if (strlen(group) <= 0 || strlen(map) <= 0)
	{
		return -1;
	}
	
	for (int i = 0; i < g_Array_NominatedMaps.Length; i++)
	{
		int nominationsData[nominations_t];
		g_Array_NominatedMaps.GetArray(i, nominationsData, sizeof(nominationsData));
		
		if (StrEqual(map, nominationsData[NominationsData_Map]) && StrEqual(group, nominationsData[NominationsData_MapGroup]))
		{
			return i;
		}
	}
	
	return -1;
}

bool RemoveMapFromNominations(const char[] group, const char[] map, int client = 0)
{
	if (strlen(group) <= 0 || strlen(map) <= 0)
	{
		return false;
	}
	
	int location = FindMapInNominations(group, map);
	if (location > -1)
	{
		bool removed = false;
		
		int nominationsData[nominations_t];
		g_Array_NominatedMaps.GetArray(location, nominationsData, sizeof(nominationsData));
		
		int pos = nominationsData[NominationsData_Nominators].FindValue(client);
		
		// This should always exist unless something went wrong
		if (pos > -1)
		{
			nominationsData[NominationsData_Nominators].Erase(pos);
		}
		
		if (nominationsData[NominationsData_Nominators].Length == 0)
		{
			// Whoops, no more nominations for this map, so lets remove it
			delete nominationsData[NominationsData_Nominators]; // close handle for nominated map
			g_Array_NominatedMaps.Erase(location);
			removed = true;
		}
		
		Call_StartForward(g_Forward_NominationRemoved);
		Call_PushString(nominationsData[NominationsData_Map]);
		Call_PushString(nominationsData[NominationsData_MapGroup]);
		Call_PushCell(client);
		Call_PushCell(removed);
		Call_Finish();
		
		return true;
	}
	
	return false;
}

bool RemoveClientMapNomination(int client)
{
	if (g_MapNominations[client][NominationsData_Map][0] != '\0' && g_MapNominations[client][NominationsData_MapGroup][0] != '\0')
	{
		RemoveMapFromNominations(g_MapNominations[client][NominationsData_Map], g_MapNominations[client][NominationsData_MapGroup], client);
	}
	g_MapNominations[client][NominationsData_Map][0] = '\0';
	g_MapNominations[client][NominationsData_MapGroup][0] = '\0';
}

int FindMapInMapList(const char[] group, const char[] map)
{
	if (strlen(group) <= 0 || strlen(map) <= 0)
	{
		return -1;
	}
	
	for (int i = 0; i < g_MapList.Length; i++)
	{
		int mapData[mapdata_t];
		g_MapList.GetArray(i, mapData, sizeof(mapData));
		
		if (StrEqual(mapData[MapData_Map], map) && StrEqual(mapData[MapData_MapGroup], group))
		{
			return i;
		}
	}
	
	return -1;
}

void InternalLoadMapList()
{
	// We're calling the external function here.  This way, if we move it to a subplugin, we can just copy/paste.
	if (MapChoices_ReadMapList(g_MapList, g_Serial, "mapchoices", MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_MAPSFOLDER) == null && g_Serial == -1)
	{
			SetFailState("Could not load map list");
	}
	
}

void StartVote(MapChoices_MapChange when, ArrayList mapList=null)
{
	if (g_bMapVoteInProgress || g_bMapVoteCompleted)
	{
		return;
	}
	
	if (Core_IsVoteInProgress())
	{
		DataPack data;
		CreateDataTimer(g_Cvar_RetryTime.FloatValue, Timer_Retry, data, TIMER_FLAG_NO_MAPCHANGE);
		data.WriteCell(when);
		data.WriteCell(mapList);
		data.Reset();
	}

	if (mapList == null)
	{
		// Figure out which maps we need to fetch
		
		// will involve a call to LoadMapList
		InternalLoadMapList();
	}
	
	// TODO the rest of the logic to start the vote
}

public Action Timer_Retry(Handle timer, DataPack data)
{
	MapChoices_MapChange when = data.ReadCell();
	ArrayList mapList = data.ReadCell();
	
	StartVote(when, mapList);
}

bool Core_IsVoteInProgress()
{
	bool inProgress = false;
	
	Action result = Plugin_Continue;
	
	Call_StartForward(g_Forward_HandlerIsVoteInProgress);
	Call_PushCellRef(inProgress);
	Call_Finish(result);
	
	if (result >= Plugin_Handled)
	{
		return inProgress;
	}
	
	return IsVoteInProgress();
}

bool CheckMapFilter(const char[] group, const char[] map, StringMap groupData, StringMap mapData)
{
	if (strlen(group) <= 0 || strlen(map) <= 0)
	{
		return false;
	}
	
	Action result = Plugin_Continue;
	Call_StartForward(g_Forward_MapFilter);
	Call_PushString(group);
	Call_PushString(map);
	Call_PushCell(groupData);
	Call_PushCell(mapData);
	Call_Finish(result);
	if (result >= Plugin_Handled)
	{
		return false;
	}
	
	return true;
}

bool CheckGroupFilter(const char[] group, StringMap groupData)
{
	if (strlen(group) <= 0)
	{
		return false;
	}
	
	Action result = Plugin_Continue;
	Call_StartForward(g_Forward_GroupFilter);
	Call_PushString(group);
	Call_PushCell(groupData);
	Call_Finish(result);
	if (result >= Plugin_Handled)
	{
		return false;
	}
	
	return true;
}


// Events
// Note: These are just the shared events

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
	Action result = Plugin_Continue;
	
	char map[PLATFORM_MAX_PATH];
	
	GetNextMap(map, sizeof(map));
	
	Call_StartForward(g_Forward_ChangeMap);
	Call_PushString(map);
	Call_PushCell(isRoundEnd);
	Call_Finish(result);
	
	if (result < Plugin_Handled)
	{
		if (!isRoundEnd)
		{
			RoundEnd();
		}
		
		if (g_Cvar_BonusTime != null)
		{
			CreateTimer(g_Cvar_BonusTime.FloatValue - 0.2, Timer_GameEnd, _, TIMER_FLAG_NO_MAPCHANGE);
		}
		else
		{
			GameEnd();
		}
	}
}

public Action Timer_GameEnd(Handle timer)
{
	GameEnd();
}

// Note: This is the generic version.  Other games have better ways of doing this, such as CSS/CSGO's CS_TerminateRound method
// and TF2's team_control_point_master's SetWinner or game_round_win entity
void RoundEnd()
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

void GameEnd()
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

// Natives

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

public int Native_AddMapFilter(Handle plugin, int numParams)
{
	Function func = GetNativeFunction(1);
	
	return AddToForward(g_Forward_MapFilter, plugin, func);
}

public int Native_RemoveMapFilter(Handle plugin, int numParams)
{
	Function func = GetNativeFunction(1);
	
	return RemoveFromForward(g_Forward_MapFilter, plugin, func);
}

public int Native_AddGroupFilter(Handle plugin, int numParams)
{
	Function func = GetNativeFunction(1);
	
	return AddToForward(g_Forward_GroupFilter, plugin, func);
}

public int Native_RemoveGroupFilter(Handle plugin, int numParams)
{
	Function func = GetNativeFunction(1);
	
	return RemoveFromForward(g_Forward_GroupFilter, plugin, func);
}

public int Native_StartVote(Handle plugin, int numParams)
{
	// TODO: Fix this to handle Group and Tier votes
	
	MapChoices_MapChange when = GetNativeCell(1);
	ArrayList mapList = view_as<ArrayList>(GetNativeCell(4));
	
	StartVote(when, mapList);
}

public int Native_WillChangeAtRoundEnd(Handle plugin, int numParams)
{
	return g_bChangeAtRoundEnd;
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

// native void MapChoices_GetCurrentMapGroup(char[] group, int maxlength);
public int Native_GetCurrentMapGroup(Handle plugin, int numParams)
{
	SetNativeString(1, g_MapGroup, GetNativeCell(2));
}

public int Native_GetNominatedMapList(Handle plugin, int numParams)
{
	ArrayList maparray = new ArrayList(mapdata_t);
	
	for (int i = 0; i < g_Array_NominatedMaps.Length; i++)
	{
		int nominationsData[nominations_t];
		g_Array_NominatedMaps.GetArray(i, nominationsData, sizeof(nominationsData));
		
		int mapData[mapdata_t];
		strcopy(mapData[MapData_Map], sizeof(mapData[MapData_Map]), nominationsData[NominationsData_Map]);
		strcopy(mapData[MapData_MapGroup], sizeof(mapData[MapData_MapGroup]), nominationsData[NominationsData_MapGroup]);
		
		maparray.PushArray(mapData, sizeof(mapData));
	}
	
	return view_as<int>(maparray);
}

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
	
	int mapData[nominations_t];
	
	g_Array_NominatedMaps.GetArray(pos, mapData, sizeof(mapData));
	
	ArrayList returnList = null;
	if (mapData[NominationsData_Nominators] == null)
		return view_as<int>(INVALID_HANDLE);
		
	ArrayList tempList = mapData[NominationsData_Nominators].Clone();
	returnList = view_as<ArrayList>(CloneHandle(tempList, plugin));
	delete tempList;
	
	return view_as<int>(returnList);
}

public int Native_Nominate(Handle plugin, int numParams)
{
	int mapLength;
	int groupLength;

	GetNativeStringLength(1, groupLength);
	GetNativeStringLength(2, mapLength);
	
	if (mapLength <= 0 || groupLength <= 0)
	{
		return false;
	}
	
	char[] group = new char[groupLength+1];
	GetNativeString(1, group, groupLength+1);
	
	char[] map = new char[mapLength+1];
	GetNativeString(2, map, mapLength+1);
	
	return view_as<int>(InternalNominateMap(group, map, GetNativeCell(3)));
}

MapChoices_NominateResult InternalNominateMap(char[] group, char[] map, int owner)
{
	if (!IsMapValid(map))
	{
		return MapChoicesNominateResult_InvalidMap;
	}
	
	int pos = FindMapInMapList(group, map);
	
	if (pos == -1)
	{
		//TODO New return type for maps rejected because they're not in the mapgroup?
		return MapChoicesNominateResult_InvalidMap;
	}
	
	int mapData[mapdata_t];
	g_MapList.GetArray(pos, mapData, sizeof(mapData));
	if (!CheckMapFilter(mapData[MapData_MapGroup], mapData[MapData_Map], mapData[MapData_MapAttributes], mapData[MapData_GroupAttributes]))
	{
		// Rejected by map filter
		return MapChoicesNominateResult_Rejected;
	}

	RemoveClientMapNomination(owner);
	
	bool newMap = false;
	int nominationsData[nominations_t];

	pos = FindMapInNominations(group, map);
	if (pos > -1)
	{
		g_Array_NominatedMaps.GetArray(pos, nominationsData, sizeof(nominationsData));
		
		nominationsData[NominationsData_Nominators].Push(owner);
		
	}
	else
	{
		// Create the data for this nomination
		strcopy(nominationsData[NominationsData_Map], sizeof(nominationsData[NominationsData_Map]), map);
		strcopy(nominationsData[NominationsData_MapGroup], sizeof(nominationsData[NominationsData_MapGroup]), group);
		nominationsData[NominationsData_Nominators] = new ArrayList();
		nominationsData[NominationsData_Nominators].Push(owner);
		
		g_Array_NominatedMaps.PushArray(nominationsData);
		newMap = true;
	}
	
	Call_StartForward(g_Forward_NominationAdded);
	Call_PushString(map);
	Call_PushString(group);
	Call_PushCell(owner);
	Call_PushCell(newMap);
	Call_Finish();
	
	return newMap ? MapChoicesNominateResult_Added : MapChoicesNominateResult_AlreadyInVote;
}
