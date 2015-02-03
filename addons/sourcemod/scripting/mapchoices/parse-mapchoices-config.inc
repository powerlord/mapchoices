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

 // This file is for parsing SMC constructs, such as configs/mapchoices.cfg
 
 enum MapListState
 {
	MPS_NONE,
	MPS_GLOBAL,
	MPS_MAPLIST,
 }

 enum maplist_info_t
 {
	bool:bInitialized,
	bool:bIsCompat,
	bool:bIsPath,
	last_modified_time,
	Handle:pArray,
	serial,
	String:sName[PLATFORM_MAX_PATH],
	String:sPath[PLATFORM_MAX_PATH],
 }

static String:m_ConfigFile[PLATFORM_MAX_PATH]; 
static m_ConfigLastChanged;
static Handle:m_ListLookup; // Trie of array (maplist_info_t)
static Handle:m_ListLookupNames; // Tries in 1.6 STILL don't support key lookups without just fetching the values back, so fake it
static Handle:m_MapLists; // Array of array (maplist_info_t)
static MapListState:m_CurState = MPS_NONE;
static m_IgnoreLevel;
static m_pCurMapList[maplist_info_t];
static m_nSerialChanged;

AddOrUpdateDefault(const String:name[], const String:file[])
{
	new String:path[PLATFORM_MAX_PATH];
	new pMapList[maplist_info_t];
	
	if (!GetTrieArray(m_ListLookup, name, pMapList, sizeof(pMapList)))
	{
		pMapList[bIsCompat] = true;
		pMapList[bIsPath] = true;
		pMapList[last_modified_time] = true;
		strcopy(pMapList[sName], sizeof(pMapList[sName]), name);
		strcopy(pMapList[sPath], sizeof(pMapList[sPath]), file);
		pMapList[serial] = 0;
		SetTrieArray(m_ListLookup, name, pMapList, sizeof(pMapList));
		PushArrayString(m_ListLookupNames, name);
		PushArrayArray(m_MapLists, pMapList, sizeof(pMapList));
		return;
	}
	
	/* Don't modify if it's from the config file */
	if (!pMapList[bIsCompat])
		return;
	
	strcopy(path, sizeof(path), file);
	
	/* If the path matches, don't reset the serial/time */
	if (strcmp(path, pMapList[sPath]) == 0)
		return;
		
	strcopy(pMapList[sPath], sizeof(pMapList[sPath]), path);
	pMapList[bIsPath] = true;
	pMapList[last_modified_time] = 0;
	pMapList[serial] = 0;
	
	// Because this isn't a reference in Pawn... sorta
	SetTrieArray(m_ListLookup, name, pMapList, sizeof(pMapList));
}

public UpdateCache()
{
	new SMCError:error;
	new fileTime;
	
	if (m_ConfigFile[0] == '\0')
	{
		BuildPath(Path_SM, m_ConfigFile, sizeof(m_ConfigFile), "%s", CONFIGFILE);
	}
	
	fileTime = GetFileTime(m_ConfigFile, FileTime_LastChange);
	
	/* If the file is found and hasn't changed, bail out now */
	if (fileTime > -1 && fileTime == m_ConfigLastChanged)
	{
		return;
	}
	
	/* If the file wasn't found, and we already have entries, we bail out too.
	 * This case lets us optimize when a user deletes the config file, so we
	 * don't reparse every single time the function is called.
	 */
	if (fileTime == -1 && GetArraySize(m_MapLists) > 0)
	{
		return;
	}
	
	/* Dump everything we know about. */
	new Handle:compat = CreateArray(maplist_info_t);
	DumpCache(compat);

	/* Now parse the config file even if we don't know about it.
	 * This will give us a nice error message.
	 */
	new Handle:parser = GetSMCParser();
	new line;
	new col;
	
	if ((error = SMC_ParseFile(parser, m_ConfigFile, line, col))
		!= SMCError_Okay)
	{
		new String:errmsg[256];
		SMC_GetErrorString(error, errmsg, sizeof(errmsg));
		
		LogError("[MC] Could not parse file \"%s\"", m_ConfigFile);
		LogError("[MC] Error on line %d (col %d): %s", line, col, errmsg);
	}
	else
	{
		m_ConfigLastChanged = fileTime;
	}
	
	/* Now, re-add compat stuff back in if we can. */
	for (new i = 0; i < GetArraySize(compat); i++)
	{
		new localArray[maplist_info_t];
		GetArrayArray(compat, i, localArray, sizeof(localArray));
		
		if (FindStringInArray(m_ListLookupNames, localArray[sName]) != -1)
		{
			/* The compatibility shim is no longer needed. */
			if (localArray[pArray] != INVALID_HANDLE)
			{
				CloseHandle(localArray[pArray]);
			}
		}
		else
		{
			SetTrieArray(m_ListLookup, localArray[sName], localArray, sizeof(localArray));
			PushArrayString(m_ListLookupNames, localArray[sName]);
			PushArrayArray(m_MapLists, localArray, sizeof(localArray));
		}
	}
	
	CloseHandle(compat);
}

