# MapChoices
A ground-up rewrite of the MapChooser system

## Why do a rewrite?

MapChooser is looking a bit long in the tooth.  Rather than continuing to shove more and more fixes to MapChooser
(like MapChooser Extended does), I figure its easier to start over from scratch and design a properly 

## What about Ultimate MapChooser?

I like this *idea* of Ultimate MapChooser, but its a complicated system of interlocking features that I don't want
to have to unravel before I make changes.

Besides which, UMC doesn't handle alternative logic for games at all.  Which is a problem when you consider that
several games need workarounds to work correctly.  The known games for this are: Neotokyo, CS:GO, and TF2.

Each of the above mentioned games will have their own game module which will hook into the core and handle
round counting.

## What about NativeVotes?

What, you didn't think I'd design a voting system with no NativeVotes support, did you?

## What is map filtering?

If you look through mapchoices.inc, you probably noticed there is a MapFilter callback.  This callback is used
to check if a particular map should be rejected.

At the moment, the plan is to pass a KeyValues set to the MapFilter that contains the current combined keys for map.
This is so the filtering plugins can see if the server owner put any restrictions on the map or its group.

