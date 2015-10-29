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
#include "../include/mapchoices"

#undef REQUIRE_PLUGIN
#include "../include/mapchoices-mapend"

#pragma semicolon 1
#pragma newdecls required
#define VERSION "1.0.0 alpha 1"

enum
{
	GameType_Unknown	= 0,
	GameType_CTF		= 1,
	GameType_CP			= 2,
	GameType_Payload	= 3,
	GameType_Arena		= 4,
}

ConVar g_Cvar_Winlimit;
ConVar g_Cvar_Maxrounds;
ConVar g_Cvar_Windifference;
ConVar g_Cvar_WindifferenceMin;

ConVar g_Cvar_VoteNextLevel;
ConVar g_Cvar_BonusTime;

ConVar g_Cvar_SuddenDeath;

//ConVar g_Cvar_ChatTime;

int g_TotalRounds;

int g_ObjectiveEnt = INVALID_ENT_REFERENCE;

//int g_GameType = GameType_Unknown;

bool g_bOldSuddenDeath;

bool g_bMvM = false;

bool g_bMapEndRunning = false;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (GetEngineVersion() != Engine_TF2)
	{
		strcopy(error, err_max, "Plugin is for TF2 only.");
		return APLRes_Failure;
	}
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("mapchoices_tf2_version", VERSION, "MapChoices TF2 plugin", FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	
	g_Cvar_Winlimit = FindConVar("mp_winlimit");
	g_Cvar_Maxrounds = FindConVar("mp_maxrounds");

	g_Cvar_VoteNextLevel = FindConVar("sv_vote_issue_nextlevel_allowed");
	g_Cvar_BonusTime = FindConVar("mp_bonusroundtime");
	
	g_Cvar_Windifference = FindConVar("mp_windifference");
	g_Cvar_WindifferenceMin = FindConVar("mp_windifference_min");
	
	g_Cvar_SuddenDeath = FindConVar("mp_stalemate_enable");
	
	//g_Cvar_ChatTime = FindConVar("mp_chattime");
	
	HookEvent("teamplay_win_panel", Event_TeamPlayWinPanel);
	HookEvent("arena_win_panel", Event_TeamPlayWinPanel);
	HookEvent("mvm_wave_complete", Event_MvMWaveComplete); // Should be called for MvM round end
}

public void OnMapStart()
{
	g_bMvM = false;
	g_TotalRounds = 0;
}

public void OnAllPluginsLoaded()
{
	g_bMapEndRunning = LibraryExists("mapchoices-mapend");
	
	MapChoices_AddGameFlags(MapChoicesGame_OverrideRoundEnd);
	MapChoices_AddChangeMapHandler(TF2_ChangeMap);
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
	MapChoices_RemoveChangeMapHandler(TF2_ChangeMap);
}

public void OnConfigsExecuted()
{
	//g_GameType = GameRules_GetProp("m_nGameType");
	
	g_bMvM = view_as<bool>(GameRules_GetProp("m_bPlayingMannVsMachine"));

	g_Cvar_VoteNextLevel.BoolValue = false;
}

// TODO Fix this to make calls to the mapend plugin
public void Event_TeamPlayWinPanel(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bMvM && MapChoices_WillChangeAtRoundEnd())
	{
		char map[PLATFORM_MAX_PATH];
		GetNextMap(map, sizeof(map));
		TF2_ChangeMap(map, true);
	}
	
	if (g_bMvM || !g_bMapEndRunning || !MapChoices_MapEnd_VoteEnabled() || MapChoices_MapEnd_HasVoteFinished())
	{
		return;
	}
	
	int blueScore = event.GetInt("blue_score");
	int redScore = event.GetInt("red_score");
	
	// Note: We do not call MapChoices_ProcessRoundEnd in TF2.
	// This is because TF2 has custom logic for win limit due to mp_windifference
	
	if (StrEqual(name, "arena_win_panel") || event.GetInt("round_complete") == 1)
	{
		g_TotalRounds++;
		
		CheckMaxRounds(g_TotalRounds);
		
		MapChoices_Team winningTeam = view_as<MapChoices_Team>(event.GetInt("winning_team"));
		
		int winnerScore = 0;
		int loserScore = 0;
		
		switch (winningTeam)
		{
			case MapChoices_Team1:
			{
				winnerScore = redScore;
				loserScore = blueScore;
			}
			
			case MapChoices_Team2:
			{
				winnerScore = blueScore;
				loserScore = redScore;
			}
		}

		CheckWinLimit(winnerScore, loserScore);

		//MapChoices_ProcessRoundEnd(winningTeam, winnerScore);
	}
	
}

