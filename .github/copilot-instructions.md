# QuakeSounds SourceMod Plugin - Copilot Instructions

## Project Overview

QuakeSounds is a SourceMod plugin that enhances gameplay by playing dynamic sound effects and displaying text messages based on in-game events like kills, headshots, kill streaks, and team kills. The plugin supports multiple sound sets, player preferences, and multi-language translations.

**Key Features:**
- Multiple configurable sound sets (male/female voices)
- Event-driven audio feedback (headshots, kill streaks, first blood, etc.)
- Player preference system with client cookies
- Bitwise configuration system for sound/text display
- Multi-language support via translation files

## Repository Structure

```
/addons/sourcemod/
├── scripting/
│   └── QuakeSounds.sp              # Main plugin source code
├── configs/
│   └── quake/
│       ├── sets.cfg                # Available sound sets configuration
│       └── sets/
│           ├── male.cfg            # Male voice sound configuration
│           └── female.cfg          # Female voice sound configuration
└── translations/
    └── plugin.quakesounds.txt      # Multi-language translations

/sound/quake/                       # Sound files directory
/.github/workflows/ci.yml           # CI/CD pipeline
/sourceknight.yaml                  # Build configuration
```

## Development Environment Setup

### Prerequisites
- SourceMod 1.11.0+ development environment
- SourceKnight build tool (configured in `sourceknight.yaml`)
- Access to Source engine game server for testing

### Build System
This project uses **SourceKnight** for building and packaging:

```bash
# Build the plugin
sourceknight build

# Output location: .sourceknight/package/
# Compiled plugin: .sourceknight/package/common/addons/sourcemod/plugins/QuakeSounds.smx
```

The CI/CD pipeline automatically:
1. Builds the plugin using SourceKnight
2. Packages configs, translations, and sound files
3. Creates releases with complete installation packages

### Local Development Workflow
1. Make changes to `QuakeSounds.sp`
2. Test build with `sourceknight build`
3. Deploy to test server for validation
4. Run through event scenarios (kills, headshots, streaks)
5. Verify sound/text configurations work correctly

## Code Architecture

### Core Components

1. **Event System**: Hooks game events (player_death, round_start, etc.)
2. **Sound Management**: Loads and plays sounds based on configurations
3. **Configuration System**: Bitwise flags control sound/text behavior
4. **Player Preferences**: Client cookies store individual settings
5. **Translation System**: Multi-language message support

### Key Global Variables
- `g_sSetsName[]`: Available sound set names
- `g_iConsecutiveKills[]`: Player kill streak tracking
- `g_iConsecutiveHeadshots[]`: Player headshot streak tracking
- `g_iSound[]`, `g_iShowText[]`: Player preferences
- Sound arrays: `headshotSound[][]`, `killSound[][]`, etc.
- Config arrays: `headshotConfig[][]`, `killConfig[][]`, etc.

### Configuration System Explanation

The plugin uses a bitwise configuration system where values are combined:
- `0`: Off
- `1`: Play sound to everyone
- `2`: Play sound to attacker
- `4`: Play sound to victim
- `8`: Print text to everyone
- `16`: Print text to attacker
- `32`: Print text to victim

**Example**: Value `9` (1 + 8) = play sound + print text to everyone

## Coding Standards & Best Practices

### SourcePawn Conventions
- Use `#pragma semicolon 1` and `#pragma newdecls required`
- Prefix global variables with `g_`
- Use camelCase for locals, PascalCase for functions
- 4-space indentation (configured as tabs)
- No trailing spaces

### Plugin-Specific Patterns
```sourcepawn
// Event hook pattern
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    // Handle event logic
}

// Sound playing pattern
PlayQuakeSound(target, soundFile, volume, config)
{
    if (config & 1) // Play to everyone
        EmitSoundToAll(soundFile, .volume = volume);
    if (config & 2) // Play to attacker
        EmitSoundToClient(attacker, soundFile, .volume = volume);
    // etc.
}

// Client preference handling
if (g_iSound[client] && soundFile[0] != '\0')
{
    PlayQuakeSound(client, soundFile, g_fVolume, config);
}
```

