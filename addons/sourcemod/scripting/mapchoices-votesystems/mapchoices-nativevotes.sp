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

public Action Handler_StartVote(int duration, MapChoices_VoteType voteType, ArrayList itemList, int[] clients, int numClients, float quorum)
{
	if (!g_Cvar_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}
	
	g_VoteInProgress = true;
	g_Quorum = quorum;
	
	//TODO Implement this logic
	
	// This is never MapChoices_TieredVote as that's handled by the parent plugin
	NativeVote vote;
	if (voteType == MapChoices_MapVote)
	{
		vote = new NativeVote(Handler_MapVote, NativeVotesType_NextLevelMult, NATIVEVOTES_ACTIONS_DEFAULT|MenuAction_DisplayItem);
	}
	else
	{
		vote = new NativeVote(Handler_GroupVote, NativeVotesType_Custom_Mult, NATIVEVOTES_ACTIONS_DEFAULT|MenuAction_Display);
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
		
		case MenuAction_VoteCancel:
		{
			switch (param1)
			{
				case VoteCancel_Generic:
				{
					vote.DisplayFail(NativeVotesFail_Generic);
				}
				
				case VoteCancel_NoVotes:
				{
					vote.DisplayFail(NativeVotesFail_NotEnoughVotes);
				}
			}
		}
		
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
	//TODO Write map vote win logic
}

public int Handler_GroupVote(NativeVote vote, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Display:
		{
			char title[256];
			vote.GetTitle(title, sizeof(title));
			Format(title, sizeof(title), "%T", title, param1);
			return view_as<int>(NativeVotes_RedrawVoteTitle(title));
		}
	}
	
	return 0;
}

public void Handler_GroupVoteFinish(NativeVote vote,
						int num_votes,
						int num_clients,
						const int[] client_indexes,
						const int[] client_votes,
						int num_items,
						const int[] item_indexes,
						const int[] item_votes)
{
	//TODO Write group vote win logic
}



