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

// Group for non-Grouped maplists.  Note: Extend and No Change also belong to this group
#define MAPCHOICES_DEFAULTGROUP "classic"

#define MAPCHOICES_EXTEND "__extend__"
#define MAPCHOICES_NOCHANGE "__nochange__"

#define MAPCHOICES_MAX_GROUP_LENGTH 64
#define MAPCHOICES_MAX_ATTRIBUTE_LENGTH 128
#define MAPCHOICES_MAX_MAP_ATTRIBUTES 16

/**
 * What type of vote is this?
 * 
 * Map vote is the standard MapChooser-style vote.
 * Group vote is just voting for the group, after which MapChoices will choose a valid map randomly
 * Tiered vote is a group vote, followed by a map vote of qualifying maps.
 * 
 * As a general rule, you will want MapVote or TieredVote.
 * This is configured in subplugins (such as mapchoices-mapend or mapchoices-rtv) when they start a vote.
 */
enum MapChoices_VoteType
{
	MapChoices_MapVote,
	MapChoices_GroupVote,
	MapChoices_TieredVote,
}

enum MapChoices_VoteFailedType
{
	MapChoices_Canceled,						/**< The vote was canceled */
	MapChoices_FailedQuorum,					/**< Depending on configuration, a revote may follow */
	MapChoices_FailedNoVotes,					/**< No one voted */
}

enum MapChoices_ExtendOptions
{
	MapChoicesExtend_None,
	MapChoicesExtend_Extend,
	MapChoicesExtend_NoChange
}

/**
 * Team list for score swapping.
 * 
 * Note: It's not clear if any games use Team3 and Team4, although ostensibly Fortress Forever does
 */
enum MapChoices_Team
{
	MapChoices_TeamUnassigned,
	MapChoices_TeamSpectator,
	MapChoices_Team1,
	MapChoices_Team2,
	MapChoices_Team3,
	MapChoices_Team4,
}

/**
 * The kind of map list being loaded.
 */
enum MapChoices_MapListType
{
	MapChoicesMapList_Classic,					/**< A classic MapChooser-style maplist */
	MapChoicesMapList_Advanced,					/**< An advanced UMC-style maplist */
}

/**
 * Nominating a map can have various results
 */
enum MapChoices_NominateResult
{
	MapChoicesNominateResult_Added,				/**< The map was added */
	MapChoicesNominateResult_AlreadyInVote,		/**< The map is already in the list, but now has an additional nominator */
	MapChoicesNominateResult_InvalidMap,		/**< The map doesn't exist or wasn't in the map group */
};

/**
 * When should the map change?
 */
enum MapChoices_MapChange
{
	MapChoicesMapChange_Instant,				/**< Change map as soon as the voting results have come in */
	MapChoicesMapChange_RoundEnd,				/**< Change map at the end of the round */
	MapChoicesMapChange_MapEnd,					/**< Change the sm_nextmap cvar */
};

/**
 * Compatibility flags for Game Plugins
 */
enum MapChoices_GameFlags
{
	MapChoicesGame_None = 0,
	MapChoicesGame_NoGameEnd = (1<<0),			/**< Game does NOT support game_end entities */
	MapChoicesGame_SupportsFragLimit = (1<<1),	/**< Game supports frag limits: HL2:DM, Neotokyo (?) */
	MapChoicesGame_OverrideRoundEnd = (1<<2),	/**< Game plugin will handle round_end event manually */
	MapChoicesGame_AvoidHintbox = (1<<3),		/**< Game text should not be displayed in hintboxes: HL2:DM */
}

/**
 * ConVars that Game Plugins can override
 */
enum MapChoices_ConVarOverride
{
	MapChoicesConVar_BonusTime,
	MapChoicesConVar_Winlimit,
	MapChoicesConVar_FragLimit,
	MapChoicesConVar_MaxRounds,
}

// SM 1.6-style enum because it's an enum-struct
// Used to store data about a map.
// Classic mode maplists will have the group set to MAPCHOICES_DEFAULTGROUP and null MapAttributes (to save a Handle)
// Other uses may intentionally pass null handles for map and group attributes
// MAPCHOICES_DEFAULTGROUP will have a null GroupAttributes StringMap
enum mapdata_t
{
	String:MapData_Map[PLATFORM_MAX_PATH],
	String:MapData_Group[MAPCHOICES_MAX_GROUP_LENGTH],
	StringMap:MapData_MapAttributes,
	StringMap:MapData_GroupAttributes,
};


