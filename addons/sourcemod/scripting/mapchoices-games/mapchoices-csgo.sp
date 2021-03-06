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
#include <cstrike>
#include "../include/mapchoices"

#undef REQUIRE_PLUGIN
#include "../include/mapchoices-mapend"

#pragma semicolon 1
#pragma newdecls required
#define VERSION "1.0.0 alpha 1"

ConVar g_Cvar_Winlimit;
ConVar g_Cvar_Maxrounds;

ConVar g_Cvar_VoteNextLevel;
ConVar g_Cvar_RestartMatchAtEnd;
ConVar g_Cvar_ChangeMapAtEnd;

ConVar g_Cvar_Bonusroundtime;
ConVar g_Cvar_Halftime;
ConVar g_Cvar_MatchClinch;
ConVar g_Cvar_GameType;
ConVar g_Cvar_GameMode;

bool g_bHasIntermissionStarted = false;
bool g_bArmsRace = false;

// Swiped from MapChooser
/* Upper bound of how many team there could be */
#define MAXTEAMS 10
int g_winCount[MAXTEAMS];
int g_TotalRounds;

// CSGO requires two cvars to get the game type
enum
{
	GameType_Classic	= 0,
	GameType_GunGame	= 1,
	GameType_Training	= 2,
	GameType_Custom		= 3,
}

enum
{
	GunGameMode_ArmsRace	= 0,
	GunGameMode_Demolition	= 1,
	GunGameMode_DeathMatch	= 2,
}

bool g_bMapEndRunning = false;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (GetEngineVersion() != Engine_CSGO)
	{
		strcopy(error, err_max, "Plugin is for CS:GO only.");
		return APLRes_SilentFailure;
	}
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("mapchoices_csgo_version", VERSION, "MapChoices CS:GO plugin", FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	
	g_Cvar_Winlimit = FindConVar("mp_winlimit");
	g_Cvar_Maxrounds = FindConVar("mp_maxrounds");

	g_Cvar_VoteNextLevel = FindConVar("mp_endmatch_votenextmap");
	g_Cvar_RestartMatchAtEnd = FindConVar("mp_match_end_restart");
	g_Cvar_ChangeMapAtEnd = FindConVar("mp_match_end_changelevel");
	
	g_Cvar_Bonusroundtime = FindConVar("mp_round_restart_delay");
	g_Cvar_Halftime = FindConVar("mp_halftime");
	g_Cvar_MatchClinch = FindConVar("mp_match_can_clinch");
	
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("cs_intermission", Event_Intermission);
	HookEvent("announce_phase_end", Event_PhaseEnd);
}

public void OnMapStart()
{
	g_bHasIntermissionStarted = false;
	g_bArmsRace = false;
	g_TotalRounds = 0;
}

public void OnAllPluginsLoaded()
{
	g_bMapEndRunning = LibraryExists("mapchoices-mapend");

	// Override round end mechanics
	MapChoices_AddGameFlags(MapChoicesGame_OverrideRoundEnd);
	MapChoices_OverrideConVar(MapChoicesConVar_BonusTime, g_Cvar_Bonusroundtime);
	
	MapChoices_RegisterChangeMapHandler(CSGO_ChangeMap);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "mapchoices-mapend"))
	{
		g_bMapEndRunning = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "mapchoices-mapend"))
	{
		g_bMapEndRunning = false;
	}
}

public void OnPluginEnd()
{
	MapChoices_RemoveGameFlags(MapChoicesGame_OverrideRoundEnd);
	MapChoices_UnregisterChangeMapHandler(CSGO_ChangeMap);	
	MapChoices_ResetConVar(MapChoicesConVar_BonusTime);
}

public void OnConfigsExecuted()
{
	if (g_Cvar_GameType.IntValue == GameType_GunGame && g_Cvar_GameMode.IntValue == GunGameMode_ArmsRace)
	{
		g_bArmsRace = true;
	}
	
	g_Cvar_VoteNextLevel.BoolValue = false;
	g_Cvar_RestartMatchAtEnd.BoolValue = false;
	g_Cvar_ChangeMapAtEnd.BoolValue = true;
}

// CS:GO can switch teams at halftime, these events are to make sure we switch scores properly
public void Event_Intermission(Event event, const char[] name, bool dontBroadcast)
{
	if (g_Cvar_Halftime.BoolValue)
	{
		g_bHasIntermissionStarted = true;
	}
}