Handle:UpdateMapList(Handle:pUseArray, const String:name[], &pSerial, flags)
{
	new change_serial;
	new Handle:pNewArray;
	new bool:success;
	
	new bool:free_new_array;
	
	if ((success = GetMapList(pNewArray, name, change_serial)) == false)
	{
		if ((flags & MAPLIST_FLAG_NO_DEFAULT) != MAPLIST_FLAG_NO_DEFAULT)
		{
			/* If this list failed, and it's not the default, try the default.
			 */
			if (strcmp(name, "default") != 0)
			{
				success = GetMapList(pNewArray, name, change_serial);
			}
			/* If either of the last two conditions failed, try again if we can */
			if (!success && strcmp(name, "mapcyclefile") != 0)
			{
				success = GetMapList(pNewArray, "mapcyclefile", change_serial);
			}
		}
	}
	
	/* If there was a success, and the serial has not changed, bail out */
	if (success && pSerial == change_serial)
	{
		return INVALID_HANDLE;
	}
	
	/**
	 * If there was a success but no map list, we need to look in the maps folder
	 * If there was a failure and the flag is specified, we need to look in the maps folder
	 */
	if ((success && pNewArray == INVALID_HANDLE)
		|| (!success && (flags & MAPLIST_FLAG_MAPSFOLDER)))
	{
		pNewArray = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
		free_new_array = true;
		
		new blk;
		
		// TODO Find all files
	}
}

bool:GetMapList(Handle:ppKv, const String:name[], &pSerial)
{
	new last_time;
	new pMapList[maplist_info_t];
	
	if (!GetTrieArray(m_ListLookup, name, pMapList, sizeof(pMapList)))
		return false;
	
	if (!pMapList[bIsPath])
		return GetMapList(ppKv, pMapList[sPath], pSerial);
		
	/* If it is a path, and the path is "*", assume all files must be used. */
	if (strcmp(pMapList[sPath], "*") == 0)
	{
		ppKv = INVALID_HANDLE;
		return true;
	}
	
	if ((last_time = GetFileTime(pMapList[sPath], FileTime_LastChange)) > -1
		|| last_time > pMapList[last_modified_time])
	{
		/* Reparse */
		// TODO: logic to read file here
	}
	
	if (pMapList[pArray] == INVALID_HANDLE)
	{
		return false;
	}
	pSerial = pMapList[serial];
	ppKv = pMapList[pArray];
	
	return true;
}

/**
 * Dump the cache and re-add the maplists to it
 * @param compat_list	Handle (passed by ref, do NOT close)
 */
DumpCache(Handle:compat_list)
{
	ClearTrie(m_ListLookup);
	ClearArray(m_ListLookupNames);
	
	for (new i = GetArraySize(m_MapLists) - 1; i >= 0; i--)
	{
		new localArray[maplist_info_t];
		GetArrayArray(m_MapLists, i, localArray, sizeof(localArray));
		if (compat_list != INVALID_HANDLE && localArray[bIsCompat])
		{
			PushArrayArray(compat_list, localArray, sizeof(localArray));
		}
		else
		{
			if (localArray[pArray] != INVALID_HANDLE)
			{
				CloseHandle(localArray[pArray]);
			}
		}
		RemoveFromArray(m_MapLists, i);
	}
}

