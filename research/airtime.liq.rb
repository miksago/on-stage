%include "/etc/airtime/liquidsoap.cfg"

set("log.file.path", log_file)
set("server.telnet", true)
set("server.telnet.port", 1234)
set("init.daemon.pidfile.path", "/var/run/airtime-liquidsoap.pid")

%include "library/pervasives.liq"

#Dynamic source list
#dyn_sources = ref []
webstream_enabled = ref false

time = ref string_of(gettimeofday())

#live stream setup
set("harbor.bind_addr", "0.0.0.0")

current_dyn_id = ref '-1'

pypo_data = ref '0'
stream_metadata_type = ref 0
default_dj_fade = ref 0.
station_name = ref ''
show_name = ref ''

dynamic_metadata_callback = ref fun (s) -> begin () end

s1_connected = ref ''
s2_connected = ref ''
s3_connected = ref ''
s1_namespace = ref ''
s2_namespace = ref ''
s3_namespace = ref ''
just_switched = ref false

def notify(m)
  command = "/usr/lib/airtime/pypo/bin/liquidsoap_scripts/notify.sh --media-id=#{m['schedule_table_id']} &"
  log(command)
  system(command)
end

def notify_queue(m)
  f = !dynamic_metadata_callback
  ignore(f(m))
  notify(m)
end

def notify_stream(m)
  json_str = string.replace(pattern="\n",(fun (s) -> ""), json_of(m))
  #if a string has a single apostrophe in it, let's comment it out by ending the string before right before it
  #escaping the apostrophe, and then starting a new string right after it. This is why we use 3 apostrophes.
  json_str = string.replace(pattern="'",(fun (s) -> "'\''"), json_str)
  command = "/usr/lib/airtime/pypo/bin/liquidsoap_scripts/notify.sh --webstream='#{json_str}' --media-id=#{!current_dyn_id} &"
  
  if !current_dyn_id != "-1" then
    log(command)
    system(command)
  end
end

# A function applied to each metadata chunk
def append_title(m) =  
  log("Using stream_format #{!stream_metadata_type}")

  if list.mem_assoc("mapped", m) then
    #protection against applying this function twice. It shouldn't be happening
    #and bug file with Liquidsoap.
    m
  else
      if !stream_metadata_type == 1 then
        [("title", "#{!show_name} - #{m['artist']} - #{m['title']}"), ("mapped", "true")]
      elsif !stream_metadata_type == 2 then
        [("title", "#{!station_name} - #{!show_name}"), ("mapped", "true")]
      else
        [("title", "#{m['artist']} - #{m['title']}"), ("mapped", "true")]
      end
  end
end

def crossfade_airtime(s)
  #duration is automatically overwritten by metadata fields passed in
  #with audio
  s = fade.in(type="log", duration=0., s)
  s = fade.out(type="log", duration=0., s)
  fader = fun (a,b) -> add(normalize=false,[b,a])
  cross(fader,s)
end

def transition(a,b) =
  log("transition called...")
  add(normalize=false,
     [ sequence([ blank(duration=0.01),
                   fade.initial(duration=!default_dj_fade, b) ]),
        fade.final(duration=!default_dj_fade, a) ])
end

# we need this function for special transition case(from default to queue)
# we don't want the trasition fade to have effect on the first song that would
# be played siwtching out of the default(silent) source
def transition_default(a,b) =
  log("transition called...")
  if !just_switched then
      just_switched := false
      add(normalize=false,
         [ sequence([ blank(duration=0.01),
                       fade.initial(duration=!default_dj_fade, b) ]),
            fade.final(duration=!default_dj_fade, a) ])
  else
    just_switched := false
    b
  end
end


# Define a transition that fades out the
# old source, adds a single, and then 
# plays the new source
def to_live(old,new) = 
  # Fade out old source
  old = fade.final(old)
  # Compose this in sequence with
  # the new source
  sequence([old,new])
end


