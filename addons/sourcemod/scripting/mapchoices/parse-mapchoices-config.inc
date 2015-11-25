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
#if defined _mapchoices_config_parser_included_
  #endinput
#endif
#define _mapchoices_config_parser_included_

/**
 * This file is HEAVILY influenced by SourceMod's smn_maplists.cpp.
 * 
 * This file exists almost exclusively to replace core's ReadMapList with our 
 * own version that also works for advanced map lists.
 * 
 * This means some "creative" changes had to be made to make it work like the
 * C++ version does.
 */
 
// This file is for parsing SMC constructs, such as configs/mapchoices.cfg
//#include "../include/mapchoices" // Include our own file to gain access to enums and the like
#define CONFIGFILE "configs/mapchoices.cfg"

//#pragma newdecls required
enum MapListState:
{
	MPS_NONE,
	MPS_GLOBAL,
	MPS_MAPLIST,
}

// Old style enum for enum-struct
enum maplist_info_t
{
	MapChoices_MapListType:maplist_Type,
	bool:maplist_bInitialized,
	bool:maplist_bIsCompat,
	bool:maplist_bIsPath,
	maplist_last_modified_time,
	ArrayList:maplist_pArray,				/**< ArrayList of mapdata_t */
	ArrayList:maplist_pGroupArray,			/**< ArrayList of groupdata_t */
	maplist_serial,
	String:maplist_name[PLATFORM_MAX_PATH],
	String:maplist_path[PLATFORM_MAX_PATH],
}

#include "mapchoices/parse-advanced-config"

static char m_ConfigFile[PLATFORM_MAX_PATH]; 
static int m_ConfigLastChanged;
static StringMap m_ListLookup; /**< StringMap of maplist_info_t */
static ArrayList m_MapLists; /**< ArrayList of maplist_info_t */
static MapListState m_CurState = MPS_NONE;
static int m_IgnoreLevel;
static int m_pCurMapList[maplist_info_t];
static int m_nSerialChange;
static ConVar m_pMapCycleFile;

void InitializeConfigurationParser()
{
	BuildPath(Path_SM, m_ConfigFile, sizeof(m_ConfigFile), "%s", CONFIGFILE);
}

void GetMapCycleFilePath(char[] pBuffer, int maxlen)
{
	char pMapCycleFileName[PLATFORM_MAX_PATH];
	EngineVersion engineType = GetEngineVersion();
	
	if (m_pMapCycleFile != null)
	{
		m_pMapCycleFile.GetString(pMapCycleFileName, sizeof(pMapCycleFileName));
	}
	else
	{
		pMapCycleFileName = "mapcycle.txt";
	}
	
	switch (engineType)
	{
		case Engine_TF2, Engine_CSS, Engine_DODS, Engine_HL2DM, Engine_SDK2013:
		{
			// These found games and Source SDK 2013 do a lookup in this order; so shall we.
			// Note: Source SDK 2013 is left out in the SM core in 1.6, check 1.7 to see what it does.
			Format(pBuffer, maxlen, "cfg/%s", pMapCycleFileName);
			
			if (!FileExists(pBuffer, true))
			{
				Format(pBuffer, maxlen, "%s", pMapCycleFileName);

				if (!FileExists(pBuffer, true))
				{
					Format(pBuffer, maxlen, "cfg/mapcycle_default.txt");
				}
			}
		}
		
		default:
		{
			Format(pBuffer, maxlen, "%s", pMapCycleFileName);
		}
	}
}

void AddOrUpdateDefault(const char[] name, const char[] file, MapChoices_MapListType mapListType)
{
	char path[PLATFORM_MAX_PATH];
	int pMapList[maplist_info_t];
	
	if (!m_ListLookup.GetArray(name, pMapList, sizeof(pMapList)))
	{
		pMapList[maplist_bIsCompat] = true;
		pMapList[maplist_bIsPath] = true;
		pMapList[maplist_last_modified_time] = true;
		strcopy(pMapList[maplist_name], sizeof(pMapList[maplist_name]), name);
		pMapList[maplist_pArray] = null;
		strcopy(pMapList[maplist_path], sizeof(pMapList[maplist_path]), file);
		pMapList[maplist_serial] = 0;
		pMapList[maplist_Type] = mapListType;
		m_ListLookup.SetArray(name, pMapList, sizeof(pMapList));
		m_MapLists.PushArray(pMapList, sizeof(pMapList));
		return;
	}
	
	/* Don't modify if it's from the config file */
	if (!pMapList[maplist_bIsCompat])
		return;
	
	strcopy(path, sizeof(path), file);
	
	/* If the path matches, don't reset the serial/time */
	if (strcmp(path, pMapList[maplist_path]) == 0)
		return;
		
	strcopy(pMapList[maplist_path], sizeof(pMapList[maplist_path]), path);
	pMapList[maplist_bIsPath] = true;
	pMapList[maplist_last_modified_time] = 0;
	pMapList[maplist_serial] = 0;
	
	// This line may be extraneous, test to verify this
	m_ListLookup.SetArray(name, pMapList, sizeof(pMapList));
}

