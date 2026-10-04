/*
	ff2r_hooks extension backend

	The extension fires the global forwards below, no include file is needed.
	When the extension isn't loaded, dhooks.sp falls back to DHooks.
*/

#pragma semicolon 1
#pragma newdecls required

#define EXTHOOKS_LIBRARY	"ff2r_hooks"

native Address FF2Ext_GetGameStats();
native bool FF2Ext_SetAlwaysTransmit(int entity, bool enable);

static bool ExtLoaded;

void ExtHooks_PluginLoad()
{
	MarkNativeAsOptional("FF2Ext_GetGameStats");
	MarkNativeAsOptional("FF2Ext_SetAlwaysTransmit");
}

void ExtHooks_PluginStart()
{
	ExtLoaded = LibraryExists(EXTHOOKS_LIBRARY);
}

// Returns true if the library was the extension
bool ExtHooks_LibraryAdded(const char[] name)
{
	if(!ExtLoaded && StrEqual(name, EXTHOOKS_LIBRARY))
	{
		ExtLoaded = true;
		return true;
	}

	return false;
}

// Returns true if the library was the extension
bool ExtHooks_LibraryRemoved(const char[] name)
{
	if(ExtLoaded && StrEqual(name, EXTHOOKS_LIBRARY))
	{
		ExtLoaded = false;
		return true;
	}

	return false;
}

bool ExtHooks_Active()
{
	return ExtLoaded;
}

void ExtHooks_PrintStatus()
{
	PrintToServer("'%s' is %sloaded%s", EXTHOOKS_LIBRARY, ExtLoaded ? "" : "not ", ExtLoaded ? " (active)" : "");
}

Address ExtHooks_GetGameStats()
{
	return FF2Ext_GetGameStats();
}

void ExtHooks_SetAlwaysTransmit(int entity)
{
	if(!FF2Ext_SetAlwaysTransmit(entity, true))
		LogError("[FF2R Hooks] Failed to set always transmit on entity %d", entity);
}

public Action FF2Ext_OnApplyPunchImpulse(int client, bool &result)
{
	if(!ExtLoaded || !Hooks_BlockPunchImpulse(client))
		return Plugin_Continue;

	result = false;
	return Plugin_Handled;
}

public Action FF2Ext_OnDropAmmoPack(int client)
{
	if(!ExtLoaded || !Hooks_BlockAmmoPack(client))
		return Plugin_Continue;

	return Plugin_Handled;
}

public Action FF2Ext_OnPickupWeaponFromOther(int client, int weapon, bool &result)
{
	if(!ExtLoaded)
		return Plugin_Continue;

	return Hooks_PickupWeapon(client, weapon, result);
}

public void FF2Ext_OnRegenThink(int client)
{
	if(ExtLoaded)
		Hooks_RegenThinkPre(client);
}

public void FF2Ext_OnRegenThinkPost(int client)
{
	if(ExtLoaded)
		Hooks_RegenThinkPost(client);
}

public Action FF2Ext_OnChangeTeam(int client, int team)
{
	if(!ExtLoaded || !Hooks_BlockChangeTeam(client))
		return Plugin_Continue;

	return Plugin_Handled;
}

public void FF2Ext_OnForceRespawn(int client)
{
	if(ExtLoaded)
		Hooks_ForceRespawnPre(client);
}

public void FF2Ext_OnForceRespawnPost(int client)
{
	if(ExtLoaded)
		Hooks_ForceRespawnPost(client);
}

public void FF2Ext_OnRoundRespawn()
{
	if(ExtLoaded)
		Hooks_RoundRespawn();
}

public Action FF2Ext_OnSetWinningTeam(int &team, int reason)
{
	if(!ExtLoaded)
		return Plugin_Continue;

	return Hooks_SetWinningTeam(team, reason);
}

public Action FF2Ext_OnGetCaptureValue(int client, int &value)
{
	if(!ExtLoaded || client < 1 || client > MaxClients)
		return Plugin_Continue;

	return Hooks_GetCaptureValue(client, value) ? Plugin_Changed : Plugin_Continue;
}

public Action FF2Ext_OnKnifeInjured(int weapon, int victim, int attacker, int &damagetype)
{
	if(!ExtLoaded)
		return Plugin_Continue;

	return Hooks_KnifeInjured(attacker, damagetype) ? Plugin_Changed : Plugin_Continue;
}

public void FF2Ext_OnApplyPostHitEffects(int weapon, int victim)
{
	if(ExtLoaded && IsPomson(weapon))
		Hooks_PostHitPre(victim);
}

public void FF2Ext_OnApplyPostHitEffectsPost(int weapon, int victim)
{
	if(ExtLoaded)
		Hooks_PostHitPost(victim);
}

static bool IsPomson(int weapon)
{
	char classname[32];
	return weapon != -1 && GetEntityClassname(weapon, classname, sizeof(classname)) && !StrContains(classname, "tf_weapon_drg_pomson");
}