def output_to(output_type, type, bitrate, host, port, pass, mount_point, url, description, genre, user, s, stream, connected, name, channels) =
    source = ref s
    def on_error(msg)
        connected := "false"
        command = "/usr/lib/airtime/pypo/bin/liquidsoap_scripts/notify.sh --error='#{msg}' --stream-id=#{stream} --time=#{!time} &"
        system(command)
        log(command)
        5.
    end
    def on_connect()
        connected := "true"
        command = "/usr/lib/airtime/pypo/bin/liquidsoap_scripts/notify.sh --connect --stream-id=#{stream} --time=#{!time} &"
        system(command)
        log(command)
    end

    stereo = (channels == "stereo")

    if output_type == "icecast" then
        user_ref = ref user
        if user == "" then
            user_ref := "source"
        end
        output_mono = output.icecast(host = host,
                    port = port,
                    password = pass,
                    mount = mount_point,
                    fallible = true,
                    url = url,
                    description = description,
                    name = name,
                    genre = genre,
                    user = !user_ref,
                    on_error = on_error,
                    on_connect = on_connect)

        output_stereo = output.icecast(host = host,
                    port = port,
                    password = pass,
                    mount = mount_point,
                    fallible = true,
                    url = url,
                    description = description,
                    name = name,
                    genre = genre,
                    user = !user_ref,
                    on_error = on_error,
                    on_connect = on_connect)
        if type == "mp3" then
            %include "mp3.liq"
        end
        if type == "ogg" then
            %include "ogg.liq"
        end

        %ifencoder %opus
        if type == "opus" then
            %include "opus.liq"
        end
        %endif

        %ifencoder %aac
        if type == "aac" then
            %include "aac.liq"
        end
        %endif

        %ifencoder %aacplus
        if type == "aacplus" then
            %include "aacplus.liq"
        end
        %endif

        %ifencoder %fdkaac
        if type == "fdkaac" then
            %include "fdkaac.liq"
        end
        %endif
    else
        user_ref = ref user
        if user == "" then
            user_ref := "source"
        end

        output_mono = output.shoutcast(id = "shoutcast_stream_#{stream}",
                    host = host,
                    port = port,
                    password = pass,
                    fallible = true,
                    url = url,
                    genre = genre,
                    name = description,
                    user = !user_ref,
                    on_error = on_error,
                    on_connect = on_connect)

        output_stereo = output.shoutcast(id = "shoutcast_stream_#{stream}",
                    host = host,
                    port = port,
                    password = pass,
                    fallible = true,
                    url = url,
                    genre = genre,
                    name = description,
                    user = !user_ref,
                    on_error = on_error,
                    on_connect = on_connect)

        if type == "mp3" then
            %include "mp3.liq"
        end

        %ifencoder %aac
        if type == "aac" then
            %include "aac.liq"
        end
        %endif
        
        %ifencoder %aacplus
        if type == "aacplus" then
            %include "aacplus.liq"
        end
        %endif
    end
end

# Add a skip function to a source
# when it does not have one
# by default
#def add_skip_command(s)
# # A command to skip
#  def skip(_)
#    # get playing (active) queue and flush it
#    l = list.hd(server.execute("queue.secondary_queue"))
#    l = string.split(separator=" ",l)
#    list.iter(fun (rid) -> ignore(server.execute("queue.remove #{rid}")), l)
#
#    l = list.hd(server.execute("queue.primary_queue"))
#    l = string.split(separator=" ", l)
#    if list.length(l) > 0 then
#      source.skip(s)
#      "Skipped"
#    else
#      "Not skipped"
#    end
#  end
# # Register the command:
# server.register(namespace="source",
#                 usage="skip",
#                 description="Skip the current song.",
#                 "skip",fun(s) -> begin log("source.skip") skip(s) end)
#end

def clear_queue(s)
    source.skip(s)
end

def set_dynamic_source_id(id) =
    current_dyn_id := id 
    string_of(!current_dyn_id)
end

def get_dynamic_source_id() =
    string_of(!current_dyn_id)
end

#cc-4633


# NOTE
# A few values are hardcoded and may be dependent:
#  - the delay in gracetime is linked with the buffer duration of input.http
#    (delay should be a bit less than buffer)
#  - crossing duration should be less than buffer length
#    (at best, a higher duration will be ineffective)