// SM 1.6-style enum because it's an enum-struct
// Used to store data about a group
// Note that the StringMap may be null if there were no attributes
// MAPCHOICES_DEFAULTGROUP will have a null GroupAttributes StringMap
enum groupdata_t
{
	String:GroupData_Group[MAPCHOICES_MAX_GROUP_LENGTH],
	StringMap:GroupData_GroupAttributes,
}

/**
 * This is the MapChoices equivalent to SourceMod's ReadMapList.
 * 
 * Note: If you're calling this, you should be calling MapChoices_CheckMapFilter
 * and MapChoices_CheckGroupFilter when you do things with maps.
 * 
 * Loads a map list to an ADT Array.
 * The ADT Array contains mapdata_t structures.
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
 * @param array		Array to store the map list.  If INVALID_HANDLE, a new blank 
 *						array will be created.  The blocksize should be mapdata_t; 
 *						otherwise results may be truncated.  Items are added to the array
 *						as mapdata_t arrays.  The array is never checked for duplicates, 
 *						and it is not read beforehand.  Only the serial number is used to
 *						detect changes.
 * @param serial		Serial number to identify last known map list change.  If -1, the 
 *						the value will not be checked.  If the map list has since changed, 
 *						the serial is updated (even if -1 was passed).  If there is an error 
 *						finding a valid maplist, then the serial is set to -1.
 * @param config			Config name, or "default" for the default map list.  Config names 
 *						should be somewhat descriptive.  For example, the admin menu uses 
 *						a config name of "admin menu".  The list names can be configured 
 *						by users in addons/sourcemod/configs/maplists.cfg.
 * @param flags		MAPLIST_FLAG flags.
 * @return			On failure:
 *						INVALID_HANDLE is returned, the serial is set to -1, and the input 
 *						array (if any) is left unchanged.
 *					On no change:
 *						INVALID_HANDLE is returned, the serial is unchanged, and the input 
 *						array (if any) is left unchanged.
 *					On success:
 *						A valid array Handle is returned, containing at least one mapdata_t.  
 *						If an array was passed, the return value is equal to the passed Array 
 *						Handle.  If the passed array was not cleared, it will have grown by at 
 *						least one item.  The serial number is updated to a positive number.
 * @error			Invalid array Handle that is not INVALID_HANDLE.
 */
native ArrayList MapChoices_ReadMapList(ArrayList array=null, &serial=-1, const char[] config="default", int flags=MAPLIST_FLAG_CLEARARRAY);

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
native void MapChoices_SetMapListCompatBind(const char[] file, const char[] name, MapChoices_MapListType mapListType = MapChoicesMapList_Classic);

/**
 * Clean up a map list ArrayList
 * 
 * A map list Handle is an adt_array of mapdata_t entries.
 * mapdata_t contains a Trie of MapAttributes, which is CloneHandled to the calling plugin
 */
stock void MapChoices_CloseMapList(ArrayList &mapList)
{
	if (mapList == null)
	{
		return;
	}
	
	for (int i = 0 ; i < mapList.Length; i++)
	{
		int mapData[mapdata_t];
		mapList.GetArray(i, mapData, sizeof(mapData));
		MapChoices_DeleteMapData(mapData);
	}
	delete mapList;
}

/**
 * Delete a single map entry
 */
stock void MapChoices_DeleteMapData(int mapData[mapdata_t])
{
	delete mapData[MapData_MapAttributes];
	delete mapData[MapData_GroupAttributes];
}

stock void MapChoices_DeleteGroupData(int groupData[groupdata_t])
{
	delete groupData[GroupData_GroupAttributes];
}

stock void MapChoices_CopyMapData(int mapData[mapdata_t], int mapDataCopy[mapdata_t])
{
	strcopy(mapDataCopy[MapData_Map], sizeof(mapDataCopy[MapData_Map]), mapData[MapData_Map]);
	strcopy(mapDataCopy[MapData_Group], sizeof(mapDataCopy[MapData_Group]), mapData[MapData_Group]);
	
	CopyStringMap(mapData[MapData_MapAttributes], mapDataCopy[MapData_MapAttributes]);
	CopyStringMap(mapData[MapData_GroupAttributes], mapDataCopy[MapData_GroupAttributes]);
}