void ValidateObjectiveEntity()
{
	if (!IsValidEntity(g_ObjectiveEnt))
	{
		int entity = FindEntityByClassname(-1, "tf_objective_resource");
		
		if (IsValidEntity(entity))
		{
			g_ObjectiveEnt = EntIndexToEntRef(entity);
		}
	}
}

// TODO Fix this to make calls to the mapend plugin
public void Event_MvMWaveComplete(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bMapEndRunning || !MapChoices_MapEnd_VoteEnabled() || MapChoices_MapEnd_HasVoteFinished())
	{
		return;
	}
	
	g_TotalRounds++;
	
	ValidateObjectiveEntity();
	
	if (IsValidEntity(g_ObjectiveEnt))
	{
		//TODO Check if m_nMannVsMachineWaveCount is the current wave number
		if (g_TotalRounds >= GetEntProp(g_ObjectiveEnt, Prop_Send, "m_nMannVsMachineWaveCount") - 1)
		{
			MapChoices_InitiateVote(MapChoicesMapChange_MapEnd, "mapchoices-mapend");
		}
	}
}

// TODO Fix this to make calls to the mapend plugin
void CheckMaxRounds(int roundCount)
{
	if (g_Cvar_Maxrounds.IntValue && roundCount >= g_Cvar_Maxrounds.IntValue - MapChoices_MapEnd_GetStartRounds())
	{
		MapChoices_InitiateVote(MapChoicesMapChange_MapEnd, "mapchoices-mapend");
	}
}

// TODO Fix this to make calls to the mapend plugin
void CheckWinLimit(int winnerScore, int loserScore)
{
	if (g_Cvar_Winlimit.IntValue && winnerScore >= (g_Cvar_Winlimit.IntValue - MapChoices_MapEnd_GetStartRounds()))
	{
		MapChoices_InitiateVote(MapChoicesMapChange_MapEnd, "mapchoices-mapend");
	}
	
	// Win Difference seems to be exclusive to TF2	
	if (g_Cvar_Windifference.IntValue && winnerScore >= (g_Cvar_WindifferenceMin.IntValue - 1) && (winnerScore - loserScore) >= (g_Cvar_Windifference.IntValue - 1))
	{
		MapChoices_InitiateVote(MapChoicesMapChange_MapEnd, "mapchoices-mapend");
	}
	
}

public Action TF2_ChangeMap(const char[] map, bool isRoundEnd)
{
	if (!isRoundEnd)
	{
		g_bOldSuddenDeath = g_Cvar_SuddenDeath.BoolValue;
		RoundEnd();
	}

	DataPack data;
	// Subtract 0.2 seconds because SourceMod timer resolution is only 0.1 seconds.
	CreateDataTimer(g_Cvar_BonusTime.FloatValue - 0.2, Timer_GameEnd, data, TIMER_FLAG_NO_MAPCHANGE);
	data.WriteString(map);
	data.WriteCell(isRoundEnd);
	data.Reset();
	
	return Plugin_Handled;
}

public Action Timer_GameEnd(Handle timer, DataPack data)
{
	char map[PLATFORM_MAX_PATH];
	data.ReadString(map, sizeof(map));
	
	bool isRoundEnd = data.ReadCell();
	if (!isRoundEnd)
	{
		g_Cvar_SuddenDeath.BoolValue = g_bOldSuddenDeath;
	}
	GameEnd(map);
}

// Note: This is the TF2-specific version
void RoundEnd()
{
	g_Cvar_SuddenDeath.BoolValue = false;
	
	int entity = FindEntityByClassname(-1, "team_control_point_master");
	if (entity > 1)
	{
		SetVariantInt(0);
		AcceptEntityInput(entity, "SetWinner");
	}
	else
	{
		entity = CreateEntityByName("game_round_win");
		DispatchKeyValue(entity, "TeamNum", "0");
		if (DispatchSpawn(entity))
		{
			AcceptEntityInput(entity, "RoundWin");
		}
	}
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