# HTTP input with "restart" command that waits for "stop" to be effected
# before "start" command is issued. Optionally it takes a new URL to play,
# which makes it a convenient replacement for "url".
# In the future, this may become a core feature of the HTTP input.
# TODO If we stop and restart quickly several times in a row,
#   the data bursts accumulate and create buffer overflow.
#   Flushing the buffer on restart could be a good idea, but
#   it would also create an interruptions while the buffer is
#   refilling... on the other hand, this would avoid having to
#   fade using both cross() and switch().
def input.http_restart(~id,~initial_url="http://dummy/url")

  source = audio_to_stereo(input.http(buffer=5.,max=15.,id=id,autostart=false,initial_url))

  def stopped()
    "stopped" == list.hd(server.execute("#{id}.status"))
  end

  server.register(namespace=id,
                  "restart",
                  usage="restart [url]",
                  fun (url) -> begin
                    if url != "" then
                      log(string_of(server.execute("#{id}.url #{url}")))
                    end
                    log(string_of(server.execute("#{id}.stop")))
                    add_timeout(0.5,
                      { if stopped() then
                          log(string_of(server.execute("#{id}.start"))) ;
                          (-1.)
                        else 0.5 end})
                    "OK"
                  end)

  # Dummy output should be useless if HTTP stream is meant
  # to be listened to immediately. Otherwise, apply it.
  #
  # output.dummy(fallible=true,source)

  source

end

# Transitions between URL changes in HTTP streams.
def cross_http(~debug=true,~http_input_id,source)

  id = http_input_id
  last_url = ref ""
  change = ref false

  def on_m(m)
    notify_stream(m)
    changed = m["source_url"] != !last_url
    log("URL now #{m['source_url']} (change: #{changed})")
    if changed then
      if !last_url != "" then change := true end
      last_url := m["source_url"]
    end
  end

  # We use both metadata and status to know about the current URL.
  # Using only metadata may be more precise is crazy corner cases,
  # but it's also asking too much: the metadata may not pass through
  # before the crosser is instantiated.
  # Using only status in crosser misses some info, eg. on first URL.
  source = on_metadata(on_m,source)

  cross_d = 3.

  def crosser(a,b)
    url = list.hd(server.execute('#{id}.url'))
    status = list.hd(server.execute('#{id}.status'))
    on_m([("source_url",url)])
    if debug then
      log("New track inside HTTP stream")
      log("  status: #{status}")
      log("  need to cross: #{!change}")
      log("  remaining #{source.remaining(a)} sec before, \
             #{source.remaining(b)} sec after")
    end
    if !change then
      change := false
      # In principle one should avoid crossing on a live stream
      # it'd be okay to do it here (eg. use add instead of sequence)
      # because it's only once per URL, but be cautious.
      sequence([fade.out(duration=cross_d,a),fade.in(b)])
    else
      # This is done on tracks inside a single stream.
      # Do NOT cross here or you'll gradually empty the buffer!
      sequence([a,b])
    end
  end

  # Setting conservative=true would mess with the delayed switch below
  cross(duration=cross_d,conservative=false,crosser,source)

end

# Custom fallback between http and default source with fading of
# beginning and end of HTTP stream.
# It does not take potential URL changes into account, as long as
# they do not interrupt streaming (thanks to the HTTP buffer).
def http_fallback(~http_input_id,~http,~default)

  id = http_input_id

  # We use a custom switching predicate to trigger switching (and thus,
  # transitions) before the end of a track (rather, end of HTTP stream).
  # It is complexified because we don't want to trigger switching when
  # HTTP disconnects for just an instant, when changing URL: for that
  # we use gracetime below.

  def gracetime(~delay=3.,f)
    last_true = ref 0.
    { if f() then
        last_true := gettimeofday()
        true
      else
        gettimeofday() < !last_true+delay
      end }
  end

  def connected()
    status = list.hd(server.execute("#{id}.status"))
    not(list.mem(status,["polling","stopped"]))
  end
  connected = gracetime(connected)

  def to_live(a,b) =
    log("TRANSITION to live")
    add(normalize=false,
        [fade.initial(b),fade.final(a)])
  end
  def to_static(a,b) =
    log("TRANSITION to static")
    sequence([fade.out(a),fade.initial(b)])
  end

  switch(
    track_sensitive=false,
    transitions=[to_live,to_static],
    [(# make sure it is connected, and not buffering
      {connected() and source.is_ready(http) and !webstream_enabled}, http),
     ({true},default)])

