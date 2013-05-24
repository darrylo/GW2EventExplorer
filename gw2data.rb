#! /usr/bin/env ruby
###############################################################################
#
# File:         gw2data.rb
# RCS:          $Header: $
# Description:  Ruby moudle for reading GW2 event data from anet and storing
#		it into a sqlite database
# Author:       Darryl Okahata
# Created:      Tue May 21 18:05:39 2013
# Modified:     Fri May 24 10:10:29 2013 (Darryl Okahata) darryl@fake.domain
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
require 'pp'

module GW2

  USER_AGENT = "GW2 Event Explorer 0.1 " + RUBY_PLATFORM

  STATE_ACTIVE = "Active"
  STATE_SUCCESS = "Success"
  STATE_FAIL = "Fail"
  STATE_WARMUP = "Warmup"
  STATE_PREPARATION = "Preparation"

  def GW2.state_to_int(state)
    i = 0
    if state == GW2::STATE_ACTIVE then
      i = 1
    elsif state == GW2::STATE_SUCCESS then
      i = 2
    elsif state == GW2::STATE_FAIL then
      i = 3
    elsif state == GW2::STATE_WARMUP || state == "Inactive" then
      i = 4
    elsif state == GW2::STATE_PREPARATION then
      i = 5
    end
    return i
  end

  def GW2.int_to_state(i)
    if i == 1 then
      state = GW2::STATE_ACTIVE
    elsif i == 2 then
      state = GW2::STATE_SUCCESS
    elsif i == 3 then
      state = GW2::STATE_FAIL
    elsif i == 4 then
      state = GW2::STATE_WARMUP
    elsif i == 5 then
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
  end

  class EventItem
    attr_reader   :world_id, :map_id, :event_id, :generation

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

    def initialize(world_id, map_id, event_id, state, generation)
      @world_id = world_id
      @map_id = map_id
      @event_id = event_id
      @state = state
      @generation = generation
    end

    def world
      return @@world_names[@world_id] || "<UNKNOWN WORLD>"
    end

    def map
      return @@map_names[@map_id] || "<UNKNOWN MAP>"
    end

    def name
      return @@event_names[@event_id] || "<UNKNOWN EVENT>"
    end

    def state
      return GW2.int_to_state(@state)
    end

    def update_time
      if @@generatations[@generation] then
        return Time.at(@@generatations[@generation])
      end
      return Time.at(0)
    end

  end

  class GW2Database

    def initialize(filename, lang = nil)
      @db = SQLite3::Database.new(filename)
      @lang = lang || ""

      # @current_generation = 0

      @event_names = {}
      @map_names = {}
      @world_names = {}
      load_metadata
      if need_metadata then
        GW2::DebugLog.print "Need metadata\n"
        update_metadata
        load_metadata
      end
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
      check_metadata_table(table_name, keys_are_integer)
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
      check_metadata_table(table_name, keys_are_integer)
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
      check_generation_table
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

    def update_metadata
      GW2::DebugLog.print "Updating metadata from anet\n"
      @event_names = GW2.get_names_id_mapping("https://api.guildwars2.com/v1/event_names.json" + @lang)
      update_metadata_table(@event_names, "event_names")

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
      @db.execute("CREATE TABLE IF NOT EXISTS event_data (generation INTEGER, world INTEGER, map INTEGER, event_id TEXT, state INTEGER);")
    end

    def get_current_generation
      check_generation_table
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
      append = ""
      update_time = Time.now
      if world then
        world = world.to_s
      end
      if not world.nil? and not world.empty? then
        append = GW2.add_parameter(append, "world_id=#{world}")
      end
      uri = "https://api.guildwars2.com/v1/events.json" + append
      data = GW2.get_uri_json(uri)
      if data then
        if data.empty? then
          GW2::DebugLog.print "***** EMPTY DATA RECEIVED\n"
        end
        check_eventdata_table
        check_generation_table
        @previous_generation = @current_generation
        @current_generation = @current_generation + 1
        @db.transaction {
          data['events'].each { |item|
            world = item['world_id'].to_i
            map = item['map_id'].to_i
            event_id = item['event_id']
            state = GW2.state_to_int(item['state'])

            cmd = "INSERT OR REPLACE INTO event_data (generation,world,map,event_id,state) VALUES ('#{@current_generation}',#{world},#{map},'#{event_id}','#{state}');"
            @db.execute(cmd)
          }
          @db.execute("DROP INDEX IF EXISTS event_index;")
          @db.execute("CREATE INDEX event_index ON event_data (generation,world,map,event_id,state);")
          @db.execute("INSERT INTO generation_data (generation,update_time) VALUES ('#{@current_generation}',#{update_time.to_f});")
        }
        # @db.execute("VACUUM;")
      else
        GW2::DebugLog.print "***** NO DATA RECEIVED\n"
      end
      update_generations
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

    def get_update_generations(world)
      check_eventdata_table()
      generations = []
      cmd = "SELECT DISTINCT generation FROM event_data WHERE world = #{world} ORDER BY generation DESC;"
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

    def get_update_times(world)
      update_times = []
      generations = get_update_generations(world)
      generations.each { |generation|
        if generation > 0 then
          update_times << Time.at(@generations[generation])
        else
          update_times << Time.at(0)
        end
      }
      return update_times
    end

    def get_last_update_generation(world)
      check_eventdata_table()
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

    def get_eventdata(world = nil, map = nil, event = nil, states = nil, all_events = false)
      check_eventdata_table

