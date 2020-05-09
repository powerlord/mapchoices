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

#include "../include/mapchoices" // Include our own file to gain access to enums and the like
#include <multicolors>

#pragma semicolon 1
#pragma newdecls required
#define VERSION "1.0.0 alpha 1"

//ConVars
ConVar g_Cvar_Enabled;
ConVar g_Cvar_RecentMaps;

ArrayList g_RecentMapList = null; // ArrayList of mapdata_t instances

public Plugin myinfo = {
	name			= "MapChoices Recently Played",
	author			= "Powerlord",
	description		= "Remove recently played maps",
	version			= VERSION,
	url				= ""
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("mapchoices.phrases");
	
	CreateConVar("mapchoices_version", VERSION, "MapChoices version", FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	g_Cvar_Enabled = CreateConVar("mapchoices_recent_enable", "1", "Enable MapChoices?", FCVAR_NOTIFY|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	g_Cvar_RecentMaps = CreateConVar("mapchoices_recent_count", "5", "How many recent maps to skip in the map list? Note: The same map in different groups will be considered different maps.", _, true, 0.0);
	
	g_RecentMapList = new ArrayList(sizeof(MapChoices_MapDTO));
	
	AutoExecConfig(true, "mapchoices/mapchoices-recent");
}

public void OnAllPluginsLoaded()
{
	MapChoices_RegisterMapFilter(FilterMaps);
}

public void OnMapStart()
{
	if (g_Cvar_RecentMaps.IntValue > 0)
	{
		if (g_RecentMapList.Length >= g_Cvar_RecentMaps.IntValue)
		{
			for (int i = g_RecentMapList.Length; i >= g_Cvar_RecentMaps.IntValue - 1; i--)
			{
				// We don't store other information, only the map and group.
				g_RecentMapList.Erase(0);
			}
		}
		
		MapChoices_MapDTO mapData;
		
		char mapGroup[MAPCHOICES_MAX_GROUP_LENGTH];
		MapChoices_GetCurrentMapGroup(mapGroup, sizeof(mapGroup));
		
		GetCurrentMap(mapData.map, sizeof(mapData.map));
		strcopy(mapData.group, sizeof(mapData.group), mapGroup);
		g_RecentMapList.PushArray(mapData);
	}
}

public Action FilterMaps(MapChoices_MapDTO mapData)
{
	if (!g_Cvar_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}
	
	if (FindMapInMapList(g_RecentMapList, mapData.group, mapData.map) != -1)
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}
