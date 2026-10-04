// Matches the include the prod binaries were built with: no ".ff2" stripping.
// Define FF2_SUBPLUGIN_ACCUMULATE_SLASH for the variant m7_abilities_extended was built with.
char this_plugin_name[80];

void GetThisPluginName()
{
	char pluginName[80];
	GetPluginFilename(INVALID_HANDLE, pluginName, sizeof(pluginName));
	int forwardSlash = -1;
	int backwardSlash = -1;
	int finalPluginName = -1;
	for(;;)
	{
		forwardSlash = StrContains(pluginName[finalPluginName+1], "/");
		backwardSlash = StrContains(pluginName[finalPluginName+1], "\\");
		if((backwardSlash<forwardSlash && backwardSlash!=-1) || forwardSlash==-1)
		{
			if(backwardSlash == -1)
				break;

#if defined FF2_SUBPLUGIN_ACCUMULATE_SLASH
			if(finalPluginName == -1)
				finalPluginName = 0;

			finalPluginName += backwardSlash;
#else
			finalPluginName = backwardSlash;
#endif
		}
		else if((forwardSlash<backwardSlash && forwardSlash!=-1) || backwardSlash==-1)
		{
			if(forwardSlash == -1)
				break;

#if defined FF2_SUBPLUGIN_ACCUMULATE_SLASH
			if(finalPluginName == -1)
				finalPluginName = 0;

			finalPluginName += forwardSlash;
#else
			finalPluginName = forwardSlash;
#endif
		}
	}
	strcopy(this_plugin_name, sizeof(this_plugin_name), pluginName[finalPluginName+1]);
}

public void OnPluginStart()
{
	OnPluginStart2();
	GetThisPluginName();
}

// This is very broken-FF2_OnAbility's args are client, plugin_name, ability_name, SLOT, status
public Action FF2_OnAbility(client, const char[] plugin_name, const char[] ability_name, int status)
{
	if(plugin_name[0])
	{
		if(!StrEqual(this_plugin_name, plugin_name))
			return Plugin_Continue;
	}
	// So we're really passing 'slot' here and not 'status'-currently subplugins have no way of getting status
	FF2_OnAbility2(client, plugin_name, ability_name, status);
	return Plugin_Continue;
}
