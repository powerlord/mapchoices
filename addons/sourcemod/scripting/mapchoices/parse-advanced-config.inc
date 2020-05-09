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

static MapChoices_MapDTO m_MapData;
static GroupData m_GroupData;
static AdvMapListState m_CurAdvState = ADV_MPS_NONE;
static int m_AdvIgnoreLevel;
static StringMap tempMapTrie;

bool ReadAdvancedMapFile(MaplistInfo pMapList)
{
	if (!FileExists(pMapList.path, true))
	{
		return false;
	}
	
	pMapList.pTrie.Close();
	
	SMCParser parser = GetAdvancedCfgSMCParser();
	
	int line;
	int col;
	
	SMCError error;
	
	if ((error = parser.ParseFile(pMapList.path, line, col))
		!= SMCError_Okay)
	{
		char errmsg[256];
		SMC_GetErrorString(error, errmsg, sizeof(errmsg));
		
		LogError("[MC] Could not parse file \"%s\"", pMapList.path);
		LogError("[MC] Error on line %d (col %d): %s", line, col, errmsg);		
		return false;
	}
	
	pMapList.pTrie = tempMapTrie;
	return true;
}

// Parser functions
public void ParseAdvancedList_ParseStart(SMCParser smc)
{
	m_CurAdvState = ADV_MPS_NONE;
	m_AdvIgnoreLevel = 0;
	m_GroupData.Close();
	tempMapTrie = new StringMap();
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
		m_GroupData.Close();
		
		strcopy(m_GroupData.group, sizeof(m_GroupData.group), name);
		m_GroupData.attributes = new StringMap();
		m_GroupData.mapList = new StringMap();
		
		m_CurAdvState = ADV_MPS_GROUP;
	}
	else if (m_CurAdvState == ADV_MPS_GROUP)
	{
		m_MapData.Close();
		
		strcopy(m_MapData.map, sizeof(m_MapData.map), name);
		m_MapData.attributes = new StringMap();
		
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
		m_GroupData.attributes.SetString(key, value);
	}
	else if (m_CurAdvState == ADV_MPS_MAP)
	{
		m_MapData.attributes.SetString(key, value);
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
		m_GroupData.mapList.SetValue(m_MapData.map, CloneHandle(m_MapData.attributes));
		
		m_MapData.Close();
		
		m_CurAdvState = ADV_MPS_GROUP;
	}
	else if (m_CurAdvState == ADV_MPS_GROUP)
	{
		GroupData realGroupData;
		CopyGroupData(m_GroupData, realGroupData);
		
		tempMapTrie.SetArray(realGroupData.group, realGroupData, sizeof(realGroupData));
		
		m_GroupData.Close();
		
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
	// Make sure these handles are closed even if parsing fails
	m_MapData.Close();
	m_GroupData.Close();
}

stock void CopyGroupData(GroupData source, GroupData target)
{
	strcopy(target.group, sizeof(target.group), source.group);
	target.attributes = view_as<StringMap>(CloneHandle(source.attributes));
	target.mapList = view_as<StringMap>(CloneHandle(source.mapList));
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

