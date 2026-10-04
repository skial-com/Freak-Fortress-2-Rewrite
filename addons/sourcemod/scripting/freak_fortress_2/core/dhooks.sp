#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

//#define CHECK_DETOUR_CRASHES

#define DHOOKS_LIBRARY	"dhooks"

/*
	Hooks are provided by one of two backends:
	- ff2r_hooks extension (exthooks.sp), preferred whenever it is loaded
	- DHooks, used as a fallback when the extension is not loaded

	The DHook_* functions below are the entry points the rest of the plugin uses,
	the Hooks_* functions hold the logic shared by both backends.
*/

enum struct RawHooks
{
	int Ref;
	int Pre;
	int Post;
}

static DynamicHook ChangeTeam;
static DynamicHook ShouldTransmit;
static DynamicHook ForceRespawn;
static DynamicHook RoundRespawn;
static DynamicHook SetWinningTeam;
static DynamicHook GetCaptureValue;
static DynamicHook ApplyOnInjured;
static DynamicHook ApplyPostHit;
static ArrayList RawEntityHooks;
static Address CTFGameStats;
static int DamageTypeOffset = -1;

static int ChangeTeamPreHook[MAXTF2PLAYERS];
static int ForceRespawnPreHook[MAXTF2PLAYERS];
static int ForceRespawnPostHook[MAXTF2PLAYERS];
static int ForceRespawnUserId[MAXTF2PLAYERS];
static bool GamerulesHooked;
static bool RoundSetupEventHooked;
static int TransmitRef = INVALID_ENT_REFERENCE;

static bool BlockChangeTeam[MAXTF2PLAYERS];
static int PrefClass;
static int EffectClass = -1;
static int KnifeWasChanged = -1;

void DHook_PluginStart()
{
	ExtHooks_PluginStart();

	if(!ExtHooks_Active() && LibraryExists(DHOOKS_LIBRARY))
		SetupDHook();
}

void DHook_LibraryAdded(const char[] name)
{
	if(ExtHooks_LibraryAdded(name))
	{
		// Leftover DHooks hooks stay installed but are ignored while the extension is active
		int dome = Dome_GetProp();
		if(dome != -1)
			DHook_SetAlwaysTransmit(dome);
	}
	else if(!RawEntityHooks && !ExtHooks_Active() && StrEqual(name, DHOOKS_LIBRARY))
	{
		SetupDHook();
		DHook_HookExisting();
	}
}

void DHook_LibraryRemoved(const char[] name)
{
	if(ExtHooks_LibraryRemoved(name))
	{
		// Extension went away, fall back to DHooks
		if(LibraryExists(DHOOKS_LIBRARY))
		{
			if(!RawEntityHooks)
				SetupDHook();

			DHook_HookExisting();
		}
	}
	else if(RawEntityHooks && StrEqual(name, DHOOKS_LIBRARY))
	{
		delete RawEntityHooks;
		ChangeTeam = null;
		ShouldTransmit = null;
		ForceRespawn = null;
		RoundRespawn = null;
		SetWinningTeam = null;
		GetCaptureValue = null;
		ApplyOnInjured = null;
		ApplyPostHit = null;
		GamerulesHooked = false;
		TransmitRef = INVALID_ENT_REFERENCE;

		for(int i; i < sizeof(ForceRespawnUserId); i++)
		{
			ForceRespawnUserId[i] = 0;
			ChangeTeamPreHook[i] = 0;
		}
	}
}

void DHook_PrintStatus()
{
	ExtHooks_PrintStatus();
	PrintToServer("'%s' is %sloaded%s", DHOOKS_LIBRARY, RawEntityHooks ? "" : "not ", (RawEntityHooks && !ExtHooks_Active()) ? " (active)" : "");
}