stock void MapChoices_CopyGroupData(int groupData[groupdata_t], int groupDataCopy[groupdata_t])
{
	strcopy(groupDataCopy[GroupData_Group], sizeof(groupDataCopy[GroupData_Group]), groupData[GroupData_Group]);
	
	CopyStringMap(groupData[GroupData_GroupAttributes], groupDataCopy[GroupData_GroupAttributes]);
}

stock void MapChoices_CopyGroupDataToMapData(int groupData[groupdata_t], int mapData[mapdata_t])
{
	strcopy(mapData[MapData_Group], sizeof(mapData[MapData_Group]), groupData[GroupData_Group]);
	
	CopyStringMap(groupData[GroupData_GroupAttributes], mapData[MapData_GroupAttributes]);
}

static stock void CopyStringMap(StringMap original, StringMap copy)
{
	// If the original is null, the new version should also be null
	if (original == null)
		return;
	
	// This should always run as the copy should be empty, but...
	if (copy == null)
		copy = new StringMap();
	
	StringMapSnapshot snapshot = original.Snapshot();
	
	for (int i = 0; i < snapshot.Length; i++)
	{
		int size = snapshot.KeyBufferSize(i);
		char[] key = new char[size];
		snapshot.GetKey(i, key, size);
		char value[MAPCHOICES_MAX_ATTRIBUTE_LENGTH];
		original.GetString(key, value, sizeof(value));
		
		copy.SetString(key, value);
	}
	
	delete snapshot;
}

/**
 * Get the item string for specific map data
 * This may change later and should be considered temporary for the time being
 * 
 * @param itemString		The string to store the item
 * @param maxlength		We recommend that length be PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 1
 */
stock void MapChoices_GetItemString(int item[mapdata_t], char[] itemString, int maxlength)
{
	if (StrEqual(item[MapData_Map], MAPCHOICES_EXTEND) || StrEqual(item[MapData_Map], MAPCHOICES_NOCHANGE))
	{
		strcopy(itemString, maxlength, item[MapData_Map]);
		return;
	}
	
	Format(itemString, maxlength, "%s;%s", item[MapData_Group], item[MapData_Map]);
}

stock void MapChoices_GetMapDisplayString(int item[mapdata_t], char[] displayString, int maxlength)
{
	if (StrEqual(item[MapData_Map], MAPCHOICES_EXTEND))
	{
		strcopy(displayString, maxlength, "MapChoices_Extend");
	}
	else if (StrEqual(item[MapData_Map], MAPCHOICES_NOCHANGE))
	{
		strcopy(displayString, maxlength, "MapChoices_NoChange");
	}
	else
	{
		GetMapDisplayName(item[MapData_Map], displayString, maxlength);
		
		if (item[MapData_Group][0] != '\0' && !StrEqual(item[MapData_Group], MAPCHOICES_DEFAULTGROUP))
		{
			Format(displayString, maxlength, "%s (%s)", displayString, item[MapData_Group]);
		}
	}
}

stock void MapChoices_SplitItemString(const char[] itemString, char[] group, int groupSize, char[] map, int mapSize)
{
	if (StrEqual(itemString, MAPCHOICES_EXTEND) || StrEqual(itemString, MAPCHOICES_NOCHANGE))
	{
		strcopy(map, mapSize, itemString);
		return;
	}
	
	char itemParts[PLATFORM_MAX_PATH][2];
	ExplodeString(itemString, ";", itemParts, sizeof(itemParts), sizeof(itemParts[]), false);
	
	strcopy(group, groupSize, itemParts[0]);
	strcopy(map, mapSize, itemParts[1]);
}

/**
 * Attempt to add a map to the nomination list
 * 
 * Note: Before calling this function from a plugin, read up on how Nominations differ
 * from MapChooser than in this plugin
 * 
 * @param map		Map to add.
 * @param owner	The person nominating the map. Use 0 for constant nominations.
 * @param group	The group of the map, defaults to MAPCHOICES_DEFAULTGROUP
 * @return		Nomination Result.
 */
native MapChoices_NominateResult MapChoices_Nominate(const char[] group, const char[] map, int owner);

/**
 * Attempt to remove a map from the MapChoices map list.
 * 
 * NOTE:  This may never be implemented until I see a good reason to keep it.
 * Remove a named map from the nominations list.
 * 
 * @param map		Map to remove.
 * @return		True if the nomination was found and removed, or false if the nomination was not found
 */
//native bool MapChoices_RemoveNominationByMap(const char[] map);

