-module(pk_serve1).
-author("Mathieu Sabourin").

-export([listen/1, start/1, spine/1]).

-define(TCP_OPTIONS, [binary, {packet, 0}, {active, once}, {reuseaddr, true}]).

start(test) ->
    start(8888);

start(Socket) ->
    spawn(?MODULE, listen, [Socket]).


pk_init({N}) ->
    io:format("In pk_init/1~n"),
    D = dict:new(),
    pk_init({D, N, tmp});

pk_init({D, 0, Map}) ->
    io:format("In pk_init/3 with 0~n"),
    register(maps, spawn(fun() -> get_map_list(D) end)),
    %io:format("~p~n", [Maps]),
    Map;

pk_init({D, N, Map}) ->
    io:format("In pk_init/3 ~p~n", [N]),
    Map2 = spawn(?MODULE, spine, [start]),
    D1 = dict:store(N, Map2, D),
    pk_init({D1, N-1, Map2}).


listen(Port) ->
    {ok, LSocket} = gen_tcp:listen(Port, ?TCP_OPTIONS),
    Spine = pk_init({3}),
    accept(LSocket, Spine).


accept(LSocket, Spine) ->
    case gen_tcp:accept(LSocket) of
	{ok, Socket} ->
	    inet:setopts(Socket, ?TCP_OPTIONS),
	    spawn(fun() -> accept(LSocket, Spine) end),
	    loop(Socket, Spine);
	Other ->
	    io:format("Got [~w]~n", [Other]),
	    ok
    end.


spine(start) ->
    D = dict:new(),
    spine(D);

spine(D) ->
    receive
	{get, Pid} ->
	    Pid ! D,
	    D1 = D;
	{del, Id} ->
	    D1 = dict:erase(Id, D);
	{Key, Value} ->
	    D1 = dict:store(Key, Value, D)
    end,
    spine(D1).


pk_set({Key, Value}, Spine) ->
    Spine ! {Key, Value}.

pk_del(Id, Spine) ->
    Spine ! {del, Id}.

pk_get(Spine) ->
    Spine ! {get, self()},
    receive
	D ->
	    io:format("In pk_get~n D -> ~p~n", [dict:to_list(D)])
    end,
    dict:to_list(D).

		  
get_map_list(Maps) ->
    receive
	{Pid, Map} ->
	    io:format("In get_map_list ~p|~p~n", [Map, dict:to_list(Maps)]),
	    Pid ! {dict:fetch(Map, Maps)}
    end,
    io:format("Sent~n"),
    get_map_list(Maps).


ch_map(Map) ->
    {M_int, _} = string:to_integer(Map),
    io:format("In ch_map~n"),
    maps ! {self(), M_int},
    receive
	{New_map} ->
	    io:format("Received ~p~n", [New_map])
    end,
    New_map.


parse(Str) ->
    S = Str ++ ".",
    {ok, Tks,_} = erl_scan:string(S),
    {ok, T} = erl_parse:parse_term(Tks),
    io:format("~p~n", [T]),
    T.


clean(Str) ->
    (((Str -- " ") -- "\n") -- "\r").

            
loop(Socket, Spine) ->
    inet:setopts(Socket, [{active, once}]),
    receive
        {tcp, Socket, Data} ->
	    case bitstring_to_list(Data) of
		[$s, $e, $t | Coord] ->
		    Spine2 = Spine,
		    KV = parse(clean(Coord)),
		    pk_set(KV, Spine);
		[$g, $e, $t | _] ->
		    Spine2 = Spine,
		    gen_tcp:send(Socket, io_lib:format("~p~n", [pk_get(Spine)]));
		[$d, $e, $l | Id] ->
		    Spine2 = Spine,
		    pk_del(clean(Id), Spine);
		[$m, $a, $p | Map] ->
		    io:format("~p|~p~n", [Map, clean(Map)]),
		    %gen_tcp:send(Socket, "ok\n"),
		    Spine2 = ch_map(clean(Map)),
		    io:format("In ~p New map pid is ~p~n", [self(), Spine2]);
		Other ->
		    Spine2 = Spine,
		    gen_tcp:send(Socket, io_lib:format("~p not recognized~n", [Other]))
	    end,
	    loop(Socket, Spine2);
        {tcp_closed, Socket} ->
	    %gen_tcp:close(Socket),
            ok;
	Other ->
	    io:format("~p~n", [Other]),
	    ok
    end.
