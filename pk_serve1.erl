-module(pk_serve1).
-author("Mathieu Sabourin").

-export([listen/1, start/1, spine/1]).

-define(TCP_OPTIONS, [binary, {packet, 0}, {active, false}, {reuseaddr, true}]).

spine(start) ->
    D = dict:new(),
    spine(D);

spine(D) ->
    receive
	{get, Pid} ->
	    Pid ! D,
	    D1 = D;
	{Key, Value} ->
	    D1 = dict:store(Key, Value, D)
    end,
    spine(D1).

to_from({Key, Value, Spine}, dict)->
    Spine ! {self(), Key, Value},
    receive
	D ->
	    io:format("In to_from~n D -> ~p~n", [dict:to_list(D)])
    end,
    D;

to_from({Key, Value, Spine}, list) ->
    dict:to_list(to_from({Key, Value, Spine}, dict)).

pk_set({Key, Value}, Spine) ->
    Spine ! {Key, Value}.

pk_get(Spine) ->
    Spine ! {get, self()},
    receive
	D ->
	    io:format("In pk_get~n D -> ~p~n", [dict:to_list(D)])
    end,
    dict:to_list(D).

% Call echo:listen(Port) to start the service.
listen(Port) ->
    {ok, LSocket} = gen_tcp:listen(Port, ?TCP_OPTIONS),
    Pid = spawn(?MODULE, spine, [start]),
    accept(LSocket, Pid).

% Wait for incoming connections and spawn the echo loop when we get one.
accept(LSocket, Pid) ->
    {ok, Socket} = gen_tcp:accept(LSocket),
    spawn(fun() -> loop(Socket, Pid) end),
    accept(LSocket, Pid).

parse(Str)->
    S = Str ++ ".",
    {ok,Scanned,_} = erl_scan:string(S),
    {ok,Parsed} = erl_parse:parse_exprs(Scanned),
    {value, L, _} = erl_eval:exprs(Parsed,[]),
    io:format("~p~n", [L]),
    L.

cmd(Input) ->
    case string:sub_word(Input, 1) of
	"set" ->
	    {set, Input -- "set "};
	"get"  ->
	    {get, Input -- "get "}
    end.
            
loop(Socket, Pid) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, Data} ->
	    case cmd(bitstring_to_list(Data)) of
		{set, Coord} ->
		    KV = parse(Coord),
		    pk_set(KV, Pid);
		{get, _} ->
		    gen_tcp:send(Socket, io_lib:format("~p~n", [pk_get(Pid)]))
	    end,
	    loop(Socket, Pid);
        {error, closed} ->
            ok
    end.

start(Socket) ->
    spawn(?MODULE, listen, [Socket]).
