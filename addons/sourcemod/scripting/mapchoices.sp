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
#pragma newdecls required
#define VERSION "1.0.0 alpha 1"

int roundCount;
StringMap g_Trie_NominatedMaps;
char g_MapNominations[MAXPLAYERS+1][PLATFORM_MAX_PATH];

//ConVars
ConVar g_Cvar_Enabled;

// Valve ConVars
ConVar g_Cvar_MaxRounds;
ConVar g_Cvar_Timelimit;

// Global Forwards
Handle g_Forward_MapVoteStarted;
Handle g_Forward_MapVoteEnded;
Handle g_Forward_NominationAdded;
Handle g_Forward_NominationRemoved;

// Private Forwards
Handle g_Forward_HandlerVoteStart;
Handle g_Forward_HandlerCancelVote;
Handle g_Forward_MapFilter;




//new Handle:m_ListLookup;

#include "mapchoices/parse-mapchoices-config.inc"

public Plugin myinfo = {
	name			= "MapChoices",
	author			= "Powerlord",
	description		= "An advanced map voting system for SourceMod",
	version			= VERSION,
	url				= ""
};

// Native Support
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("MapChoices_RegisterMapFilter", Native_AddMapFilter);
	CreateNative("MapChoices_RemoveMapFilter", Native_RemoveMapFilter);
	RegPluginLibrary("mapchoices");
}
  
public void OnPluginStart()
{
	InitializeConfigurationParser();
	//m_ListLookup = new StringMap();
	
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

public void OnConfigsExecuted()
{
}

public void OnClientDisconnect(int client)
{
	// Clear the client's nominations
	if (g_MapNominations[client][0] != '\0')
	{
		int count;
		if (g_Trie_NominatedMaps.GetValue(g_MapNominations[client], count))
		{
			--count;
			
			// Whoops, no more nominations for this map, so lets remove it.
			if (count <= 0)
			{
				g_Trie_NominatedMaps.Remove(g_MapNominations[client]);
			}
		}
		
		g_MapNominations[client][0] = '\0';
	}
}

void StartVote(MapChoices_MapChange when, ArrayList mapList=null)
{
	if (mapList == null)
	{
		//GetRemainingChoices("mapchoices");
	}
}

bool CheckMapFilter(const char[] map)
{
	Action result = Plugin_Continue;
	Call_StartForward(g_Forward_MapFilter);
	Call_PushString(map);
	Call_Finish(result);
	//TODO What we do in subplugins
}

// Ugh, caching is going to be a mess... might want to reconsider caching and just make this a general method for reading from the appropriate config file.
stock ArrayList ReadMapChoicesList(ArrayList kv=null, int &serial=1, const char[] str="default", int flags=MAPLIST_FLAG_CLEARARRAY)
{
	KeyValues kvConfig = new KeyValues("MapChoices");
	
	char configFile[PLATFORM_MAX_PATH+1];
	
	BuildPath(Path_SM, configFile, sizeof(configFile), "%s", CONFIGFILE);
	if (!FileToKeyValues(kvConfig, configFile))
	{
		SetFailState("Could not read configuration file: %s", configFile);
	}
	
}

stock ArrayList GetMapListFromFile(const char[] filename)
{
	
}

stock void LocateConfigurationFile(const char[] section, char[] filename, int maxlength)
{
	
}


// Events
// Note: These are just the shared events

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	++roundCount;
	
	// Missing logic to actually check the rounds and start the vote.
}

// Natives

public int Native_ReadMapChoicesList(Handle plugin, int numParams)
{
	Handle mapKv = GetNativeCell(1);
	int serial = GetNativeCellRef(2);
}

public int Native_AddMapFilter(Handle plugin, int numParams)
{
	Function func = GetNativeCell(1);
	
	return AddToForward(g_Forward_MapFilter, plugin, func);
}

public int Native_RemoveMapFilter(Handle plugin, int numParams)
{
	Function func = GetNativeCell(1);
	
	return RemoveFromForward(g_Forward_MapFilter, plugin, func);
}

public int Native_StartVote(Handle plugin, int numParams)
{
	MapChoices_MapChange when = GetNativeCell(1);
	ArrayList mapList = view_as<ArrayList>(GetNativeCell(2));
	
	StartVote(when, mapList);
}

// native Handle:MapChoices_ReadMapList(Handle:mapList=INVALID_HANDLE, &serial=1, const String:str[]="default", flags=MAPLIST_FLAG_CLEARARRAY);
public int Native_ReadMapList(Handle plugin, int numParams)
{
	ArrayList mapList = view_as<ArrayList>(GetNativeCell(1));
	int serial = GetNativeCellRef(2);
	int flags = GetNativeCell(4);
	
	int length;
	GetNativeStringLength(3, length);
	char[] str = new char[length+1];
	GetNativeString(3, str, length+1);
	
	ArrayList pArray;
	ArrayList pNewArray;
	
	UpdateCache();
	
	if ((pNewArray = UpdateMapList(mapList, str, serial, flags)) == null)
	{
		return view_as<int>(INVALID_HANDLE);
	}

	SetNativeCellRef(2, serial); // Update serial with the copy from UpdateMapList
	
	/* If the user wanted a new array, create it now. */
	if (mapList == INVALID_HANDLE)
	{
		mapList = view_as<ArrayList>(CloneHandle(pNewArray, plugin)); // Changes ownership
		delete pNewArray; // Delete our copy of this handle
	}
	
	return view_as<int>(mapList);
	
	// TODO Remaining map logic
}