end

sources = ref []
source_id = ref 0

def create_source()
    l = request.equeue(id="s#{!source_id}", length=0.5)

    l = audio_to_stereo(id="queue_src", l)
    l = cue_cut(l)
    l = amplify(1., override="replay_gain", l)

    # the crossfade function controls fade in/out
    l = crossfade_airtime(l)

    l = on_metadata(notify_queue, l)
    sources := list.append([l], !sources)
    server.register(namespace="queues",
                "s#{!source_id}_skip",
                fun (s) -> begin log("queues.s#{!source_id}_skip") 
                    clear_queue(l) 
                    "Done" 
                end)
    source_id := !source_id + 1
end

create_source()
create_source()
create_source()
create_source()

create_source()
create_source()
create_source()
create_source()

queue = add(!sources, normalize=false)

pair = insert_metadata(queue)
dynamic_metadata_callback := fst(pair)
queue = snd(pair)

output.dummy(fallible=true, queue)

http = input.http_restart(id="http")
http = cross_http(http_input_id="http",http)
output.dummy(fallible=true, http)
stream_queue = http_fallback(http_input_id="http", http=http, default=queue)
stream_queue = map_metadata(update=false, append_title, stream_queue)

ignore(output.dummy(stream_queue, fallible=true))

server.register(namespace="vars",
                "pypo_data",
                fun (s) -> begin log("vars.pypo_data") pypo_data := s "Done" end)
server.register(namespace="vars",
                "stream_metadata_type",
                fun (s) -> begin log("vars.stream_metadata_type") stream_metadata_type := int_of_string(s) s end)
server.register(namespace="vars",
                "show_name",
                fun (s) -> begin log("vars.show_name") show_name := s s end)
server.register(namespace="vars",
                "station_name",
                fun (s) -> begin log("vars.station_name") station_name := s s end)
server.register(namespace="vars",
                "bootup_time",
                fun (s) -> begin log("vars.bootup_time") time := s s end)
server.register(namespace="streams",
                "connection_status",
                fun (s) -> begin log("streams.connection_status") "1:#{!s1_connected},2:#{!s2_connected},3:#{!s3_connected}" end)
server.register(namespace="vars",
                "default_dj_fade",
                fun (s) -> begin log("vars.default_dj_fade") default_dj_fade := float_of_string(s) s end)

server.register(namespace="dynamic_source",
                description="Enable webstream output",
                usage='start',
                "output_start",
                fun (s) -> begin log("dynamic_source.output_start")
                    notify([("schedule_table_id", !current_dyn_id)])
                    webstream_enabled := true "enabled" end)
server.register(namespace="dynamic_source",
                description="Enable webstream output",
                usage='stop',
                "output_stop",
                fun (s) -> begin log("dynamic_source.output_stop") webstream_enabled := false "disabled" end)

server.register(namespace="dynamic_source",
                description="Set the streams cc_schedule row id",
                usage="id <id>",
                "id",
                fun (s) -> begin log("dynamic_source.id") set_dynamic_source_id(s) end)

server.register(namespace="dynamic_source",
                description="Get the streams cc_schedule row id",
                usage="get_id",
                "get_id",
                fun (s) -> begin log("dynamic_source.get_id") get_dynamic_source_id() end)

#server.register(namespace="dynamic_source",
#                description="Start a new dynamic source.",
#                usage="start <uri>",
#                "read_start",
#                fun (uri) -> begin log("dynamic_source.read_start") begin_stream_read(uri) end)
#server.register(namespace="dynamic_source",
#                description="Stop a dynamic source.",
#                usage="stop <id>",
#                "read_stop",
#                fun (s) -> begin log("dynamic_source.read_stop") stop_stream_read(s) end)

