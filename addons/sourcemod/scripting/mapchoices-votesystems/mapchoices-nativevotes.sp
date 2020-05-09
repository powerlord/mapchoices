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

#define VERSION "1.0.0 alpha 2"

ConVar g_Cvar_Enabled;

MapChoices_VoteType g_VoteType = MapChoices_MapVote;

StringMap g_ItemData;

NativeVote g_NativeVote = null;

// Only used for tiered votes
char g_Group[MAPCHOICES_MAX_GROUP_LENGTH];

public Plugin myinfo = {
	name			= "MapChoices NativeVotes",
	author			= "Powerlord",
	description		= "NativeVotes vote handler for MapChoices",
	version			= VERSION,
	url				= ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (!NativeVotes_IsVoteTypeSupported(NativeVotesType_NextLevelMult) ||
	    !NativeVotes_IsVoteTypeSupported(NativeVotesType_Custom_Mult))
	{
		strcopy(error, err_max, "Multiple type map vote not supported.");
		return APLRes_Failure;
	}
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("mapchoices_nativevotes_version", VERSION, "MapChoices NativeVotes version", FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	g_Cvar_Enabled = CreateConVar("mapchoices_nativevotes_enable", "1", "Enable MapChoices NativeVotes?", FCVAR_NOTIFY|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	
	LoadTranslations("mapchoices.phrases");
}

public void OnAllPluginsLoaded()
{
	MapChoices_RegisterVoteHandler(Handler_StartVote, Handler_CancelVote, Handler_IsVoteInProgress, NativeVotes_GetMaxItems(), Handler_VoteWon, Handler_VoteLost);
}

public void OnPluginEnd()
{
	MapChoices_UnregisterVoteHandler(Handler_StartVote, Handler_CancelVote, Handler_IsVoteInProgress);
}

public Action Handler_VoteWon(MapChoices_MapChange when, char[] winner)
{
	DisplayPass(g_NativeVote, winner, when);
	
	if (g_VoteType == MapChoices_MapVote)
	{
		g_Group[0] = '\0';
	}
}

public Action Handler_VoteLost(MapChoices_VoteFailedType failType)
{
	switch (failType)
	{
		// This should be handled internally, but just in case...
		case MapChoices_Canceled:
		{
			g_NativeVote.DisplayFail(NativeVotesFail_Generic);
		}
		
		// Although these two are semantically different, NativeVotes only has one "not enough votes" message
		case MapChoices_FailedQuorum, MapChoices_FailedNoVotes:
		{
			g_NativeVote.DisplayFail(NativeVotesFail_NotEnoughVotes);
		}
	}
}

// If Extend or No Change are in a vote, they should have been passed in the itemList from core
public Action Handler_StartVote(int[] voters, int voterCount, int duration, MapChoices_VoteType voteType, ArrayList itemList, bool noVoteOption)
{
	if (!g_Cvar_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}
	
	// We are naively assuming that NativeVotes_IsVoteInProgress was checked before our handler was called

	//g_Quorum = quorum;
	g_VoteType = voteType;
	//g_NoVotesSelect = noVotesSelect;
	
	// This is never MapChoices_TieredVote as that's handled by the parent plugin

	// Make a deep copy of the itemList
	if (g_ItemData != null)
		delete g_ItemData;
		
	g_ItemData = new StringMap();
	
	for (int i = 0; i < itemList.Length; i++)
	{
		MapChoices_MapDTO mapData;
		MapChoices_MapDTO mapDataCopy;
		itemList.GetArray(i, mapData, sizeof(mapData));
		MapChoices_CloneMapDTO(mapData, mapDataCopy);

		switch (voteType)
		{
			case MapChoices_MapVote:
			{
				char itemString[PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 1];
				MapChoices_GetItemString(mapDataCopy, itemString, sizeof(itemString));
				
				g_ItemData.SetArray(itemString, mapDataCopy, sizeof(mapDataCopy));
			}
			
			case MapChoices_GroupVote:
			{
				g_ItemData.SetArray(mapDataCopy.group, mapDataCopy, sizeof(mapDataCopy));
			}
		}
	}
	
	if (voteType == MapChoices_MapVote)
	{
		g_NativeVote = new NativeVote(Handler_MapVote, NativeVotesType_NextLevelMult, NATIVEVOTES_ACTIONS_DEFAULT|MenuAction_DisplayItem);
	}
	else
	{
		g_NativeVote = new NativeVote(Handler_MapVote, NativeVotesType_Custom_Mult, NATIVEVOTES_ACTIONS_DEFAULT|MenuAction_Display);
		g_NativeVote.SetTitle("MapChoices Group Vote Title");
	}
		
	for (int i = 0; i < itemList.Length; i++)
	{
		switch (voteType)
		{
			case MapChoices_MapVote:
			{
				MapChoices_MapDTO item;
				itemList.GetArray(i, item, sizeof(item));
				
				char itemString[PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 1];
				MapChoices_GetItemString(item, itemString, sizeof(itemString));
				
				char displayString[PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 3];
				MapChoices_GetMapDisplayString(item, displayString, sizeof(displayString));
				
				g_NativeVote.AddItem(itemString, displayString);
			}
			
			case MapChoices_GroupVote:
			{
				MapChoices_GroupDTO item;
				itemList.GetArray(i, item, sizeof(item));
				
				g_NativeVote.AddItem(item.group, item.group);
			}
		}
	}
	
	g_NativeVote.NoVoteButton = noVoteOption;
	
	g_NativeVote.DisplayVote(voters, voterCount, duration);
	
	return Plugin_Handled;
}

public Action Handler_CancelVote()
{
	if (!g_Cvar_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}
	
	if (NativeVotes_IsVoteInProgress())
	{
		NativeVotes_Cancel();
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
			// This *should* be called after the win/lose callbacks
			vote.Close();
			delete g_ItemData;
			delete g_NativeVote;
		}
		
		// Only runs for Group votes
		case MenuAction_Display:
		{
			if (g_VoteType == MapChoices_GroupVote)
			{
				char title[256];
				vote.GetTitle(title, sizeof(title));
				Format(title, sizeof(title), "%T", title, param1);
				return view_as<int>(NativeVotes_RedrawVoteTitle(title));
			}
		}
		
		case MenuAction_VoteCancel:
		{
			ArrayList items = new ArrayList(sizeof(MapChoices_MapDTO));
			ArrayList votes = new ArrayList();
			
			switch (param1)
			{
				case VoteCancel_Generic:
				{
					// Vote was canceled from outside source, show the NativeVotes cancel screen
					vote.DisplayFail(NativeVotesFail_Generic);
				}
				
				case VoteCancel_NoVotes:
				{
					// Prepare data to send back to core
					for (int i = 0; i < vote.ItemCount; i++)
					{
						char item[PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 1];
						MapChoices_MapDTO mapData;
						vote.GetItem(i, item, sizeof(item));
						
						g_ItemData.GetArray(item, mapData, sizeof(mapData));
						items.PushArray(mapData, sizeof(mapData));
						votes.Push(0);
					}
				}
				
			}

			MapChoices_VoteCompleted(g_VoteType, items, votes, 0, true);
			delete items;
			delete votes;
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
	ArrayList items = new ArrayList(sizeof(MapChoices_MapDTO));
	ArrayList votes = new ArrayList();
	
	for (int i = 0; i < num_items; i++)
	{
		char item[PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 1];
		MapChoices_MapDTO mapData;
		vote.GetItem(item_indexes[i], item, sizeof(item));
		
		g_ItemData.GetArray(item, mapData, sizeof(mapData));
		items.PushArray(mapData, sizeof(mapData));
		votes.Push(item_votes[i]);
	}
	
	MapChoices_VoteCompleted(g_VoteType, items, votes, num_votes);
	delete items;
	delete votes;
	
	// Old logic, needs to be moved to core
	
	/*
	float percentage = float(item_votes[0]) / float(num_votes);

	if (percentage < g_Quorum)
	{
		
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
	*/
}

void DisplayPass(NativeVote vote, char[] winner, MapChoices_MapChange when)
{
	if (g_VoteType == MapChoices_GroupVote)
	{
		strcopy(g_Group, sizeof(g_Group), winner);
		vote.DisplayPass(winner);
	}
	else if (StrEqual(winner, MAPCHOICES_EXTEND) || StrEqual(winner, MAPCHOICES_NOCHANGE))
	{
		vote.DisplayPassEx(NativeVotesPass_Extend);
	}
	else
	{
		char displayString[PLATFORM_MAX_PATH + MAPCHOICES_MAX_GROUP_LENGTH + 3];
		MapChoices_MapDTO mapData;
		if (g_Group[0] != '\0')
		{
			strcopy(mapData.group, sizeof(mapData.group), g_Group);
		}
		strcopy(mapData.map, sizeof(mapData.map), winner);
		
		MapChoices_GetMapDisplayString(mapData, displayString, sizeof(displayString));
		
		if (when == MapChoicesMapChange_Instant)
		{
			vote.DisplayPassEx(NativeVotesPass_ChgLevel, displayString);
		}
		else
		{
			vote.DisplayPass(displayString);
		}
	}
}
