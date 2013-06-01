#! /usr/bin/env ruby
###############################################################################
#
# File:         gw2explorer.rbw
# RCS:          $Header: $
# Description:  GW2Explorer is a desktop application designed to browse
#		Guild Wars 2 events.
#
#		This file implements the GUI side.  The database backend
#		is handled by the file, "gw2data.rb".
#
# Author:       Darryl Okahata
# Created:      Tue May 21 21:02:42 2013
# Modified:     Fri May 31 20:00:36 2013 (Darryl Okahata) darryl@fake.domain
# Language:     Ruby
# Package:      N/A
# Status:       Experimental
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


###############################################################################
# Main GUI class
###############################################################################

class GW2EventExplorer
  include MonitorMixin

  DEBUG = false
  DEBUG_TIMINGS = false

  DATABASE_FILE = "gw2events.sqlite"
  OPTIONS_FILE = "gw2explorer.cfg"
  DEBUGLOG_FILE = "gw2events-debug.log"
  GROUP_EVENTS_CSV = "group_events.csv"

  MAP_ALL = "All"
  DEFAULT_WORLD = "Tarnished Coast"	# just a default
  DEFAULT_MAP = MAP_ALL

  NO_NOTIFY_VALUE = "None"
  ANY_NOTIFY_VALUE = "Any"
  ACTIVE_PREP_NOTIFY_VALUE = "Active/Prep"

  DEFAULT_UPDATE_INTERVAL = 60
  ABSOLUTE_MIN_UPDATE_TIME = 45

  # How much data to keep, in seconds.  This time, divided by the update time,
  # must allow at least 2 sets of event data to be kept (the current plus the
  # previous set) -- if not, bad things will happen.
  DEFAULT_MAX_KEEP_TIME =  3 * DEFAULT_UPDATE_INTERVAL	# seconds

  # Vacuum the database every VACUUM_ITERATIONS.
  VACUUM_ITERATIONS = 10

  DEFAULT_BACKGROUND_COLOR = "gray94"
  HEADER_COLOR = "#5ED9DD"
  IN_PROGRESS_COLOR = "#5EFF9E"
  FAIL_COLOR = "#FFB8B8"

  FIELD_WIDTH_STATE = 10
  FIELD_WIDTH_DESCRIPTION = 100
  FIELD_WIDTH_SERVER = 20
  FIELD_WIDTH_NOTIFY = 10
  FIELD_WIDTH_LAST_CHANGED = 20

  #############################################################################
  #
  # Notification sending class
  #
  #############################################################################

  class Notifier
    private

    GROWL_APP_NAME = "GW2Explorer"
    GROWL_NOTIFICATION_TYPE = "Events"

    @@growl = nil

    def send_growl_notification (title, msg)
      if @@growl.nil? then
	@@growl = Growl.new("localhost", GROWL_APP_NAME)
	@@growl.add_notification(GROWL_NOTIFICATION_TYPE)
      end
      @@growl.notify(GROWL_NOTIFICATION_TYPE, title, msg)
    end

    public

    def initialize
      @notify_list = []
    end

    def record(event)
      @notify_list << event
    end

    def send
      if not @notify_list.empty?
	msg = ""
	@notify_list.each { |event|
	  state = event.state
	  if state == "Warmup" then
	    state = "Inactive"
	  end
	  msg << "#{state}: #{event.name}\n\n"
	}
	send_growl_notification("Events", msg)
	@notify_list = []
      end
    end
  end


  #############################################################################
  #
  # Options handling class
  #
  #############################################################################

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
      @options[:show_group_enents] = false
      @options[:update_interval] = DEFAULT_UPDATE_INTERVAL
      @options[:time24] = false
      @options[:notify_events] = {}
      @options[:event_logging] = false

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

  end	# class Options


  #############################################################################
  # GW2EventExplorer methods
  #############################################################################

  private

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
    if @want_group_events.value.empty? then
      @options[:show_group_events] = nil
    else
      @options[:show_group_events] = true
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
    if @options[:show_group_events] then
      @want_group_events.value = "1"
    else
      @want_group_events.value = ""
    end
  end

  def update_display_events
    @display_events = {}
    if @options[:show_group_events] then
      @display_events = @special_events.select { |k,v| v == :group }
    end
  end

  def is_group_event(event)
    return (@special_events[event.event_id] == :group)
  end

  def update_notify_event(event_id, notify_var)
    value = notify_var.value
    if value == NO_NOTIFY_VALUE then
      @notify_events[event_id] = nil
    elsif value == ANY_NOTIFY_VALUE then
      @notify_events[event_id] = :any
    elsif value == ACTIVE_PREP_NOTIFY_VALUE then
      @notify_events[event_id] = :active_prep
    else
      @notify_events[event_id] = GW2.state_to_int(value)
    end
    #print "#{@data_manager.get_event_name(event_id)}, #{@notify_events[event_id]}\n"
  end

