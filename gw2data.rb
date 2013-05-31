#! /usr/bin/env ruby
###############################################################################
#
# File:         gw2data.rb
# RCS:          $Header: $
# Description:  Ruby moudle for reading GW2 event data from anet and storing
#		it into a sqlite database
# Author:       Darryl Okahata
# Created:      Tue May 21 18:05:39 2013
# Modified:     Fri May 31 04:23:22 2013 (Darryl Okahata) darryl@fake.domain
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

require 'net/http'
require 'uri'
require 'json'
require 'zlib'
require 'monitor'
require 'sqlite3'
require 'csv'
require 'pp'

module GW2

  USER_AGENT = "GW2 Event Explorer 0.2 " + RUBY_PLATFORM

  STATE_ACTIVE = "Active"
  STATE_ACTIVE_NUM = 1
  STATE_SUCCESS = "Success"
  STATE_SUCCESS_NUM = 2
  STATE_FAIL = "Fail"
  STATE_FAIL_NUM = 3
  STATE_WARMUP = "Warmup"
  STATE_WARMUP_NUM = 4
  STATE_PREPARATION = "Preparation"
  STATE_PREPARATION_NUM = 5

  def GW2.state_to_int(state)
    i = 0
    if state == GW2::STATE_ACTIVE then
      i = GW2::STATE_ACTIVE_NUM
    elsif state == GW2::STATE_SUCCESS then
      i = GW2::STATE_SUCCESS_NUM
    elsif state == GW2::STATE_FAIL then
      i = GW2::STATE_FAIL_NUM
    elsif state == GW2::STATE_WARMUP || state == "Inactive" then
      i = GW2::STATE_WARMUP_NUM
    elsif state == GW2::STATE_PREPARATION then
      i = GW2::STATE_PREPARATION_NUM
    end
    return i
  end

  def GW2.int_to_state(i)
    if i == GW2::STATE_ACTIVE_NUM then
      state = GW2::STATE_ACTIVE
    elsif i == GW2::STATE_SUCCESS_NUM then
      state = GW2::STATE_SUCCESS
    elsif i == GW2::STATE_FAIL_NUM then
      state = GW2::STATE_FAIL
    elsif i == GW2::STATE_WARMUP_NUM then
      state = GW2::STATE_WARMUP
    elsif i == GW2::STATE_PREPARATION_NUM then
      state = GW2::STATE_PREPARATION
    else
      state = "Unknown"
    end
    return state
  end

  def GW2.add_parameter(str, param)
    if str.nil? or str.empty? then
      str = "?" + param
    else
      str = str + "&" + param
    end
    return str
  end

  def GW2.get_uri_json(uri)
    GW2::DebugLog.print "Getting: '#{uri}'\n"
    uri = URI(URI.encode(uri))

    http = Net::HTTP.new(uri.host, uri.port)

    use_ssl = uri.scheme == 'https'
    http.use_ssl = use_ssl
    if use_ssl then
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    req = Net::HTTP::Get.new(uri.to_s)

    req['User-Agent'] = USER_AGENT

    req['Accept'] = 'application/json'
    req['Accept-Encoding'] = 'gzip'

    response = nil
    http.start {
      response = http.request(req)
    }
    if response.code.to_i != 200 then
      code = response.code
      msg = response.message

      text = ""
      text << "Code = #{code}\n"
      text << "Message = #{msg}\n"
      response.each { |key, val|
        text << sprintf("%-14s = %-40.40s\n", key, val)
      }
      text << response.body
      text << "\n"

      raise HTTPexception(code, msg, text)
    end
    body = response.body
    if response['content-encoding'] == "gzip" then
      body = Zlib::GzipReader.new(StringIO.new(body.to_s)).read
    end
    return JSON.parse(body)
  end

  def GW2.get_names_id_mapping(uri)
    names = {}
    data = get_uri_json(uri)
    if data then
      data.each { |item|
        if item['id'].nil? then
          pp item
          raise "Huh?  Item id is nil?"
        end
        if item['name'].nil? then
          pp item
          raise "Huh?  Item name is nil?"
        end
        names[item['id']] = item['name']
      }
    end
    return names
  end

  def GW2.read_group_events_csv(file, event_array = {})
    CSV.foreach(file) { |row|
      event_array[row[0]] = :group
    }
    return event_array
  end


  #############################################################################
  #############################################################################

  class DebugLog

    DEBUG_DEBUG = true

    @@outstream = nil
    @@lock_mutex = Mutex.new

    def initialize
    end

    def DebugLog.active()
      return (not @@outstream.nil?)
    end

    def DebugLog.close_stream()
      @@lock_mutex.synchronize {
        if @@outstream and 
            @@outstream != STDOUT and @@outstream != STDERR then
          @@outstream.close()
        end
        @@outstream = nil
      }
    end

    def DebugLog.set_stream(fh)
      if fh then
        @@outstream = fh
      end
    end

    def DebugLog.open_stream(file)
      DebugLog.close_stream()
      #
      # This mutex locking should include close_stream(), above, but Mutex
      # isn't re-entrant.
      #
      @@lock_mutex.synchronize {
        fh = File.open(file, "a")
        DebugLog.set_stream(fh)
      }
    end

    def DebugLog.print (*args)
      if @@outstream then
        @@lock_mutex.synchronize {
          if DEBUG_DEBUG then
            STDOUT.print *args
          end
          @@outstream.print *args
          @@outstream.flush
        }
      end
    end

    def DebugLog.printf (*args)
      if @@outstream then
        @@lock_mutex.synchronize {
          if DEBUG_DEBUG then
            STDOUT.printf *args
          end
          @@outstream.printf *args
          @@outstream.flush
        }
      end
    end
  end		# DebugLog


  #############################################################################
  #############################################################################

  class EventItem
    attr_reader   :world_id, :map_id, :event_id, :generation, :last_changed
    attr_accessor :update_time

    @@event_names = nil
    @@map_names = nil
    @@world_names = nil
    @@generations = {}

    def EventItem.set_metadata(event_names, map_names, world_names)
      @@event_names = event_names
      @@map_names = map_names
      @@world_names = world_names
    end

    def EventItem.set_generations(generations)
      @@generations = generations
    end

    def EventItem.sorter(a, b)
      val = a.generation <=> b.generation
      if val == 0 then
        val = a.world <=> b.world
        if val == 0 then
          val = a.map <=> b.map
          if val == 0 then
            val = a.name <=> b.name
          end
        end
      else
        val = -val
      end
      return val
    end

    def EventItem.sort_list(data)
      return data.sort { |a,b| EventItem.sorter(a,b) }
    end

    def initialize(world_id, map_id, event_id, state, generation, last_changed)
      @world_id = world_id
      @map_id = map_id
      @event_id = event_id
      @state = state
      @generation = generation
      @update_time = @@generations[@generation]
      @last_changed = last_changed
    end

    def world
      return @@world_names[@world_id] || "<UNKNOWN WORLD>"
    end

    def map
      return @@map_names[@map_id] || "<UNKNOWN MAP>"
    end

    def name_raw
      return @@event_names[@event_id]
    end

    def name
      return name_raw || "<UNKNOWN EVENT>"
    end

    def state_num
      return @state
    end

    def state
      return GW2.int_to_state(@state)
    end

    def update_time
      if @@generations[@generation] then
        return Time.at(@@generations[@generation])
      end
      return Time.at(0)
    end

    def last_change_time
      return Time.at(@last_changed)
    end
  end		# EventItem


  #############################################################################
  #############################################################################

  class EventsSnapshot
    attr_reader		:update_time

    def initialize(events, update_time = nil)
      if update_time.nil? then
	update_time = Time.now
      end
      @update_time = update_time
      @events = events
      @events_index = {}
      @events.each { |event|
	if @events_index[event.event_id].nil? then
	  @events_index[event.event_id] = [ event ]
	else
	  @events_index[event.event_id] << event
	end
      }
    end

    def event(id, world = nil)
      e = nil
      events = @events_index[id]
      if events then
	events.each { |evt|
	  if world.nil? || evt.world_id == world then
	    e = evt
	    if world then
	      break
	    end
	  end
	}
      end
      return e
    end

    def world_events(world)
      events = []
      @events.each { |e|
	if e.world == world then
	  events << e
	end
      }
      return events
    end
  end		# EventsSnapshot


  #############################################################################
  #############################################################################

  class GW2Database

    class BadDBVersionException < Exception
      def initialize
	super
      end
    end

    CURRENT_DATABASE_VERSION = 1

    def get_version
      cmd = "PRAGMA user_version;"
      ver = @db.execute(cmd)
      if ver then
	ver = ver[0][0]
      else
      end
      return ver
    end

    def set_version(ver)
      cmd = "PRAGMA user_version = #{ver};"
      ver = @db.execute(cmd)
    end

    def get_tables
      result = []
      cmd = "SELECT tbl_name FROM sqlite_master WHERE type = 'table';"
      tables = @db.execute(cmd)
      if tables then
	tables.each { |entry|
	  result << entry[0]
	}
      end
      return result
    end

    def upgrade_db(current_db_ver)
      @db.transaction {
	if current_db_ver < 1 then
	  cmd = "ALTER TABLE event_data ADD COLUMN last_changed REAL DEFAULT 0;"
	  @db.execute(cmd)
	end
	set_version(CURRENT_DATABASE_VERSION)
      }
    end

    def set_event_logging(logging)
      @event_logging = logging
    end

    def initialize(filename, lang = nil)
      @lang = lang || ""

      @event_logging = false

      db_timeout = 60 * 1000	# In milliseconds
      db_retry = 500		# In milliseconds
      @db = SQLite3::Database.new(filename)
      @db.busy_timeout(db_retry)
      @db.busy_handler() { |data, retries|
	return (retries >= (db_timeout / db_retry))
      }

      tables = get_tables()
      @db.transaction {
	check_generation_table
	check_eventdata_table
	check_metadata_table("world_names", true)
	check_metadata_table("map_names", true)
	check_metadata_table("event_names")
      }

      if tables.empty? then
	set_version(CURRENT_DATABASE_VERSION)
      else
	current_db_ver = get_version()
	if current_db_ver < CURRENT_DATABASE_VERSION then
	  upgrade_db(current_db_ver)
	elsif current_db_ver > CURRENT_DATABASE_VERSION
	  raise BadDBVersionException
	end
      end

      # @current_generation = 0

      @event_names = {}
      @map_names = {}
      @world_names = {}

      @last_snapshot = nil

      @current_generation = 0
      @previous_generation = 0

      init
    end

    def init
      # We always update metadata at startup
      update_metadata
      load_metadata

      @current_generation = get_current_generation
      @previous_generation = 0
      update_generations
    end

    def check_metadata_table(table_name, id_is_integer = false)
      if id_is_integer then
        @db.execute("CREATE TABLE IF NOT EXISTS #{table_name} (id INTEGER PRIMARY KEY, name TEXT);")
      else
        @db.execute("CREATE TABLE IF NOT EXISTS #{table_name} (id TEXT PRIMARY KEY, name TEXT);")
      end
    end

    def update_metadata_table(data, table_name, keys_are_integer = false)
      @db.transaction {
        data.each { |id, name|
          if keys_are_integer then
            cmd = "INSERT OR REPLACE INTO #{table_name} (id,name) VALUES (#{id}, '#{name.gsub(/'/,"''")}');"
          else
            cmd = "INSERT OR REPLACE INTO #{table_name} (id,name) VALUES ('#{id}', '#{name.gsub(/'/,"''")}');"
          end
          @db.execute(cmd)
        }
      }
    end

    def load_a_metadata_table(table_name, keys_are_integer = false)
      result = {}
      cmd = "SELECT id,name FROM #{table_name};"
      data = @db.execute(cmd)
      if data then
        data.each { |item|
          if keys_are_integer then
            result[item[0].to_i] = item[1]
          else
            result[item[0]] = item[1]
          end
        }
      end
      return result
    end

    def update_generations
      @generations = {}
      cmd = "SELECT generation,update_time FROM generation_data;"
      data = @db.execute(cmd)
      if data and data.length > 0 then
        data.each { |item|
          @generations[item[0].to_i] = Time.at(item[1])
        }
      end
      EventItem.set_generations(@generations)
    end

    def need_metadata()
      return @world_names.empty? || @map_names.empty? || @event_names.empty?
    end

    def load_metadata()
      GW2::DebugLog.print "Trying to load metadata from db\n"
      @world_names = load_a_metadata_table("world_names", true)
      @map_names = load_a_metadata_table("map_names", true)
      @event_names = load_a_metadata_table("event_names")
      EventItem.set_metadata(@event_names, @map_names, @world_names)
    end

    def update_event_names
      @event_names = GW2.get_names_id_mapping("https://api.guildwars2.com/v1/event_names.json" + @lang)
      update_metadata_table(@event_names, "event_names")
    end

    def update_metadata
      GW2::DebugLog.print "Updating metadata from anet\n"

      update_event_names

      @map_names = GW2.get_names_id_mapping("https://api.guildwars2.com/v1/map_names.json" + @lang)
      update_metadata_table(@map_names, "map_names", true)

      @world_names = GW2.get_names_id_mapping("https://api.guildwars2.com/v1/world_names.json" + @lang)
      update_metadata_table(@world_names, "world_names", true)

      EventItem.set_metadata(@event_names, @map_names, @world_names)
    end

    def check_generation_table()
      @db.execute("CREATE TABLE IF NOT EXISTS generation_data (generation INTEGER PRIMARY KEY, update_time REAL);")
    end

    def check_eventdata_table()
      # We create both tables here.
      @db.execute("CREATE TABLE IF NOT EXISTS event_data (generation INTEGER, world INTEGER, map INTEGER, event_id TEXT, state INTEGER, last_changed REAL);")
      @db.execute("CREATE TABLE IF NOT EXISTS event_log_data (world INTEGER, map INTEGER, event_id TEXT, state INTEGER, last_changed REAL);")
    end

    def get_current_generation
      cmd = "SELECT generation FROM generation_data ORDER BY generation DESC LIMIT 1;"
      data = @db.execute(cmd)
      if data and data.length > 0 then
        data = data[0][0]
      else
        data = 0
      end
      return data
    end

    def update_eventdata(world = nil)
      GW2::DebugLog.print "update_eventdata(#{world})\n"
      update_log = false
      append = ""
      update_time = Time.now
      if world then
        world = world.to_s
      end
      if not world.nil? and not world.empty? then
        append = GW2.add_parameter(append, "world_id=#{world}")
      end

      # We can't necessarily use data from the last update, because, if the
      # world changes, we may have to go back more than one update to find the
      # data.  So, we have to use this expensive method.
      previous_events = get_eventdata(world)
      if previous_events && !previous_events.empty? then
	# The generation number should be the same for all previous events:
	previous_update_time = 
	  get_generation_update_time(previous_events[0].generation)
	previous_snapshot = EventsSnapshot.new(previous_events, 
					       previous_update_time)
      else
	previous_snapshot = nil
	previous_update_time = update_time
      end

      uri = "https://api.guildwars2.com/v1/events.json" + append
      data = GW2.get_uri_json(uri)
      if data then
        if data.empty? then
          GW2::DebugLog.print "***** EMPTY DATA RECEIVED\n"
        end
        @previous_generation = @current_generation
        @current_generation = @current_generation + 1
	log_updated = false
	s = Time.now
        @db.transaction {
          data['events'].each { |item|
            world = item['world_id'].to_i
            map = item['map_id'].to_i
            event_id = item['event_id']
            state = GW2.state_to_int(item['state'])

	    last_changed = update_time.to_f
	    if @event_logging then
	      update_log = true
	    end
	    if previous_snapshot then
	      previous_event = previous_snapshot.event(event_id, world)

	      # Note that events sometimes disappear and reappear from
	      # snapshots.  If this happens, the reappearing event gets marked
	      # as being changed (the last_changed state gets reset to the
	      # time that the event reappears).
	      #
	      # We probably want this, but it's unclear.

	      if previous_event then
		if previous_event.state_num == state then
		  last_changed = previous_event.last_changed
		  update_log = false
		end
	      end
	    else
	      # Don't update the log
	      update_log = false
	    end

            cmd = "INSERT OR REPLACE INTO event_data (generation,world,map,event_id,state,last_changed) VALUES ('#{@current_generation}',#{world},#{map},'#{event_id}','#{state}',#{last_changed});"
            @db.execute(cmd)

	    if update_log then
	      cmd = "INSERT OR REPLACE INTO event_log_data (world,map,event_id,state,last_changed) VALUES (#{world},#{map},'#{event_id}','#{state}',#{last_changed});"
	      @db.execute(cmd)
	      log_updated = true
	    end

	    #events << EventItem.new(world, map, event_id, state,
	    #			    @current_generation)
          }
          @db.execute("INSERT INTO generation_data (generation,update_time) VALUES ('#{@current_generation}',#{update_time.to_f});")
          #@db.execute("DROP INDEX IF EXISTS event_index;")
          @db.execute("CREATE INDEX IF NOT EXISTS event_index ON event_data (generation,world,map,event_id,state,last_changed);")
	  if log_updated then
	    @db.execute("CREATE INDEX IF NOT EXISTS event_log_index ON event_data (world,map,event_id,state,last_changed);")
	  end
	  @db.execute("REINDEX;")
	  @db.execute("ANALYZE;")
	  #snapshot = EventsSnapshot.new(events, update_time)
        }
        # @db.execute("VACUUM;")
	GW2::DebugLog.print "Transaction took #{(Time.now - s).to_s} sec\n"
      else
        GW2::DebugLog.print "***** NO DATA RECEIVED\n"
      end
      update_generations
      #return snapshot
      return nil
    end

    def world_id_from_name(name)
      id = nil
      @world_names.each { |world_id, world_name|
        if world_name == name then
          id = world_id.to_i
          break
        end
      }
      return id
    end

    def map_id_from_name(name)
      id = nil
      @map_names.each { |map_id, map_name|
        if map_name == name then
          id = map_id.to_i
          break
        end
      }
      return id
    end

    def world_name(id)
      return @world_names[id]
    end

    def map_name(id)
      return @map_names[id]
    end

    def event_name(id)
      return @event_names[id]
    end

    def event_ids
      return @event_names.keys
    end

    def get_world_names()
      return @world_names.values.sort
    end

    def get_map_names()
      return @map_names.values.sort
    end

    def get_world_info()
      return @world_names
    end

    def get_map_info()
      return @map_names
    end

    def append_selection(selection, constraint)
      if selection.nil? then
        selection = ""
      else
        selection << " AND "
      end
      selection << constraint
      return selection
    end

    def get_update_generations(world, limit = nil)
      if world.nil? || (world.is_a?(String) && world.empty?) ||
	  (world.is_a?(Fixnum) && (world <= 0)) then
	raise "Huh?"
      end
      generations = []
      limit_cmd = ""
      if limit then
	limit_cmd = "LIMIT #{limit}"
      end
      cmd = "SELECT DISTINCT generation FROM event_data WHERE world = #{world} ORDER BY generation DESC #{limit_cmd};"
      data = @db.execute(cmd)
      if data and data.size > 0 then
        data.each { |result|
          generations << result[0]
        }
      else
        generations << 0
      end
      return generations
    end

    def get_generation_update_time(generation)
      if generation > 0 && @generations[generation] then
	update_time = Time.at(@generations[generation])
      else
	update_time = Time.at(0)
      end
      return update_time
    end

    def get_update_times(world, generations = nil)
      update_times = []
      if generations.nil? then
	generations = get_update_generations(world)
      end
      generations.each { |generation|
	update_times << get_generation_update_time(generation)
      }
      return update_times
    end

    def get_last_update_generation(world)
      cmd = "SELECT DISTINCT generation FROM event_data WHERE world = #{world} ORDER BY generation DESC LIMIT 1;"
      #pp cmd
      data = @db.execute(cmd)
      if data and data.size > 0 then
        idx = data[0][0]
        generation = idx
      else
        generation = 0
      end
      return generation
    end

    def get_last_update_time(world)
      generation = get_last_update_generation(world)
      if generation > 0 then
        if @generations[generation] then
          update_time = Time.at(@generations[generation])
        else
          print "Huh?  Generation '#{generation}' has no time associated with it\n"
          update_time = Time.at(0)
        end
      else
        update_time = Time.at(0)
      end
      return update_time
    end

    def get_eventdata(world = nil, map = nil, event = nil, states = nil)
      s = Time.now

      worldspec = ""
      selection = ""

      if world then
        worldspec = "WHERE world = #{world}"
        selection << " AND (event_data.world = #{world})"
      end
      if map then
        selection << " AND (event_data.map = #{map})"
      end
      if event then
        selection << " AND (event_data.event_id = '#{event}')"
      end
      if states then
        if states.class == Array then
          if states.size > 0 then
            selection << " AND ("
            first = true
            states.each { |st|
              if not first then
                selection << " OR "
              end
              if st.class == String then
                st = GW2.state_to_int(st)
              end
              selection << "(state == #{st})"
              first = false
            }
            selection << ")"
          end
        else
          selection << " AND (state == #{states})"
        end
      end

      cmd =
