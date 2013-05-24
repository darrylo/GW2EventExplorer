#! /usr/bin/env ruby
###############################################################################
#
# File:         gw2explorer.rb
# RCS:          $Header: $
# Description:  GW2Explorer is a desktop application designed to browse
#		Guild Wars 2 events.
#
#		This file implements the GUI side.  The database backend
#		is handled by the file, "gw2data.rb".
#
# Author:       Darryl Okahata
# Created:      Tue May 21 21:02:42 2013
# Modified:     Fri May 24 10:22:22 2013 (Darryl Okahata) darryl@fake.domain
# Language:     Ruby
# Package:      N/A
# Status:       Experimental (Do Not Distribute)
#
# (C) Copyright 2013, Darryl Okahata, all rights reserved.
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License along
#    with this program; if not, write to the Free Software Foundation, Inc.,
#    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
#    A copy of the license can be found in the file, "COPYING".
#
###############################################################################

require 'tk'
require 'tkextlib/tile'
require 'yaml'
require 'ruby-growl'
require 'monitor'
require 'thread'
require 'pp'

load "gw2data.rb"


class GW2EventExplorer
  include MonitorMixin

  DEBUG = true

  DATABASE_FILE = "gw2events.sqlite"
  OPTIONS_FILE = "gw2explorer.cfg"
  DEBUGLOG_FILE = "gw2events-debug.log"

  MAP_ALL = "All"
  DEFAULT_WORLD = "Tarnished Coast"	# just a default
  DEFAULT_MAP = MAP_ALL

  DEFAULT_UPDATE_INTERVAL = 300

  # Vacuum the database every VACUUM_ITERATIONS.
  VACUUM_ITERATIONS = 10

  DEFAULT_BACKGROUND_COLOR = "gray94"
  HEADER_COLOR = "#5ED9DD"
  IN_PROGRESS_COLOR = "#5EFF9E"
  FAIL_COLOR = "#FFB8B8"

  FIELD_WIDTH_STATE = 10
  FIELD_WIDTH_DESCRIPTION = 100
  FIELD_WIDTH_SERVER = 20

  class Options
    def initialize(file = nil)
      @options = {}
      @options[:current_world] = DEFAULT_WORLD
      @options[:current_map] = DEFAULT_MAP

      @options[:show_active] = true
      @options[:show_success] = true
      @options[:show_fail] = true
      @options[:show_warmup] = false
      @options[:show_preparation] = true

      @options[:update_interval] = DEFAULT_UPDATE_INTERVAL

      if file and File.exists?(file) then
        load(file)
      end
    end

    def save(file)
      File.open(file, "w") { |fh|
        data = {
          :options => @options
        }
        YAML.dump(data, fh) 
      }
    end

    def load(file)
      data = YAML.load_file(file)

      # Merge the loaded options, to preserve new option defaults:
      data[:options].each { |key, value|
        @options[key] = value
      }
    end

    def [](index)
      return @options[index]
    end

    def []=(index, value)
      @options[index] = value
    end

  end

  def get_states()
    states = []
    if not @want_active.value.empty? then
      states << 1
    end
    if not @want_success.value.empty? then
      states << 2
    end
    if not @want_fail.value.empty? then
      states << 3
    end
    if not @want_warmup.value.empty? then
      states << 4
    end
    if not @want_preparation.value.empty? then
      states << 5
    end
    return states
  end

  def update_states_in_options()
    if @want_active.value.empty? then
      @options[:show_active] = nil
    else
      @options[:show_active] = true
    end
    if @want_success.value.empty? then
      @options[:show_success] = nil
    else
      @options[:show_success] = true
    end
    if @want_fail.value.empty? then
      @options[:show_fail] = nil
    else
      @options[:show_fail] = true
    end
    if @want_warmup.value.empty? then
      @options[:show_warmup] = nil
    else
      @options[:show_warmup] = true
    end
    if @want_preparation.value.empty? then
      @options[:show_preparation] = nil
    else
      @options[:show_preparation] = true
    end
  end

  def get_states_from_options()
    if @options[:show_active] then
      @want_active.value = "1"
    else
      @want_active.value = ""
    end
    if @options[:show_success] then
      @want_success.value = "1"
    else
      @want_success.value = ""
    end
    if @options[:show_fail] then
      @want_fail.value = "1"
    else
      @want_fail.value = ""
    end
    if @options[:show_warmup] then
      @want_warmup.value = "1"
    else
      @want_warmup.value = ""
    end
    if @options[:show_preparation] then
      @want_preparation.value = "1"
    else
      @want_preparation.value = ""
    end
  end

  def update_display(server, map, states)