public void UpdateCache()
{
	bool fileFound;
	SMCError error;
	int fileTime;
	
	fileTime = GetFileTime(m_ConfigFile, FileTime_LastChange);
	
	fileFound = (fileTime > -1);
	
	/* If the file is found and hasn't changed, bail out now */
	if (fileFound && fileTime == m_ConfigLastChanged)
	{
		return;
	}
	
	/* If the file wasn't found, and we already have entries, we bail out too.
	 * This case lets us optimize when a user deletes the config file, so we
	 * don't reparse every single time the function is called.
	 */
	if (!fileFound && m_MapLists.Length > 0)
	{
		return;
	}
	
	m_pMapCycleFile = FindConVar("mapcyclefile");
	
	/* Dump everything we know about. */
	ArrayList compat = new ArrayList(maplist_info_t); // This is the size, not contents
	DumpCache(compat);

	/* All this to add the default entry back in */
	int pDefList[maplist_info_t];
	
	pDefList[maplist_Type] = MapChoicesMapList_Classic; // We mark this as a classic-style maplist
	pDefList[maplist_bIsPath] = true;
	strcopy(pDefList[maplist_name], sizeof(pDefList[maplist_name]), "mapcyclefile");
	
	GetMapCycleFilePath(pDefList[maplist_path], sizeof(pDefList[maplist_path]));
	
	pDefList[maplist_last_modified_time] = 0;
	pDefList[maplist_pArray] = null;
	pDefList[maplist_serial] = 0;
	
	m_ListLookup.SetArray("mapcyclefile", pDefList, sizeof(pDefList));
	m_MapLists.PushArray(pDefList);
	
	/* Now parse the config file even if we don't know about it.
	 * This will give us a nice error message.
	 */
	SMCParser parser = GetMapListsCfgSMCParser();
	
	int line;
	int col;
	
	if ((error = parser.ParseFile(m_ConfigFile, line, col))
		!= SMCError_Okay)
	{
		char errmsg[256];
		SMC_GetErrorString(error, errmsg, sizeof(errmsg));
		
		LogError("[MC] Could not parse file \"%s\"", m_ConfigFile);
		LogError("[MC] Error on line %d (col %d): %s", line, col, errmsg);
	}
	else
	{
		m_ConfigLastChanged = fileTime;
	}
	
	/* Now, re-add compat stuff back in if we can. */
	for (int i = 0; i < compat.Length; i++)
	{
		int localArray[maplist_info_t];
		GetArrayArray(compat, i, localArray, sizeof(localArray));
		
		if (IsKeyInStringMap(m_ListLookup, localArray[maplist_name]))
		{
			/* The compatibility shim is no longer needed. */
			delete localArray[maplist_pArray];
		}
		else
		{
			m_ListLookup.SetArray(localArray[maplist_name], localArray, sizeof(localArray));
			m_MapLists.PushArray(localArray, sizeof(localArray));
		}
	}
	
	delete compat;
}

// Parser functions

public void ParseMapList_ParseStart(SMCParser smc)
{
	m_CurState = MPS_NONE;
	m_IgnoreLevel = 0;
	ResetMapList(m_pCurMapList);
	if (m_ListLookup == null)
	{
		m_ListLookup = CreateTrie();
	}
	
	if (m_MapLists == null)
	{
		m_MapLists = new ArrayList(maplist_info_t);
	}
}
  
public SMCResult ParseMapList_NewSection(SMCParser smc, const char[] name, bool opt_quotes)
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
		m_pCurMapList[maplist_bInitialized] = true;
		
		strcopy(m_pCurMapList[maplist_name], sizeof(m_pCurMapList[maplist_name]), name);
		
		m_CurState = MPS_MAPLIST;
	}
	else if (m_CurState == MPS_MAPLIST)
	{
		m_IgnoreLevel++;
	}
	
	return SMCParse_Continue;
}

