GW2EventExplorer -- A desktop app for browsing Guild Wars 2 events
==================================================================

Version: 0.1, May 24, 2013

GW2Explorer.rb is a crude ruby script that allows you to browse Guild
Wars 2 events on various servers.  Currently, the functionality is
fairly primitive, but this will be enhanced to include desktop,
smartphone, and tablet event notifications.  Right now, you are limited
to:

* Seeing the available events on a given server.  You can choose from
  any of the available servers.

* You can see all events on a server, or you can limit the events to a
  particular map.  (However, see, "Known Issues", below.)

* You can filter the display by event status: active, failed, success,
  warmup, or preparation (I've yet to see any event in the "preparation"
  state, though).

* The events automatically update every 5 minutes (this will be
  configurable in a future version).

* Your settings are automatically saved when you quit the program, and
  are automatically restored when you restart.

  The settings and the event database are stored in the current
  directory (the directory from which you started the program).

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


Requirements
------------

* Ruby 1.9 or later.

  Windows users can download [the latest Ruby 1.9
  rubyinstaller](http://rubyinstaller.org/downloads/) ("Ruby 1.9.3-p429"
  as of May 24, 2013.)

* You must have installed the following gems:

    gem install ruby-growl
    gem install sqlite3

* (Windows) You need to obtain the SQLite DLL.  Go to the [sqlite
  download page](https://www.sqlite.org/download.html) and download the
  ZIP archive that contains the SQLite DLL.  Open the ZIP archive and
  copy the contents to the "bin" directory of your Ruby 1.9
  installation.  Example: if you have installed Ruby1.9 in "C:\Ruby193",
  copy the SQLite DLLs to the "C:\Ruby193\bin" directory.


Usage
-----

There are two ways to run this script:

* Via the command line, like:

    ruby gw2explorer.rb

  Windows users should not directly run cmd.exe, but should instead get
  a command-line prompt via "Start->All Programs->Ruby 1.9.X ...->Start
  Command Prompt With Ruby".

* If you have the appropriate file associations set, you can
  double-click on "gw2explorer.rb" in your file manager.  (Example:
  windows users should be able to just double-click on "gw2explorer.rb"
  to start it -- but note that, since the file extension is ".rb" and
  not ".rbw", an extra console window will still be opened.)

NOTE: while it is possible to convert this script into a windows .exe,
there are no plans to do so.  This is because the resulting executable
is often incorrectly flagged as a virus, trojan, or other malware, due
to the ruby script to .exe conversion method used.


Known Issues
------------

* Displaying all events on a server is slow.  Expect to see nothing for
  many (10-15+) seconds.

* There is some kind of resource/memory leak.  The process grows with
  each update.  It's strongly recommended that you not continuously
  display all events on a server, as this causes the quickest process
  size growth.  Instead, limiting the view to a particular map is best,
  but even this causes a slow process growth.  It's recommended that you
  restart this script at least once a day.


TODO
----

* Add desktop, smartphone, and tablet notifications for events.
  Notifications can occur when an event's state changes, or when an
  event enters a particular state (this is useful for seeing when a
  temple opens).

  Note that these notifications will be done using growl, which means:

  * You need a program to handle growl messages, and you might have to
    buy such a program.  On windows, you need [Growl for
    Windows](http://www.growlforwindows.com) (free).  On OS X, you need
    to [buy Growl](http://growl.info/).  Linux users are on their own,
    altough [mumbles](http://sourceforge.net/projects/mumbles) might
    work.

  * For smartphone or tablet notifications, you have to buy one of the
    apps supported for growl message forwarding (this is supported only
    for windows and OS X).  See the above websites for Growl for Windows
    or OS X Growl for supported apps.

    For iOS, I recommend the [Prowl App](http://www.prowlapp.com)
    (around $3?), as this app tends to have larger limits (e.g., its
    competitors have small max message sizes, like 512 characters, have
    relatively small per-month message limits, or reformat the message).

  Basically, GW2EventExplorer sends a growl message to the local system,
  and the growl program forwards the message to your smartphone or
  tablet.

* "Sticky events"  This is the ability to mark an event as "sticky",
  which means that it will always be shown, even if you have limited the
  event display to a different map.

* Configurable update times.  Right now, updates occur every 5 minutes.