#   def rebuild_notify_events()
#     @notify_events = {}
#     if @events_to_display then
#       event_index = 0
#       @events_to_display.each { |event|
# 	var = @notify_event_vars[event_index]
# 	if var then
# 	  val = var.value
# 	  if val != NO_NOTIFY_VALUE then
# 	    if val == ANY_NOTIFY_VALUE then
# 	      @notify_events[event.event_id] = :any
# 	    elsif val == ACTIVE_PREP_NOTIFY_VALUE then
# 	      @notify_events[event.event_id] = :active_prep
# 	    else
# 	      @notify_events[event.event_id] = GW2.state_to_int(val)
# 	    end
# 	  end
# 	end
# 	event_index = event_index + 1
#       }
#     end
#     @options[:notify_events] = @notify_events
#   end

  def update_world_events(world_id)
    if @current_world_id == world_id then
      if !@first_update then
	@check_notify = true
      end
      @first_update = false
    else
      @first_update = true
    end

    @current_world_id = world_id

    @world_events = @data_manager.filter_events(world_id)
  end

  def update_display(server, map, states, display_events)
    @options[:current_world] = server
    @options[:current_map] = map

    @data_manager.db_synchronize {
      world_id = @data_manager.world_id_from_name(server)
      map_id = nil
      if map and map != MAP_ALL then
        map_id = @data_manager.map_id_from_name(map)
      end
      if not world_id.nil? then
	@event_matcher.set_map(map_id)
	@event_matcher.set_events(display_events)
	@event_matcher.set_types(states)

	if world_id != @current_world_id then
	  update_world_events(world_id)
	end

	#print "Number of world events = #{@world_events.size}\n"

	#File.open("data.dat", "w") { |f| YAML.dump(@world_events, f) }

	events = @event_matcher.filter_events(@world_events)
	@events_to_display = GW2::EventItem.sort_list(events)
	#print "Number of display events = #{@events_to_display.size}\n"

        update_event_display(@events_to_display)
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

    twid.grid :row => 0, :column => 0, :sticky => "nsew"
    vert.grid :row => 0, :column => 1, :sticky => "nsew"
    horiz.grid :row => 1, :column => 0, :sticky => "nsew"

    TkGrid.rowconfigure(frame, 0, :weight => 1)
    TkGrid.columnconfigure(frame, 0, :weight => 1)
    TkGrid.columnconfigure(frame, 1, :weight => 0)
    TkGrid.rowconfigure(frame, 1, :weight => 0)

    TkGrid.rowconfigure(twid, 0, :weight => 1)
    TkGrid.columnconfigure(twid, 0, :weight => 1)
    TkGrid.rowconfigure(vert, 0, :weight => 1)
    TkGrid.columnconfigure(vert, 1, :weight => 1)

    [frame, twid, vert]
  end

  def update_event_display(event_data)
    notify_states = [ 
      NO_NOTIFY_VALUE,
      GW2::STATE_ACTIVE,
      GW2::STATE_SUCCESS,
      GW2::STATE_FAIL,
      GW2::STATE_WARMUP,
      GW2::STATE_PREPARATION,
      ACTIVE_PREP_NOTIFY_VALUE,
      ANY_NOTIFY_VALUE
    ]

    vert_scroll_pos = nil
    if @event_frame then
      @event_frame.destroy
      @event_frame = nil
      @event_widget = nil
#       if @event_vscroll then
# 	pp @event_vscroll.public_methods.sort
# 	vert_scroll_pos = @event_vscroll.get()
#       end
      @event_vscroll = nil
      @delwids.each { |wid|
        wid.destroy
      }
    end
    @delwids = []

    @event_frame, @event_widget, @event_vscroll =
      scrolledWidget(@app, 
                     :width => 130,
                     :height => 30,
                     :background => DEFAULT_BACKGROUND_COLOR,
                     :wrap=>:none, :undo => false)
    @event_frame.grid :row => 2, :column => 0, :sticky => "nsew"
    TkGrid.rowconfigure( @app, 2, :weight => 1 )
    TkGrid.columnconfigure( @event_frame, 0, :weight => 1 )
    TkGrid.columnconfigure( @app, 0, :weight => 1 )

    @event_widget.grid :sticky => "nsew"

    #@root.update

    # @event_widget.delete("1.0", "end")
    event_index = 0
    event_data.each { |event_item|
      event_name = event_item.name
      state = event_item.state
      map_name = event_item.map

      if is_group_event(event_item) then
	event_name = "(G) " + event_name
      end

      #########################################################################
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

      #########################################################################
      label = Tk::Tile::Label.new(@event_widget) {
        text event_name
        width FIELD_WIDTH_DESCRIPTION
        background bgcolor
        state widget_state
      }
      newwin = TkTextWindow.new(@event_widget, 'end', :window => label)
      @delwids << newwin << label

      #########################################################################
      label = Tk::Tile::Label.new(@event_widget) {
        text map_name
        width FIELD_WIDTH_SERVER
        background bgcolor
        state widget_state
      }
      newwin = TkTextWindow.new(@event_widget, 'end', :window => label)
      @delwids << newwin << label

      #########################################################################
      # Naaaasty ugly kludge.  Use recycled variables to prevent memory leak.
      # We hates it.
      # Basically, we assume that the display order is fixed, and so we use
      # the display order as an index into the variable array.
      default_state = NO_NOTIFY_VALUE
      state = @notify_events[event_item.event_id]
      if state then
	if state == :any then
	  default_state = ANY_NOTIFY_VALUE
	elsif state == :active_prep then
	  default_state = ACTIVE_PREP_NOTIFY_VALUE
	else
	  default_state = GW2.int_to_state(state)
	end
      end
      notify_var = @notify_event_vars[event_index]
      if notify_var.nil? then
	notify_var = TkVariable.new(default_state)
	@notify_event_vars[event_index] = notify_var
      else
	notify_var.value = default_state
      end
      notify_wid = Tk::Tile::Combobox.new(@event_widget) {
        textvariable notify_var
        width FIELD_WIDTH_NOTIFY
        background bgcolor
	values notify_states
      }
      id = event_item.event_id
      notify_wid.state(:readonly)
      notify_wid.bind("<ComboboxSelected>") { 
	update_notify_event(id, notify_var)
	#rebuild_notify_events
      }
      newwin = TkTextWindow.new(@event_widget, 'end', :window => notify_wid)
      @delwids << newwin << notify_wid

      #########################################################################
      if @options[:time24] then
	last_changed = "  " + event_item.last_change_time.strftime("%H:%M (%a)")
      else
	last_changed = "  " + event_item.last_change_time.strftime("%I:%M %P (%a)")
      end
      label = Tk::Tile::Label.new(@event_widget) {
        text last_changed
	width FIELD_WIDTH_LAST_CHANGED
        background bgcolor
        state widget_state
      }
      newwin = TkTextWindow.new(@event_widget, 'end', :window => label)
      @delwids << newwin << label

      #########################################################################
      @event_widget.insert('end', "\n")

      event_index = event_index + 1
    }
    @event_widget.state(:disabled)
    if vert_scroll_pos then
      @event_vscroll.set vert_scroll_pos
    end
  end

  def save
    @options.save(OPTIONS_FILE)
  end

  def terminate
    begin
      retries = 0
      while @updating && (retries < 20)
	sleep(1)
	retries = retries + 1
      end
      save
    rescue
      #
      # Catch any exceptions and dump them to a log file
      #
      if not GW2::DebugLog.active() then
	GW2::DebugLog.open_stream(GW2EventExplorer::DEBUGLOG_FILE)
      end
      GW2::DebugLog.print "\n\n\n***** Crash log started at #{Time.now} *****\n\n"
      stacktrace = exc.backtrace.join("\n")
      GW2::DebugLog.print "Exception occurred during termination:\n\n#{exc}\n\n#{stacktrace}\n\n"
    end
    exit
  end

  def max_generations
    return (@max_keep_time / @update_interval).to_i
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
  end

  def thread_do_update
    update_count = 0
    while true
      world_id = @task_queue.pop
      begin
        begin
          GW2::DebugLog.print "Update request for world id '#{world_id}'\n"
	  s0 = Time.now
          @updating = true

          process_data_update(world_id)
	  update_world_events(world_id)

	  @gui_queue.push("update")
	  update_count = update_count + 1
	  @data_manager.db_synchronize {
	    g = @data_manager.get_update_generations(world_id)
	    if g.size > max_generations then
	      cutoff = g[max_generations]
	      GW2::DebugLog.print "Deleting generations #{cutoff} and before\n"
	      @data_manager.delete_old_generations(cutoff)

	      # We only do vacuum checks if we delete
	      if update_count % VACUUM_ITERATIONS == 0 then
		s = Time.now
		GW2::DebugLog.print "Vacuuming ...\n"
		@data_manager.vacuum
		GW2::DebugLog.print "Vacuuming done (#{(Time.now - s).to_f}).\n"
	      end
	    end
	  }
	  if @check_notify then
	    GW2::DebugLog.print "Checking notify\n"
	    if @world_events then
	      notifier = Notifier.new
	      @world_events.each { |event|
		notify_type = @notify_events[event.event_id]
		if notify_type then
		  #print "Notify data exists for event \"#{event.name}\" (#{event.event_id})\n"
		  if (event.update_time - event.last_change_time).abs < 1 then
		    do_notify = false

		    #
		    # Here, we ignore any success->warmup or fail->warmup
		    # transitions, as we consider that to be noise.
		    #
		    if ! (event.state_num == GW2::STATE_WARMUP &&
			  (event.previous_state_num == GW2::STATE_SUCCESS ||
			   event.previous_state_num == GW2::STATE_FAIL)) then
		      if notify_type == :any then
			do_notify = true
		      elsif notify_type == :active_prep then
			if event.state_num == GW2::STATE_ACTIVE_NUM ||
			    event.state_num == GW2::STATE_PREPARATION_NUM then
			  do_notify = true
			end
		      elsif notify_type.is_a?(Fixnum) &&
			  event.state_num == notify_type then
			do_notify = true
		      end
		    end
		    if do_notify then
		      GW2::DebugLog.print "Notify for event \"#{event.name}\", #{event.state} (#{event.previous_state}) at time '#{event.last_change_time}' (#{event.update_time})\n"
		      notifier.record(event)
		    end
		  end
		end
	      }
	      notifier.send
	      @check_notify = false
	    else
	      GW2::DebugLog.print "NOT checking notify\n"
	    end
	  end
          GW2::DebugLog.print "Update request done (#{(Time.now - s0).to_s} sec)\n"
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
    @data_manager.db_synchronize {
      world_id = @data_manager.world_id_from_name(@server_wid.to_s)
      last_update_time = @data_manager.get_last_update_time(world_id)
    }
    #print "last update time = #{last_update_time} (now: #{Time.now})\n"
    current_time = Time.now
    if (current_time - last_update_time).to_f > @update_interval then
      if @last_request_time[world_id].nil? ||
         ((current_time - @last_request_time[world_id]) >= ABSOLUTE_MIN_UPDATE_TIME) then
        if not @updating then
          @last_request_time[world_id] = current_time
          GW2::DebugLog.print "Sending update request for '#{@server_wid.to_s}' (#{world_id}) at '#{@last_request_time[world_id]}'\n"
	  s = Time.now
          @task_queue.push(world_id)
          GW2::DebugLog.print "   ... update request took #{(Time.now - s).to_s} sec\n"
        end
      else
        GW2::DebugLog.print "***** Not sending request (#{(current_time - @last_request_time[world_id]).to_f} < #{ABSOLUTE_MIN_UPDATE_TIME})\n"
      end
    end
    if not @gui_queue.empty? then
      item = @gui_queue.pop
      GW2::DebugLog.print "Got back: '#{item}'\n"
      update_display(@server_wid.to_s, @map_wid.to_s, get_states(),
		     @display_events)
      if DEBUG_TIMINGS then
	if @last_request_time[world_id] then
	  GW2::DebugLog.print "Update time = #{(Time.now - @last_request_time[world_id]).to_s}\n"
	else
	  GW2::DebugLog.print "last_request_time is nil??\n"
	end
      end
    end
    Tk.after(1000, proc { gui_monitor } )
  end

  def set_update_interval(secs)
    if secs < ABSOLUTE_MIN_UPDATE_TIME + 1 then
      secs = ABSOLUTE_MIN_UPDATE_TIME + 1
    end
    @update_interval = secs
    if @max_keep_time < secs * 3 then
      @max_keep_time = secs * 3
    end
  end

  public

  def initialize()
    super()	# needed to initialize MonitorMixin

    @max_keep_time = DEFAULT_MAX_KEEP_TIME

    @notify_event_vars = []
    @notify_events = {}			# irrelevant, because of below
    @updating = false
    @last_request_time = {}
    @current_world_id = nil
    @world_events = nil
    @check_notify = false
    @events_to_display = nil

    @event_frame = nil
    @event_widget = nil
    @event_vscroll = nil

    @options = Options.new(OPTIONS_FILE)
    @notify_events = @options[:notify_events]

    @special_events = {}
    if File.exists?(GROUP_EVENTS_CSV) then
      GW2.read_group_events_csv(GROUP_EVENTS_CSV, @special_events)
    end

    @event_matcher = GW2::EventMatcher.new

    @display_events = {}
    update_display_events

    @delwids = []

    @data_manager = GW2::EventManager.new(DATABASE_FILE,
					  @options[:event_logging])

    set_update_interval(@options[:update_interval] || DEFAULT_UPDATE_INTERVAL)

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
    @want_group_events = TkVariable.new

    # rubytk doesn't like to access method variables directly:
    v_active = @want_active
    v_success = @want_success
    v_fail = @want_fail
    v_warmup = @want_warmup
    v_preparation = @want_preparation
    v_group_events = @want_group_events

    get_states_from_options()

    @box_active = 
      view.add(:checkbutton, :label => "Active", :variable => v_active,
               :onvalue => 1, :offvalue => nil,
               :command => proc {
                 update_states_in_options()
                 update_display(@server_wid.to_s, @map_wid.to_s, get_states(),
				@display_events)
               } )
    @box_success =
      view.add(:checkbutton, :label => "Success", :variable => v_success,
               :onvalue => 1, :offvalue => nil,
               :command => proc {
                 update_states_in_options()
                 update_display(@server_wid.to_s, @map_wid.to_s, get_states(),
				@display_events)
               } )
    @box_fail =
      view.add(:checkbutton, :label => "Fail", :variable => v_fail,
               :onvalue => 1, :offvalue => nil,
               :command => proc {
                 update_states_in_options()
                 update_display(@server_wid.to_s, @map_wid.to_s, get_states(),
				@display_events)
               } )
    @box_inactive =
      view.add(:checkbutton, :label => "Inactive", :variable => v_warmup,
               :onvalue => 1, :offvalue => nil,
               :command => proc {
                 update_states_in_options()
                 update_display(@server_wid.to_s, @map_wid.to_s, get_states(),
				@display_events)
               } )
    @box_preparation =
      view.add(:checkbutton, :label => "Preparation", 
               :variable => v_preparation,
               :onvalue => 1, :offvalue => nil,
               :command => proc {
                 update_states_in_options()
                 update_display(@server_wid.to_s, @map_wid.to_s, get_states(),
				@display_events)
               } )
    @box_group_events =
      view.add(:checkbutton, :label => "All Group Events", 
               :variable => v_group_events,
               :onvalue => 1, :offvalue => nil,
               :command => proc {
                 update_states_in_options()
		 update_display_events
                 update_display(@server_wid.to_s, @map_wid.to_s, get_states(),
				@display_events)
               } )

    update_checkbox(@box_active, @options[:show_active])
    update_checkbox(@box_success, @options[:show_success])
    update_checkbox(@box_fail, @options[:show_fail])
    update_checkbox(@box_inactive, @options[:show_warmup])
    update_checkbox(@box_preparation, @options[:show_preparation])

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
    @options_frame.grid :row => 0, :column => 0, :sticky => "nsew"
    TkGrid.rowconfigure( @app, 0, :weight => 0 )
    TkGrid.columnconfigure( @options_frame, 0, :weight => 0 )

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
      update_display(@server_wid.to_s, @map_wid.to_s, get_states(),
		     @display_events)
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
      update_display(@server_wid.to_s, @map_wid.to_s, get_states(),
		     @display_events)
    }
    wid.grid :row => 0, :column => 4

    ###########################################################################
    ###########################################################################

    @header_frame = Tk::Frame.new(@app) {
      background HEADER_COLOR
    }
    @header_frame.grid :row => 1, :column => 0, :sticky => "nsew"
    TkGrid.rowconfigure( @app, 1, :weight => 0 )
    TkGrid.columnconfigure( @header_frame, 0, :weight => 0 )


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

    label = Tk::Tile::Label.new(@header_frame) {
      text "Notify"
      anchor "w"
      width FIELD_WIDTH_NOTIFY + 4
      background HEADER_COLOR
    }
    label.grid :row => 0, :column => 3, :sticky => "nsew"

    label = Tk::Tile::Label.new(@header_frame) {
      text "Last Changed"
      anchor "w"
      width FIELD_WIDTH_LAST_CHANGED
      background HEADER_COLOR
    }
    label.grid :row => 0, :column => 4, :sticky => "nsew"


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

    update_display(@server_wid.to_s, @map_wid.to_s, get_states(),
		   @display_events)

    ###########################################################################

    @task_queue = Queue.new()
    @gui_queue = Queue.new()

    t = Thread.new {
      thread_do_update
    }

    Tk.after(1000, proc { gui_monitor })

  end	# initialize

end


# def error_msg_popup(title, msg)
#   msgBox = Tk.messageBox('type'    => "ok",
# 			 'icon'    => "error",
# 			 'title'   => title,
# 			 'message' => msg)
# end


if GW2EventExplorer::DEBUG then
  GW2::DebugLog.open_stream(GW2EventExplorer::DEBUGLOG_FILE)
  GW2::DebugLog.print "\n\n\n***** New log started at #{Time.now} *****\n\n"
end

begin
  gui = GW2EventExplorer.new()

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