// Since we don't new/delete enum arrays, just reset it.
// Remember to set bInitialized when you'd normally new it
ResetMapList(mapList[])
{
	mapList[bInitialized] = false;
	mapList[bIsCompat] = false;
	mapList[bIsPath] = false;
	mapList[last_modified_time] = 0;
	// Since we store this for later, don't close it
	/*
	if (mapList[pArray] != INVALID_HANDLE)
	{
		CloseHandle(mapList[pArray]);
	}
	*/
	mapList[pArray] = INVALID_HANDLE;
	mapList[serial] = -1;
	mapList[sName] = "";
	mapList[sPath] = "";
}

// Set up the functions for use in the parser.
Handle:GetSMCParser()
{
	new Handle:parser = SMC_CreateParser();
	SMC_SetReaders(parser, ParseMapList_NewSection, ParseMapList_KeyValue, ParseMapList_LeavingSection);
	SMC_SetParseStart(parser, ParseMapList_ParseStart);
	SMC_SetParseEnd(parser, ParseMapList_ParseEnd);
	
	return parser;
}

// Parser functions

public ParseMapList_ParseStart(Handle:smc)
{
	m_CurState = MPS_NONE;
	m_IgnoreLevel = 0;
	ResetMapList(m_pCurMapList);
	if (m_ListLookup == INVALID_HANDLE)
	{
		m_ListLookup = CreateTrie();
	}
	
	if (m_MapLists == INVALID_HANDLE)
	{
		m_MapLists = CreateArray(maplist_info_t);
	}
	
	if (m_ListLookupNames == INVALID_HANDLE)
	{
		m_ListLookupNames = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
	}
}
  
public SMCResult:ParseMapList_NewSection(Handle:smc, const String:name[], bool:opt_quotes)
{
	if (m_IgnoreLevel)
	{
		m_IgnoreLevel++;
		return SMCParse_Continue;
	}
	
	if (m_CurState == MPS_NONE)
	{
		if (strcmp(name, "MapLists") == 0)
		{
			m_CurState = MPS_GLOBAL;
		}
		else
		{
			m_IgnoreLevel = 1;
		}
	}
	else if (m_CurState == MPS_GLOBAL)
	{
		ResetMapList(m_pCurMapList);
		m_pCurMapList[bInitialized] = true;
		
		strcopy(m_pCurMapList[sName], sizeof(m_pCurMapList[sName]), name);
		
		m_CurState = MPS_MAPLIST;
	}
	else if (m_CurState == MPS_MAPLIST)
	{
		m_IgnoreLevel++;
	}
	
	return SMCParse_Continue;
}

public SMCResult:ParseMapList_KeyValue(Handle:smc, const String:key[], const String:value[], bool:key_quotes, bool:value_quotes)
{
	if (m_IgnoreLevel || !m_pCurMapList[bInitialized])
	{
		return SMCParse_Continue;
	}
	
	if (strcmp(key, "file") == 0)
	{
		strcopy(m_pCurMapList[sPath], sizeof(m_pCurMapList[sPath]), value);
		m_pCurMapList[bIsPath] = true;
	}
	else if (strcmp(key, "target") == 0)
	{
		strcopy(m_pCurMapList[sPath], sizeof(m_pCurMapList[sPath]), value);
		m_pCurMapList[bIsPath] = false;
	}
	
	return SMCParse_Continue;
}

public SMCResult:ParseMapList_LeavingSection(Handle:smc)
{
	if (m_IgnoreLevel)
	{
		m_IgnoreLevel--;
		return SMCParse_Continue;
	}
	
	if (m_CurState == MPS_MAPLIST)
	{
		if (m_pCurMapList[bInitialized]
			&& m_pCurMapList[sPath][0] != '\0'
			&& FindStringInArray(m_ListLookupNames, m_pCurMapList[sName]) == -1)
		{
			SetTrieArray(m_ListLookup, m_pCurMapList[sName], m_pCurMapList, sizeof(m_pCurMapList));
			PushArrayString(m_ListLookupNames, m_pCurMapList[sName]);
			PushArrayArray(m_MapLists, m_pCurMapList);
			ResetMapList(m_pCurMapList);
		}
		else
		{
			ResetMapList(m_pCurMapList);
		}
		m_CurState = MPS_GLOBAL;
	}
	else if (m_CurState == MPS_GLOBAL)
	{
		m_CurState = MPS_NONE;
	}
	
	return SMCParse_Continue;
}
 
 public ParseMapList_ParseEnd(Handle:smc, bool:halted, bool:failed)
 {
	ResetMapList(m_pCurMapList);
 }
