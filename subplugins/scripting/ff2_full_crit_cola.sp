public Plugin:myinfo = 
{
	name        = "FF2 Full Crit Cola",
	author      = "Bottiger",
	description = "Make Crit Cola give full crit instead of minis",
	version     = "1.0",
	url         = "https://www.skial.com"
};

#include <sdktools>
#include <tf2>
#include <tf2_stocks>
// was <custom>, which only supplied SKIAL_MAX_PLAYERS
#if !defined SKIAL_MAX_PLAYERS
	#define SKIAL_MAX_PLAYERS 256
#endif

bool g_drank[SKIAL_MAX_PLAYERS+1];

public void OnClientDisconnect(int client)
{
	g_drank[client] = false;
}

public void TF2_OnConditionAdded(int client, TFCond condition)
{
	if(condition == TFCond_Taunting)
	{
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if(IsValidEdict(weapon))
		{
			int idx = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
			if(idx == 163)
			{
				float meter = GetEntPropFloat(client, Prop_Send, "m_flEnergyDrinkMeter");
				if(meter >= 100.0)
				{
					g_drank[client] = true;
				}
			}
		}
	}
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
    if(condition == TFCond_Taunting && TF2_IsPlayerInCondition(client, TFCond_CritCola) && g_drank[client])
    {
    	g_drank[client] = false;

        TF2_RemoveCondition(client, TFCond_Buffed);
        TF2_RemoveCondition(client, TFCond_CritCola);
        // not Kritzkrieged: medigun/dispenser healing recalculates charge effects and strips it
        TF2_AddCondition(client, TFCond_CritCanteen, 8.0, client);
    }
}