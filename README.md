# MapChoices
A ground-up rewrite of the MapChooser system

## Why do a rewrite?

MapChooser is looking a bit long in the tooth.  Rather than continuing to shove more and more fixes into MapChooser
(which is what MapChoosed Extended is), I figure its easier to start over from scratch and design a modular adaption of it.

MapChoices is a hybrid between a Classic map vote plugin (like MapChooser) and an advanced map vote plugin (like UMC).
The idea is to support both map vote types.

## What about Ultimate MapChooser?

I like this *idea* of Ultimate MapChooser, but its a complicated system of interlocking features, including a lot of
undocumented KeyValues data.

UMC also doesn't handle alternative logic for games.  Which is a problem when you consider that
several games need workarounds to work correctly.  The known games for this are: Neotokyo, CS:GO, and TF2.

Each of the above mentioned games will have their own game module which will hook into the core and handle
round counting.

## Why does MapChoices require SourceMod 1.8?

SourceMod 1.8 supports both the FindMap and GetMapDisplayName functions.

- FindMap is used to resolve a mapcycle entry to its map name.
  - This resolves "fuzzy" names to their real names.
  - This resolves Workshop short map names to their full paths.
- GetMapDisplayName is used to get a "natural" name for a Workshop map.
  - For CS:GO, this changes workshop/125488374 or workshop/125488374/de_dust2_se to de_dust2_se
  - For TF2, this changes workshop/454118349 or workshop/cp_glassworks_rc6a.ugc454118349 to cp_glassworks_rc6a

## What's the current status of MapChoices?

MapChoices is very much in alpha.  Right now, nothing is set in stone.

During alpha development, natives may come and go as I try to determine what the best way of doing things is.

A good example is 2015 November 25 change that rearranged the argument order for many natives.  As of this
update, the map group is always the first argument to methods that take both the map and map group.
This is for consistency reasons.

There are some internal calls necessary for specific games that should only be called from game plugins.
for example, MapChoices_SwapTeamScores.  This was added because it is mandatory for TF2 and CS:GO game plugins.

## What will MapChoices not support on launch?

At the current time, these will likely not be supported at launch:

- Map renaming.  At the current moment, MapChoices relies on SourceMod itself to do map renaming for Workshop maps.
- Map reweighting.  This is a feature UMC has, where it can reweight a map based on external plugins (i.e. Map Rate).

## What about NativeVotes?

What, you didn't think I'd design a voting system with no NativeVotes support, did you?  MapChoices will have
full support for NativeVotes 1.1.

I stole an idea from UMC and allow you to replace the core vote display logic.
This features appeared in UMC to support the BuiltinVotes extension, the precursor to NativeVotes.

It really shouldn't be a surprise that MapChoices will have the same feature.

It is implemented as a subplugin, much like it is in UMC.

## What is map filtering?

This is another idea stolen from UMC.

If you look through mapchoices.inc, you probably noticed there are GroupFilter and MapFilter callbacks.  These callbacks
are used to check if a particular group or map should be rejected.

At the moment, the plan is to pass the map, group, and StringMaps for the group and map properties.
This is so the filtering plugins can see if the server owner put any restrictions on the map or its group.
