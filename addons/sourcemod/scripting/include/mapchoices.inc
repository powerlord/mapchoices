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
 * @param choices	The user that added the map
 * 
 */
forward MapChoices_NominationAdded(const String:map[], owner);


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

native MapChoices_RegisterMapFilter(MapFilter:filter);
native MapChoices_UnregisterMapFilter(MapFilter:filter);

public SharedPlugin:__pl_mapchoices = 
{
	name = "mapchoices",
	file = "mapchoices-core.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_mapchoices_SetNTVOptional()
{
	
}
#endif
