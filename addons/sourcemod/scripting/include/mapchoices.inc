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

#if defined _mapchoices_included_
  #endinput
#endif
#define _mapchoices_included_

// Plugin 1.0 series

#define MAPCHOICES_NOCHANGE "__nochange__"
#define MAX_GROUP_LENGTH 64
#define MAX_MAP_ATTRIBUTES 16

// Team list for score swapping.
// Note: It's not clear if any games use Team3 and Team4, although ostensibly Fortress Forever does
enum MapChoices_Team
{
	MapChoices_TeamUnassigned,
	MapChoices_TeamSpectator,
	MapChoices_Team1,
	MapChoices_Team2,
	MapChoices_Team3,
	MapChoices_Team4,
}

enum MapChoices_MapListType
{
	MapChoicesMapList_Classic,
	MapChoicesMapList_Advanced,
}

enum MapChoices_NominateResult
{
	MapChoicesNominateResult_Added,		/** The map was added */
	MapChoicesNominateResult_Rejected,	/** The map was rejected by a map filter */
	MapChoicesNominateResult_InvalidMap,	/** The map doesn't exist. */
	MapChoicesNominateResult_AlreadyInVote, /** The map is already in the list and you tried to constant nominate it */
};

enum MapChoices_MapChange
{
	MapChoicesMapChange_Instant,		/** Change map as soon as the voting results have come in */
	MapChoicesMapChange_RoundEnd,		/** Change map at the end of the round */
	MapChoicesMapChange_MapEnd,		/** Change the sm_nextmap cvar */
};

enum MapChoices_GameFlags
{
	MapChoicesGame_None = 0,
	MapChoicesGame_NoGameEnd = (1<<0),			/** Game does NOT support game_end entities */
	MapChoicesGame_SupportsFragLimit = (1<<1),	/** Game supports frag limits: HL2:DM, Neotokyo (?) */
	MapChoicesGame_OverrideRoundEnd = (1<<2),	/** Game plugin will handle round_end event manually */
	MapChoicesGame_AvoidHintbox = (1<<3),		/** Game text should not be displayed in hintboxes: HL2:DM */
}

enum MapChoices_ConVarOverride
{
	MapChoicesConVar_BonusTime,
	MapChoicesConVar_Winlimit,
	MapChoicesConVar_FragLimit,
	MapChoicesConVar_MaxRounds,
}

// 1.6-style enum because it's an enum-struct
// Used to store data about a map.
// Classic mode maplists will have the group set to "classic" and null MapAttributes (to save a Handle)
enum mapdata_t
{
	String:MapData_Map[PLATFORM_MAX_PATH+1],
	String:MapData_MapGroup[MAX_GROUP_LENGTH+1],
	StringMap:MapData_MapAttributes,
	StringMap:MapData_GroupAttributes,
};

// 1.6-style enum to store group data
// Note that the StringMap may be null if there were no attributes
// "classic" will not actually exist, so don't bother looking for it
enum groupdata_t
{
	String:GroupData_Group[MAX_GROUP_LENGTH+1],
	StringMap:GroupData_GroupAttributes,
}