static void SetupDHook()
{
	GameData gamedata = new GameData("ff2");

	DamageTypeOffset = gamedata.GetOffset("m_bitsDamageType");
	if(DamageTypeOffset == -1)
		LogError("[Gamedata] Could not find m_bitsDamageType");

	CreateDetour(gamedata, "CTFGameStats::ResetRoundStats", _, DHook_ResetRoundStats, true);
	CreateDetour(gamedata, "CTFPlayer::ApplyPunchImpulseX", DHook_ApplyPunchImpulsePre);
	CreateDetour(gamedata, "CTFPlayer::DropAmmoPack", DHook_DropAmmoPackPre);
	CreateDetour(gamedata, "CTFPlayer::PickupWeaponFromOther", DHook_PickupWeaponFromOtherPre, _, !SDK_WeaponPickups());
	CreateDetour(gamedata, "CTFPlayer::RegenThink", DHook_RegenThinkPre, DHook_RegenThinkPost, true);

	ChangeTeam = CreateHook(gamedata, "CBaseEntity::ChangeTeam");
	ShouldTransmit = CreateHook(gamedata, "CBaseEntity::ShouldTransmit");
	ForceRespawn = CreateHook(gamedata, "CBasePlayer::ForceRespawn");
	RoundRespawn = CreateHook(gamedata, "CTeamplayRoundBasedRules::RoundRespawn");
	SetWinningTeam = CreateHook(gamedata, "CTeamplayRules::SetWinningTeam");
	GetCaptureValue = CreateHook(gamedata, "CTFGameRules::GetCaptureValueForPlayer");
	ApplyOnInjured = CreateHook(gamedata, "CTFWeaponBase::ApplyOnInjuredAttributes");
	ApplyPostHit = CreateHook(gamedata, "CTFWeaponBase::ApplyPostHitEffects");

	delete gamedata;

	RawEntityHooks = new ArrayList(sizeof(RawHooks));
}

static DynamicHook CreateHook(GameData gamedata, const char[] name)
{
	DynamicHook hook = DynamicHook.FromConf(gamedata, name);
	if(!hook)
		LogError("[Gamedata] Could not find %s", name);

	return hook;
}

static DynamicDetour CreateDetour(GameData gamedata, const char[] name, DHookCallback preCallback = INVALID_FUNCTION, DHookCallback postCallback = INVALID_FUNCTION, bool noError = false)
{
#if defined CHECK_DETOUR_CRASHES
	PrintToServer("DynamicDetour %s", name);
#endif

	DynamicDetour detour = DynamicDetour.FromConf(gamedata, name);
	if(detour)
	{
#if defined CHECK_DETOUR_CRASHES
		if(preCallback != INVALID_FUNCTION)
			PrintToServer("Hook_Pre %s", name);
#endif
		if(preCallback != INVALID_FUNCTION && !detour.Enable(Hook_Pre, preCallback))
			LogError("[Gamedata] Failed to enable pre detour: %s", name);

#if defined CHECK_DETOUR_CRASHES
		if(postCallback != INVALID_FUNCTION)
			PrintToServer("Hook_Post %s", name);
#endif
		if(postCallback != INVALID_FUNCTION && !detour.Enable(Hook_Post, postCallback))
			LogError("[Gamedata] Failed to enable post detour: %s", name);

		delete detour;
	}
	else if(!noError)
	{
		LogError("[Gamedata] Could not find %s", name);
	}

	return detour;
}

// Hooks entities that already exist after DHooks becomes the active backend mid-map
static void DHook_HookExisting()
{
	if(!RawEntityHooks)
		return;

	DHook_MapStart();

	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
		{
			DHook_HookClient(client);
			if(Client(client).IsBoss)
				DHook_HookBoss(client);
		}
	}

	char classname[64];
	int entity = -1;
	while((entity = FindEntityByClassname(entity, "tf_weapon_*")) != -1)
	{
		GetEntityClassname(entity, classname, sizeof(classname));
		DHook_EntityCreated(entity, classname);
	}

	int dome = Dome_GetProp();
	if(dome != -1)
		DHook_SetAlwaysTransmit(dome);
}

void DHook_MapStart()
{
	if(ExtHooks_Active())
		return;

	if(!GamerulesHooked)
	{
		GamerulesHooked = true;

		if(GetCaptureValue)
			GetCaptureValue.HookGamerules(Hook_Post, DHook_GetCaptureValue);

		if(!RoundRespawn || RoundRespawn.HookGamerules(Hook_Pre, DHook_RoundRespawn) == INVALID_HOOK_ID)
		{
			if(!RoundSetupEventHooked)
			{
				RoundSetupEventHooked = true;
				HookEvent("teamplay_round_start", DHook_RoundSetup, EventHookMode_PostNoCopy);
			}
		}

		if(SetWinningTeam)
			SetWinningTeam.HookGamerules(Hook_Pre, DHook_SetWinningTeam);
	}
}

void DHook_MapEnd()
{
	// Gamerules hooks are removed along with the gamerules entity
	GamerulesHooked = false;
}

