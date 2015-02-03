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
#include "include/mapchoices" // Include our own file to gain access to enums and the like
#pragma semicolon 1

#define VERSION "1.0.0 alpha 1"

#define CONFIGFILE "configs/mapchoices.cfg"

new roundCount;
new Handle:g_Trie_NominatedMaps;
new String:g_MapNominations[MAXPLAYERS+1][PLATFORM_MAX_PATH];

//ConVars
new Handle:g_Cvar_Enabled;

// Valve ConVars
new Handle:g_Cvar_MaxRounds;
new Handle:g_Cvar_Timelimit;

// Global Forwards
new Handle:g_Forward_MapVoteStarted;
new Handle:g_Forward_MapVoteEnded;
new Handle:g_Forward_NominationAdded;
new Handle:g_Forward_NominationRemoved;

// Private Forwards
new Handle:g_Forward_HandlerVoteStart;
new Handle:g_Forward_HandlerCancelVote;
new Handle:g_Forward_MapFilter;




new Handle:m_ListLookup;

#include "mapchoices/parse-mapchoices-config.inc"

public Plugin:myinfo = {
	name			= "MapChoices",
	author			= "Powerlord",
	description		= "An advanced map voting system for SourceMod",
	version			= VERSION,
	url				= ""
};

// Native Support
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("MapChoices_RegisterMapFilter", Native_AddMapFilter);
	CreateNative("MapChoices_RemoveMapFilter", Native_RemoveMapFilter);
	RegPluginLibrary("mapchoices");
	
	new Handle:kvConfig = CreateKeyValues("MapChoices");
	
	new String:configFile[PLATFORM_MAX_PATH+1];
	
	BuildPath(Path_SM, configFile, sizeof(configFile), "%s", CONFIGFILE);
	if (!FileToKeyValues(kvConfig, configFile))
	{
		Format(error, err_max, "Could not read configuration file: %s", configFile);
		return APLRes_Failure;
	}
	
	return APLRes_Success;
}
  
public OnPluginStart()
{
	m_ListLookup = CreateTrie();
	
	LoadTranslations("common.phrases");
	LoadTranslations("mapchoices.phrases");
	
	CreateConVar("mapchoices_version", VERSION, "MapChoices version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	g_Cvar_Enabled = CreateConVar("mapchoices_enable", "1", "Enable MapChoices?", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	
	g_Cvar_MaxRounds = FindConVar("mp_maxrounds");
	g_Cvar_Timelimit = FindConVar("mp_timelimit");
	
	g_Forward_MapVoteStarted = CreateGlobalForward("MapChoices_MapVoteStarted", ET_Ignore);
	g_Forward_MapVoteEnded = CreateGlobalForward("MapChoices_MapVoteEnded", ET_Ignore, Param_String, Param_Cell, Param_String);
	g_Forward_NominationAdded = CreateGlobalForward("MapChoices_NominationAdded", ET_Ignore, Param_String, Param_Cell);
	g_Forward_NominationRemoved = CreateGlobalForward("MapChoices_NominationRemoved", ET_Ignore, Param_String, Param_Cell);
	
	g_Forward_HandlerVoteStart = CreateForward(ET_Hook, Param_Cell);
	g_Forward_HandlerCancelVote = CreateForward(ET_Hook);
	g_Forward_MapFilter = CreateForward(ET_Hook, Param_String, Param_Cell);
	
	HookEvent("round_end", Event_RoundEnd);
}

public OnConfigsExecuted()
{
}

public OnClientDisconnect(client)
{
	// Clear the client's nominations
	if (g_MapNominations[client][0] != '\0')
	{
		new count;
		if (GetTrieValue(g_Trie_NominatedMaps, g_MapNominations[client], count))
		{
			--count;
			
			// Whoops, no more nominations for this map, so lets remove it.
			if (count <= 0)
			{
				RemoveFromTrie(g_Trie_NominatedMaps, g_MapNominations[client]);
			}
		}
		
		g_MapNominations[client][0] = '\0';
	}
}

StartVote(MapChoices_MapChange:when, Handle:mapList=INVALID_HANDLE)
{
	if (mapList == INVALID_HANDLE)
	{
		//GetRemainingChoices("mapchoices");
	}
}

bool:CheckMapFilter(const String:map[])
{
	new Action:result = Plugin_Continue;
	Call_StartForward(g_Forward_MapFilter);
	Call_PushString(map);
	Call_Finish(result);
	//TODO What we do in subplugins
}

// Ugh, caching is going to be a mess... might want to reconsider caching and just make this a general method for reading from the appropriate config file.
stock Handle:ReadMapChoicesList(Handle:kv=INVALID_HANDLE, &serial=1, const String:str[]="default", flags=MAPLIST_FLAG_CLEARARRAY)
{
	new Handle:kvConfig = CreateKeyValues("MapChoices");
	
	new String:configFile[PLATFORM_MAX_PATH+1];
	
	BuildPath(Path_SM, configFile, sizeof(configFile), "%s", CONFIGFILE);
	if (!FileToKeyValues(kvConfig, configFile))
	{
		SetFailState("Could not read configuration file: %s", configFile);
	}
	
}

stock Handle:GetMapListFromFile(const String:filename[])
{
	
}

stock LocateConfigurationFile(const String:section[], String:filename[], maxlength)
{
	
}


// Events
// Note: These are just the shared events

public Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	++roundCount;
	
	// Missing logic to actually check the rounds and start the vote.
}

// Natives

public Native_ReadMapChoicesList(Handle:plugin, numParams)
{
	new Handle:mapKv = GetNativeCell(1);
	new serial = GetNativeCellRef(2);
}

public Native_AddMapFilter(Handle:plugin, numParams)
{
	new Function:func = GetNativeCell(1);
	
	return AddToForward(g_Forward_MapFilter, plugin, func);
}

public Native_RemoveMapFilter(Handle:plugin, numParams)
{
	new Function:func = GetNativeCell(1);
	
	return RemoveFromForward(g_Forward_MapFilter, plugin, func);
}

public Native_StartVote(Handle:plugin, numParams)
{
	new MapChoices_MapChange:when = GetNativeCell(1);
	new Handle:mapList = GetNativeCell(2);
	
	StartVote(when, mapList);
}

// native Handle:MapChoices_ReadMapList(Handle:mapList=INVALID_HANDLE, &serial=1, const String:str[]="default", flags=MAPLIST_FLAG_CLEARARRAY);
public Native_ReadMapList(Handle:plugin, numParams)
{
	new Handle:mapList = GetNativeCell(1);
	new serial = GetNativeCellRef(2);
	new flags = GetNativeCell(4);
	
	new String:str[MAX_GROUP_LENGTH+1];
	GetNativeString(3, str, sizeof(str));
	
	new Handle:pArray;
	new Handle:pNewArray;
	
	UpdateCache();
	
	if ((pNewArray = UpdateMapList(pArray, str, serial, flags)) == INVALID_HANDLE)
	{
		return INVALID_HANDLE;
	}

	if (mapList == INVALID_HANDLE)
	{
		new Handle:tempList = CreateArray(mapdata_t);
		mapList = CloneHandle(tempList, plugin); // Changes ownership
		CloseHandle(tempList);
	}
	
	return mapList;
	
	// TODO Remaining map logic
}