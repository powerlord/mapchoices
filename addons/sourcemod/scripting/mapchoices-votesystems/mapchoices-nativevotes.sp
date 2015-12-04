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
		char item[PLATFORM_MAX_PATH];
		
		itemList.GetString(i, item, sizeof(item));
		
		if (voteType == MapChoices_MapVote && !StrEqual(item, MAPCHOICES_EXTEND) && !StrEqual(item, MAPCHOICES_NOCHANGE))
		{
			// Maps have a display name that we need to fetch
			char displayMap[PLATFORM_MAX_PATH];
			GetMapDisplayName(item, displayMap, sizeof(displayMap));
			vote.AddItem(item, displayMap);
		}
		else
		{
			vote.AddItem(item, item);
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
						
						char item[PLATFORM_MAX_PATH];
						do
						{
							int winner = GetRandomInt(0, vote.ItemCount - 1);
							vote.GetItem(winner, item, sizeof(item));
							timeout++;
						} while ((StrEqual(item, MAPCHOICES_EXTEND) || StrEqual(item, MAPCHOICES_NOCHANGE)) && timeout < 10);
						
						DisplayPass(vote, item);
						
						MapChoices_VoteSucceeded(g_VoteType, item, 0, 0);
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
	
	char item[PLATFORM_MAX_PATH];
	vote.GetItem(item_indexes[winner], item, sizeof(item));
	DisplayPass(vote, item);
	MapChoices_VoteSucceeded(g_VoteType, item, num_votes, item_votes[winner]);
}

void DisplayPass(NativeVote vote, const char[] item)
{
	if (StrEqual(item, MAPCHOICES_EXTEND) || StrEqual(item, MAPCHOICES_NOCHANGE))
	{
		vote.DisplayPassEx(NativeVotesPass_Extend);
	}
	else
	{
		vote.DisplayPass(item);
	}
}
