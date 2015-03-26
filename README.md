# MapChoices
A ground-up rewrite of the MapChooser system

## Why do a rewrite?

MapChooser is looking a bit long in the tooth.  Rather than continuing to shove more and more fixes to MapChooser
(like MapChooser Extended does), I figure its easier to start over from scratch and design a modular adaption of it.

## What about Ultimate MapChooser?

I like this *idea* of Ultimate MapChooser, but its a complicated system of interlocking features that I don't want
to have to unravel before I make changes.

Besides which, UMC doesn't handle alternative logic for games at all.  Which is a problem when you consider that
several games need workarounds to work correctly.  The known games for this are: Neotokyo, CS:GO, and TF2.

Each of the above mentioned games will have their own game module which will hook into the core and handle
round counting.

## What's the current status of MapChoices?

MapChoices is very much in alpha.  Right now, nothing is set in stone.

During alpha development, natives may come and go as I try to determine what the best way of doing things is.

Even the MapChoices_GameFlags enum is currently in flux.  MapChoicesGame_BonusTime and MapChoicesGame_RestartTime
wil disappear shortly.  MapChoicesGame_OverrideRoundEnd is set to replace the MapChoices_GamePluginOverrideRoundEnd
function.

There are some internal calls necessary for specific games that should only be called from game plugins.
for example, MapChoices_SwapTeamScores.  This was added because it is mandantory for TF2 and CS:GO game plugins.

## What about NativeVotes?

What, you didn't think I'd design a voting system with no NativeVotes support, did you?

I stole an idea from UMC and allow you to replace the core vote display logic.  Then again, UMC gained this feature
when BuiltinVotes (NativeVotes predecessor) came around, so it really shouldn't be a surprise that MapChoices
will have the same feature.

It is implemented as a subplugin, much like it is in UMC.

## What is map filtering?

This is another idea stolen from UMC.

If you look through mapchoices.inc, you probably noticed there is a MapFilter callback.  This callback is used
to check if a particular map should be rejected.

At the moment, the plan is to pass a KeyValues set to the MapFilter that contains the current combined keys for map.
This is so the filtering plugins can see if the server owner put any restrictions on the map or its group.