/**
 * This is the MapChoices equivalent to SourceMod's ReadMapList.
 * 
 * Loads a map list to an ADT Array.
 * The ADT Array containts arrays of mapdata_t enum structures.
 *
 * A map list is a list of maps from a file.  SourceMod allows easy configuration of 
 * maplists through addons/sourcemod/configs/mapchoices.cfg.  Each entry is given a 
 * name and a file (for example, "rtv" => "rtv.cfg"), or a name and a redirection 
 * (for example, "rtv" => "default").  This native will read a map list entry, 
 * cache the file, and return the list of maps it holds.
 * 
 * Each entry may also have a "type" => "classic" or "type" => "advanced" mapping.
 * This determines which type of map files are being used.
 * If not specified, "classic" is assumed.
 * 
 * "classic" maplists are just a list of maps in the same format as mapcycle.txt
 * "advanced" maplists are configuration files that may use groups and have subplugin
 *  configuration items.
 *
 * Serial change numbers are used to identify if a map list has changed.  Thus, if 
 * you pass a serial change number and it's equal to what MapChoices currently knows 
 * about the map list, then SourceMod won't reparse the file.
 *
 * If the maps end up being read from the maps folder (MAPLIST_FLAG_MAPSFOLDER), they 
 * are automatically sorted in alphabetical, ascending order.
 *
 * Arrays created by this function are temporary and must be freed via CloseHandle().
 * Modifying arrays created by this function will not affect future return values or 
 * or the contents of arrays returned to other plugins.
 *
 * @param array			Array to store the map list.  If INVALID_HANDLE, a new blank 
 *						array will be created.  The blocksize should be mapdata_t; 
 *						otherwise results may be truncated.  Items are added to the array
 *						as mapdata_t arrays.  The array is never checked for duplicates, 
 *						and it is not read beforehand.  Only the serial number is used to
 *						detect changes.
 * @param serial		Serial number to identify last known map list change.  If -1, the 
 *						the value will not be checked.  If the map list has since changed, 
 *						the serial is updated (even if -1 was passed).  If there is an error 
 *						finding a valid maplist, then the serial is set to -1.
 * @param str			Config name, or "default" for the default map list.  Config names 
 *						should be somewhat descriptive.  For example, the admin menu uses 
 *						a config name of "admin menu".  The list names can be configured 
 *						by users in addons/sourcemod/configs/maplists.cfg.
 * @param flags			MAPLIST_FLAG flags.
 * @return				On failure:
 *						 INVALID_HANDLE is returned, the serial is set to -1, and the input 
 *						 array (if any) is left unchanged.
 *						On no change:
 *						 INVALID_HANDLE is returned, the serial is unchanged, and the input 
 *						 array (if any) is left unchanged.
 *						On success:
 *						 A valid array Handle is returned, containing at least one map string.  
 *						 If an array was passed, the return value is equal to the passed Array 
 *						 Handle.  If the passed array was not cleared, it will have grown by at 
 *						 least one item.  The serial number is updated to a positive number.
 * @error				Invalid array Handle that is not INVALID_HANDLE.
 */
native ArrayList MapChoices_ReadMapList(ArrayList array=null, &serial=1, const char[] str="default", int flags=MAPLIST_FLAG_CLEARARRAY);

/**
 * Makes a compatibility binding for map lists.  For example, if a function previously used 
 * "clam.cfg" for map lists, this function will insert a "fake" binding to "clam.cfg" that 
 * will be overridden if it's in the maplists.cfg file. 
 * 
 * This is the MapChoices equivalent of SourceMod's SetMapListCompatBind.
 * 
 * @param name			Configuration name that would be used with MapChoices_ReadMapList().
 * @param file			Default file to use.
 * @param mapListType		Which map list type this is.
 * @noreturn
 */
native void MapChoices_SetMapListCompatBind(const char[] file, const char[] name, MapChoices_MapListType:mapListType=MapChoicesMapList_Classic);

native bool MapChoices_EndOfMapVoteEnabled();

native int MapChoices_GetStartRounds();

/**
 * Clean up a map list ArrayList
 * 
 * A map list Handle is an adt_array of mapdata_t entries.
 * mapdata_t contains a Trie of MapAttributes, which is CloneHandled to the calling plugin
 */
stock void CloseMapList(ArrayList &mapList)
{
	if (mapList == null)
	{
		return;
	}
	
	for (int i = 0 ; i < mapList.Length; i++)
	{
		int mapData[mapdata_t];
		mapList.GetArray(i, mapData, sizeof(mapData));
		delete mapData[MapData_MapAttributes];
	}
	delete mapList;
	mapList = null;
}

/**
 * Attempt to add a map to the nomination list
 * 
 * Note: Before calling this function from a plugin, read up on how Nominations differ
 * from MapChooser than in this plugin
 * 
 * @param map		Map to add.
 * @param owner	The person nominating the map. Use 0 for constant nominations.
 * @return		Nomination Result.
 */
native MapChoices_NominateResult MapChoices_Nominate(const char[] map, int owner);

/**
 * NOTE:  This may never be implemented until I see a good reason to keep it.
 * Remove a named map from the nominations list.
 * 
 * @param map		Map to remove.
 */