public SMCResult ParseMapList_KeyValue(SMCParser smc, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
	if (m_IgnoreLevel || !m_pCurMapList[maplist_bInitialized])
	{
		return SMCParse_Continue;
	}
	
	if (strcmp(key, "type") == 0)
	{
		if (strcmp(value, "advanced") == 0)
		{
			m_pCurMapList[maplist_Type] = MapChoicesMapList_Advanced;
		}
		else
		{
			m_pCurMapList[maplist_Type] = MapChoicesMapList_Classic;
		}
	}
	else if (strcmp(key, "file") == 0)
	{
		strcopy(m_pCurMapList[maplist_path], sizeof(m_pCurMapList[maplist_path]), value);
		m_pCurMapList[maplist_bIsPath] = true;
	}
	else if (strcmp(key, "target") == 0)
	{
		strcopy(m_pCurMapList[maplist_path], sizeof(m_pCurMapList[maplist_path]), value);
		m_pCurMapList[maplist_bIsPath] = false;
	}
	
	return SMCParse_Continue;
}

public SMCResult ParseMapList_LeavingSection(SMCParser smc)
{
	if (m_IgnoreLevel)
	{
		m_IgnoreLevel--;
		return SMCParse_Continue;
	}
	
	if (m_CurState == MPS_MAPLIST)
	{
		if (m_pCurMapList[maplist_bInitialized]
			&& m_pCurMapList[maplist_path][0] != '\0'
			&& !IsKeyInStringMap(m_ListLookup, m_pCurMapList[maplist_name]))
		{
			m_ListLookup.SetArray(m_pCurMapList[maplist_name], m_pCurMapList, sizeof(m_pCurMapList));
			m_MapLists.PushArray(m_pCurMapList);
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

public void ParseMapList_ParseEnd(SMCParser smc, bool halted, bool failed)
{
	ResetMapList(m_pCurMapList);
}

ArrayList UpdateMapList(ArrayList pUseArray, const char[] name, int &pSerial, int flags, Handle plugin=INVALID_HANDLE)
{
	int change_serial;
	ArrayList pNewArray;
	bool success;
	
	bool free_new_array = false;
	
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
		return null;
	}
	
	/**
	 * If there was a success but no map list, we need to look in the maps folder
	 * If there was a failure and the flag is specified, we need to look in the maps folder
	 */
	if ((success && pNewArray == null)
		|| (!success && ((flags & MAPLIST_FLAG_MAPSFOLDER) == MAPLIST_FLAG_MAPSFOLDER)))
	{
		pNewArray = new ArrayList(mapdata_t);
		free_new_array = true;
		
		// Moved to a separate function so that we can call it recursively
		FindMapsInDirectory("maps", pNewArray);
		
		/* Remove the array if there were no items */
		if (pNewArray.Length == 0)
		{
			delete pNewArray;
			pNewArray = null;
		}
		else
		{
			SortADTArray(pNewArray, Sort_Ascending, Sort_String);
		}
		
		ArrayList oldArray = pNewArray;
		pNewArray = view_as<ArrayList>(CloneHandle(oldArray, plugin));
		delete oldArray;
		
		change_serial = -1;
	}
	
	/* If there is still no array by this point, bail out. */
	if (pNewArray == null)
	{
		pSerial = -1;
		return null;
	}
	
	pSerial = change_serial;
	
	// OK, we need to make sure all the MapData_MapAttributes entries in pNewArray belong to the calling plugin
	
	/* If there is no input array, return something temporary. */
	if (pUseArray == null)
	{
		if (free_new_array)
		{
			// This was already converted to plugin in the above block
			return pNewArray;
		}
		else
		{
			ArrayList tempArray = new ArrayList(mapdata_t);
			ArrayList cloneArray = view_as<ArrayList>(CloneHandle(tempArray, plugin));
			delete tempArray;
			
			CopyMapDataArray(pNewArray, cloneArray, plugin);
			return cloneArray;
		}
	}
	
	/* Clear the input array if necessary. */
	if ((flags & MAPLIST_FLAG_CLEARARRAY) == MAPLIST_FLAG_CLEARARRAY)
	{
		pUseArray.Clear();
	}
	
	/* Copy. */
	CopyMapDataArray(pNewArray, pUseArray, plugin);
	
	for (int i = 0; i < pNewArray.Length; i++)
	{
		int pMapData[mapdata_t];
		pNewArray.GetArray(i, pMapData, sizeof(pMapData));
		
		int pNewMapData[mapdata_t];
		
		strcopy(pNewMapData[MapData_Map], sizeof(pNewMapData[MapData_Map]), pMapData[MapData_Map]);
		strcopy(pNewMapData[MapData_Group], sizeof(pNewMapData[MapData_Group]), pMapData[MapData_Group]);
		/* If attributes exist, we need to CloneHandle them to the other plugin */
		if (pMapData[MapData_MapAttributes] != null)
		{
			pNewMapData[MapData_MapAttributes] = view_as<StringMap>(CloneHandle(pNewMapData[MapData_MapAttributes], plugin));
		}
		
		pUseArray.PushArray(pNewMapData, sizeof(pNewMapData));
	}
	
	/* Free resources if necessary. */
	if (free_new_array)
	{
		delete pNewArray;
	}
	
	/* Return the array we were given. */
	return pUseArray;
}

void CopyMapDataArray(ArrayList mapData, ArrayList &newData, Handle plugin)
{
	if (mapData == null)
	{
		return;
	}
	
	if (newData == null)
	{
		ArrayList tempData = new ArrayList(mapdata_t);
		newData = view_as<ArrayList>(CloneHandle(tempData, plugin));
		delete tempData;
	}
	
	for (int i = 0; i < mapData.Length; i++)
	{
		int pMapData[mapdata_t];
		mapData.GetArray(i, pMapData, sizeof(pMapData));
		
		int pNewMapData[mapdata_t];
		
		strcopy(pNewMapData[MapData_Map], sizeof(pNewMapData[MapData_Map]), pMapData[MapData_Map]);
		strcopy(pNewMapData[MapData_Group], sizeof(pNewMapData[MapData_Group]), pMapData[MapData_Group]);
		/* If attributes exist, we need to CloneHandle them to the other plugin */
		if (pMapData[MapData_MapAttributes] != null)
		{
			pNewMapData[MapData_MapAttributes] = view_as<StringMap>(CloneHandle(pNewMapData[MapData_MapAttributes], plugin));
		}
		
		newData.PushArray(pNewMapData, sizeof(pNewMapData));
	}
	
}

void FindMapsInDirectory(const char[] directory, ArrayList files)
{
	if (!DirExists(directory, true))
	{
		return;
	}
	
	DirectoryListing findHandle = OpenDirectory(directory, true);
	
	// Even if a directory exists, a null DirectoryListing handle can be returned due to permissions, etc...
	if (findHandle == null)
	{
		return;
	}
	
	char fileName[PLATFORM_MAX_PATH];
	FileType fileType;
	
	while (findHandle.GetNext(fileName, sizeof(fileName), fileType))
	{
		char filePath[PLATFORM_MAX_PATH];
		Format(filePath, sizeof(filePath), "%s/%s", directory, fileName);
		
		switch (fileType)
		{
			case FileType_File:
			{
				int trimEnd = strlen(filePath) - 4;
				if (!StrEqual(filePath[trimEnd], ".bsp"))
					continue;
				
				int pMapData[mapdata_t];
				
				// Find the number of characters to skip
				int size = strlen(directory);
				if (FindCharInString(directory, '/') > -1)
				{
					size++;
				}
				
				if (size >= strlen(filePath))
				{
					continue;
				}
				
				// Trim the .bsp from the end and directory from the start
				strcopy(pMapData[MapData_Map], trimEnd, filePath[size]);
				
				if (!IsMapValid(pMapData[MapData_Map]))
					continue;
				
				strcopy(pMapData[MapData_Group], sizeof(pMapData[MapData_Group]), MAPCHOICES_DEFAULTGROUP);
				pMapData[MapData_MapAttributes] = null;
				
				files.PushArray(pMapData, sizeof(pMapData));
			}
			
			case FileType_Directory:
			{
				// 1.7's documentation says . and .. can be returned even though they don't appear to be in 1.7.
				if (StrEqual(directory, ".") || StrEqual(directory, ".."))
					continue;
				// Recursively call for subdirectories
				FindMapsInDirectory(filePath, files);
			}
		}
	}
	
	delete findHandle;
}

static bool GetMapList(ArrayList &ppArray, const char[] name, int &pSerial)
{
	int last_time;
	int pMapList[maplist_info_t];
	
	if (!m_ListLookup.GetArray(name, pMapList, sizeof(pMapList)))
		return false;
	
	if (!pMapList[maplist_bIsPath])
		return GetMapList(ppArray, pMapList[maplist_path], pSerial);
		
	/* If it is a path, and the path is "*", assume all files must be used. */
	if (strcmp(pMapList[maplist_path], "*") == 0)
	{
		ppArray = null;
		return true;
	}
	
	if (m_pMapCycleFile != null && strcmp(name, "mapcyclefile") == 0)
	{
		char path[PLATFORM_MAX_PATH];
		GetMapCycleFilePath(path, sizeof(path));
		
		if (strcmp(path, pMapList[maplist_path]) != 0)
		{
			strcopy(pMapList[maplist_path], sizeof(pMapList[maplist_path]), path);
			pMapList[maplist_last_modified_time] = 0;
		}
	}
	
	if ((last_time = GetFileTime(pMapList[maplist_path], FileTime_LastChange)) == -1
		|| last_time > pMapList[maplist_last_modified_time])
	{
		/* Reparse. */
		switch (pMapList[maplist_Type])
		{
			case MapChoicesMapList_Classic:
			{
				if (!ReadClassicMapFile(pMapList))
				{
					return false;
				}
			}
			
			case MapChoicesMapList_Advanced:
			{
				if (!ReadAdvancedMapFile(pMapList))
				{
					return false;
				}
			}
		}
		
		pMapList[maplist_last_modified_time] = last_time;
		pMapList[maplist_serial] = ++m_nSerialChange;
	}
	
	if (pMapList[maplist_pArray] == null || pMapList[maplist_pArray].Length == 0)
	{
		return false;
	}
	
	pSerial = pMapList[maplist_serial];
	ppArray = pMapList[maplist_pArray].Clone();
	
	return true;
}

/**
 * Read a classic mapcycle style list.
 * 
 * NOTE: Filters do not operate on this kind of list
 */
static bool ReadClassicMapFile(int[] pMapList)
{
	File fp;
	char buffer[PLATFORM_MAX_PATH];
	
	if ((fp = OpenFile(pMapList[maplist_path], "rt", true)) == null)
	{
		return false;
	}
	
	delete pMapList[maplist_pArray];
	pMapList[maplist_pArray] = new ArrayList(mapdata_t);
	
	while (!fp.EndOfFile() && fp.ReadLine(buffer, sizeof(buffer)))
	{
		TrimString(buffer);
		if (buffer[0] == '\0'
			|| buffer[0] == ';'
			|| strncmp(buffer, "//", 2) == 0)
		{
			continue;
		}
		
		if (GetEngineVersion() == Engine_Insurgency)
		{
			// Insurgency (presumably?) doesn't allow spaces in map names
			// and does use a space to delimit the map name from the map mode
			
			// Note: SM's version of this code is daft and strips the game mode out
			// We make a copy first, then manipulate the copy to get just the map name
			char mapName[PLATFORM_MAX_PATH];
			strcopy(mapName, sizeof(mapName), buffer);
			
			int i = FindCharInString(mapName, ' ');
			
			if (i > -1)
			{
				mapName[i] = '\0';
			}
			
			if (!IsMapValid(mapName))
			{
				continue;
			}	
		}
		else	 if (!IsMapValid(buffer))
		{
			continue;
		}
		
		int pMapData[mapdata_t];
		strcopy(pMapData[MapData_Map], sizeof(pMapData[MapData_Map]), buffer);
		strcopy(pMapData[MapData_Group], sizeof(pMapData[MapData_Group]), MAPCHOICES_DEFAULTGROUP);
		pMapData[MapData_MapAttributes] = null;
		
		pMapList[maplist_pArray].PushArray(pMapData);
	}
	
	fp.Close();
	return true;
}

/**
 * Dump the cache and re-add the maplists to it
 * @param compat_list	Handle (passed by ref, do NOT close)
 */
static void DumpCache(ArrayList compat_list)
{
	m_ListLookup.Clear();
	
	for (int i = m_MapLists.Length - 1; i >= 0; i--)
	{
		int localArray[maplist_info_t];
		m_MapLists.GetArray(i, localArray, sizeof(localArray));
		if (compat_list != null && localArray[maplist_bIsCompat])
		{
			compat_list.PushArray(localArray, sizeof(localArray));
		}
		else
		{
			if (localArray[maplist_pArray] != null)
			{
				for (int j = 0; j < localArray[maplist_pArray].Length; j++)
				{
					int pMapData[mapdata_t];
					localArray[maplist_pArray].GetArray(j, pMapData, sizeof(pMapData));
					if (pMapData[MapData_MapAttributes] != null)
					{
						delete pMapData[MapData_MapAttributes];
					}
				}
				
				delete localArray[maplist_pArray];
			}
		}
		m_MapLists.Erase(i);
	}
}

// native ArrayList MapChoices_ReadMapList(ArrayList array=null, &serial=1, const char[] config=MAPCHOICES_DEFAULTGROUP, int flags=MAPLIST_FLAG_CLEARARRAY);
public int Native_ReadMapList(Handle plugin, int numParams)
{
	ArrayList pArray;
	int addr, flags; // addr is a ptr in C++
	ArrayList pNewArray;
	
	pArray = view_as<ArrayList>(GetNativeCell(1));
	addr = GetNativeCellRef(2);
	int length;
	GetNativeStringLength(3, length);
	char[] str = new char[length+1];
	GetNativeString(3, str, length+1);
	flags = GetNativeCell(4);
	
	pNewArray = LoadMapList(pArray, addr, str, flags, plugin);

	SetNativeCellRef(2, addr); // Update serial with the copy from UpdateMapList
	
	return view_as<int>(pNewArray);	
}

// Internal function to call
ArrayList LoadMapList(ArrayList pArray=null, int &serial=-1, const char[] config=MAPCHOICES_DEFAULTGROUP, int flags=MAPLIST_FLAG_CLEARARRAY, Handle plugin=null)
{
	ArrayList pNewArray;
	
	/* Make sure the input Handle is valid */
	// Not checkable in SourcePawn

	/* Make sure the map list cache is up to date at the root */
	UpdateCache();
	
	/* Try to get the map list. */
	// In C++, hndl is pArray... the array inside the Handle, but SourcePawn doesn't differentiate between them
	if ((pNewArray = UpdateMapList(pArray, config, serial, flags, plugin)) == null)
	{
		return null;
	}

	/* If the user wanted a new array, create it now. */
	if (pArray == INVALID_HANDLE)
	{
		// Removed irrelevant null check on handle creation, not applicable to SourcePawn
		pArray = view_as<ArrayList>(CloneHandle(pNewArray, plugin)); // Changes ownership
		delete pNewArray; // Delete our copy of this handle
	}
	
	return pArray;
}

public int Native_SetMapListCompatBind(Handle plugin, int numParams)
{
	int length;
	GetNativeStringLength(1, length);
	char[] name = new char[length+1];
	GetNativeString(1, name, length+1);
	
	GetNativeStringLength(2, length);
	char[] file = new char[length+1];
	GetNativeString(2, name, length+1);
	
	MapChoices_MapListType mapListType = GetNativeCell(3);
	
	UpdateCache();
	AddOrUpdateDefault(name, file, mapListType);
}

// Since we don't new/delete enum arrays, just reset it.
// Remember to set maplist_bInitialized when you'd normally new it
void ResetMapList(mapList[])
{
	mapList[maplist_bInitialized] = false;
	mapList[maplist_bIsCompat] = false;
	mapList[maplist_bIsPath] = false;
	mapList[maplist_last_modified_time] = 0;
	// Since we store this for later, don't close it
	/*
	if (mapList[maplist_pArray] != null)
	{
		delete mapList[maplist_pArray];
	}
	*/
	mapList[maplist_pArray] = null;
	mapList[maplist_serial] = -1;
	mapList[maplist_name] = "";
	mapList[maplist_path] = "";
	mapList[maplist_Type] = MapChoicesMapList_Classic;
}

stock int FindKeyInStringMap(StringMap map, const char[] key, bool caseSensitive=true)
{
	StringMapSnapshot snapshot = map.Snapshot();
	
	for (int i = 0; i < snapshot.Length; i++)
	{
		int keySize = snapshot.KeyBufferSize(i);
		char[] checkKey = new char[keySize];
		snapshot.GetKey(i, checkKey, keySize);
		
		if (StrEqual(key, checkKey, caseSensitive))
		{
			return i;
		}
	}
	
	return -1;
}

stock bool IsKeyInStringMap(StringMap map, const char[] key, bool caseSensitive=true)
{
	return (FindKeyInStringMap(map, key, caseSensitive) > -1);
}

SMCParser GetMapListsCfgSMCParser()
{
	SMCParser parser = new SMCParser();
	parser.OnStart = ParseMapList_ParseStart;
	parser.OnEnd = ParseMapList_ParseEnd;
	parser.OnEnterSection = ParseMapList_NewSection;
	parser.OnLeaveSection = ParseMapList_LeavingSection;
	parser.OnKeyValue = ParseMapList_KeyValue;
	
	return parser;
}