#     pp @options
#     pp @want_active.value
#     pp @want_success.value
#     pp @want_fail.value
#     pp @want_warmup.value
#     pp @want_preparation.value
#     pp get_states
    @options[:current_world] = server
    @options[:current_map] = map

    @data_manager.db_synchronize {
      world_id = @data_manager.world_id_from_name(server)
      map_id = nil
      if map and map != MAP_ALL then
        map_id = @data_manager.map_id_from_name(map)
      end
      if not world_id.nil? then
        events = @data_manager.filter_events(world_id, map_id, nil, states)
        #pp events[0]
        #print events[0].world, "\n"
        update_event_display(events)
        @last_update_widget.value = @data_manager.get_last_update_time(world_id)
      else
        raise "Wat? (#{server})"
      end
    }
  end

  def update_checkbox(checkbox, status)
    if status then
      checkbox.select()
    else
      #checkbox.deselect()
    end
  end

  def scrolledWidget(parent, *args)
    frame = Tk::Tile::Frame.new(parent) {
      relief "sunken"
    }
    twid = Tk::Text.new(frame, *args)
    vert = Tk::Tile::Scrollbar.new(frame)
    horiz = Tk::Tile::Scrollbar.new(frame)
    twid.yscrollbar(vert)
    twid.xscrollbar(horiz)

    TkGrid.rowconfigure(frame, 0, :weight => 1)
    TkGrid.columnconfigure(frame, 0, :weight => 1)
    TkGrid.columnconfigure(frame, 1, :weight => 0)
    TkGrid.rowconfigure(frame, 1, :weight => 0)

    TkGrid.rowconfigure(twid, 0, :weight => 1)
    TkGrid.columnconfigure(twid, 0, :weight => 1)
    TkGrid.rowconfigure(vert, 0, :weight => 1)
    TkGrid.columnconfigure(vert, 1, :weight => 1)

    twid.grid :row => 0, :column => 0, :sticky => "nsew"
    vert.grid :row => 0, :column => 1, :sticky => "nsew"
    horiz.grid :row => 1, :column => 0, :sticky => "nsew"

    [frame, twid]
  end

  def update_event_display(event_data)
    if @event_frame then
      @event_frame.destroy
      @event_frame = nil
      @event_widget = nil
      @delwids.each { |wid|
        wid.destroy
      }
    end
    @delwids = []

    @event_frame, @event_widget =
      scrolledWidget(@app, 
                     :width => 110,
                     :height => 30,
                     :background => DEFAULT_BACKGROUND_COLOR,
                     :wrap=>:none, :undo => false)
    @event_frame.grid :row => 2, :column => 0, :sticky => "nsew"

    @event_widget.grid :sticky => "nsew"

    @root.update

    # @event_widget.delete("1.0", "end")
    event_data.each { |event_item|
      event_name = event_item.name
      state = event_item.state
      map_name = event_item.map

      widget_state = "normal"
      if state == GW2::STATE_WARMUP then
        state = "Inactive"
        widget_state = "disabled"
      end

      bgcolor = DEFAULT_BACKGROUND_COLOR
      if state == GW2::STATE_ACTIVE then
        bgcolor = IN_PROGRESS_COLOR
      elsif state == GW2::STATE_FAIL then
        bgcolor = FAIL_COLOR
      end

      label = Tk::Tile::Label.new(@event_widget) {
        text state
        anchor "center"
        relief "groove"
        width FIELD_WIDTH_STATE
        background bgcolor
      }
      newwin = TkTextWindow.new(@event_widget, 'end', :window => label)
      @delwids << newwin << label

      label = Tk::Tile::Label.new(@event_widget) {
        text event_name
        width FIELD_WIDTH_DESCRIPTION
        background bgcolor
        state widget_state
      }
      newwin = TkTextWindow.new(@event_widget, 'end', :window => label)
      @delwids << newwin << label

      label = Tk::Tile::Label.new(@event_widget) {
        text map_name
        width FIELD_WIDTH_SERVER
        background bgcolor
        state widget_state
      }
      newwin = TkTextWindow.new(@event_widget, 'end', :window => label)
      @delwids << newwin << label

      @event_widget.insert('end', "\n")
    }
    @event_widget.state(:disabled)
  end

  def save
    @options.save(OPTIONS_FILE)
  end

  def terminate
    save
    while @updatine
      sleep(1)
    end
    exit
  end

  def initialize(manager)
    super()	# needed to initialize MonitorMixin

    @updating = false

    @max_generations = 10

    @delwids = []

    @data_manager = manager

    @options = Options.new(OPTIONS_FILE)

    @update_interval = @options[:update_interval] || DEFAULT_UPDATE_INTERVAL
    if @update_interval < 60
      # No way do we allow anything smaller than this
      @update_interval = 60	# This is the absolute limit
    end

    @worlds = @data_manager.get_world_names()

    @maps = [ MAP_ALL ].concat(@data_manager.get_map_names())

    #
    # No tearoff menus for pulldowns:
    #
    TkOption.add '*tearOff', 0

    @root = TkRoot.new { title "GW2 Event Explorer" }

    TkGrid.rowconfigure( @root, 0, :weight => 1 )
    TkGrid.columnconfigure( @root, 0, :weight => 1 )

    #
    # Intercept window close
    #
    @root.protocol('WM_DELETE_WINDOW', proc { terminate })

    ###########################################################################
    # Add menubar
    ###########################################################################

    @menubar = TkMenu.new(@root)
    @root['menu'] = @menubar

    file = TkMenu.new(@menubar)
    @menubar.add :cascade, :menu => file, :label => 'File'
    file.add('command',
             'label'     => "Exit",
             'command'   => proc { terminate },
             'underline' => 1)

    view = TkMenu.new(@menubar)
    @menubar.add :cascade, :menu => view, :label => 'View'

    @want_active = TkVariable.new
    @want_success = TkVariable.new
    @want_fail = TkVariable.new
    @want_warmup = TkVariable.new
    @want_preparation = TkVariable.new

    # rubytk doesn't like to access method variables directly:
    v_active = @want_active
    v_success = @want_success
    v_fail = @want_fail
    v_warmup = @want_warmup
    v_preparation = @want_preparation

    get_states_from_options()

    @box_active = 
      view.add(:checkbutton, :label => "Active", :variable => v_active,
               :onvalue => 1, :offvalue => nil,
               :command => proc {
                 update_states_in_options()
                 update_display(@server_wid.to_s, @map_wid.to_s, get_states())
               } )
    @box_success =
      view.add(:checkbutton, :label => "Success", :variable => v_success,
               :onvalue => 1, :offvalue => nil,
               :command => proc {
                 update_states_in_options()
                 update_display(@server_wid.to_s, @map_wid.to_s, get_states())
               } )
    @box_fail =
      view.add(:checkbutton, :label => "Fail", :variable => v_fail,
               :onvalue => 1, :offvalue => nil,
               :command => proc {
                 update_states_in_options()
                 update_display(@server_wid.to_s, @map_wid.to_s, get_states())
               } )
    @box_inactive =
      view.add(:checkbutton, :label => "Inactive", :variable => v_warmup,
               :onvalue => 1, :offvalue => nil,
               :command => proc {
                 update_states_in_options()
                 update_display(@server_wid.to_s, @map_wid.to_s, get_states())
               } )
    @box_preparation =
      view.add(:checkbutton, :label => "Preparation", 
               :variable => v_preparation,
               :onvalue => 1, :offvalue => nil,
               :command => proc {
                 update_states_in_options()
                 update_display(@server_wid.to_s, @map_wid.to_s, get_states())
               } )

    update_checkbox(@box_active, @options[:show_active])
    update_checkbox(@box_success, @options[:show_success])
    update_checkbox(@box_fail, @options[:show_fail])
    update_checkbox(@box_inactive, @options[:show_warmup])
    update_checkbox(@box_preparation, @options[:show_preparation])

    #pp v_active.nil?
    #pp v_active.to_s

    ###########################################################################
    # Main app area
    ###########################################################################

    @app = Tk::Tile::Frame.new(@root)
    @app.grid :row => 0, :column => 0, :sticky => "nsew"

    TkGrid.rowconfigure( @app, 0, :weight => 0 )
    TkGrid.columnconfigure( @app, 0, :weight => 1 )
    TkGrid.rowconfigure( @app, 1, :weight => 1 )

    ###########################################################################
    @options_frame = Tk::Tile::Frame.new(@app) {
      borderwidth 5
      #relief "sunken"
    }
    TkGrid.rowconfigure( @options_frame, 0, :weight => 0 )
    TkGrid.columnconfigure( @options_frame, 0, :weight => 0 )
    @options_frame.grid :row => 0, :column => 0, :sticky => "nsew"

    bold_font = TkFont.new :family => 'Calibri', :size => 11, :weight => 'bold'

    wid = Tk::Tile::Label.new(@options_frame) {
      text "Server: "
      font bold_font
    }
    wid.grid :row => 0, :column => 0

    @server_wid = TkVariable.new(@worlds[0])
    @map_wid = TkVariable.new(@maps[0])

    @server_wid.value = @options[:current_world]
    @map_wid.value = @options[:current_map]

    # rubytk doesn't like to access method variables directly:
    v = @server_wid
    w = @worlds
    wid = Tk::Tile::Combobox.new(@options_frame) {
      textvariable v
      values w
    }
    wid.state(:readonly)
    wid.bind("<ComboboxSelected>") { 
      update_display(@server_wid.to_s, @map_wid.to_s, get_states())
    }
    wid.grid :row => 0, :column => 1

    wid = Tk::Tile::Label.new(@options_frame) {
      text "       "
    }
    wid.grid :row => 0, :column => 2

    wid = Tk::Tile::Label.new(@options_frame) {
      text "Map: "
      font bold_font
    }
    wid.grid :row => 0, :column => 3

    # rubytk doesn't like to access method variables directly:
    v = @map_wid
    m = @maps
    wid = Tk::Tile::Combobox.new(@options_frame) {
      textvariable v
      values m
    }
    wid.state(:readonly)
    wid.bind("<ComboboxSelected>") {
      update_display(@server_wid.to_s, @map_wid.to_s, get_states())
    }
    wid.grid :row => 0, :column => 4

    ###########################################################################
    ###########################################################################

    @header_frame = Tk::Frame.new(@app) {
      background HEADER_COLOR
    }
    @header_frame.grid :row => 1, :column => 0, :sticky => "nsew"


    label = Tk::Tile::Label.new(@header_frame) {
      text "State"
      anchor "center"
      width FIELD_WIDTH_STATE
      background HEADER_COLOR
    }
    label.grid :row => 0, :column => 0, :sticky => "nsew"

    label = Tk::Tile::Label.new(@header_frame) {
      text "Description"
      anchor "w"
      width FIELD_WIDTH_DESCRIPTION
      background HEADER_COLOR
    }
    label.grid :row => 0, :column => 1, :sticky => "nsew"

    label = Tk::Tile::Label.new(@header_frame) {
      text "Map"
      anchor "w"
      width FIELD_WIDTH_SERVER
      background HEADER_COLOR
    }
    label.grid :row => 0, :column => 2, :sticky => "nsew"


    ###########################################################################

    @status_frame = Tk::Frame.new(@app) {
      #background HEADER_COLOR
    }
    @status_frame.grid :row => 3, :column => 0, :sticky => "nsew"

    label = Tk::Tile::Label.new(@status_frame) {
      text " Last update: "
      anchor "e"
    }
    label.grid :row => 0, :column => 0, :sticky => "nsew"

    @last_update_widget = TkVariable.new()
    # rubytk doesn't like to access method variables directly:
    v = @last_update_widget
    label = Tk::Tile::Label.new(@status_frame) {
      textvariable v
      anchor "e"
    }
    label.grid :row => 0, :column => 1, :sticky => "nsew"


    ###########################################################################

    update_display(@server_wid.to_s, @map_wid.to_s, get_states())

    ###########################################################################

    @task_queue = Queue.new()
    @gui_queue = Queue.new()

    t = Thread.new {
      thread_do_update
    }

    Tk.after(1000, proc { gui_monitor })

  end

  def process_data_update(world)
    GW2::DebugLog.print "\nGOT UPDATE (#{world}/#{world.class})\n\n"
    @data_manager.db_synchronize {
      if world.class == String then
        world_id = @data_manager.world_id_from_name(world)
      else
        world_id = world
      end

      GW2::DebugLog.print "Update world '#{world}' (#{world_id})\n"
      @data_manager.update_eventdata(world_id)
    }

    return true
  end

  def thread_do_update
    update_count = 0
    while true
      world_id = @task_queue.pop
      begin
        begin
          GW2::DebugLog.print "Update request for world id '#{world_id}'\n"
          @updating = true
          if process_data_update(world_id) then
            @gui_queue.push("update")
            update_count = update_count + 1
            @data_manager.db_synchronize {
              g = @data_manager.get_update_generations(world_id)
              if g.size > @max_generations then
                cutoff = g[@max_generations]
                GW2::DebugLog.print "Deleting generations #{cutoff} and before\n"
                @data_manager.delete_old_generations(cutoff)
                if update_count % VACUUM_ITERATIONS == 0 then
                  s = Time.now
                  GW2::DebugLog.print "Vacuuming ...\n"
                  @data_manager.vacuum
                  GW2::DebugLog.print "Vacuuming done (#{(Time.now - s).to_f}).\n"
                end
              end
            }
          end
        ensure
          @updating = false
        end
      rescue => e
        if not GW2::DebugLog.active() then
          GW2::DebugLog.open_stream(DEBUGLOG_FILE)
        end
        GW2::DebugLog.print "\n***** Caught exception at #{Time.now}!\n#{e}\n\n"
        stacktrace = e.backtrace.join("\n")
        GW2::DebugLog.print "Stacktrace:\n#{stacktrace}\n"
        GW2::DebugLog.print "\n\n"
      end
    end
  end

  def gui_monitor
    world_id = nil
    last_update_time = nil
    last_request_time = nil
    @data_manager.db_synchronize {
      world_id = @data_manager.world_id_from_name(@server_wid.to_s)
      last_update_time = @data_manager.get_last_update_time(world_id)
    }
    #print "last update time = #{last_update_time} (now: #{Time.now})\n"
    current_time = Time.now
    if (current_time - last_update_time).to_f > @update_interval then
      if last_request_time.nil? ||
         ((current_time - last_request_time) >= 60) then
        if not @updating then
          GW2::DebugLog.print "sending update request for '#{@server_wid.to_s}' (#{world_id})\n"
          @task_queue.push(world_id)
          last_request_time = current_time
        end
      else
        GW2::DebugLog.print "***** Not sending request (#{(current_time - last_request_time).to_f} < 60)\n"
      end
    end
    if not @gui_queue.empty? then
      item = @gui_queue.pop
      GW2::DebugLog.print "Got back: '#{item}'\n"
      update_display(@server_wid.to_s, @map_wid.to_s, get_states())
    end
    Tk.after(1000, proc { gui_monitor } )
  end

end


if GW2EventExplorer::DEBUG then
  GW2::DebugLog.open_stream(GW2EventExplorer::DEBUGLOG_FILE)
  GW2::DebugLog.print "\n\n\n***** New log started at #{Time.now} *****\n\n"
end

begin
  data_manager = GW2::EventManager.new(GW2EventExplorer::DATABASE_FILE)

  gui = GW2EventExplorer.new(data_manager)

  Tk.mainloop

rescue => exc
  #
  # Catch any exceptions and dump them to a log file
  #
  if not GW2::DebugLog.active() then
    GW2::DebugLog.open_stream(GW2EventExplorer::DEBUGLOG_FILE)
  end
  GW2::DebugLog.print "\n\n\n***** Crash log started at #{Time.now} *****\n\n"
  stacktrace = exc.backtrace.join("\n")
  GW2::DebugLog.print "Exception occurred:\n\n#{exc}\n\n#{stacktrace}\n\n"
end
