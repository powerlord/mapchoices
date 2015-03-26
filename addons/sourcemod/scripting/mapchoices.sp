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

int roundCount;
StringMap g_Trie_NominatedMaps;
char g_MapNominations[MAXPLAYERS+1][PLATFORM_MAX_PATH];

int g_WinCount[MapChoices_Team];

//ConVars
ConVar g_Cvar_Enabled;

// Valve ConVars
ConVar g_Cvar_Timelimit;

ConVar g_Cvar_BonusTime;
ConVar g_Cvar_Winlimit;
ConVar g_Cvar_FragLimit;
ConVar g_Cvar_MaxRounds;

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

bool g_bChangeAtRoundEnd = false;

//new Handle:m_ListLookup;

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
	CreateNative("MapChoices_RegisterMapFilter", Native_AddMapFilter);
	CreateNative("MapChoices_RemoveMapFilter", Native_RemoveMapFilter);
	CreateNative("MapChoices_ReadMapList", LoadMapList);
	
	CreateNative("MapChoices_ProcessRoundEnd", Native_ProcessRoundEnd);
	CreateNative("MapChoices_OverrideConVar", Native_OverrideConVar);
	CreateNative("MapChoices_SwapTeamScores", Native_SwapTeamScores);
	
	RegPluginLibrary("mapchoices");
}
  
public void OnPluginStart()
{
	InitializeConfigurationParser();
	//m_ListLookup = new StringMap();
	
	LoadTranslations("common.phrases");
	LoadTranslations("mapchoices.phrases");
	
	CreateConVar("mapchoices_version", VERSION, "MapChoices version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	g_Cvar_Enabled = CreateConVar("mapchoices_enable", "1", "Enable MapChoices?", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	
	g_Cvar_Timelimit = FindConVar("mp_timelimit");

	// These 4 cvars may be overridden by game plugins
	g_Cvar_BonusTime = FindConVar("mp_bonusroundtime");
	g_Cvar_Winlimit = FindConVar("mp_winlimit");
	g_Cvar_FragLimit = FindConVar("mp_fraglimit");
	g_Cvar_MaxRounds = FindConVar("mp_maxrounds");
	
	g_Forward_MapVoteStarted = CreateGlobalForward("MapChoices_MapVoteStarted", ET_Ignore);
	g_Forward_MapVoteEnded = CreateGlobalForward("MapChoices_MapVoteEnded", ET_Ignore, Param_String, Param_Cell, Param_String);
	g_Forward_NominationAdded = CreateGlobalForward("MapChoices_NominationAdded", ET_Ignore, Param_String, Param_Cell);
	g_Forward_NominationRemoved = CreateGlobalForward("MapChoices_NominationRemoved", ET_Ignore, Param_String, Param_Cell);
	
	g_Forward_HandlerVoteStart = CreateForward(ET_Hook, Param_Cell);
	g_Forward_HandlerCancelVote = CreateForward(ET_Hook);
	g_Forward_HandlerIsVoteInProgress = CreateForward(ET_Hook);
	
	
	g_Forward_MapFilter = CreateForward(ET_Hook, Param_String, Param_String, Param_Cell, Param_Cell);
	
	g_Forward_ChangeMap = CreateForward(ET_Hook, Param_String, Param_Cell);
	
	HookEvent("round_end", Event_RoundEnd);
	
}

public void OnMapStart()
{
	g_bChangeAtRoundEnd = false;
	
	// Reset win counters
	for (int i = 0; i < sizeof(g_WinCount); i++)
	{
		g_WinCount[i] = 0;
	}
}

public void OnConfigsExecuted()
{
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
	if (mapList == null)
	{
		//GetRemainingChoices("mapchoices");
	}
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

// Ugh, caching is going to be a mess... might want to reconsider caching and just make this a general method for reading from the appropriate config file.
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

stock ArrayList GetMapListFromFile(const char[] filename)
{
	
}

stock void LocateConfigurationFile(const char[] section, char[] filename, int maxlength)
{
	
}


// Events
// Note: These are just the shared events

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	++roundCount;
	
	if (g_bChangeAtRoundEnd)
	{
		
	}
	
	// Missing logic to actually check the rounds and start the vote.
}

void ProcessRoundEnd(int winner)
{
	++roundCount;
	
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
		
		int entity = -1;
		
		entity = FindEntityByClassname(-1, "game_end");
		
		if (entity == -1)
		{
			entity = CreateEntityByName("game_end");
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
	
	Event gameEndEvent = CreateEvent("game_end");
	gameEndEvent.SetInt("winner", view_as<int>(MapChoices_TeamUnassigned)); // This won't work for HL2:DM, which expects a player for non-team games
	gameEndEvent.Fire();
}

// Natives

public int Native_ReadMapChoicesList(Handle plugin, int numParams)
{
	Handle mapKv = GetNativeCell(1);
	int serial = GetNativeCellRef(2);
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

public int Native_ProcessRoundEnd(Handle plugin, int numParams)
{
	int winner = GetNativeCell(1);
	
	ProcessRoundEnd(winner);
}

// native void MapChoices_SwapTeamScores(MapChoices_Team team1, MapChoices_Team team2);
public int Native_SwapTeamScores(Handle plugin, int numParams)
{
	// MapChoices_Team is really just an int anyway
	int team1 = GetNativeCell(1);
	int team2 = GetNativeCell(2);
	
	int temp = g_WinCount[team1];
	g_WinCount[team1] = g_WinCount[team2];
	g_WinCount[team2] = temp;
}