void DHook_HookClient(int client)
{
	if(ExtHooks_Active())
		return;

	int userid = GetClientUserId(client);
	if(ForceRespawn && ForceRespawnUserId[client] != userid)
	{
		ForceRespawnUserId[client] = userid;
		ForceRespawnPreHook[client] = ForceRespawn.HookEntity(Hook_Pre, client, DHook_ForceRespawnPre);
		ForceRespawnPostHook[client] = ForceRespawn.HookEntity(Hook_Post, client, DHook_ForceRespawnPost);
	}
}

void DHook_HookBoss(int client)
{
	DHook_UnhookBoss(client);
	if(!Cvar[AggressiveSwap].BoolValue)
		return;

	BlockChangeTeam[client] = true;
	if(!ExtHooks_Active() && ChangeTeam)
		ChangeTeamPreHook[client] = ChangeTeam.HookEntity(Hook_Pre, client, DHook_ChangeTeamPre);
}

void DHook_SetAlwaysTransmit(int entity)
{
	if(ExtHooks_Active())
	{
		ExtHooks_SetAlwaysTransmit(entity);
	}
	else if(ShouldTransmit)
	{
		int ref = EntIndexToEntRef(entity);
		if(TransmitRef != ref)
		{
			TransmitRef = ref;
			ShouldTransmit.HookEntity(Hook_Pre, entity, DHook_EntityShouldTransmit);
		}
	}
}

void DHook_EntityCreated(int entity, const char[] classname)
{
	if(ExtHooks_Active() || !RawEntityHooks)
		return;

	DynamicHook hook;
	DHookCallback pre, post;
	if(!StrContains(classname, "tf_weapon_knife"))
	{
		hook = ApplyOnInjured;
		pre = DHook_KnifeInjuredPre;
		post = DHook_KnifeInjuredPost;
	}
	else if(!StrContains(classname, "tf_weapon_drg_pomson"))
	{
		hook = ApplyPostHit;
		pre = DHook_ApplyPostHitPre;
		post = DHook_ApplyPostHitPost;
	}

	if(hook)
	{
		RawHooks raw;
		raw.Ref = EntIndexToEntRef(entity);
		if(RawEntityHooks.FindValue(raw.Ref, RawHooks::Ref) == -1)
		{
			raw.Pre = hook.HookEntity(Hook_Pre, entity, pre);
			raw.Post = hook.HookEntity(Hook_Post, entity, post);
			RawEntityHooks.PushArray(raw);
		}
	}
}

void DHook_EntityDestoryed()
{
	if(RawEntityHooks)
		RequestFrame(DHook_EntityDestoryedFrame);
}

static void DHook_EntityDestoryedFrame()
{
	if(RawEntityHooks)
	{
		int length = RawEntityHooks.Length;
		if(length)
		{
			RawHooks raw;
			for(int i; i < length; i++)
			{
				RawEntityHooks.GetArray(i, raw);
				if(!IsValidEntity(raw.Ref))
				{
					if(raw.Pre != INVALID_HOOK_ID)
						DynamicHook.RemoveHook(raw.Pre);

					if(raw.Post != INVALID_HOOK_ID)
						DynamicHook.RemoveHook(raw.Post);

					RawEntityHooks.Erase(i--);
					length--;
				}
			}
		}
	}
}

void DHook_PluginEnd()
{
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
			DHook_UnhookClient(client);
	}
}

void DHook_UnhookClient(int client)
{
	if(ForceRespawn && ForceRespawnUserId[client])
	{
		DynamicHook.RemoveHook(ForceRespawnPreHook[client]);
		DynamicHook.RemoveHook(ForceRespawnPostHook[client]);
	}

	ForceRespawnUserId[client] = 0;
}

void DHook_UnhookBoss(int client)
{
	BlockChangeTeam[client] = false;
	if(ChangeTeamPreHook[client])
	{
		DynamicHook.RemoveHook(ChangeTeamPreHook[client]);
		ChangeTeamPreHook[client] = 0;
	}
}

Address DHook_GetGameStats()
{
	if(ExtHooks_Active())
		return ExtHooks_GetGameStats();

	return CTFGameStats;
}

static void DHook_RoundSetup(Event event, const char[] name, bool dontBroadcast)
{
	if(ExtHooks_Active())
		return;

	Hooks_RoundRespawn();	// Back up plan

	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) > TFTeam_Spectator)
			TF2Tools_RespawnPlayer(client);
	}
}

/*
	Shared hook logic
*/

