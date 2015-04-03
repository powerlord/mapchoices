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
#include "../include/mapchoices" // Include our own file to gain access to enums and the like

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
ConVar g_Cvar_Windiference;
ConVar g_Cvar_WindiferenceMin;

ConVar g_Cvar_VoteNextLevel;
ConVar g_Cvar_BonusTime;

ConVar g_Cvar_SuddenDeath;


int g_TotalRounds;

int g_gameType = GameType_Unknown;

bool g_bOldSuddenDeath;

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
	CreateConVar("mapchoices_tf2_version", VERSION, "MapChoices TF2 plugin", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	
	g_Cvar_Winlimit = FindConVar("mp_winlimit");
	g_Cvar_Maxrounds = FindConVar("mp_maxrounds");

	g_Cvar_VoteNextLevel = FindConVar("sv_vote_issue_nextlevel_allowed");
	g_Cvar_BonusTime = FindConVar("mp_bonusroundtime");
	
	g_Cvar_Windiference = FindConVar("mp_windifference");
	g_Cvar_WindiferenceMin = FindConVar("mp_windifference_min");
	
	g_Cvar_SuddenDeath = FindConVar("mp_stalemate_enable");
	
	HookEvent("teamplay_win_panel", Event_TeamPlayWinPanel);
	HookEvent("arena_win_panel", Event_TeamPlayWinPanel);
}

public void OnMapStart()
{
	g_TotalRounds = 0;
}

public void OnAllPluginsLoaded()
{
	// Override round end mechanics
	//MapChoices_RegisterGamePlugin(true);
	MapChoices_AddGameFlags(MapChoicesGame_OverrideRoundEnd);
	MapChoices_AddChangeMapHandler(TF2_ChangeMap);
}

public void OnPluginEnd()
{
	MapChoices_RemoveGameFlags(MapChoicesGame_OverrideRoundEnd);
	MapChoices_RemoveChangeMapHandler(TF2_ChangeMap);
}

public void OnConfigsExecuted()
{
	g_gameType = GameRules_GetProp("m_nGameType");
	
	g_Cvar_VoteNextLevel.BoolValue = false;
}

public void Event_TeamPlayWinPanel(Event event, const char[] name, bool dontBroadcast)
{
	if (!IsMvM() && MapChoices_WillChangeAtRoundEnd())
	{
		char map[PLATFORM_MAX_PATH];
		GetNextMap(map, sizeof(map));
		TF2_ChangeMap(map, true);
	}
	
	int blueScore = event.GetInt("blue_score");
	int redScore = event.GetInt("red_score");
	
	if (StrEqual(name, "arena_win_panel") || event.GetInt("round_complete") == 1)
	{
		g_TotalRounds++;
		
		CheckMaxRounds(g_TotalRounds);
		
		switch (event.GetInt("winning_team"))
		{
			case MapChoices_Team1:
			{
				CheckWinLimit(redScore, blueScore);
			}
			
			case MapChoices_Team2:
			{
				CheckWinLimit(blueScore, redScore);
			}
		}
	}
}

void CheckMaxRounds(int roundCount)
{
}

void CheckWinLimit(int winnerScore, int loserScore)
{
	if (g_Cvar_Winlimit)
	{
		int winlimit = g_Cvar_Winlimit.IntValue;
		if (winlimit)
		{			
			if (winnerScore >= (winlimit - MapChoices_GetStartRounds()))
			{
				MapChoices_StartVote(MapChoicesMapChange_MapEnd, null);
			}
		}
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
	CreateDataTimer(g_Cvar_BonusTime.FloatValue - 0.2, Timer_GameEnd, data, TIMER_FLAG_NO_MAPCHANGE);
	data.WriteCell(isRoundEnd);
	data.Reset();
	
	return Plugin_Handled;
}

public Action Timer_GameEnd(Handle timer, DataPack data)
{
	if (data.ReadCell())
	{
		g_Cvar_SuddenDeath.BoolValue = g_bOldSuddenDeath;
	}
	GameEnd();
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

bool IsMvM()
{
	return view_as<bool>(GameRules_GetProp("m_bPlayingMannVsMachine"));
}