public void Event_PhaseEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_Cvar_Halftime.BoolValue)
	{
		return;
	}
	
	/* announce_phase_end fires for both half time and the end of the map, but intermission fires first for end of the map. */
	if (g_bHasIntermissionStarted)
	{
		return;
	}

	/* No intermission yet, so this must be half time. Swap the score counters. */
	MapChoices_MapEnd_SwapTeamScores();
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (MapChoices_WillChangeAtRoundEnd())
	{
		char map[PLATFORM_MAX_PATH];
		GetNextMap(map, sizeof(map));
		CSGO_ChangeMap(map, true);
	}
	
	if (g_bArmsRace || !g_bMapEndRunning || !MapChoices_MapEnd_VoteEnabled() || MapChoices_MapEnd_HasVoteFinished())
	{
		return;
	}
	
	int winner = winner = event.GetInt("winner");
	
	if (winner < 2 || !MapChoices_MapEnd_VoteEnabled())
	{
		return;
	}
	
	if (winner >= MAXTEAMS)
	{
		SetFailState("Too many teams (more than %d)", MAXTEAMS);
	}
	
	g_TotalRounds++;
	
	g_winCount[winner]++;
	
	CheckWinLimit(g_winCount[winner]);
	CheckMaxRounds(g_TotalRounds);
}

void CheckMaxRounds(int roundCount)
{
	if (g_Cvar_Maxrounds.IntValue && roundCount >= g_Cvar_Maxrounds.IntValue - MapChoices_MapEnd_GetStartRounds())
	{
		MapChoices_MapEnd_StartVote();
	}
}

void CheckWinLimit(int winner_score)
{
	if (g_Cvar_Winlimit)
	{
		int winlimit = g_Cvar_Winlimit.IntValue;
		if (winlimit)
		{			
			if (winner_score >= (winlimit - MapChoices_MapEnd_GetStartRounds()))
			{
				MapChoices_MapEnd_StartVote();
			}
		}
	}
	
	//CS:GO Clinch support
	if (g_Cvar_MatchClinch && g_Cvar_Maxrounds)
	{
		if (g_Cvar_MatchClinch.BoolValue)
		{
			int maxrounds = g_Cvar_Maxrounds.IntValue;
			int winlimit = RoundFloat(maxrounds / 2.0);
			
			if(winner_score == winlimit - 1)
			{
				MapChoices_MapEnd_StartVote();
			}
		}
	}
}

public Action CSGO_ChangeMap(const char[] map, bool isRoundEnd)
{
	if (!isRoundEnd)
	{
		RoundEnd();
	}
	
	DataPack data;
	CreateDataTimer(g_Cvar_Bonusroundtime.FloatValue - 0.2, Timer_GameEnd, data, TIMER_FLAG_NO_MAPCHANGE);
	data.WriteString(map);
	data.Reset();
	
	return Plugin_Handled;
}

public Action Timer_GameEnd(Handle timer, DataPack data)
{
	char map[PLATFORM_MAX_PATH];
	data.ReadString(map, sizeof(map));
	GameEnd(map);
}

// Note: The is the CSS/CSGO-specific version
void RoundEnd()
{
	CS_TerminateRound(0.0, CSRoundEnd_Draw, true);
}

void GameEnd(const char[] map)
{
	int entity = FindEntityByClassname(-1, "game_end");
	
	if (entity != -1)
	{
		AcceptEntityInput(entity, "EndGame");
	}
	else
	{
		entity = CreateEntityByName("game_end");
		if (entity > -1)
		{
			if (DispatchSpawn(entity))
			{
				AcceptEntityInput(entity, "EndGame");
				return;
			}
			else
			{
				ForceChangeLevel(map, "Map Vote");
			}
		}
		else
		{
			ForceChangeLevel(map, "Map Vote");
		}
	}
	
//	DataPack data;
//	CreateTimer(g_Cvar_ChatTime.FloatValue, Timer_End, data, TIMER_FLAG_NO_MAPCHANGE);
//	data.WriteString(map);
//	data.Reset();
}

//public Action Timer_End(Handle timer, DataPack data)
//{
//	char map[PLATFORM_MAX_PATH];
//	data.ReadString(map, sizeof(map));
//	
//	ForceChangeLevel(map, "Map Vote");
//}
