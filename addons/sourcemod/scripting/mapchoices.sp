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

StringMap g_Trie_NominatedMaps;
char g_MapNominations[MAXPLAYERS+1][PLATFORM_MAX_PATH];

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
ArrayList g_RecentMapList = null;

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
	
	CreateNative("MapChoices_WillChangeAtRoundEnd", Native_WillChangeAtRoundEnd);
	
	CreateNative("MapChoices_OverrideConVar", Native_OverrideConVar);
	CreateNative("MapChoices_ResetConVar", Native_ResetConVar);
	
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
	g_Forward_MapVoteEnded = CreateGlobalForward("MapChoices_OnMapVoteEnded", ET_Ignore, Param_String, Param_Cell, Param_String);
	g_Forward_NominationAdded = CreateGlobalForward("MapChoices_OnNominationAdded", ET_Ignore, Param_String, Param_Cell);
	g_Forward_NominationRemoved = CreateGlobalForward("MapChoices_OnNominationRemoved", ET_Ignore, Param_String, Param_Cell);
	
	g_Forward_HandlerVoteStart = CreateForward(ET_Hook, Param_Cell);
	g_Forward_HandlerCancelVote = CreateForward(ET_Hook);
	g_Forward_HandlerIsVoteInProgress = CreateForward(ET_Hook);
	
	
	g_Forward_MapFilter = CreateForward(ET_Hook, Param_String, Param_String, Param_Cell, Param_Cell);
	
	g_Forward_ChangeMap = CreateForward(ET_Hook, Param_String, Param_Cell);
	
	g_MapList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	g_RecentMapList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	
	HookEvent("round_end", Event_RoundEnd);
	HookEventEx("round_win", Event_RoundEnd);
	HookEventEx("teamplay_round_win", Event_RoundEnd);
	
	AutoExecConfig(true, "mapchoices");
}

public void OnMapStart()
{
	g_bChangeAtRoundEnd = false;
	g_bTempIgnoreRoundEnd = false;
	
	g_bMapVoteInProgress = false;
	g_bMapVoteCompleted = false;
}

public void OnClientDisconnect(int client)
{
	// Clear the client's nominations
	if (g_MapNominations[client][0] != '\0')
	{
		int count;
		if (g_Trie_NominatedMaps.GetValue(g_MapNominations[client], count))
		{
			--count;
			
			if (count <= 0)
			{
				// Whoops, no more nominations for this map, so lets remove it.
				g_Trie_NominatedMaps.Remove(g_MapNominations[client]);
			}
			else
			{
				// Save the new count back to the trie
				g_Trie_NominatedMaps.SetValue(g_MapNominations[client], count);
			}
		}
		
		g_MapNominations[client][0] = '\0';
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
		if (LoadMapList(g_MapList, g_Serial, "mapchoices", MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_MAPSFOLDER) == null)
		{
			//TODO Decide how to recover from this error
			SetFailState("Could not load map list");
		}
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

bool CheckMapFilter(const char[] mapGroup, const char[] map, StringMap mapData, StringMap groupData)
{
	Action result = Plugin_Continue;
	Call_StartForward(g_Forward_MapFilter);
	Call_PushString(mapGroup);
	Call_PushString(map);
	Call_PushCell(mapData);
	Call_PushCell(groupData);
	Call_Finish(result);
	if (result >= Plugin_Handled)
	{
		return false;
	}
	
	return true;
}

//Replaced with LoadMapList in parse-mapchooser-config.inc which implements the MapChoices_ReadMapList native
/*
stock ArrayList ReadMapChoicesList(ArrayList kv=null, int &serial=1, const char[] str="default", int flags=MAPLIST_FLAG_CLEARARRAY)
{
	KeyValues kvConfig = new KeyValues("MapChoices");
	
	char configFile[PLATFORM_MAX_PATH+1];
	
	BuildPath(Path_SM, configFile, sizeof(configFile), "%s", CONFIGFILE);
	if (!FileToKeyValues(kvConfig, configFile))
	{
		SetFailState("Could not read configuration file: %s", configFile);
	}
	
}
*/

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

public int Native_ReadMapChoicesList(Handle plugin, int numParams)
{
	Handle mapKv = GetNativeCell(1);
	int serial = GetNativeCellRef(2);
	
	//TODO Complete this or remove native
}

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
	int voteLimit = GetNativeCell(4);
	
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

public int Native_StartVote(Handle plugin, int numParams)
{
	MapChoices_MapChange when = GetNativeCell(1);
	ArrayList mapList = view_as<ArrayList>(GetNativeCell(2));
	
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