#server.register(namespace="dynamic_source",
#                description="Stop a dynamic source.",
#                usage="stop <id>",
#                "read_stop_all",
#                fun (s) -> begin log("dynamic_source.read_stop") destroy_dynamic_source_all() end)

default = amplify(id="silence_src", 0.00001, noise())
ref_off_air_meta = ref off_air_meta
if !ref_off_air_meta == "" then
    ref_off_air_meta := "Airtime - offline"
end
default = rewrite_metadata([("title", !ref_off_air_meta)], default)
ignore(output.dummy(default, fallible=true))

master_dj_enabled = ref false
live_dj_enabled = ref false
scheduled_play_enabled = ref false

def make_master_dj_available()
    master_dj_enabled := true
end

def make_master_dj_unavailable()
    master_dj_enabled := false
end

def make_live_dj_available()
    live_dj_enabled := true
end

def make_live_dj_unavailable()
    live_dj_enabled := false
end

def make_scheduled_play_available()
    scheduled_play_enabled := true
    just_switched := true
end

def make_scheduled_play_unavailable()
    scheduled_play_enabled := false
end

def update_source_status(sourcename, status) =
    command = "/usr/lib/airtime/pypo/bin/liquidsoap_scripts/notify.sh --source-name=#{sourcename} --source-status=#{status} &"
    system(command)
    log(command)
end

def live_dj_connect(header) =
    update_source_status("live_dj", true)
end

def live_dj_disconnect() =
    update_source_status("live_dj", false)
end

def master_dj_connect(header) =
    update_source_status("master_dj", true)
end

def master_dj_disconnect() =
    update_source_status("master_dj", false)
end

#auth function for live stream
def check_master_dj_client(user,password) =
    log("master connected")
    #get the output of the php script
    ret = get_process_lines("python /usr/lib/airtime/pypo/bin/liquidsoap_scripts/liquidsoap_auth.py --master #{user} #{password}")
    #ret has now the value of the live client (dj1,dj2, or djx), or "ERROR"/"unknown" ...
    ret = list.hd(ret)

    #return true to let the client transmit data, or false to tell harbor to decline
    ret == "True"
end

def check_dj_client(user,password) =
    log("live dj connected")
    #get the output of the php script
    ret = get_process_lines("python /usr/lib/airtime/pypo/bin/liquidsoap_scripts/liquidsoap_auth.py --dj #{user} #{password}")
    #ret has now the value of the live client (dj1,dj2, or djx), or "ERROR"/"unknown" ...
    hd = list.hd(ret)
    log("Live DJ authenticated: #{hd}")
    hd == "True"
end

s = switch(id="schedule_noise_switch",
            track_sensitive=false,
            transitions=[transition_default, transition],
            [({!scheduled_play_enabled}, stream_queue), ({true}, default)]
    )

s = if dj_live_stream_port != 0 and dj_live_stream_mp != "" then
    dj_live =
        audio_to_stereo(
            input.harbor(id="live_dj_harbor",
                dj_live_stream_mp,
                port=dj_live_stream_port,
                auth=check_dj_client,
                max=40.,
                on_connect=live_dj_connect,
                on_disconnect=live_dj_disconnect))

    ignore(output.dummy(dj_live, fallible=true))

    switch(id="show_schedule_noise_switch",
            track_sensitive=false,
            transitions=[transition, transition],
            [({!live_dj_enabled}, dj_live), ({true}, s)]
        )
else
    s
end

s = if master_live_stream_port != 0 and master_live_stream_mp != "" then
    master_dj =
        audio_to_stereo(
            input.harbor(id="master_harbor",
                master_live_stream_mp,
                port=master_live_stream_port,
                auth=check_master_dj_client,
                max=40.,
                on_connect=master_dj_connect,
                on_disconnect=master_dj_disconnect))

    ignore(output.dummy(master_dj, fallible=true))

    switch(id="master_show_schedule_noise_switch",
            track_sensitive=false,
            transitions=[transition, transition],
            [({!master_dj_enabled}, master_dj), ({true}, s)]
        )
else
    s
end


# Attach a skip command to the source s:
#add_skip_command(s)

