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
	
	g_RecentMapList = new ArrayList(mapdata_t);
	
	AutoExecConfig(true, "mapchoices-recent");
}

public void OnAllPluginsLoaded()
{
	MapChoices_RegisterMapFilter(FilterMaps);
}

public void OnMapStart()
{
	if (g_Cvar_RecentMaps.IntValue)
	{
		if (g_RecentMapList.Length >= g_Cvar_RecentMaps.IntValue)
		{
			for (int i = g_RecentMapList.Length; i >= g_Cvar_RecentMaps.IntValue - 1; i--)
			{
				// We don't store other information, only the map and group.
				g_RecentMapList.Erase(0);
			}
		}
		
		int mapData[mapdata_t];
		
		char mapGroup[MAX_GROUP_LENGTH];
		MapChoices_GetCurrentMapGroup(mapGroup, sizeof(mapGroup));
		
		GetCurrentMap(mapData[MapData_Map], sizeof(mapData[MapData_Map]));
		strcopy(mapData[MapData_MapGroup], sizeof(mapData[MapData_MapGroup]), mapGroup);
		g_RecentMapList.PushArray(mapData);
	}
}

public Action FilterMaps(const char[] mapGroup, const char[] map)
{
	if (!g_Cvar_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}
	
	for (int i = 0; i < g_RecentMapList.Length; i++)
	{
		int mapData[mapdata_t];
		g_RecentMapList.GetArray(i, mapData);
		
		if (!StrEqual(mapGroup, mapData[MapData_MapGroup], false))
		{
			continue;
		}
		
		char resolvedMap1[PLATFORM_MAX_PATH], resolvedMap2[PLATFORM_MAX_PATH];
		FindMap(mapData[MapData_Map], resolvedMap1, sizeof(resolvedMap1));
		FindMap(map, resolvedMap2, sizeof(resolvedMap2));
		
		if (StrEqual(resolvedMap2, resolvedMap1, false))
		{
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}