"SELECT event_data.world,event_data.map,event_data.event_id,event_data.state,event_data.generation,event_data.last_changed FROM event_data INNER JOIN
(
   SELECT event_id, MAX(generation) as maxgeneration
   FROM event_data #{worldspec}
   GROUP BY event_id
) m
ON event_data.generation = m.maxgeneration
   AND event_data.event_id = m.event_id
   #{selection}
"

      #print cmd
      data = []
      @db.execute(cmd) { |item|
        world = item[0]
        map = item[1]
        event_id = item[2]
        state = item[3]
        generation = item[4]
	last_changed = item[5]

        newitem = EventItem.new(world, map, event_id, state, generation,
				last_changed)
        data << newitem
      }
      GW2::DebugLog.print "get_eventdata() took #{(Time.now - s).to_s} sec\n"
      return data
    end

    def delete_old_generations(generation)
      @db.transaction {
        cmd = "DELETE FROM event_data WHERE generation <= #{generation};"
        result = @db.execute(cmd)
        cmd = "DELETE FROM generation_data WHERE generation <= #{generation};"
        result = @db.execute(cmd)
      }
    end

    def vacuum
      @db.execute("VACUUM;")
    end

    def get_log_data
      data = []
      cmd = "SELECT world,map,event_id,state,last_changed FROM event_log_data;"
      results = @db.execute(cmd)
      if results then
	results.each { |column|
	  world = column[0]
	  map = column[1]
	  event_id = column[2]
	  state = column[3]
	  last_changed = column[4]

	  data << EventItem.new(world, map, event_id, state, 0, last_changed)
	}
      end
      return data
    end

    def dump_events_csv(stream = nil)
      if stream.nil? then
	stream = STDOUT
      end
      @event_names.each{ |k,v| 
	stream.print "\"#{k}\",\"#{v.gsub('"','""')}\"\n"
      }
    end
  end	# class GW2Database


  #############################################################################
  #############################################################################

  class EventManager
    include MonitorMixin

    ##########################################################################
    private

    ##########################################################################
    public

    def initialize(database_filename, enable_logging = false)
      super()	# needed to initialize MonitorMixin
      @lang = "?lang=fr"
      @lang = "?lang=de"
      @lang = ""

      @database = GW2Database.new(database_filename, @lang)
      if enable_logging then
	@database.set_event_logging(true)
      end
    end

    def db_synchronize
      # MonitorMixin's are re-entrant, yay!
      self.synchronize { yield }
    end

    def update_metadata
      @database.update_metadata
    end

    def update_eventdata(world = nil)
      return @database.update_eventdata(world)
    end

    def world_id_from_name(name)
      return @database.world_id_from_name(name)
    end

    def map_id_from_name(name)
      return @database.map_id_from_name(name)
    end

    def get_world_names()
      return @database.get_world_names()
    end

    def get_map_names()
      return @database.get_map_names()
    end

    def get_world_name(id)
      return @database.world_name(id)
    end

    def get_map_name(id)
      return @database.map_name(id)
    end

    def get_update_generations(world)
      return @database.get_update_generations(world)
    end

    def get_update_times(world)
      return @database.get_update_times(world)
    end

    def get_last_update_generation(world)
      return @database.get_last_update_generation(world)
    end

    def get_last_update_time(world)
      return @database.get_last_update_time(world)
    end

    def filter_events(world_id = nil, map_id = nil, event = nil, states = nil)
      return @database.get_eventdata(world_id, map_id, event, states)
    end

    def delete_old_generations(generation)
      @database.delete_old_generations(generation)
    end

    def vacuum
      @database.vacuum
    end

    def dump
      sorted_events = filter_events()
      sorted_events.each { |event|
        print "#{event.name} (map: #{event.map}, #{event.event_id})\n"
      }
    end

  end	# class EventManager


  #############################################################################
  #############################################################################

  class EventMatcher
    public

    def initialize
      @world = nil
      @map = nil
      @events = {}
      @types = nil
    end

    def set_world(world)
      @world = world.to_i
    end

    def set_map(map)
      if map then
	@map = map.to_i
      else
	@map = nil
      end
    end

    def set_types(types)
      if types.nil? || types.empty? then
	@types = nil
      else
	@types = []
	types.each { |type|
	  @types[type] = true
	}
      end
    end

    def set_events(events, add = nil)
      if events.class == Array then
	if not add then
	  @events = {}
	end
	events.each { |event|
	  @events[event] = true
	}
      elsif events.class == Hash then
	if add then
	  events.each { |event|
	    @events[event] = true
	  }
	else
	  @events = events
	end
      elsif events.class == String then
	if not add then
	  @events = {}
	end
	@events[events] = true
      elsif
	raise "Huh? (#{events.class})"
      end
    end

    def match(event)	# event is of type EventItem
      if @events && @events[event.event_id] then
	return true
      end
      if @world && @world != event.world_id then
	return false
      end
      if @map && @map != event.map_id then
	return false
      end
      if @types && ! @types[event.state_num] then
	return false
      end
      return true
    end

    def filter_events(events)
      data = []
      events.each { |event|
	if match(event) then
	  data << event
	end
      }
      return (data)
    end
    
  end	# class EventMatcher