/**
 * Attempt to remove a map from the MapChoices map list.
 * 
 * NOTE: This may never be implemented until I see a good reason to keep it.  Core can track this on its own.
 * Remove a player's nomination from the nominations list.
 * 
 * @param owner	Client index of the nominator.
 * @return		True if the nomination was found and removed, or false if the nomination was not found
 */
//native bool MapChoices_RemoveNominationByOwner(int client);

/**
 * Gets the current list of nominated maps.
 * 
 * Note: Returns copies of the array, updating these arrays do not change the originals.
 *					
 * @return			An ADT array handle of mapdata_t arrays that store information about the nominated maps.
 * 					Remember to delete this ArrayList or call MapChoices_CloseMapList on it.
 */
native ArrayList MapChoices_GetNominatedMapList();

/**
 * Get the list of nominators for a specific map
 * 
 * @return			An ADT array handle of client indexes or INVALID_HANDLE if the map isn't in the nominate list
 */
native ArrayList MapChoices_GetNominatedMapOwners(const char[] group, const char[] map);

// Check if this is possible with new architecture
/**
 * Gets the current list of excluded maps.
 * 
 * @param array	An ADT array handle to add the map strings to.
 * @noreturn
 */
//native void MapChoices_GetExcludedMapList(ArrayList array);

/**
 * Get the group for the current map.
 * 
 * @param group		A string to copy the name into
 * @param maxlength	The length of the string.
 */
native void MapChoices_GetCurrentMapGroup(char[] group, int maxlength);

/**
 * Get the vote type currently being used.
 * Intended for other plugins to use for determining what kind of data they send in.
 * 
 * @return			The vote type currently being used.
 */
native MapChoices_VoteType MapChoices_GetVoteType();

/**
 * Get a Trie of keys and values for a map and map group.
 * This is the same trie that would be passed to a map filter.
 * 
 * NOTE: This function may yet be removed in favor of MapFilters only
 * 
 * @param group	The mapGroup for the map whose data you want
 * @param map			The map whose data you want
 * @param mapData		On success, a mapdata_t with the map's data
 * 
 * @return			true if we have data for a map, false otherwise
 * @error			if data is INVALID_HANDLE
 */
native bool MapChoices_GetMapData(const char[] group, const char[] map, int mapData[mapdata_t]);

/**
 * Checks if MapChoices will allow a vote
 * 
 * @return		True if a vote can be held, or false if MapChoices is already holding a vote.
 */
native bool MapChoices_CanStartVote();

typedef MapChoices_VoteFinished = function void (MapChoices_VoteType voteType);

/**
 * Start a map vote.
 * 
 * @param when			When should the map change?
 * @param itemList		An initial list of items to use.
 * @param module			Which MapChoices module is holding the vote
 * @param voteType		Which type of vote are we doing?  Note that TieredVote will be a minimum of two votes even without runoff votes.
 * @param finishedFunction	A function to run in the calling plugin after the vote finishes
 * 
 * TODO: Figure out if we really want module
 * TODO: Document what's in mapList as it's not just a flat list.
 */
native void MapChoices_InitiateVote(MapChoices_MapChange when, ArrayList itemList, const char[] module, MapChoices_VoteFinished finishedFunction = INVALID_FUNCTION);

// --------------------------------------------------------------------------------
// Forwards used by MapChoices subplugins for telling when votes start and finish

/**
 * A map vote started.
 * 
 * MapChoices_OnMapVoteEnded will not be called between the original vote and
 * any runoff votes.
 * 
 * @param runoff	True if this is a runoff vote, false otherwise
 * @noreturn
 */
forward void MapChoices_OnMapVoteStarted(bool runoff);

/**
 * A map vote just ended and a map won.
 * 
 * @param map		The map that was voted in.  This will be equal to the constant
 *                 MAPCHOICES_NOCHANGE if the map is not changing
 * @param instant	True if MapChoices is going to instantly change the map, false if not.
 * @param group	If the map was part of a group, which group it was from.
 * @noreturn
 */
forward void MapChoices_OnMapVoteEnded(const char[] group, const char[] map, bool instant);

/**
 * A map was added to the nominations list.
 * 
 * NOTE: 
 * 
 * @param map		The map that was added.
 * @param owner	The user that added the map.  Will be 0 if the map was programatically added.
 * @param newMap	True if the map was added to the nominations list for the first time, false if it was already nominated
 */
forward void MapChoices_OnNominationAdded(const char[] group, const char[] map, int owner, bool newMap);

