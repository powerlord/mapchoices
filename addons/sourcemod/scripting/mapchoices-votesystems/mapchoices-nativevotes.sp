/**
 * vim: set ts=4 :
 * =============================================================================
 * MapChoices NativeVotes
 * NativeVotes vote handler for MapChoices
 *
 * MapChoices NativeVotes (C)2015 Powerlord (Ross Bemrose).  All rights reserved.
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

// Load the two plugins this is for
#include "../include/mapchoices"
#include "../include/nativevotes"

#pragma semicolon 1
#pragma newdecls required

#define VERSION "1.0.0 alpha 1"

ConVar g_Cvar_Enabled;

bool g_VoteInProgress;
float g_Quorum = 0.0;
MapChoices_VoteType g_VoteType = MapChoices_MapVote;
bool g_NoVotesSelect = false;

StringMap g_ItemData;

public Plugin myinfo = {
	name			= "MapChoices NativeVotes",
	author			= "Powerlord",
	description		= "NativeVotes vote handler for MapChoices",
	version			= VERSION,
	url				= ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (!NativeVotes_IsVoteTypeSupported(NativeVotesType_NextLevelMult))
	{
		strcopy(error, err_max, "Multiple type map vote not supported.");
	}
}

public void OnPluginStart()
{
	CreateConVar("mapchoices_nativevotes_version", VERSION, "MapChoices NativeVotes version", FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	g_Cvar_Enabled = CreateConVar("mapchoices_nativevotes_enable", "1", "Enable MapChoices NativeVotes?", FCVAR_NOTIFY|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	
	LoadTranslations("mapchoices.phrases");
}

public void OnAllPluginsLoaded()
{
	MapChoices_RegisterVoteHandler(Handler_StartVote, Handler_CancelVote, Handler_IsVoteInProgress, NativeVotes_GetMaxItems());
}

public void OnPluginEnd()
{
	MapChoices_UnregisterVoteHandler(Handler_StartVote, Handler_CancelVote, Handler_IsVoteInProgress);
}

public Action Handler_StartVote(int duration, MapChoices_VoteType voteType, ArrayList itemList, int[] clients, int numClients, float quorum, bool noVotesSelect, bool noVoteOption)
{
	if (!g_Cvar_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}
	
	// We are naively assuming that NativeVotes_IsVoteInProgress was checked before our handler was called

	g_VoteInProgress = true;
	g_Quorum = quorum;
	g_VoteType = voteType;
	g_NoVotesSelect = noVotesSelect;
	
	// This is never MapChoices_TieredVote as that's handled by the parent plugin

	// Make a deep copy of the itemList
	if (g_ItemData != null)
		delete g_ItemData;
		
	g_ItemData = new StringMap();
	
	for (int i = 0; i < itemList.Length; i++)
	{
		switch (voteType)
		{
			case MapChoices_MapVote:
			{
				int mapData[mapdata_t];
				int mapDataCopy[mapdata_t];
				itemList.GetArray(i, mapData, sizeof(mapData));
				MapChoices_CopyMapData(mapData, mapDataCopy);
				
				char itemString[PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 1];
				MapChoices_GetItemString(mapDataCopy, itemString, sizeof(itemString));
				
				g_ItemData.SetArray(itemString, mapDataCopy, sizeof(mapDataCopy));
			}
			
			case MapChoices_GroupVote:
			{
				int groupData[groupdata_t];
				int groupDataCopy[groupdata_t];
				itemList.GetArray(i, groupData, sizeof(groupData));
				MapChoices_CopyGroupData(groupData, groupDataCopy);
				
				g_ItemData.SetArray(groupData[GroupData_Group], groupDataCopy, sizeof(groupDataCopy));
			}
		}
	}
	
	NativeVote vote;
	if (voteType == MapChoices_MapVote)
	{
		vote = new NativeVote(Handler_MapVote, NativeVotesType_NextLevelMult, NATIVEVOTES_ACTIONS_DEFAULT|MenuAction_DisplayItem);
	}
	else
	{
		vote = new NativeVote(Handler_MapVote, NativeVotesType_Custom_Mult, NATIVEVOTES_ACTIONS_DEFAULT|MenuAction_Display);
		vote.SetTitle("MapChoices Group Vote Title");
	}
		
	for (int i = 0; i < itemList.Length; i++)
	{
		switch (voteType)
		{
			case MapChoices_MapVote:
			{
				int item[mapdata_t];
				itemList.GetArray(i, item, sizeof(item));
				
				char itemString[PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 1];
				MapChoices_GetItemString(item, itemString, sizeof(itemString));
				
				char displayString[PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 3];
				MapChoices_GetMapDisplayString(item, displayString, sizeof(displayString));
				
				vote.AddItem(itemString, displayString);
			}
			
			case MapChoices_GroupVote:
			{
				int item[groupdata_t];
				itemList.GetArray(i, item, sizeof(item));
				
				vote.AddItem(item[GroupData_Group], item[GroupData_Group]);
			}
		}
	}
	
	vote.NoVoteButton = noVoteOption;
	
	vote.DisplayVote(clients, numClients, duration);
	
	return Plugin_Handled;
}

public Action Handler_CancelVote()
{
	if (!g_Cvar_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}
	
	if (g_VoteInProgress)
	{
		if (NativeVotes_IsVoteInProgress())
		{
			NativeVotes_Cancel();
		}
		
		g_VoteInProgress = false;
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Handler_IsVoteInProgress(bool &isInProgress)
{
	if (!g_Cvar_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}
	
	isInProgress = NativeVotes_IsVoteInProgress();
	
	return Plugin_Handled;
}

public int Handler_MapVote(NativeVote vote, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			vote.Close();
		}
		
		// Only runs for Group votes
		case MenuAction_Display:
		{
			char title[256];
			vote.GetTitle(title, sizeof(title));
			Format(title, sizeof(title), "%T", title, param1);
			return view_as<int>(NativeVotes_RedrawVoteTitle(title));
		}
		
		case MenuAction_VoteCancel:
		{
			switch (param1)
			{
				case VoteCancel_Generic:
				{
					vote.DisplayFail(NativeVotesFail_Generic);
					MapChoices_VoteFailed(g_VoteType, MapChoices_Canceled);
				}
				
				case VoteCancel_NoVotes:
				{
					if (g_NoVotesSelect)
					{
						// Prevent infinite loop
						int timeout = 0;
						
						char itemString[PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 1];
						do
						{
							int winner = GetRandomInt(0, vote.ItemCount - 1);
							vote.GetItem(winner, itemString, sizeof(itemString));
							timeout++;
						} while ((StrEqual(itemString, MAPCHOICES_EXTEND) || StrEqual(itemString, MAPCHOICES_NOCHANGE)) && timeout < 10);
						
						int mapData[mapdata_t];

						switch (g_VoteType)
						{
							case MapChoices_MapVote:
							{
								g_ItemData.GetArray(itemString, mapData, sizeof(mapData));
								
								// Internal function
								DisplayPass(vote, mapData);
								
								MapChoices_VoteSucceeded(g_VoteType, mapData, 0, 0);
								MapChoices_DeleteMapData(mapData);
							}
							
							case MapChoices_GroupVote:
							{
								int groupData[groupdata_t];
								g_ItemData.GetArray(itemString, groupData, sizeof(groupData));
								
								MapChoices_CopyGroupDataToMapData(groupData, mapData);
								
								// Internal function
								DisplayPass(vote, mapData);
								
								MapChoices_DeleteGroupData(groupData);
							}
						}
						MapChoices_VoteSucceeded(g_VoteType, mapData, 0, 0);
						MapChoices_DeleteMapData(mapData);
					}
					else
					{
						vote.DisplayFail(NativeVotesFail_NotEnoughVotes);
						MapChoices_VoteFailed(g_VoteType, MapChoices_FailedNoVotes);
					}
					
				}
				
			}
		}
		
		// Only runs for Map votes
		case MenuAction_DisplayItem:
		{
			char item[PLATFORM_MAX_PATH];
			char display[256];
			vote.GetItem(param2, item, sizeof(item), display, sizeof(display));
			
			// Regular items are map;group, but these are left intact
			if (StrEqual(item, MAPCHOICES_EXTEND) || StrEqual(item, MAPCHOICES_NOCHANGE))
			{
				Format(display, sizeof(display), "%T", display, param1);
				
				return view_as<int>(NativeVotes_RedrawVoteItem(display));
			}
		}
	}
	
	return 0;
}

public void Handler_MapVoteFinish(NativeVote vote,
						int num_votes,
						int num_clients,
						const int[] client_indexes,
						const int[] client_votes,
						int num_items,
						const int[] item_indexes,
						const int[] item_votes)
{
	float percentage = float(item_votes[0]) / float(num_votes);

	if (percentage < g_Quorum)
	{
		ArrayList items = new ArrayList(PLATFORM_MAX_PATH);
		ArrayList votes = new ArrayList();
		
		for (int i = 0; i < num_items; i++)
		{
			char item[PLATFORM_MAX_PATH];
			vote.GetItem(item_indexes[i], item, sizeof(item));
			items.PushString(item);
			votes.Push(item_votes[i]);
		}
		
		vote.DisplayFail(NativeVotesFail_NotEnoughVotes);
		MapChoices_VoteFailed(g_VoteType, MapChoices_FailedQuorum, items, votes);
		
		// Delete these ArrayLists to prevent memory leaks
		delete items;
		delete votes;
		return;
	}
	
	int count = 1;
	int winner = 0;
	
	// Check for ties, skip the first entry since we know it'll be there
	while (count < num_items && item_votes[count] == item_votes[0])
	{
		count++;
	}
	
	// If there is a tie, grab a random entry of the tied entries
	if (count > 1)
	{
		winner = GetRandomInt(0, count-1);
	}
	
	char itemString[PLATFORM_MAX_PATH];
	vote.GetItem(item_indexes[winner], itemString, sizeof(itemString));
	
	int mapData[mapdata_t];
	
	switch (g_VoteType)
	{
		case MapChoices_MapVote:
		{
			g_ItemData.GetArray(itemString, mapData, sizeof(mapData));
			
			// Internal function
			DisplayPass(vote, mapData);
			
			MapChoices_VoteSucceeded(g_VoteType, mapData, 0, 0);
			MapChoices_DeleteMapData(mapData);
		}
		
		case MapChoices_GroupVote:
		{
			int groupData[groupdata_t];
			g_ItemData.GetArray(itemString, groupData, sizeof(groupData));
			
			MapChoices_CopyGroupDataToMapData(groupData, mapData);
			
			// Internal function
			DisplayPass(vote, mapData);
			
			MapChoices_DeleteGroupData(groupData);
		}
	}
	
	DisplayPass(vote, mapData);
	MapChoices_VoteSucceeded(g_VoteType, mapData, num_votes, item_votes[winner]);
	MapChoices_DeleteMapData(mapData);		
}

void DisplayPass(NativeVote vote, int mapData[mapdata_t])
{
	if (StrEqual(mapData[MapData_Map], MAPCHOICES_EXTEND) || StrEqual(mapData[MapData_Map], MAPCHOICES_NOCHANGE))
	{
		vote.DisplayPassEx(NativeVotesPass_Extend);
	}
	else
	{
		char displayString[PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 3];
		MapChoices_GetMapDisplayString(mapData, displayString, sizeof(displayString));
		
		vote.DisplayPass(displayString);
	}
}