end	# End of module


if $0 == __FILE__ then
  ############################################################################
  # For testing.
  ############################################################################
  if false then
    d = GW2::GW2Database.new("gw2events.sqlite")
    d.dump_events_csv()
  end
  if false then
    d = GW2::GW2Database.new("gw2events.sqlite")
    s = Time.now
    e = d.get_eventdata()
    print "Time = #{(Time.now - s).to_s}\n"
    print "count = #{e.size}\n"
    pp e
    exit 0
  end
  if false then
    s = Time.now
    d = GW2::GW2Database.new("gw2events.sqlite")
    d.get_last_update_time(2003)
    print "Time = #{(Time.now - s).to_s}\n"
    exit 0
  end
  if false then

    #require 'profiler'

    s = Time.now
    m = GW2::EventMatcher.new

    #Profiler__::start_profile

    CSV.foreach("group_events.csv") { |row|
      event = row[0]
      m.set_events(event, true)
    }
    print "CSV load time = #{(Time.now - s).to_s}\n"

    s1 = Time.now
    d = GW2::EventManager.new("gw2events.sqlite")
    data = []
    results = d.filter_events(2003)
    print "Event extraction time = #{(Time.now - s1).to_s}\n"
    s1 = Time.now
    results.each { |event|
      if m.match(event) then
	data << event
      end
    }
    data = GW2::EventItem.sort_list(data)
    print "Filtering time = #{(Time.now - s1).to_s}\n"


    print "Total Time = #{(Time.now - s).to_s}\n"
    #Profiler__::stop_profile
    #Profiler__::print_profile(STDOUT)
    #pp data
    data.each { |event|
      print "Name: #{event.name}\n"
    }
    exit 0
  end
  if false then
    d = GW2::EventManager.new("gw2events.sqlite")
    s = Time.now
    #d.update_metadata
    #d.update_eventdata
    #d.update_eventdata(2003)
    #data = d.filter_events(2003, 15, nil, [1,2])
    data = d.filter_events(2003)
    #d.get_last_update_time(2003)
    #pp data
    print "Time = #{(Time.now - s).to_s}\n"
    #pp data.size
  end
  if true then
    d = GW2::GW2Database.new("gw2events.sqlite")
    data = d.get_log_data
    if data and not data.empty? then
      data.each { |event|
	print "#{event.name} in #{event.map}, #{event.state} at #{event.last_change_time} (#{event.event_id})\n"
      }
    end
  end
end
