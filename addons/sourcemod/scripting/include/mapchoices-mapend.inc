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

#if defined _mapchoices_mapend_included_
  #endinput
#endif
#define _mapchoices_mapend_included_

// Plugin 1.0 series

enum MapChoices_ConVarOverride
{
	MapChoicesConVar_BonusTime,
	MapChoicesConVar_Winlimit,
	MapChoicesConVar_FragLimit,
	MapChoicesConVar_MaxRounds,
}

native bool MapChoices_EndOfMapVoteEnabled();

native bool MapChoices_HasEndOfMapVoteFinished();

native int MapChoices_GetStartRounds();

/**
 * Called by Game plugins to swap scores.
 * Swap the scores for team 1 and team 2.
 * 
 * @param team1	First team to swap.
 * @param team2	Second team to swap.
 */
native void MapChoices_SwapTeamScores(MapChoices_Team team1=MapChoices_Team1, MapChoices_Team team2=MapChoices_Team2);

/**
 * Process round end logic.
 * 
 * Call this from a game plugin if a game uses a different event.
 * 
 * @param winner		Which team won
 * @param score		What that team's score is.  If -1, use internal scores
 */
native void MapChoices_ProcessRoundEnd(MapChoices_Team winner, int score=-1);

/**
 * Override one of the plugins cvars
 * 
 * Used by game plugins to alter that ConVars used
 * 
 * @param conVar		Which conVar are we overriding?
 * @param name		name of the new ConVar to use
 * 
 * NOTE: ConVars are owned by core, not by individual plugins.  They can not be closed or cloned.
 */
native bool MapChoices_OverrideConVar(MapChoices_ConVarOverride overrideConVar, ConVar conVar);

/**
 * Reset a ConVar back to its default value.
 * 
 * Used by game plugins that exit
 * 
 * @param conVar		Which conVar are we resetting?
 * 
 * NOTE: This function isn't really necessary but is included for completenesss.
 */
native void MapChoices_ResetConVar(MapChoices_ConVarOverride overrideConVar);

// --------------------------------------------------------------------------------
// Standard plugin stuff

public SharedPlugin __pl_mapchoices = 
{
	name = "mapchoices-mapend",
	file = "mapchoices-mapend.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_mapchoices-mapend_SetNTVOptional()
{
	MarkNativeAsOptional("MapChoices_EndOfMapVoteEnabled");
	MarkNativeAsOptional("MapChoices_HasEndOfMapVoteFinished");
	MarkNativeAsOptional("MapChoices_GetStartRounds");
	MarkNativeAsOptional("MapChoices_SwapTeamScores");
	MarkNativeAsOptional("MapChoices_ProcessRoundEnd");
	MarkNativeAsOptional("MapChoices_OverrideConVar");
	MarkNativeAsOptional("MapChoices_ResetConVar");
}
#endif
