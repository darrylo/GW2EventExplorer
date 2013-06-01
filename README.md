GW2EventExplorer -- A desktop app for browsing Guild Wars 2 events
==================================================================

Version: 0.2, May 31, 2013
IMPORTANT NOTE: See the first issue under, "Known Issues", below.

GW2Explorer.rbw is a crude ruby script that allows you to browse Guild
Wars 2 events on various servers.  Currently, the functionality is
fairly primitive, but currently includes rudimentary UDP (old,
windows-only) growl support, which provides for basic desktop,
smartphone, and tablet event notifications.

Right now, you are limited to:

* Seeing the available events on a given server.  You can choose from any of
  the available servers.

* You can see all events on a server, or you can limit the events to a
  particular map.  (However, it's strongly recommended that you only view
  events on a particular map and not the entire server -- see, "Known Issues",
  below.)

  The list of group events is stored in the CSV file, "group_events.csv", and
  comes from Tiscan.8345, obtained via:

    https://forum-en.guildwars2.com/forum/community/api/List-of-all-group-events

* You can filter the display by event status: active, failed, success, warmup,
  or preparation.  There is also a "AllGroup Events" selection, which adds
  group events to the display (this ignores the currently selected map, and
  will always display the event if selected).  Group events are marked with a
  "(G)" in front of the description.

* The events automatically update every minute (60 seconds -- this will be
  configurable in a future version).

* Your settings are automatically saved when you quit the program, and are
  automatically restored when you restart.

  The settings and the event database are stored in the current directory (the
  directory from which you started the program).

That's it.  See the TODO list, below, for future features.

Because this is a ruby script, it's really intended for advanced users.
Novice users will have difficulty using it.

This is not intended to replace the GW2 event timer sites.  In fact, if
you want event timer information, I recommend [the excellent
GW2STUFF.com site](http://www.gw2stuff.com).

This is all rather minimal: there is **NO** installatation or setup
program.  Everything is from the command line, and the instructions are
minimal, as it's assumed that users know how to run ruby scripts from
the command line.

See the file, COPYING, for licensing information.

See the file, ChangeLog, for major change information.


Requirements
------------

* Ruby 1.9 or later, with the "tk" extension (e.g., "require 'tk'" must work).

  Windows users can download [the latest Ruby 1.9
  rubyinstaller](http://rubyinstaller.org/downloads/) ("Ruby 1.9.3-p429" as of
  May 24, 2013.)  When you install ruby, you must select the "tk" option.

* You must have installed the following gems:

    gem install ruby-growl
    gem install sqlite3

* (Windows) You need to obtain the SQLite DLL.  Go to the [sqlite download
  page](https://www.sqlite.org/download.html) and download the ZIP archive
  that contains the SQLite DLL.  Open the ZIP archive and copy the contents to
  the "bin" directory of your Ruby 1.9 installation.  Example: if you have
  installed Ruby1.9 in "C:\Ruby193", copy the SQLite DLLs to the
  "C:\Ruby193\bin" directory.

* Notifications (windows only): if you want desktop/smartphone/tablet
  notifications, you need to install growl-for-windows (free), from:

        http://www.growlforwindows.com

  If you want iOS/android/WP7 smartphone/tablet notifications, you need to buy
  and configure one of the notification apps supported by growl-for-windows.
  See the growl-for-windows website for supported apps (some of which also
  work on tablets).  Note that you'll have to do additional app-specific=
  configuration.

  Personally, for iOS, I happen to like the [Prowl
  App](http://www.prowlapp.com) (around $3?), as this app tends to have larger
  limits (e.g., its competitors have small max message sizes, like 512
  characters, have relatively small per-month message limits, or reformat the
  message).  These are important, as many event notifications can occur often
  or be large (if multiple events occur at the same time).

  Because growl notifications are currently done only via UDP, which is the
  old growl protocol, notifications are only supported on windows (the latest
  OS X growl no longer supports this).


Usage
-----

There are two ways to run this script:

* Via the command line, like:

    rubyw gw2explorer.rbw

  Windows users should not directly run cmd.exe, but should instead get a
  command-line prompt via "Start->All Programs->Ruby 1.9.X ...->Start Command
  Prompt With Ruby".

  After running the command, nothing will happen for several seconds, as the
  program has to contact anet and download an initial set of data.

  Note that, since "rubyw" is used instead of "ruby", running the above
  command will immediately return.  The program is running in the background,
  and a window should appear after a moment.

* If you have the appropriate file associations set, you can just double-click
  on "gw2explorer.rbw" in your file manager.  (Example: windows users should
  be able to just double-click on "gw2explorer.rbw" to start it.)

NOTE: while it is possible to convert this script into a windows .exe, there
are no plans to do so.  This is because the resulting executable is often
incorrectly flagged as a virus, trojan, or other malware, due to the ruby
script to .exe conversion methods.


Known Issues
------------

* (IMPORTANT) You need to delete any existing "gw2events.sqlite" database
  before running this version.  While this version does try to upgrade the
  database schema, sqlite seems to return incorrect query results.  Deleting
  the database and letting GW2EventExplorer recreate it seems to fix the
  issue.

* When an update occurs, the display window is completely redrawn, and the
  window view is reset to the top.  Since updates occur frequently, this can
  be highly annoying.

* Even though a background thread is used to update the database, the poor
  ruby threading causes the other GUI thread to pause while the database is
  updated.  As updates can take several seconds, this causes the GUI to lock
  up during that period, which is highly annoying.

* Initially, the "Last Changed" column will contain the time of the very first
  event update stored in the database.  As event status changes occur, this
  time will correctly reflect the time of last change.  Note that
  GW2EventExplorer must be running in order for this time to be correct.

* Growl support currently has no support for passwords or the newer GNTP
  protocol.

* Displaying all events on a server is slow.  Expect to see nothing for a long
  time.  In fact, it's recommended that you not do this, because of the
  slowness, and because of the next item (resource/memory leak).

* There is some kind of resource/memory leak.  The process grows with each
  update.  It's strongly recommended that you not continuously display all
  events on a server, as this causes the quickest process size growth.
  Instead, limiting the view to a particular map is best, but even this causes
  a slow process growth.  It's recommended that you restart this script at
  least once a day.

* For some types of ruby exceptions, a "gw2events-crashlog.log" file is
  produced.  This file records the exception information for debugging
  purposes.

* (Will not be addressed) The database has an extra/empty, "event_log_data",
  table.  While this program does not use it, the backend GW2 event database
  manager supports optional recording of event status changes, and this table
  is used to record those.



TODO
----

Possible future tasks, in no particular order:

* "Meta event notifications".  This is the ability to use checkboxes to say
  that you want to be told when a major pre-event occurs for Tequatl, Shadow
  Behemoth, etc., etc..

* Need to be able to save/restore event notification sets.  Perhaps allow the
  user to define multiple notification profiles?

* Configurable update times.  Right now, updates occur every 5 minutes.

* "Sticky events"  This is the ability to mark an event as "sticky",
  which means that it will always be shown, even if you have limited the
  event display to a different map.

* Unlike sticky events, should there be a way to always "hide" an event?

* The ability to limit event display via a regular expression.