//native bool MapChoices_RemoveNominationByMap(const char[] map);

/**
 * NOTE: This may never be implemented until I see a good reason to keep it.  Core can track this on its own.
 * Remove a player's nomination from the nominations list.
 * 
 * @param owner	Client whose nomination we will remove.
 */
//native bool MapChoices_RemoveNominationByClient(int client);

/**
 * Start a map vote.
 * 
 * @param when		When should the map change?
 * @param mapList		An initial list of maps to use.  Will be supplmented by maps from the mapGroup if necessary.
 * @param mapGroup	Which mapgroup should we use?
 */
native void MapChoices_StartVote(MapChoices_MapChange when, ArrayList mapList=null, const char[] mapGroup="mapchoices");

// --------------------------------------------------------------------------------
// Forwards used by MapChoices subplugins for telling when votes start and finish

/**
 * A map vote started.
 */
forward void MapChoices_MapVoteStarted();

/**
 * A map vote just ended and a map won.
 * 
 * @param map		The map that was voted in.  This will be equal to the constant
 *                 MAPCHOICES_NOCHANGE if the map is not changing
 * @param instant	True if MapChoices is going to instantly change the map, false if not.
 * @param group	If the map was part of a group, which group it was from.
 * @noreturn
 */
forward void MapChoices_MapVoteEnded(const char[] map, bool instant, const char[] group);

/**
 * A map was added to the nominations list.
 * 
 * @param map		The map that was added.
 * @param owner	The user that added the map.  Will be 0 if the map was programatically added.
 * 
 */
forward void MapChoices_NominationAdded(const char[] map, int owner);

/**
 * A map has been removed from the nominations list.
 * 
 * @param map		The map that was removed.
 * @param owner	The user that added the map.
 * 
 */
forward void MapChoices_NominationRemoved(const char[] map, int owner);

// --------------------------------------------------------------------------------
// Functions used by Vote System plugins (read: NativeVotes)

// Private forwards for vote managers

typedef MapChoices_HandlerStartVote = function Action (ArrayList mapList, bool runoff);
typedef MapChoices_HandlerCancelVote = function Action ();
typedef MapChoices_HandlerIsVoteInProgress = function Action (bool &isInProgress);

/**
 * Override the main vote system with a different one.
 * This really exists for NativeVotes, so unless you have some use for it,
 * you really shouldn't be messing with it.
 * 
 * @param startVote		The function to call when a vote starts.
 * @param cancelVote		The function to call when a vote is canceled.
 * @param isVoteInProgress	The function to call to determine whether or not a vote is in progress
 * @param voteLimit		The number of items that can be in a vote.
 */
native bool MapChoices_RegisterVoteHandler(MapChoices_HandlerStartVote startVote, MapChoices_HandlerCancelVote cancelVote, MapChoices_HandlerIsVoteInProgress isVoteInProgress, int voteLimit=0);
native bool MapChoices_UnregisterVoteHandler(MapChoices_HandlerStartVote startVote, MapChoices_HandlerCancelVote cancelVote, MapChoices_HandlerIsVoteInProgress isVoteInProgress);

// --------------------------------------------------------------------------------
// Functions used by Map Filter plugins

/**
 * Allow the named map to be played?
 * 
 * @param mapGroup	The group the map is in
 * @param map			The map name from a map list
 * @param mapData		A Trie of keys and values for the selected map
 * @param groupData	A Trie of keys and values for the selected group
 * 
 * @return 			Plugin_Continue to allow, Plugin_Handled or Plugin_Stop to deny
 *
 * Note: Any other plugin can deny the map before your plugin executes this, so do not
 * expect to use this for statistical purposes
 */
typedef MapChoices_MapFilter = function Action (const char[] mapGroup, const char[] map, StringMap mapData, StringMap groupData);


/**
 * Get a Trie of keys and values for a map.
 * This is the same trie that would be passed to a map filter.
 * 
 * NOTE: This function may yet be removed in favor of MapFilters only
 * 
 * @param mapGroup	The mapGroup for the map whose data you want
 * @param map			The map whose data you want
 * @param mapData		A Trie Handle to store map keys and values
 * @param groupData	A Trie Handle to store map group keys and values
 * 
 * @return			true if we have data for a map, false otherwise
 * @error			if data is INVALID_HANDLE
 */
