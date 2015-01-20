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
#pragma semicolon 1

#define VERSION "1.0.0 alpha 1"

new Handle:g_Cvar_Enabled;

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
	CreateNative("Plugin_FunctionWithArg", Native_FunctionWithArg);
	CreateNative("Plugin_FunctionWithoutArg", Native_FunctionWithoutArg);
	CreateNative("Plugin_RegisterCallback", Native_RegisterCallback);
	CreateNative("Plugin_UnregisterCallback", Native_UnregisterCallback);
	
	RegPluginLibrary("mapchoices");
	
	return APLRes_Success;
}
  
public OnPluginStart()
{
	CreateConVar("mapchoices_version", VERSION, "MapChoices version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	g_Cvar_Enabled = CreateConVar("mapchoices_enable", "1", "Enable MapChoices?", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	
}

/*
// Natives

// native FunctionWithArg(const String:param1[]);
public Native_FunctionWithArg(Handle:plugin, numParams)
{
	// for const Strings
	new size;
	GetNativeStringLength(1, size);
	decl String:param1[size+1];
	GetNativeString(1, param1, size+1);
}

// native bool:FunctionWithoutArg();
public Native_FunctionWithoutArg(Handle:plugin, numParams)
{
	return true;
}

// native RegisterCallback(ACallback);
public Native_RegisterCallback(Handle:plugin, numParams)
{
}
	
// native UnregisterCallback(ACallback);
public Native_UnregisterCallback(Handle:plugin, numParams)
{
}
*/

