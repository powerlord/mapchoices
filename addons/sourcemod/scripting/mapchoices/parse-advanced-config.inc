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

#if defined _mapchoices_advanced_parser_included_
  #endinput
#endif
#define _mapchoices_advanced_parser_included_

/**
 * This file is the parser for Advanced map configuration files
 */
 
//#include "../include/mapchoices" // Include our own file to gain access to enums and the like

#define CONFIGFILE "configs/mapchoices.cfg"

//#pragma newdecls required
enum AdvMapListState:
{
	ADV_MPS_NONE,
	ADV_MPS_GLOBAL,
	ADV_MPS_GROUP,
	ADV_MPS_MAP,
}
static int m_MapData[mapdata_t];
static int m_GroupData[groupdata_t];
static AdvMapListState m_CurAdvState = ADV_MPS_NONE;
static int m_AdvIgnoreLevel;
static ArrayList tempMapList;
static ArrayList tempGroupList;

bool ReadAdvancedMapFile(int[] pMapList)
{
	if (!FileExists(pMapList[maplist_path], true))
	{
		return false;
	}
	
	delete pMapList[maplist_pArray];
	delete pMapList[maplist_pGroupArray];
	
	SMCParser parser = GetAdvancedCfgSMCParser();
	
	int line;
	int col;
	
	SMCError error;
	
	if ((error = parser.ParseFile(pMapList[maplist_path], line, col))
		!= SMCError_Okay)
	{
		char errmsg[256];
		SMC_GetErrorString(error, errmsg, sizeof(errmsg));
		
		LogError("[MC] Could not parse file \"%s\"", pMapList[maplist_path]);
		LogError("[MC] Error on line %d (col %d): %s", line, col, errmsg);		
		return false;
	}
	
	pMapList[maplist_pArray] = tempMapList;
	pMapList[maplist_pGroupArray] = tempGroupList;
	return true;
}

// Parser functions
public void ParseAdvancedList_ParseStart(SMCParser smc)
{
	m_CurAdvState = ADV_MPS_NONE;
	m_AdvIgnoreLevel = 0;
	ResetMapData(m_MapData);
	tempMapList = new ArrayList(mapdata_t);
}
  
public SMCResult ParseAdvancedList_NewSection(SMCParser smc, const char[] name, bool opt_quotes)
{
	if (m_AdvIgnoreLevel)
	{
		m_AdvIgnoreLevel++;
		return SMCParse_Continue;
	}
	
	if (m_CurAdvState == ADV_MPS_NONE)
	{
		if (strcmp(name, "mapchoices_mapcycle") == 0)
		{
			m_CurAdvState = ADV_MPS_GLOBAL;
		}
		else
		{
			m_AdvIgnoreLevel = 1;
		}
	}
	else if (m_CurAdvState == ADV_MPS_GLOBAL)
	{
		ResetGroupData(m_GroupData);
		
		strcopy(m_GroupData[GroupData_Group], sizeof(m_GroupData[GroupData_Group]), name);
		
		m_CurAdvState = ADV_MPS_GROUP;
	}
	else if (m_CurAdvState == ADV_MPS_GROUP)
	{
		ResetMapData(m_MapData);
		
		strcopy(m_MapData[MapData_MapGroup], sizeof(m_MapData[MapData_MapGroup]), m_GroupData[GroupData_Group]);		
		strcopy(m_MapData[MapData_Map], sizeof(m_MapData[MapData_Map]), name);
		
		m_CurAdvState = ADV_MPS_MAP;
	}
	else if (m_CurAdvState == ADV_MPS_MAP)
	{
		m_AdvIgnoreLevel++;
	}
	
	return SMCParse_Continue;
}

public SMCResult ParseAdvancedList_KeyValue(SMCParser smc, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
	if (m_AdvIgnoreLevel)
	{
		return SMCParse_Continue;
	}
	
	if (m_CurAdvState == ADV_MPS_GROUP)
	{
		if (m_GroupData[GroupData_GroupAttributes] == null)
		{
			m_GroupData[GroupData_GroupAttributes] = new StringMap();
		}
		
		m_GroupData[GroupData_GroupAttributes].SetString(key, value);
	}
	else if (m_CurAdvState == ADV_MPS_MAP)
	{
		if (m_MapData[MapData_MapAttributes] == null)
		{
			m_MapData[MapData_MapAttributes] = new StringMap();
		}
		
		m_MapData[MapData_MapAttributes].SetString(key, value);
	}
	
	return SMCParse_Continue;
}

public SMCResult ParseAdvancedList_LeavingSection(SMCParser smc)
{
	if (m_AdvIgnoreLevel)
	{
		m_AdvIgnoreLevel--;
		return SMCParse_Continue;
	}
	
	if (m_CurAdvState == ADV_MPS_MAP)
	{
		// Copy array
		int realMapData[mapdata_t];
		CopyMapData(m_MapData, realMapData);
		
		ResetMapData(m_MapData);
		
		tempMapList.PushArray(realMapData, sizeof(realMapData));
		
		m_CurAdvState = ADV_MPS_GROUP;
	}
	else if (m_CurAdvState == ADV_MPS_GROUP)
	{
		int realGroupData[groupdata_t];
		CopyGroupData(m_GroupData, realGroupData);
		
		ResetGroupData(m_GroupData);
		
		tempGroupList.PushArray(realGroupData, sizeof(realGroupData));
		
		m_CurAdvState = ADV_MPS_GLOBAL;
	}
	else if (m_CurAdvState == ADV_MPS_GLOBAL)
	{
		m_CurAdvState = ADV_MPS_NONE;
	}

	return SMCParse_Continue;
}

public void ParseAdvancedList_ParseEnd(SMCParser smc, bool halted, bool failed)
{
	ResetMapData(m_MapData);
}

// Since we don't new/delete enum arrays, just reset it.
stock void ResetMapData(int mapData[mapdata_t])
{
	mapData[MapData_Map][0] = '\0';
	mapData[MapData_MapGroup][0] = '\0';
	delete mapData[MapData_MapAttributes];
	mapData[MapData_MapAttributes] = null;
}

stock void ResetGroupData(int groupData[groupdata_t])
{
	groupData[GroupData_Group][0] = '\0';
	delete groupData[GroupData_GroupAttributes];
	groupData[GroupData_GroupAttributes] = null;
}

stock void CopyMapData(int source[mapdata_t], int target[mapdata_t])
{
	strcopy(target[MapData_Map], sizeof(target[MapData_Map]), source[MapData_Map]);
	strcopy(target[MapData_MapGroup], sizeof(target[MapData_MapGroup]), source[MapData_MapGroup]);
	target[MapData_MapAttributes] = view_as<StringMap>(CloneHandle(source[MapData_MapAttributes]));
}

stock void CopyGroupData(int source[groupdata_t], int target[groupdata_t])
{
	strcopy(target[GroupData_Group], sizeof(target[GroupData_Group]), source[GroupData_Group]);
	target[GroupData_GroupAttributes] = view_as<StringMap>(CloneHandle(source[GroupData_GroupAttributes]));
}

SMCParser GetAdvancedCfgSMCParser()
{
	SMCParser parser = new SMCParser();
	parser.OnStart = ParseAdvancedList_ParseStart;
	parser.OnEnd = ParseAdvancedList_ParseEnd;
	parser.OnEnterSection = ParseAdvancedList_NewSection;
	parser.OnLeaveSection = ParseAdvancedList_LeavingSection;
	parser.OnKeyValue = ParseAdvancedList_KeyValue;
	
	return parser;
}

