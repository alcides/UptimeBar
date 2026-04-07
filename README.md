# UptimeBar

A minimal macOS menubar app that periodically checks if a list of servers are online.

## Origin

This project was built with [Claude Code](https://claude.ai/claude-code) from the following prompt:

> I need a menubar-only app for macos that periodically (every 5 minutes) checks if a given list of servers are online.
>
> It should be a minimal Swift application, ideally with only one file, but can have more if it makes it more organized.
>
> It should have an icon that you need to create. Do not using existing icons.
>
> The menubar should have the following menu:
>
> * Edit configuration file
> * Open on startup
> * Set frequency (with a submenu with 1, 5, 15 and 30 minutes)
> * Quit
>
> The configuration file should be stored on the recommended location for macos applications. It should be open with the default editor.
>
> Open on startup should make the app open when logging in.
>
> Setting the frequency should change how frequently servers are checked for status.
>
> Quit quits the application.
>
> The configuration file should have the following format: "\<ip\>:\<port\>" with port being optional and ip being an ip or hostname.
>
> For checking online status, you should do the following: Check if google.com or sapo.pt work. If they do not, we are offline and there is no point in checking the status of other ips. If the computer is online, then we iterate each ip and port on the configuration file, and we try to connect. If the socket is established (regardless of it being http, https or ssh), it is considered online.
>
> Ideally, before the menus, you should state the list of machines with their status. Clicking them will copy the hostname/ip address.

## Building

```bash
swift build -c release
```

## Installing

```bash
# Build and create .app bundle
swift build -c release
mkdir -p UptimeBar.app/Contents/MacOS
cp .build/release/UptimeBar UptimeBar.app/Contents/MacOS/
cp -R UptimeBar.app /Applications/
```

## Configuration

The configuration file is located at `~/Library/Application Support/UptimeBar/servers.txt`.

Format: one server per line, `hostname:port` (port defaults to 22 if omitted). Lines starting with `#` are comments.

```
# Example
myserver.com:443
192.168.1.1
anotherhost.local:8080
```