### Memory Management
- Use `delete` for handles without null checks
- Avoid `.Clear()` on StringMap/ArrayList (memory leaks)
- Proper cleanup in `OnPluginEnd()` if needed

## Configuration Files

### Sound Sets (`addons/sourcemod/configs/quake/sets.cfg`)
Defines available sound sets:
```
"SetsList"
{
    "1" { "name" "male" }
    "2" { "name" "female" }
}
```

### Sound Set Configuration (`addons/sourcemod/configs/quake/sets/male.cfg`)
Defines sounds and behaviors for each event:
```
"SoundSet"
{
    "headshot"
    {
        "0" { "sound" "quake/standard/headshot.mp3", "config" "9" }
        "1" { "sound" "quake/standard/headshot.mp3", "config" "9" }
    }
    "killsound"
    {
        "4" { "sound" "quake/standard/dominating.mp3", "config" "9" }
    }
}
```

### Translation Files (`addons/sourcemod/translations/plugin.quakesounds.txt`)
Multi-language support:
```
"Phrases"
{
    "headshot"
    {
        "en" "{1} Headshot"
        "fr" "{1} aime les grosses têtes !!"
    }
}
```

## Common Development Tasks

### Adding New Sound Events
1. Add sound file paths to global arrays
2. Add config arrays for the new event
3. Create config parsing in `LoadQuakeSetConfig()`
4. Add event hook in `HookGameEvents()`
5. Implement event handler function
6. Update configuration files with new sounds
7. Add translation phrases

### Adding New Sound Set
1. Add new entry to `sets.cfg`
2. Create new `.cfg` file in `sets/` directory
3. Configure all sound events with appropriate files
4. Test with different configuration values

### Modifying Configuration Behavior
- Configuration uses bitwise operations
- Test all combinations (sound only, text only, both, different targets)
- Verify backward compatibility with existing configs

## Testing Guidelines

### Manual Testing Scenarios
1. **Kill Events**: Single kills, multi-kills, headshots
2. **Streak Events**: Kill streaks, headshot streaks
3. **Special Events**: First blood, team kills, self kills
4. **Player Preferences**: Different sound/text settings
5. **Sound Sets**: Switch between available sets
6. **Multi-language**: Test different language translations

### Configuration Testing
- Test bitwise config values (0, 1, 2, 4, 8, 16, 32, combinations)
- Verify sound file loading and playback
- Check client preference persistence

## Debugging Tips

### Common Issues
1. **Sounds not playing**: Check file paths, server sv_downloadurl
2. **Config not loading**: Verify KeyValues parsing, file syntax
3. **Events not triggering**: Check game engine compatibility
4. **Memory leaks**: Review handle cleanup, avoid `.Clear()`

### Debug Commands
- `sm_quake`: Opens client preference menu
- Server console shows configuration loading messages
- Check SourceMod error logs for parsing issues

## Performance Considerations

### Optimization Guidelines
- Cache frequently accessed data
- Minimize string operations in event handlers
- Use efficient data structures (StringMap for lookups)
- Consider server tick rate impact for frequent events

### Resource Management
- Precache all sound files in `OnMapStart()`
- Limit concurrent sound effects
- Monitor memory usage with multiple sound sets

## Deployment Notes

### Installation Package Contents
- Compiled plugin (.smx)
- Configuration files (sets.cfg, individual sound configs)
- Translation files
- Sound files (in /sound/quake/)

### Server Requirements
- SourceMod 1.11.0+
- Sufficient download bandwidth for sound files
- sv_downloadurl configured for client downloads

### Version Management
- Plugin version defined in myinfo structure
- Follows semantic versioning (MAJOR.MINOR.PATCH)
- Releases created automatically via GitHub Actions

## Contributing Guidelines

### Code Review Checklist
- [ ] Follows SourcePawn coding standards
- [ ] No memory leaks introduced
- [ ] Backward compatibility maintained
- [ ] Configuration changes documented
- [ ] Translation files updated if needed
- [ ] Manual testing completed
- [ ] Build passes CI/CD pipeline

### Pull Request Requirements
- Clear description of changes
- Test results included
- Breaking changes highlighted
- Documentation updates included

This repository uses automated building and packaging. Focus on the core plugin logic and configuration system rather than build tooling modifications.