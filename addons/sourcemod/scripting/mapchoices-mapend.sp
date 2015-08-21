/**
 * vim: set ts=4 :
 * =============================================================================
 * MapChoices Map End Vote
 * End map vote support for MapChoices
 *
 * MapChoices Map End Vote (C)2015 Powerlord (Ross Bemrose).
 * All rights reserved.
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

#include "include/mapchoices" // Include our own parent's file to make native calls against it
#include "include/mapchoices-mapend" // Include our own file to gain access to enums and the like
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required
#define VERSION "1.0.0 alpha 1"

int g_RoundCount;

int g_WinCount[MapChoices_Team];

//ConVars
ConVar g_Cvar_Enabled;
ConVar g_Cvar_FragVoteStart;
ConVar g_Cvar_FragFromStart;
ConVar g_Cvar_TimelimitVoteStart;
ConVar g_Cvar_TimelimitFromStart;
ConVar g_Cvar_RoundVoteStart;
ConVar g_Cvar_RoundFromStart;

// Valve ConVars
// ConVar g_Cvar_Timelimit;

// ConVar g_Cvar_ChatTime;

//Handle g_Forward_ChangeMap;

// The value is the round a vote should start.
// It is calculated on map start based on whether rounds count from beginning or end
int g_VoteStartRound = 0;
int g_VoteStartFrag = 0;

bool g_bVoteStarted = false;
bool g_bVoteFinished = false;

Handle g_hTimeLimitVote;

public Plugin myinfo = {
	name			= "MapChoices Map End Vote",
	author			= "Powerlord",
	description		= "Map End vote support for MapChoices",
	version			= VERSION,
	url				= ""
};

// Native Support
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("MapChoices_MapEnd_VoteEnabled", Native_EndOfMapVoteEnabled);
	CreateNative("MapChoices_MapEnd_HasVoteFinished", Native_HasEndOfMapVoteFinished);
	CreateNative("MapChoices_MapEnd_GetStartRounds", Native_GetStartRounds);
	CreateNative("MapChoices_MapEnd_ProcessRoundEnd", Native_ProcessRoundEnd);
	CreateNative("MapChoices_MapEnd_SwapTeamScores", Native_SwapTeamScores);
	
	RegPluginLibrary("mapchoices-mapend");
}
  
public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("mapchoices.phrases");
	
	CreateConVar("mapchoices_mapend_version", VERSION, "MapChoices Map End Vote version", FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	g_Cvar_Enabled = CreateConVar("mapchoices_mapend_enable", "1", "Enable MapChoices End Map Vote?", FCVAR_NOTIFY|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	
	// Core map vote starting stuff
	g_Cvar_FragVoteStart = CreateConVar("mapchoices_frag_votestart", "5", "If a person is this close to the frag limit, start a vote.", _, true, 1.0);
	g_Cvar_FragFromStart = CreateConVar("mapchoices_frag_fromstart", "0", "0: Start frags vote based on frags until frag limit. 1: Start frags vote on frags since map start.", _, true, 0.0, true, 1.0);
	
	g_Cvar_TimelimitVoteStart = CreateConVar("mapchoices_timelimit_votestart", "6", "Start a vote based on the timelimit. Note: TF2 will end if less than 5 minutes is left on the clock.", _, true, 0.0);
	g_Cvar_TimelimitFromStart = CreateConVar("mapchoices_timelimit_fromstart", "0", "0: Start timeleft vote based on time before map changes. 1: Start timeleft vote based on time from map start.", _, true, 0.0, true, 1.0);
	
	g_Cvar_RoundVoteStart = CreateConVar("mapchoices_maxrounds_votestart", "2", "Start a vote based on how many rounds have passed. 0 means after final round during bonus time.", _, true, 0.0);
	g_Cvar_RoundFromStart = CreateConVar("mapchoices_maxrounds_fromstart", "0", "0: Start maxrounds vote based on rounds before the map ends.  1: Start maxrounds vote based on rounds from map start.", _, true, 0.0, true, 1.0);
	
	// Valve cvars
	// g_Cvar_Timelimit = FindConVar("mp_timelimit");
	// g_Cvar_ChatTime = FindConVar("mp_chattime");
	
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_death", Event_PlayerDeath);
	
	AutoExecConfig(true, "mapchoices_mapend");
}

public void OnMapStart()
{
	// Reset win counters
	for (int i = 0; i < sizeof(g_WinCount); i++)
	{
		g_WinCount[i] = 0;
	}
	
	g_bVoteStarted = false;
	g_bVoteFinished = false;
}

public void OnMapEnd()
{
	if (g_hTimeLimitVote != null)
	{
		KillTimer(g_hTimeLimitVote);
		g_hTimeLimitVote = null;
	}
}

public void OnConfigsExecuted()
{
	SetupRoundVote();
	SetupFragVote();
	SetupTimeleftVote();
}

void SetupRoundVote()
{
	if (!g_Cvar_Enabled.BoolValue)
	{
		return;
	}
	
	ConVar conMaxRounds = MapChoices_GetConVarOverride(MapChoicesConVar_MaxRounds);
	
	if (conMaxRounds == null || conMaxRounds.IntValue <= 0)
	{
		g_VoteStartRound = 0;
		return;
	}
	
	if (g_Cvar_RoundVoteStart.IntValue == 0)
	{
		g_VoteStartRound = conMaxRounds.IntValue;
		return;
	}
	
	int tempRounds = 0;
	
	if (g_Cvar_RoundFromStart.BoolValue)
	{
		tempRounds = g_Cvar_RoundVoteStart.IntValue;
		
		// They tried to have the vote after maxrounds, reduce the vote to happen one round before maxrounds.
		g_VoteStartRound = tempRounds > conMaxRounds.IntValue ? conMaxRounds.IntValue - 1 : tempRounds;
	}
	else
	{
		tempRounds = conMaxRounds.IntValue - g_Cvar_RoundVoteStart.IntValue;
		
		g_VoteStartRound = tempRounds <= 0 ? 1 : tempRounds;
	}
}

void SetupFragVote()
{
	g_VoteStartFrag = 0;

	if (MapChoices_GetGameFlags() & MapChoicesGame_SupportsFragLimit != MapChoicesGame_SupportsFragLimit)
	{
		return;
	}

	ConVar conFragLimit = MapChoices_GetConVarOverride(MapChoicesConVar_FragLimit);
	
	if (conFragLimit == null || conFragLimit.IntValue <= 0)
	{
		return;
	}
	
	if (g_Cvar_FragFromStart.BoolValue)
	{
		g_VoteStartFrag = g_Cvar_FragVoteStart.IntValue;
		
		if (g_VoteStartFrag > conFragLimit.IntValue)
		{
			g_VoteStartFrag = conFragLimit.IntValue - 2;
		}
	}
	else
	{
		g_VoteStartFrag = conFragLimit.IntValue - g_Cvar_FragVoteStart.IntValue;
		
		if (g_VoteStartFrag <= 0)
		{
			g_VoteStartFrag = conFragLimit.IntValue - 2;
		}
	}
}

void SetupTimeleftVote()
{
	if (g_hTimeLimitVote != null)
	{
		delete g_hTimeLimitVote;
	}
	
	int timelimit;

	if (!GetMapTimeLimit(timelimit) && !g_Cvar_TimelimitFromStart.BoolValue)
	{
		// Map doesn't have timelimit and we're not measuring from start
		return;
	}

	float timer;
	if (g_Cvar_TimelimitFromStart.BoolValue)
	{
		timer = g_Cvar_TimelimitVoteStart.FloatValue * 60.0;
		
		// If the timer would be too long, truncate it to one minute before the timelimit
		if (timelimit > 0 && timelimit * 60.0 <= timer)
		{
			timer = (timelimit - 1) * 60.0;
		}
	}
	else if (timelimit > 0)
	{
		timer = (timelimit - g_Cvar_TimelimitVoteStart.IntValue) * 60.0;

		// If the timer would be too long, truncate it to one minute before the timelimit
		if (timelimit * 60.0 <= timer)
		{
			timer = (timelimit - 1) * 60.0;
		}
	}
	
	g_hTimeLimitVote = CreateTimer(timer, Timer_StartVote);
}

public Action Timer_StartVote(Handle timer)
{
	StartVote();
}

public void OnMapTimeLeftChanged()
{
	int timeleft;
	if (GetMapTimeLeft(timeleft) && timeleft <= 0 && GetClientCount() > 0)
	{
		// Time left is less than 0, so start vote
		StartVote();
	}
	
	// TODO Checks to see if timer reset
	SetupTimeleftVote();
}

public void OnClientDisconnect_Post(int client)
{
	if (GetClientCount() == 0)
	{
		KillTimer(g_hTimeLimitVote);
		g_hTimeLimitVote = null;
	}
}


// Events
// Note: These are just the shared events

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (MapChoices_GetGameFlags() & MapChoicesGame_OverrideRoundEnd)
	{
		return;
	}
	
	MapChoices_Team winner = view_as<MapChoices_Team>(event.GetInt("winner"));

	ProcessRoundEnd(winner);
	
	// Missing logic to actually check the rounds and start the vote.
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (MapChoices_GetGameFlags() & MapChoicesGame_SupportsFragLimit != MapChoicesGame_SupportsFragLimit || g_VoteStartFrag <= 0)
	{
		return;
	}
	
	int attacker = event.GetInt("attacker");
	
	if (attacker == 0)
	{
		return;
	}
	
	int client = GetClientOfUserId(attacker);
	
	if (client < 1 || client > MaxClients)
	{
		return;
	}
	
	if (GetClientFrags(client) >= g_VoteStartFrag)
	{
		StartVote();
	}
}

void ProcessRoundEnd(MapChoices_Team winner, int score=-1)
{
	// If core is changing maps, don't run our logic
	if (MapChoices_WillChangeAtRoundEnd())
	{
		return;
	}
	
	++g_RoundCount;
	
	CheckMaxRounds(g_RoundCount);

	g_WinCount[winner]++;
	
	if (score > -1)
	{
		CheckWinLimit(score);
	}
	else
	{
		CheckWinLimit(g_WinCount[winner]);
	}
}

void CheckMaxRounds(int roundCount)
{
	if (roundCount >= g_VoteStartRound)
	{
		StartVote();
	}
}

void CheckWinLimit(int winner_score)
{
	ConVar conWinLimit = MapChoices_GetConVarOverride(MapChoicesConVar_Winlimit);
	if (conWinLimit != null)
	{
		int winlimit = conWinLimit.IntValue;
		if (winlimit > 0 && winner_score >= (winlimit - g_VoteStartRound))
		{
			StartVote();
		}
	}
}

void StartVote()
{
	if (g_bVoteStarted || g_bVoteFinished)
	{
		return;
	}
	
	g_bVoteStarted = true;
	MapChoices_InitiateVote(MapChoicesMapChange_MapEnd, "mapchoices-mapend", .finishedFunction=OnVoteFinished);
}

public void OnVoteFinished()
{
	g_bVoteFinished = true;
}

// Natives

// May move back to core
public int Native_ProcessRoundEnd(Handle plugin, int numParams)
{
	MapChoices_Team winner = GetNativeCell(1);
	int score = GetNativeCell(2);
	
	ProcessRoundEnd(winner, score);
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

// native bool MapChoices_MapEnd_EndOfMapVoteEnabled();
public int Native_EndOfMapVoteEnabled(Handle plugin, int numParams)
{
	return g_Cvar_Enabled.BoolValue;
}

// native bool MapChoices_MapEnd_HasEndOfMapVoteFinished();
public int Native_HasEndOfMapVoteFinished(Handle plugin, int numParams)
{
	return g_bVoteFinished;
}

// native int MapChoices_MapEnd_GetStartRounds();
public int Native_GetStartRounds(Handle plugin, int numParams)
{
	return g_VoteStartRound;
}
