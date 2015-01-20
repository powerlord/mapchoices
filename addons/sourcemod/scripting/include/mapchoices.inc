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

enum MapChoices_NominateResult
{
	NominateResult_Added,		/** The map was added */
	NominateResult_Rejected,	/** The map was rejected by a map filter */
	NominateResult_InvalidMap,	/** The map doesn't exist. */
	NominateResult_AlreadyInVote, /** The map is already in the list and you tried to constant nominate it */
}

enum MapChoices_MapChange
{
	MapChoicesMapChange_Instant,		/** Change map as soon as the voting results have come in */
	MapChoicesMapChange_RoundEnd,		/** Change map at the end of the round */
	MapChoicesMapChange_MapEnd,		/** Change the sm_nextmap cvar */
};



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
native MapChoices_NominateResult:MapChoices_Nominate(const String:map[], owner);

/**
 * NOTE:  This may never be implemented until I see a good reason to keep it.
 * Remove a named map from the nominations list.
 * 
 * @param map		Map to remove.
 */
//native bool:MapChoices_RemoveNominationByMap(const String:map[]);

/**
 * NOTE: This may never be implemented until I see a good reason to keep it.  Core can track this on its own.
 * Remove a player's nomination from the nominations list.
 * 
 * @param owner	Client whose nomination we will remove.
 */
//native bool:MapChoices_RemoveNominationByClient(client);

/**
 * Start a map vote.
 * 
 * @param when		When should the map change?
 * @param mapList		Don't get too attached to this arg as it may go away.
 * 					A holdback from the MapChooser days.
 * 
 */
native MapChoices_StartVote(MapChoices_MapChange:when, Handle:mapList=INVALID_HANDLE);

/**
 * A map vote started.
 */
forward MapChoices_MapVoteStarted();

/**
 * A map vote just ended and a map won.
 * 
 * @param map		The map that was voted in.  This will be equal to the constant
 *                 MAPCHOICES_NOCHANGE if the map is not changing
 * @param instant	True if MapChoices is going to instantly change the map, false if not.
 * @param group	If the map was part of a group, which group it was from.
 * @noreturn
 */
forward MapChoices_MapVoteEnded(const String:map[], bool:instant, const String:group[]);

/**
 * A map was added to the nominations list.
 * 
 * @param map		The map that was added.
 * @param owner	The user that added the map.  Will be 0 if the map was programatically added.
 * 
 */
forward MapChoices_NominationAdded(const String:map[], owner);

/**
 * A map has been removed from the nominations list.
 * 
 * @param map		The map that was removed.
 * @param owner	The user that added the map.
 * 
 */
forward MapChoices_NominationRemoved(const String:map[], owner);

// Private forwards for vote managers

functag public MapChoices_HandlerStartVote(Handle:mapList);
functag public MapChoices_HandlerCancelVote();

/**
 * Override the main vote system with a different one.
 * This really exists for NativeVotes, so unless you have some use for it,
 * you really shouldn't be messing with it.
 * 
 * @param startVote	The function to call when a vote starts.
 * @param cancelVote	The function to call when a vote is canceled.
 * @param voteLimit	The number of items that can be in a vote.
 * 
 */
native MapChoices_RegisterVoteHandler(MapChoices_HandlerStartVote:startVote, MapChoices_HandlerCancelVote:cancelVote, voteLimit=0);
native MapChoices_UnregisterVoteHandler(MapChoices_HandlerStartVote:startVote, MapChoices_HandlerCancelVote:cancelVote);

/**
 * Allow the named map to be played?
 * 
 * @param map		The map name from a map list
 * @param data	A KeyValues structure with the key for the map already selected
 * 
 * @return 		Plugin_Continue to allow, Plugin_Handled or Plugin_Stop to deny
 *
 * Note: Any other plugin can deny the map before your plugin executes this, so do not
 * expect to use this for statistical purposes
 */
functag public Action:MapFilter(const String:map[], Handle:data);

/**
 * Register a map filter.  Map Filters are called when a map is selected to be added to
 * a map vote.
 * 
 * @param filter	The map filtering function
 * 
 * @return 		true if the filter was added
 */
native bool:MapChoices_AddMapFilter(MapFilter:filter);

/**
 * Unregister a map filter.
 * 
 * @param filter	The map filtering function
 * 
 * @return 		true if the filter was removed, false if it wasn't registered
 */
native bool:MapChoices_RemoveMapFilter(MapFilter:filter);

/**
 * Remove the path from the map name
 * This was intended to remove workshop paths.
 * Used internally by MapEqual and FindMapStringInArray.
 * 
 * @param map			Map name
 * @param destination	String to copy map name to
 * @param maxlen		Length of destination string
 * 
 * @return			True if path was removed, false if map and destination are the same
 */
stock bool:RemoveMapPath(const String:map[], String:destination[], maxlen)
{
	if (strlen(map) < 1)
	{
		ThrowError("Bad map name: %s", map);
	}
	
	// UNIX paths
	new pos = FindCharInString(map, '/', true);
	if (pos == -1)
	{
		// Windows paths
		pos = FindCharInString(map, '\\', true);
		if (pos == -1)
		{
			// Copy the path out unchanged, but return false
			// This was added by request, but also simplifies MapEqual a LOT
			strcopy(destination, maxlen, map);
			return false;
		}
	}

	// pos + 1 is because pos is the last / or \ location and we want to start one char further
	// maxlen is because strcopy will auto-stop if it hits '\0' before maxlen
	strcopy(destination, maxlen, map[pos+1]);
	
	return true;
}

/**
 * Check if two maps are the same map.
 * Takes workshop paths into account.
 * 
 * @param map		First map
 * @param map2	Second map
 * 
 * @return		true if they're the same map, false if not.
 */
stock bool:MapEqual(const String:map[], const String:map2[])
{
	new String:pathlessMap[PLATFORM_MAX_PATH];
	new String:pathlessMap2[PLATFORM_MAX_PATH];
	
	RemoveMapPath(map, pathlessMap, sizeof(pathlessMap));
	RemoveMapPath(map2, pathlessMap2, sizeof(pathlessMap2));
	
	return !strcmp(pathlessMap, pathlessMap2);
}

/**
 * A replacement for FindStringInArray, but using MapEqual to compare elements.
 * Returns the index for the first occurence of the provided map. If the map cannot be located, -1 will be returned.
 * 
 * @param array		ArrayList Handle.
 * @param map			Map to search for
 *
 * @return 			Array index, or -1 on failure
 */
stock FindMapStringInMapArray(Handle:array, const String:map[])
{
	new arrayLen = GetArraySize(array);
	for (new i = 0; i < arrayLen; i++)
	{
		new String:arrayMap[PLATFORM_MAX_PATH];
		GetArrayString(array, i, arrayMap, sizeof(arrayMap));
		if (MapEqual(arrayMap, map))
		{
			return i;
		}
	}
	
	return -1;
}

public SharedPlugin:__pl_mapchoices = 
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
public __pl_mapchoices_SetNTVOptional()
{
	MarkNativeAsOptional("MapChoices_RegisterVoteHandler");
	MarkNativeAsOptional("MapChoices_AddMapFilter");
	MarkNativeAsOptional("MapChoices_RemoveMapFilter");
	
}
#endif