server.register(namespace="streams",
    description="Stop Master DJ source.",
    usage="master_dj_stop",
    "master_dj_stop",
    fun (s) -> begin log("streams.master_dj_stop") make_master_dj_unavailable() "Done." end)
server.register(namespace="streams",
    description="Start Master DJ source.",
    usage="master_dj_start",
    "master_dj_start",
    fun (s) -> begin log("streams.master_dj_start") make_master_dj_available() "Done." end)
server.register(namespace="streams",
    description="Stop Live DJ source.",
    usage="live_dj_stop",
    "live_dj_stop",
    fun (s) -> begin log("streams.live_dj_stop") make_live_dj_unavailable() "Done." end)
server.register(namespace="streams",
    description="Start Live DJ source.",
    usage="live_dj_start",
    "live_dj_start",
    fun (s) -> begin log("streams.live_dj_start") make_live_dj_available() "Done." end)
server.register(namespace="streams",
    description="Stop Scheduled Play source.",
    usage="scheduled_play_stop",
    "scheduled_play_stop",
    fun (s) -> begin log("streams.scheduled_play_stop") make_scheduled_play_unavailable() "Done." end)
server.register(namespace="streams",
    description="Start Scheduled Play source.",
    usage="scheduled_play_start",
    "scheduled_play_start",
    fun (s) -> begin log("streams.scheduled_play_start") make_scheduled_play_available() "Done." end)

if output_sound_device then
    success = ref false

    log(output_sound_device_type)

    %ifdef output.alsa
  if output_sound_device_type == "ALSA" then
    ignore(output.alsa(s))
        success := true
  end
  %endif

  %ifdef output.ao
  if output_sound_device_type == "AO" then
    ignore(output.ao(s))
        success := true
  end
  %endif

  %ifdef output.oss
  if output_sound_device_type == "OSS" then
        ignore(output.oss(s))
        success := true
  end
  %endif

  %ifdef output.portaudio
  if output_sound_device_type == "Portaudio" then
        ignore(output.portaudio(s))
        success := true
  end
  %endif

  %ifdef output.pulseaudio
  if output_sound_device_type == "Pulseaudio" then
        ignore(output.pulseaudio(s))
        success := true
  end
  %endif

    if (!success == false) then
        ignore(output.prefered(s))
  end

end

if s1_enable == true then
    if s1_output == 'shoutcast' then
        s1_namespace := "shoutcast_stream_1"
    else
        s1_namespace := s1_mount
    end
    server.register(namespace=!s1_namespace, "connected", fun (s) -> begin log("#{!s1_namespace}.connected") !s1_connected end)
    output_to(s1_output, s1_type, s1_bitrate, s1_host, s1_port, s1_pass,
                s1_mount, s1_url, s1_description, s1_genre, s1_user, s, "1",
                s1_connected, s1_name, s1_channels)
end

if s2_enable == true then
    if s2_output == 'shoutcast' then
        s2_namespace := "shoutcast_stream_2"
    else
        s2_namespace := s2_mount
    end
    server.register(namespace=!s2_namespace, "connected", fun (s) -> begin log("#{!s2_namespace}.connected") !s2_connected end)
    output_to(s2_output, s2_type, s2_bitrate, s2_host, s2_port, s2_pass,
                s2_mount, s2_url, s2_description, s2_genre, s2_user, s, "2",
                s2_connected, s2_name, s2_channels)

end

if s3_enable == true then
    if s3_output == 'shoutcast' then
        s3_namespace := "shoutcast_stream_3"
    else
        s3_namespace := s3_mount
    end
    server.register(namespace=!s3_namespace, "connected", fun (s) -> begin log("#{!s3_namespace}.connected") !s3_connected end)
    output_to(s3_output, s3_type, s3_bitrate, s3_host, s3_port, s3_pass,
                s3_mount, s3_url, s3_name, s3_genre, s3_user, s, "3",
                s3_connected, s3_description, s3_channels)
end

command = "/usr/lib/airtime/pypo/bin/liquidsoap_scripts/notify.sh --liquidsoap-started &"
log(command)
system(command)