Action Hooks_PickupWeapon(int client, int weapon, bool &result)
{
	switch(Forward_OnPickupDroppedWeapon(client, weapon))
	{
		case Plugin_Continue:
		{
			if(Client(client).IsBoss || Client(client).MinionType)
			{
				result = false;
				return Plugin_Handled;
			}
		}
		case Plugin_Handled:
		{
			result = true;
			return Plugin_Handled;
		}
		case Plugin_Stop:
		{
			result = false;
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

bool Hooks_BlockPunchImpulse(int client)
{
	return Client(client).IsBoss;
}

bool Hooks_BlockChangeTeam(int client)
{
	return BlockChangeTeam[client];
}

bool Hooks_BlockAmmoPack(int client)
{
	return Client(client).MinionType || Client(client).IsBoss;
}

void Hooks_ForceRespawnPre(int client)
{
	PrefClass = 0;
	if(Client(client).IsBoss)
	{
		int class;
		Client(client).Cfg.GetInt("class", class);
		if(class)
		{
			PrefClass = GetEntProp(client, Prop_Send, "m_iDesiredPlayerClass");
			SetEntProp(client, Prop_Send, "m_iDesiredPlayerClass", class);
		}
	}
}

void Hooks_ForceRespawnPost(int client)
{
	if(PrefClass)
		SetEntProp(client, Prop_Send, "m_iDesiredPlayerClass", PrefClass);
}

// Returns true if the capture value was changed
bool Hooks_GetCaptureValue(int client, int &value)
{
	if(!Client(client).IsBoss || Attrib_FindOnPlayer(client, "increase player capture value", 68))
		return false;

	if(Dome_Enabled() && Cvar[CaptureDomeStyle].IntValue == 0)
	{
		value = 1;
		return true;
	}

	value += TF2_GetPlayerClass(client) == TFClass_Scout ? 1 : 2;
	return true;
}

void Hooks_RegenThinkPre(int client)
{
	if(Client(client).IsBoss && TF2_GetPlayerClass(client) == TFClass_Medic)
		TF2_SetPlayerClass(client, TFClass_Unknown, _, false);
}

void Hooks_RegenThinkPost(int client)
{
	if(Client(client).IsBoss && TF2_GetPlayerClass(client) == TFClass_Unknown)
		TF2_SetPlayerClass(client, TFClass_Medic, _, false);
}

void Hooks_RoundRespawn()
{
	Gamemode_RoundSetup();
}

// Plugin_Handled to block, Plugin_Changed if team was changed
Action Hooks_SetWinningTeam(int &team, int reason)
{
	if(Enabled && RoundStatus == 1)
	{
		switch(reason)
		{
			/*case WINREASON_ALL_POINTS_CAPTURED:
			{
				if(Dome_Enabled())
					return Plugin_Handled;
			}*/
			case WINREASON_OPPONENTS_DEAD:
			{
				if(Cvar[SpecTeam].BoolValue)
				{
					Events_CheckAlivePlayers();

					int found = -1;
					for(int i; i < TFTeam_MAX; i++)
					{
						if(PlayersAlive[i])
						{
							if(found != -1)
								return Plugin_Handled;

							found = i;
						}
					}

					if(found == -1)
					{
						found = 0;
					}
					else if(found < TFTeam_Red)
					{
						Gamemode_OverrideWinner(found);
						found += 2;
					}

					team = found;
					return Plugin_Changed;
				}
			}
		}
	}

	return Plugin_Continue;
}

// Returns true if damagetype was changed
bool Hooks_KnifeInjured(int attacker, int &damagetype)
{
	if(attacker > 0 && attacker <= MaxClients && Client(attacker).IsBoss && !(damagetype & DMG_BURN))
	{
		damagetype |= DMG_BURN;
		return true;
	}

	return false;
}

void Hooks_PostHitPre(int victim)
{
	if(victim > 0 && victim <= MaxClients && Client(victim).IsBoss)
	{
		EffectClass = GetEntProp(victim, Prop_Send, "m_iClass");
		SetEntProp(victim, Prop_Send, "m_iClass", TFClass_Spy);
	}
}

void Hooks_PostHitPost(int victim)
{
	if(EffectClass != -1)
	{
		SetEntProp(victim, Prop_Send, "m_iClass", EffectClass);
		EffectClass = -1;
	}
}

/*
	DHooks callbacks, ignored while the extension is active
*/

static MRESReturn DHook_PickupWeaponFromOtherPre(int client, DHookReturn ret, DHookParam param)
{
	if(ExtHooks_Active())
		return MRES_Ignored;

	bool result;
	if(Hooks_PickupWeapon(client, param.Get(1), result) == Plugin_Continue)
		return MRES_Ignored;

	ret.Value = result;
	return MRES_Supercede;
}

static MRESReturn DHook_ApplyPunchImpulsePre(int client, DHookReturn ret, DHookParam param)
{
	if(ExtHooks_Active() || !Hooks_BlockPunchImpulse(client))
		return MRES_Ignored;

	ret.Value = false;
	return MRES_Supercede;
}

static MRESReturn DHook_ChangeTeamPre(int client, DHookParam param)
{
	if(ExtHooks_Active())
		return MRES_Ignored;

	return MRES_Supercede;
}

static MRESReturn DHook_DropAmmoPackPre(int client, DHookParam param)
{
	if(ExtHooks_Active())
		return MRES_Ignored;

	return Hooks_BlockAmmoPack(client) ? MRES_Supercede : MRES_Ignored;
}

static MRESReturn DHook_ForceRespawnPre(int client)
{
	if(!ExtHooks_Active())
		Hooks_ForceRespawnPre(client);

	return MRES_Ignored;
}

static MRESReturn DHook_ForceRespawnPost(int client)
{
	if(!ExtHooks_Active())
		Hooks_ForceRespawnPost(client);

	return MRES_Ignored;
}

static MRESReturn DHook_GetCaptureValue(DHookReturn ret, DHookParam param)
{
	if(ExtHooks_Active())
		return MRES_Ignored;

	int value = ret.Value;
	if(!Hooks_GetCaptureValue(param.Get(1), value))
		return MRES_Ignored;

	ret.Value = value;
	return MRES_Override;
}

static MRESReturn DHook_RegenThinkPre(int client, DHookParam param)
{
	if(!ExtHooks_Active())
		Hooks_RegenThinkPre(client);

	return MRES_Ignored;
}

static MRESReturn DHook_RegenThinkPost(int client, DHookParam param)
{
	if(!ExtHooks_Active())
		Hooks_RegenThinkPost(client);

	return MRES_Ignored;
}

static MRESReturn DHook_ResetRoundStats(Address address)
{
	CTFGameStats = address;
	return MRES_Ignored;
}

static MRESReturn DHook_RoundRespawn()
{
	if(!ExtHooks_Active())
		Hooks_RoundRespawn();

	return MRES_Ignored;
}

static MRESReturn DHook_SetWinningTeam(DHookParam param)
{
	if(ExtHooks_Active())
		return MRES_Ignored;

	int team = param.Get(1);
	switch(Hooks_SetWinningTeam(team, param.Get(2)))
	{
		case Plugin_Handled:
		{
			return MRES_Supercede;
		}
		case Plugin_Changed:
		{
			param.Set(1, team);
			return MRES_ChangedOverride;
		}
	}

	return MRES_Ignored;
}

static MRESReturn DHook_KnifeInjuredPre(int entity, DHookParam param)
{
	if(!ExtHooks_Active() && DamageTypeOffset != -1 && !param.IsNull(2))
	{
		int damagetype = param.GetObjectVar(3, DamageTypeOffset, ObjectValueType_Int);
		int original = damagetype;
		if(Hooks_KnifeInjured(param.Get(2), damagetype))
		{
			KnifeWasChanged = original;
			param.SetObjectVar(3, DamageTypeOffset, ObjectValueType_Int, damagetype);
		}
	}

	return MRES_Ignored;
}

static MRESReturn DHook_KnifeInjuredPost(int entity, DHookParam param)
{
	if(KnifeWasChanged != -1)
	{
		param.SetObjectVar(3, DamageTypeOffset, ObjectValueType_Int, KnifeWasChanged);
		KnifeWasChanged = -1;
	}

	return MRES_Ignored;
}

static MRESReturn DHook_ApplyPostHitPre(int entity, DHookParam param)
{
	if(!ExtHooks_Active())
		Hooks_PostHitPre(param.Get(2));

	return MRES_Ignored;
}

static MRESReturn DHook_ApplyPostHitPost(int entity, DHookParam param)
{
	Hooks_PostHitPost(param.Get(2));
	return MRES_Ignored;
}

static MRESReturn DHook_EntityShouldTransmit(int entity, DHookReturn ret)
{
	if(ExtHooks_Active())
		return MRES_Ignored;

	ret.Value = FL_EDICT_ALWAYS;
	return MRES_Supercede;
}
