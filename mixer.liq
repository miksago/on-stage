set("log.file.path","/tmp/mixer.log")
set("log.stdout", true)

set("gstreamer.debug_level", 5)

set("scheduler.log", true)
set("scheduler.fast_queues",10)
set("scheduler.generic_queues",10)
set("scheduler.non_blocking_queues",10)

# Socket control
set("server.socket",true)
set("server.socket.path","/tmp/liquidsoap-mixer")
set("server.timeout",-1.0)

set("harbor.bind_addr","0.0.0.0")
set("harbor.reverse_dns", false)
set("harbor.verbose", true)


streams = ref []
stream_names = ref []
active_source = ref 0

def counter()
  int = ref 1
  fun() -> begin
    current = !int
    int := !int + 1
    current
  end
end

stream_counter = counter()
source_counter = counter()

def add_stream(~id, s)
  streams := list.append(!streams, [ s ] )
  stream_names := list.append(!stream_names, [ id ] )

  # make sure we read from `s`
  ignore(output.dummy(fallible=true, s))
end

def add_http(uri)
  ident = "stream#{stream_counter()}"
  httpstream = input.http(id=ident, autostart=true, uri)
  ignore(add_stream(id=ident, httpstream))
  ignore(ident)
end

def add_source(password)
  ident = "source#{source_counter()}"
  harbor = input.harbor(id=ident, port=8080, password=password, ident)
  ignore(add_stream(id=ident, harbor))
end

jingle = single(id="jingle", conservative=true, default_duration=7.0, length=7.0, "~/jingle.mp3")

default = amplify(id="default", 0.00001, noise())
ignore(add_stream(id="default", default))

add_http("http://listen.ntslive.co.uk/stream")
add_source("password1")
add_source("password2")
add_source("password3")
add_source("password4")



def list.indexOf(value, thelist)
  found = ref false

  def f(index, item) =
    if item == value then
      found := true
    end

    if !found then
      index
    else
      index + 1
    end
  end

  index = list.fold(f, 0, thelist)

  if !found then
    index
  else
    -1
  end
end


def transition(name)
  index = list.indexOf(name, !stream_names)
  log("Index of #{name} in sources is: #{index}")

  # # index = int_of_string(sInt)
  # len = list.length(!streams)

  # if index >= 0 and index < len then
  if index >= 0 then
    log("switching to: #{index}")

    id = list.nth(!stream_names, index)
    log("streams.select(#{index}) => #{id}")
    active_source := index
    json_of("done")
  else
    "ERROR: Could not transition to out-of-bounds stream"
  end
end

def dyn_names(_)
  json_of(!stream_names)
end

def dyn_count(_)
  json_of(list.length(!streams))
end


def mute(_)
  active_source := 0
  json_of("done")
end

server.register(description="Retrieve number of available streams", "count", dyn_count)
server.register(description="Retrieve names of available streams", "list_streams", dyn_names)
server.register(description="Select a stream.", "transition", transition)
server.register("mute", mute)

sfs = list.map(fun (source) -> begin
  (fun() -> begin
    list.nth(!stream_names, !active_source) == source.id(source)
  end, source)
end, !streams)


def is_replay_metadata(stream)
  string.match(pattern="replay_metadata_", source.id(stream))
end

def is_default(stream)
  source.id(stream) == "default"
end

def crossfade(a,b)
  if is_replay_metadata(a) or is_replay_metadata(b) then
    log("Skip Replay s -> b")
    add(id="add_replay", [ sequence(merge=true, [ fade.final(a), b ]) ])
  # Try to match further:
  elsif is_default(a) and not is_default(b) then
    log("Set: s => _ -> b")
    add(id="add_in", normalize=false, [
      fade.initial(b)
    ])
  elsif is_default(b) and not is_default(a) then
    log("Set: s => a -> _")
    add(id="add_out", normalize=false, [
      sequence(merge=true, [ fade.final(a, duration=2.0), default ])
    ])
  else
    log("Set: s => a -> jingle -> b")
    add(id="add_crossover",normalize=false, [
      fade.final(a, duration=2.0),
      sequence(merge=true, [ blank(duration=0.9), fade.initial(jingle, duration=0.6, type="log"), blank(duration=2.5) ]),
      sequence(merge=true, [ blank(duration=4.5), fade.initial(b) ])
    ])
  end
end


stream = switch(track_sensitive=false, transitions=list.map(fun(_) -> crossfade, sfs), sfs)
stream = fallback(track_sensitive=false, transitions=[ crossfade, crossfade ], [stream, default])


output.icecast(%mp3,
  id="icecast",
  host="localhost",
  port=8000,
  password="on-stage-source",
  mount="radio",
  fallible=true,
  drop_metadata(stream)
)

