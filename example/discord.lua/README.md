# discord.lua + lavalink.lua

This example uses the `lavalinklua.discord(bot, options)` adapter. It forwards
Discord `VOICE_STATE_UPDATE` and `VOICE_SERVER_UPDATE` to the existing
Lavalink v4 manager; it does not use `VoiceClient`, UDP, DAVE, FFmpeg or a
local PCM/Opus encoder.

Copy `.env.example` to `.env` and set:

```dotenv
DISCORD_TOKEN=your_bot_token
LAVALINK_HOST=127.0.0.1
LAVALINK_PORT=2333
LAVALINK_PASSWORD=youshallnotpass
```

Then run `luvit bot.lua`. Enable the `GUILD_VOICE_STATES` gateway intent for
the bot. The example registers `/join`, `/play source`, `/pause`, `/resume`,
`/stop`, `/leave`, and `/volume value`; it is intentionally slash-command only.
HTTP(S) URLs such as MP3 are passed directly to Lavalink. Whether a format can
play depends on the Lavalink node and its FFmpeg installation.
