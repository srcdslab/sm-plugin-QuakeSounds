# QuakeSounds Method Wiki
This information is stored in: addons/sourcemod/configs/sets/{name}.cfg

**Please note the turning off sounds also stops them from downloading.**

Calcul Method
-----------------

The field now works as follows
- 0: Off
- 1: Play sound to everyone
- 2: Play sound to attacker
- 4: Play sound to victim
- 8: Print text to everyone
- 16: Print text to attacker
- 32: Print text to victim

You need to add the above values to get your value.

Exemple
-----------------

If you want to play sounds and text to everyone 1 + 8 = 9

If you want to print text to everyone but only want sounds to play for those involved: 2 + 4 + 8 = 14

```
"first blood"
	{
		"sound"			"quake/standard/firstblood.mp3"
		"config"		"9"
	}
```