/**
 * A map has been removed from the nominations list.
 * 
 * @param map		The map that was removed.
 * @param owner	The user that added the map.
 * @param removed	True if this map was removed entirely, false if there are still nominations for it.
 */
forward void MapChoices_OnNominationRemoved(const char[] group, const char[] map, int owner, bool removed);

// --------------------------------------------------------------------------------
// Functions used by Vote System plugins (read: NativeVotes)

// Private forwards for vote managers

/**
 * Tells a vote system plugin to start a vote.
 * 
 * @param duration		How long should the vote last?
 * @param voteType		Which vote type is this: Map or Group?
 * @param itemList		A flat ArrayList of items.
 * @param clients			Which clients is this vote being sent to?
 * @param numClients		How many clients is this being sent to?
 * @param quorum			What percent of votes (0.0 to 1.0) are needed for the vote to pass? 0.0 will tell the plugin to always pass.
 * @param noVotesSelect	If there are no votes, select a random item?
 * @param noVoteOption		Add the No Vote option to the menu?  May not be supported by alternative vote providers.
 * 
 * @return				Plugin_Handled to indicate that a vote system handled this vote start
 */
typedef MapChoices_HandlerStartVote = function Action (int duration, MapChoices_VoteType voteType, ArrayList itemList, int[] clients, int numClients, 
	float quorum, bool noVotesSelect, bool noVoteOption);

/**
 * Tells a vote system plugin to cancel a vote
 * 
 * @return			Plugin_Handled to indicate that a vote system handled this vote cancel
 */
typedef MapChoices_HandlerCancelVote = function Action ();

/**
 * Ask a vote system plugin whether it has a vote currently in progress
 * 
 * @param isInProgress		The plugin will set this to yet or no depending on whether a vote is in progress
 * 
 * @return			Plugin_Handled to indicate that a vote system handled this vote inprogress check
 */
typedef MapChoices_HandlerIsVoteInProgress = function Action (bool &isInProgress);

/**
 * A Vote System plugin passed a vote.
 * 
 * @param voteType		The type of vote completed: Map or Group.
 * @param mapData			Map Data for the item that won the vote.  MapData_Map and MapData_MapAttributes will be empty for a group vote
 * 
 * @error if MapChoices isn't running a vote at the time.
 */
native void MapChoices_VoteSucceeded(MapChoices_VoteType voteType, int mapData[mapdata_t], int votes, int votesTotal);

/**
 * A Vote System plugin failed a vote.
 * 
 * Note: If MapChoices issues a CancelVote, expect to get a VoteCompleted back with a Canceled reason.
 * 
 * @param voteType		The type of vote completed: Map or Group.
 * @param failType		Why did the vote fail?
 * @param items			If failedType is MapChoices_FailedQuorum or MapChoices_FailedNoVote, an array of items.
 * @param votes			If failedType is MapChoices_FailedQuorum, an array with the number of votes for each item.
 * 
 * @error if MapChoices isn't running a vote at the time.
 */
native void MapChoices_VoteFailed(MapChoices_VoteType voteType, MapChoices_VoteFailedType failType, ArrayList items=null, ArrayList votes=null);

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
 * Note: Any other plugin can deny the map before your plugin executes this, so do not
 * expect to use this for statistical purposes
 * 
 * @param mapData		Map Data.  See mapdata_t for details.
 * 
 * @return 			Plugin_Continue to allow, Plugin_Handled or Plugin_Stop to deny
 */
typedef MapChoices_MapFilter = function Action (const int mapData[mapdata_t]);

/**
 * Allow the named group to be played?
 *
 * Note: Any other plugin can deny the group before your plugin executes this, so do not
 * expect to use this for statistical purposes
 * 
 * @param groupData	Group data.  See groupdata_t for details.
 * 
 * @return 			Plugin_Continue to allow, Plugin_Handled or Plugin_Stop to deny
 */
typedef MapChoices_GroupFilter = function Action (const int groupData[groupdata_t]);

/**
 * Register a map filter.  Map Filters are called when a map is selected to be added to
 * a map vote.
 * 
 * Applies to Map and Tiered votes.
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

/**
 * Register a group filter.  Group filters are called when a group is selected to be added
 * to a group vote.
 * 
 * Applies to Group and Tiered votes.
 * 
 * @param filter	The group filtering function
 * 
 * @return		true if the filter was added
 */
native bool MapChoices_RegisterGroupFilter(MapChoices_GroupFilter filter);

/**
 * Unregister a group filter.
 * 
 * @param filter	The group filtering function
 * 
 * @return		true if the filter was removed, false if it wasn't registered
 */