native bool MapChoices_GetMapData(const char[] mapGroup, const char[] map, StringMap mapdata, StringMap groupData=null);

/**
 * Register a map filter.  Map Filters are called when a map is selected to be added to
 * a map vote.
 * 
 * @param filter	The map filtering function
 * 
 * @return 		true if the filter was added
 */
native bool MapChoices_RegisterMapFilter(MapChoices_MapFilter filter);

/**
 * Unregister a map filter.
 * 
 * @param filter	The map filtering function
 * 
 * @return 		true if the filter was removed, false if it wasn't registered
 */
native bool MapChoices_UnregisterMapFilter(MapChoices_MapFilter filter);

// --------------------------------------------------------------------------------
// Functions used by Game plugins

native bool MapChoices_WillChangeAtRoundEnd();

//typedef MapChoices_EndRound = function Action ();

/**
 * If a plugin has defined a ChangeMap function, it will be called instead of ForceChangeMap.
 * 
 * @param map			The map being changed to
 * @param isRoundEnd	true if this is at the end of the round, false otherwise.
 * @return Plugin_Handled or higher to handle map change or Plugin_Continue to let MapChoices handle it
 */
typedef MapChoices_ChangeMap = function Action (const char[] map, bool isRoundEnd);

typedef MapChoices_WinLimit = function Action (int team, int score);

typedef MapChoices_RoundLimit = function Action (int rounds);

/**
 * Register a game plugin
 * 
 * At the moment, this is just present so we can stop the main plugin from processing round_end events
 * 
 * @param overrideRoundEnd	Prevent normal round end hooks from firing
 * 
 * @return		true if plugin was registered.
 */
native void MapChoices_GamePluginOverrideRoundEnd(bool overrideRoundEnd);

native bool MapChoices_AddChangeMapHandler(MapChoices_ChangeMap changeMapHandler);
native bool MapChoices_RemoveChangeMapHandler(MapChoices_ChangeMap changeMapHandler);

native bool MapChoices_AddWinlimitCheck(MapChoices_WinLimit winLimitHandler);
native bool MapChoices_RemoveWinlimitCheck(MapChoices_WinLimit winLimitHandler);

native bool MapChoices_AddRoundLimitCheck(MapChoices_RoundLimit roundLimitHandler);
native bool MapChoices_RemoveRoundLimitCheck(MapChoices_RoundLimit roundLimitHandler);

//native void MapChoices_AddRoundEnd(MapChoices_EndRound roundEndHandler);
//native void MapChoices_RemoveRoundEnd(MapChoices_EndRound roundEndHandler);

native bool MapChoices_AddGameFlags(MapChoices_GameFlags flags);
native bool MapChoices_RemoveGameFlags(MapChoices_GameFlags flags);

/**
 * Called by Game plugins to swap scores.
 * Swap the scores for team 1 and team 2.
 * 
 * @param team1	First team to swap.
 * @param team2	Second team to swap.
 */
native void MapChoices_SwapTeamScores(MapChoices_Team team1=MapChoices_Team1, MapChoices_Team team2=MapChoices_Team2);

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
native bool MapChoices_ResetConVar(MapChoices_ConVarOverride overrideConVar);

/**
 * Process round end logic.
 * 
 * Call this from a game plugin if a game uses a different event.
 * 
 * @param winner		Which team won
 * @param score		What that team's score is.  If -1, use internal scores
 */
native void MapChoices_ProcessRoundEnd(int winner, int score=-1);

// --------------------------------------------------------------------------------
// Standard plugin stuff

public SharedPlugin __pl_mapchoices = 
{
	name = "mapchoices",
	file = "mapchoices.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_mapchoices_SetNTVOptional()
{
	MarkNativeAsOptional("MapChoices_RegisterVoteHandler");
	MarkNativeAsOptional("MapChoices_UnregisterVoteHandler");
	MarkNativeAsOptional("MapChoices_RegisterMapFilter");
	MarkNativeAsOptional("MapChoices_UnregisterMapFilter");
	
}
#endif