#       selection = nil
#       if not all_events then
#         selection = append_selection(selection,
#                                      "(generation == #{@current_generation})")
#       end
#       if world then
#         selection = append_selection(selection,
#                                      "(world == #{world})")
#       end
#       if map then
#         selection = append_selection(selection,
#                                      "(map == #{map})")
#       end
#       if event then
#         selection = append_selection(selection,
#                                      "(event_id == '#{event}')")
#       end
#       if states then
#         if states.class == Array then
#           if states.size > 0 then
#             if selection.nil? then
#               selection = "WHERE ("
#             else
#               selection << " AND ("
#             end
#             first = true
#             states.each { |st|
#               if not first then
#                 selection << " OR "
#               end
#               if st.class == String then
#                 st = GW2.state_to_int(st)
#               end
#               selection << "(state == #{st})"
#               first = false
#             }
#             selection << ")"
#           end
#         else
#           selection << "(state == #{states})"
#         end
#       end
#       cmd = "SELECT world,map,event_id,state,generation FROM event_data INDEXED BY event_index #{selection};"

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
"SELECT event_data.world,event_data.map,event_data.event_id,event_data.state,event_data.generation FROM event_data INNER JOIN
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

        newitem = EventItem.new(world, map, event_id, state, generation)
        data << newitem
      }
      data.sort! { |a,b| EventItem.sorter(a,b) }
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
  end

  class EventManager
    include MonitorMixin

    ##########################################################################
    private

    ##########################################################################
    public

    def initialize(database_filename)
      super()	# needed to initialize MonitorMixin
      @lang = "?lang=fr"
      @lang = "?lang=de"
      @lang = ""

      @database = GW2Database.new(database_filename, @lang)
    end

    def db_synchronize
      # MonitorMixin's are re-entrant, yay!
      self.synchronize { yield }
    end

    def update_metadata
      @database.update_metadata
    end

    def update_eventdata(world = nil)
      @database.update_eventdata(world)
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

  end

end


if $0 == __FILE__ then
  # For testing.
  if true
    s = Time.now
    d = GW2::GW2Database.new("d:/gw2events.sqlite")
    d.get_last_update_time(2003)
    print "Time = #{(Time.now - s).to_s}\n"
    exit 0
  end
  d = GW2::EventManager.new("d:/gw2events.sqlite")
  s = Time.now
  d.update_metadata
  d.update_eventdata
  #d.update_eventdata(2003)
  #data = d.filter_events(2003, 15, nil, [1,2])
  #d.get_last_update_time(2003)
  #d.dump
  print "Time = #{(Time.now - s).to_s}\n"
  #pp data.size
end