native bool MapChoices_UnregisterGroupFilter(MapChoices_GroupFilter filter);

/**
 * From a subplugin, check if a map matches a map filter
 * 
 * @param mapData		A map's map data
 * 
 * @return			true if a filter blocked the map, false otherwise
 */
native bool MapChoices_CheckMapFilter(const int mapData[mapdata_t]);

/**
 * From a subplugin, check if a group matches a group filter
 * 
 * @param groupData	Group data.  See groupdata_t for details.
 * 
 * @return			true if a filter blocked the group, false otherwise
 */
native bool MapChoices_CheckGroupFilter(const int groupData[groupdata_t]);

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
typedef MapChoices_ChangeMapForward = function Action (const char[] map, bool isRoundEnd);

native bool MapChoices_RegisterChangeMapHandler(MapChoices_ChangeMapForward changeMapHandler);
native bool MapChoices_UnregisterChangeMapHandler(MapChoices_ChangeMapForward changeMapHandler);

/**
 * Set game flags.
 * 
 * This enables/disables various parts of MapChoices on a per-game basis.
 */
native void MapChoices_AddGameFlags(MapChoices_GameFlags flags);
native void MapChoices_RemoveGameFlags(MapChoices_GameFlags flags);

/**
 * Get the bitflags of which game flags are enable.
 * 
 * @return 	Bitflags of the gameflags currently set.
 */
native MapChoices_GameFlags MapChoices_GetGameFlags();

/**
 * Override one of the plugins cvars
 * 
 * Used by game plugins to alter that ConVars used
 * 
 * @param overrideConVar	Which conVar are we overriding?
 * @param conVar			Handle of the new ConVar to use
 * 
 * @return True if it was overridden, false if not.
 * 
 * NOTE: ConVars are owned by the SM core, not by individual plugins.  They can not be closed or cloned.
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

/**
 * Retrieve a ConVar Handle from the Mapchoices core
 * 
 * @param overrideConVar	Which convar are we retrieving
 * 
 * @return ConVar Handle of the convar.
 */
native ConVar MapChoices_GetConVarOverride(MapChoices_ConVarOverride overrideConVar);

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
	MarkNativeAsOptional("MapChoices_ReadMapList");
	MarkNativeAsOptional("MapChoices_SetMapListCompatBind");
	
	MarkNativeAsOptional("MapChoices_Nominate");
	//MarkNativeAsOptional("MapChoices_RemoveNominationByMap");
	//MarkNativeAsOptional("MapChoices_RemoveNominationByOwner");
	MarkNativeAsOptional("MapChoices_GetNominatedMapList");
	MarkNativeAsOptional("MapChoices_GetNominatedMapOwners");
	
	//MarkNativeAsOptional("MapChoices_GetExcludedMapList");
	
	MarkNativeAsOptional("MapChoices_GetCurrentMapGroup");
	MarkNativeAsOptional("MapChoices_GetMapData");
	MarkNativeAsOptional("MapChoices_CanStartVote");
	MarkNativeAsOptional("MapChoices_InitiateVote");
	
	MarkNativeAsOptional("MapChoices_RegisterVoteHandler");
	MarkNativeAsOptional("MapChoices_UnregisterVoteHandler");
	
	MarkNativeAsOptional("MapChoices_RegisterMapFilter");
	MarkNativeAsOptional("MapChoices_UnregisterMapFilter");
	MarkNativeAsOptional("MapChoices_RegisterGroupFilter");
	MarkNativeAsOptional("MapChoices_UnregisterGroupFilter");
	MarkNativeAsOptional("MapChoices_CheckMapFilter");
	MarkNativeAsOptional("MapChoices_CheckGroupFilter");
	
	MarkNativeAsOptional("MapChoices_WillChangeAtRoundEnd");
	MarkNativeAsOptional("MapChoices_RegisterChangeMapHandler");
	MarkNativeAsOptional("MapChoices_UnregisterChangeMapHandler");
	
	MarkNativeAsOptional("MapChoices_AddGameFlags");
	MarkNativeAsOptional("MapChoices_RemoveGameFlags");
	MarkNativeAsOptional("MapChoices_GetGameFlags");
	MarkNativeAsOptional("MapChoices_OverrideConVar");
	MarkNativeAsOptional("MapChoices_ResetConVar");
	MarkNativeAsOptional("MapChoices_GetConVarOverride");
}
#endif
