-module(pk_serve1).
-author("Mathieu Sabourin").

-export([listen/1, start/1, spine/1, restart/1]).

-define(TCP_OPTIONS, [binary, {packet, 0}, {active, once}, {reuseaddr, true}]).

restart(Socket)->
    spawn(?MODULE, listen, [Socket]).

%Start server, listen on port 8888
start(test) ->
    start(8888);

%Start server, listen on port Socket
start(Socket) ->
    register(mess_serv, spawn(fun() -> mess_serv() end)),
    restart(Socket).

pk_init({N}) ->
    %io:format("In pk_init/1~n"),
    D = dict:new(),
    pk_init({D, N, tmp});

pk_init({D, 0, Map}) ->
    %io:format("In pk_init/3 with 0~n"),
    register(maps, spawn(fun() -> get_map_list(D) end)),
    %io:format("~p~n", [Maps]),
    Map;

pk_init({D, N, Map}) ->
    %io:format("In pk_init/3 ~p~n", [N]),
    Map2 = spawn(?MODULE, spine, [start]),
    D1 = dict:store(N, Map2, D),
    pk_init({D1, N-1, Map2}).

mess_serv() ->
    mess_serv(dict:new()).

mess_serv(D) ->
    receive 
	{add, Name, Pid} ->
	    D1 = dict:store(Name, Pid, D);
	{mess, Name, From, Mess} ->
	    D1 = D,
	    case dict:find(Name, D) of
		{ok, Dest} ->
		    Dest ! {From, Mess};
		error ->
		    io:format("Client not found")
	    end
    end,
    mess_serv(D1).


mess_cl(Socket) ->
    receive
	{From, Mess} ->
	    gen_tcp:send(Socket, io_lib:format("~p:~p~n", [From, Mess]))
    end,
    mess_cl(Socket).


listen(Port) ->
    {ok, LSocket} = gen_tcp:listen(Port, ?TCP_OPTIONS),
    Spine = pk_init({3}),
    accept(LSocket, Spine).


accept(LSocket, Spine) ->
    case gen_tcp:accept(LSocket) of
	{ok, Socket} ->
	    inet:setopts(Socket, ?TCP_OPTIONS),
	    io:format("Accept~n"),
	    DB = spawn(fun() -> spine(start) end),
	    gen_tcp:controlling_process(Socket, spawn(fun() ->  loop(Socket, Spine, DB) end)),
						%{error, Reason} ->
						%io:format("Error : ~p~n", [Reason])
						%end,
	    accept(LSocket, Spine);
	Other ->
	    io:format("Got [~w]~n", [Other]),
	    ok
    end.


spine(start) ->
    D = dict:new(),
    spine(D);

spine(D) ->
    receive
	{get, Key, Pid} ->
	    Pid ! dict:fetch(Key, D),
	    D1 = D;
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


db_peek(Key, DB) ->
    DB ! {get, Key, self()},
    receive
	Value ->
	    Value
    end.
	    

		  
get_map_list(Maps) ->
    receive
	{Pid, Map} ->
	    %io:format("In get_map_list ~p|~p~n", [Map, dict:to_list(Maps)]),
	    Pid ! {dict:fetch(Map, Maps)}
    end,
    %io:format("Sent~n"),
    get_map_list(Maps).


ch_map(Map) ->
    {M_int, _} = string:to_integer(Map),
    %io:format("In ch_map~n"),
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
    %io:format("~p~n", [T]),
    T.


clean(Str) ->
    (((Str -- " ") -- "\n") -- "\r").

            
loop(Socket, Spine, DB) ->
    inet:setopts(Socket, [{active, once}]),
    receive
        {tcp, Socket, Data} ->
	    case 
		case bitstring_to_list(Data) of
		    [$i, $n, $i, $t | Name] ->
			io:format("Init : ~p", [clean(Name)]),
			mess_serv ! {add, clean(Name),
				     spawn(fun()-> mess_cl(Socket) end)},
			DB ! {id,
			      clean(Name)},
			ok;
		    [$s, $e, $t | Coord] ->
			io:format("Set : ~p", [clean(Coord)]),
			KV = parse(clean(Coord)),
			pk_set(KV, Spine),
			ok;
		    [$g, $e, $t | _] ->
			io:format("Get"),
			gen_tcp:send(Socket, io_lib:format("~p", [pk_get(Spine)])),
			ok;
		    [$d, $e, $l | Id] ->
			pk_del(clean(Id), Spine),
			ok;
		    [$m, $a, $p | Map] ->
						%io:format("~p|~p~n", [Map, clean(Map)]),
						%gen_tcp:send(Socket, "ok\n"),
			{ok, ch_map(clean(Map))};
						%io:format("In ~p New map pid is ~p~n", [self(), Spine2]);
		    [$m, $e, $s, $s | Mess] ->
			First = clean(string:sub_word(Mess, 1)),
			mess_serv ! {mess,
				     First,
				     db_peek(id, DB),
				     clean(Mess -- First)},
			ok;
		    [$p, $u, $s, $h | Info] ->
			First = clean(string:sub_word(Info, 1)),
			DB ! {First,
			      clean(Info -- First)},
			ok;
		    [$p, $e, $e, $k | Key] ->
			gen_tcp:send(Socket,
				     io_lib:format("~p~n", [db_peek(clean(Key), DB)])),
			ok;
		    Other ->
			gen_tcp:send(Socket, io_lib:format("~p not recognized~n", [Other])),
			ok		   
		end
	    of 
		ok ->
		    loop(Socket, Spine, DB);
		{ok, Spine2} ->
		    loop(Socket, Spine2, DB);
		{error, Message} ->
		    Message
	    end;
        {tcp_closed, Socket} ->
	    gen_tcp:close(Socket),
	    io:format("Closed Socket~n"),
            ok;
	Other ->
	    io:format("~p~n", [Other]),
	    ok
    end.
